import AppKit
import XCTest
@testable import PRPulseApp

@MainActor
final class CIStatusFreshnessTests: XCTestCase {
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
    func fetchViewer() async throws -> String { "me" }
    func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        reads += 1
        let ci = CIStatus(headSHA: "head", revision: "head", checks: [
            .init(id: "build", name: "Build", state: running ? .running : .success)],
                          checkedAt: running ? Date() : Date().addingTimeInterval(-60))
        let pr = PullRequest(id: "PR_1", number: 1, title: "Snapshot", url: URL(string: "https://github.com/example/repo/pull/1")!,
                             repository: .init(nameWithOwner: "example/repo"), author: .init(login: "me"),
                             createdAt: Date(), updatedAt: Date(), isDraft: false, detail: .init(ci: ci))
        return .init(items: [pr], cursor: nil, hasNextPage: false)
    }
}
