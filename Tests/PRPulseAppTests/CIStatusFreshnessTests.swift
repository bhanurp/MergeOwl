import AppKit
import XCTest
@testable import PRPulseApp

@MainActor
final class CIStatusFreshnessTests: XCTestCase {
    func testPopoverThrottleDoesNotSuppressAnotherLoadedTab() async throws {
        let (dashboard, client, directory) = try await makeDashboard()
        defer { try? FileManager.default.removeItem(at: directory) }
        await dashboard.refreshActiveTab()
        dashboard.selectedTab = .mine
        await dashboard.refreshActiveTab()
        dashboard.selectedTab = .reviewRequested
        let now = Date()
        await dashboard.refreshForPopoverOpen(now: now)
        let reads = client.reads
        dashboard.selectedTab = .mine
        await dashboard.refreshForPopoverOpen(now: now.addingTimeInterval(1))
        XCTAssertEqual(client.reads, reads + 1)
        await dashboard.retire()
    }

    func testPopoverRefreshWaitsForPaginationInsteadOfDroppingRequest() async throws {
        let (dashboard, client, directory) = try await makeDashboard()
        defer { try? FileManager.default.removeItem(at: directory) }
        client.hasNextPage = true
        await dashboard.refreshActiveTab()
        dashboard.loadMoreCurrentTab()
        for _ in 0..<100 where client.pagination == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(client.pagination)
        var refreshStarted = false
        var refreshFinished = false
        let refresh = Task {
            refreshStarted = true
            await dashboard.refreshForPopoverOpen()
            refreshFinished = true
        }
        for _ in 0..<100 where !refreshStarted { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(refreshStarted)
        XCTAssertFalse(refreshFinished, "Freshness must wait while pagination remains suspended")
        client.pagination?.resume(); client.pagination = nil
        await refresh.value
        for _ in 0..<100 where dashboard.isCurrentListRefreshing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(client.reads, 3, "Initial page, pagination, then queued freshness reset")
        await dashboard.retire()
    }

    private func makeDashboard() async throws -> (DashboardViewModel, FreshnessClient, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PullRequestStore(directory: directory)
        var settings = AppSettings.default
        settings.refreshOnLaunch = false; settings.refreshInterval = 0
        try await store.save(settings: settings)
        let client = FreshnessClient()
        let dashboard = DashboardViewModel(client: client, store: store, notifier: NotificationDispatcher(store: store),
                                           scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        for _ in 0..<100 where !dashboard.isReady { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(dashboard.isReady)
        return (dashboard, client, directory)
    }
    func testReopeningRefreshesOldPassedSnapshotAndCoalescesRapidOpens() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PullRequestStore(directory: directory)
        var settings = AppSettings.default
        settings.refreshOnLaunch = false; settings.refreshInterval = 0
        try await store.save(settings: settings)
        let client = FreshnessClient()
        let dashboard = DashboardViewModel(client: client, store: store, notifier: NotificationDispatcher(store: store),
                                           scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        for _ in 0..<100 where !dashboard.isReady { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(dashboard.isReady)
        await dashboard.refreshActiveTab()
        XCTAssertEqual(dashboard.currentItems.first?.pullRequest.detail.ci?.state, .passed)
        client.running = true
        let now = Date()
        let controller = PRPulseStatusItemController(statusBar: FreshnessStatusBar(), popover: FreshnessPopover())
        controller.install(with: dashboard, actions: .noop)
        controller.togglePopover()
        for _ in 0..<100 where dashboard.currentItems.first?.pullRequest.detail.ci?.state != .running {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(dashboard.currentItems.first?.pullRequest.detail.ci?.state, .running)
        let reads = client.reads
        await dashboard.refreshForPopoverOpen(now: now.addingTimeInterval(1))
        XCTAssertEqual(client.reads, reads, "Rapid popover toggles must not hammer GitHub")
        await dashboard.refreshForPopoverOpen(now: now.addingTimeInterval(31))
        XCTAssertEqual(client.reads, reads + 1)
        await dashboard.retire()
        await dashboard.refreshForPopoverOpen(now: now.addingTimeInterval(62))
        XCTAssertEqual(client.reads, reads + 1, "Retired accounts cannot refresh")
    }
}

@MainActor private final class FreshnessStatusBar: StatusBarHosting {
    func makeButton(onClick: @escaping @MainActor () -> Void) -> any StatusItemButtonHosting { FreshnessButton() }
    func removeButton(_ button: any StatusItemButtonHosting) {}
}
@MainActor private final class FreshnessButton: StatusItemButtonHosting {
    let anchorView = NSView()
    func update(image: NSImage, accessibilityLabel: String) {}
}
@MainActor private final class FreshnessPopover: PopoverHosting {
    var isShown = false
    func configure(content: NSViewController) {}
    func show(relativeTo anchorView: NSView) { isShown = true }
    func close() { isShown = false }
}

private final class FreshnessClient: GitHubClient, @unchecked Sendable {
    var reads = 0
    var running = false
    var hasNextPage = false
    var pagination: CheckedContinuation<Void, Never>?
    func fetchViewer() async throws -> String { "me" }
    func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        reads += 1
        if cursor != nil { await withCheckedContinuation { pagination = $0 } }
        let ci = CIStatus(headSHA: "head", revision: "head", checks: [
            .init(id: "build", name: "Build", state: running ? .running : .success)],
                          checkedAt: running ? Date() : Date().addingTimeInterval(-60))
        let pr = PullRequest(id: "PR_1", number: 1, title: "Snapshot", url: URL(string: "https://github.com/example/repo/pull/1")!,
                             repository: .init(nameWithOwner: "example/repo"), author: .init(login: "me"),
                             createdAt: Date(), updatedAt: Date(), isDraft: false, detail: .init(ci: ci))
        return .init(items: [pr], cursor: hasNextPage ? "next" : nil, hasNextPage: hasNextPage)
    }
}
