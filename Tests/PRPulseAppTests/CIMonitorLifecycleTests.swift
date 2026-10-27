import XCTest
@testable import PRPulseApp

@MainActor
final class CIMonitorLifecycleTests: XCTestCase {
    func testRejectedNotificationRemainsEligibleOnNextPoll() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MonitorClient()
        let sink = CINotificationRecorder()
        let lifetime = AccountSessionLifetime()
        let monitor = CIMonitor(client: client, directory: directory, lifetime: lifetime, notifier: sink)
        defer { monitor.stop(); lifetime.invalidate() }
        var settings = AppSettings.default; settings.ciFailureAlerts = true
        monitor.configure(settings)
        for _ in 0..<100 where monitor.lastChecked == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(monitor.lastChecked)
        sink.accepts = false; client.failed = true
        await monitor.poll()
        XCTAssertTrue(sink.deliveries.isEmpty)
        sink.accepts = true
        await monitor.poll()
        XCTAssertEqual(sink.deliveries.count, 2, "Rejected requests must retry rather than advance the baseline")
        await monitor.poll()
        XCTAssertEqual(sink.deliveries.count, 2, "Accepted requests must not repeat")
    }
    func testStaleMonitorResultAlsoUpdatesAlreadyVisibleDashboardRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MonitorClient()
        let store = PullRequestStore(directory: directory)
        var preferences = AppSettings.default
        preferences.ciFailureAlerts = true; preferences.refreshOnLaunch = false; preferences.refreshInterval = 0
        try await store.save(settings: preferences)
        let dashboard = DashboardViewModel(client: client, store: store, notifier: NotificationDispatcher(store: store),
                                           scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        for _ in 0..<100 where dashboard.ciMonitor.lastChecked == nil { try await Task.sleep(for: .milliseconds(5)) }
        await dashboard.refreshAllLoaded()
        await dashboard.ciMonitor.poll()
        XCTAssertFalse(dashboard.listStates[.mine]?.rawItems.first?.detail.ci?.isStale ?? true)
        client.unavailable = true
        await dashboard.ciMonitor.poll()
        XCTAssertTrue(dashboard.listStates[.mine]?.rawItems.first?.detail.ci?.isStale ?? false)
        await dashboard.retire()
    }
    func testIntervalChangeDuringFetchStillPerformsAnImmediateNewPass() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MonitorClient(); client.delay = true
        let lifetime = AccountSessionLifetime()
        let monitor = CIMonitor(client: client, directory: directory, lifetime: lifetime, notifier: CINotificationRecorder())
        var settings = AppSettings.default; settings.ciFailureAlerts = true
        monitor.configure(settings)
        for _ in 0..<100 where !client.fetchStarted { try await Task.sleep(for: .milliseconds(5)) }
        settings.ciRefreshInterval = 900
        monitor.configure(settings)
        for _ in 0..<100 where monitor.lastChecked == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(monitor.snapshots.count, 2, "Rescheduling must not postpone the first pass by the entire interval")
        monitor.stop(); lifetime.invalidate()
    }
    func testMonitorDiscoversAllAuthoredPagesAndDeliversGroupedFailuresOnlyAfterBaseline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MonitorClient()
        let sink = CINotificationRecorder()
        let lifetime = AccountSessionLifetime()
        let monitor = CIMonitor(client: client, directory: directory, lifetime: lifetime, notifier: sink)
        var settings = AppSettings.default; settings.ciFailureAlerts = true
        monitor.configure(settings)
        for _ in 0..<100 where monitor.lastChecked == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(monitor.message, "Monitoring 2 open My PRs")
        XCTAssertEqual(monitor.snapshots.count, 2)
        XCTAssertTrue(sink.deliveries.isEmpty)
        client.discoveryFails = true
        await monitor.poll()
        XCTAssertTrue(monitor.snapshots["PR_1"]?.isStale ?? false)
        client.discoveryFails = false
        client.unavailable = true
        await monitor.poll()
        XCTAssertEqual(monitor.snapshots["PR_1"]?.checks.map(\.name), ["Build", "Tests"])
        XCTAssertTrue(monitor.snapshots["PR_1"]?.isStale ?? false)
        client.unavailable = false
        client.failed = true
        await monitor.poll()
        XCTAssertEqual(sink.deliveries, ["PR_1:Build,Tests", "PR_2:Build,Tests"])
        await monitor.poll()
        XCTAssertEqual(sink.deliveries.count, 2)
        try monitor.setMuted(true, for: "PR_2")
        client.failed = false; await monitor.poll()
        client.failed = true; await monitor.poll()
        XCTAssertEqual(sink.deliveries.count, 3)
        client.onlyFirst = true; await monitor.poll()
        XCTAssertEqual(Set(monitor.snapshots.keys), ["PR_1"])
        monitor.stop(); lifetime.invalidate()
        await monitor.poll()
        XCTAssertEqual(sink.deliveries.count, 3)
    }

    func testRetirementDuringFetchCannotWriteOrDeliver() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = MonitorClient(); client.delay = true
        let sink = CINotificationRecorder()
        let lifetime = AccountSessionLifetime()
        let monitor = CIMonitor(client: client, directory: directory, lifetime: lifetime, notifier: sink)
        var settings = AppSettings.default; settings.ciFailureAlerts = true
        monitor.configure(settings)
        for _ in 0..<100 where !client.fetchStarted { try await Task.sleep(for: .milliseconds(5)) }
        lifetime.invalidate(); monitor.stop()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(monitor.snapshots.isEmpty)
        XCTAssertTrue(sink.deliveries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ci-monitor.json").path))
    }
}

@MainActor
private final class CINotificationRecorder: CINotificationSending {
    var deliveries: [String] = []
    var accepts = true
    func requestAuthorizationIfNeeded() async {}
    func ciPermissionDescription() async -> String { "Enabled" }
    func sendCIFailure(for pr: PullRequest, checks: [CICheck]) async -> Bool {
        guard accepts else { return false }
        deliveries.append("\(pr.id):\(checks.map(\.name).joined(separator: ","))")
        return true
    }
}

private final class MonitorClient: GitHubClient, @unchecked Sendable {
    var failed = false
    var onlyFirst = false
    var delay = false
    var fetchStarted = false
    var unavailable = false
    var discoveryFails = false
    func fetchViewer() async throws -> String { "me" }
    func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        fetchStarted = true
        if discoveryFails { throw GitHubClientError.invalidResponse }
        if delay { try? await Task.sleep(for: .milliseconds(100)) }
        let index = cursor == nil ? 1 : 2
        return .init(items: [pr(index)], cursor: cursor == nil && !onlyFirst ? "next" : nil,
                     hasNextPage: cursor == nil && !onlyFirst)
    }
    func fetchCI(for pullRequest: PullRequest) async throws -> CIStatus {
        if unavailable { return .unavailable }
        return .init(headSHA: "head", revision: "head", checks: [
            .init(id: "build", name: "Build", state: failed ? .failure : .running),
            .init(id: "tests", name: "Tests", state: failed ? .failure : .queued)])
    }
    private func pr(_ index: Int) -> PullRequest {
        .init(id: "PR_\(index)", number: index, title: "CI", url: URL(string: "https://github.com/example/repo/pull/\(index)")!,
              repository: .init(nameWithOwner: "example/repo"), author: .init(login: "me"),
              createdAt: Date(), updatedAt: Date(), isDraft: false)
    }
}
