import XCTest
@testable import PRPulseApp

final class DashboardLoadingRaceTests: XCTestCase {
    @MainActor
    func testResetWaitsForPaginationAndReplacesOldPages() async throws {
        let (dashboard, client, root) = try await makeDashboard()
        defer { try? FileManager.default.removeItem(at: root) }
        await dashboard.refreshAllLoaded()
        dashboard.selectedTab = .mine
        dashboard.loadMoreCurrentTab()
        while client.page == nil { await Task.yield() }
        var entered = false
        let reset = Task { @MainActor in entered = true; await dashboard.refreshAllLoaded() }
        while !entered { await Task.yield() }
        client.page?.resume(returning: .init(items: [LoadingGate.item("second")], cursor: nil, hasNextPage: false))
        await reset.value
        XCTAssertEqual(client.firstPages, 2)
        XCTAssertEqual(dashboard.listStates[.mine]?.rawItems.map(\.id), ["fresh"])
        await dashboard.retire()
    }

    @MainActor
    func testPaginationPreservesConcurrentTriage() async throws {
        let (dashboard, client, root) = try await makeDashboard()
        defer { try? FileManager.default.removeItem(at: root) }
        await dashboard.refreshAllLoaded()
        dashboard.selectedTab = .mine
        let row = try XCTUnwrap(dashboard.listStates[.mine]?.displayedItems.first)
        dashboard.loadMoreCurrentTab()
        while client.page == nil { await Task.yield() }
        dashboard.perform(action: .markNotApplicable, on: row)
        while dashboard.listStates[.mine]?.rawItems.first?.override.state != .notApplicable { await Task.yield() }
        client.page?.resume(returning: .init(items: [LoadingGate.item("second")], cursor: nil, hasNextPage: false))
        while dashboard.listStates[.mine]?.isLoading == true { await Task.yield() }
        XCTAssertEqual(dashboard.listStates[.mine]?.rawItems.first?.override.state, .notApplicable)
        await dashboard.retire()
    }

    @MainActor
    func testViewerCompletionPresentsAlreadyLoadedRows() async throws {
        let (dashboard, client, root) = try await makeDashboard(delayViewer: true)
        defer { try? FileManager.default.removeItem(at: root) }
        while client.viewer == nil { await Task.yield() }
        await dashboard.refreshAllLoaded()
        XCTAssertEqual(dashboard.listStates[.mine]?.rawItems.count, 1)
        client.viewer?.resume(returning: "alice")
        while dashboard.viewerLogin.isEmpty { await Task.yield() }
        XCTAssertEqual(dashboard.listStates[.mine]?.displayedItems.count, 1)
        await dashboard.retire()
    }

    @MainActor
    private func makeDashboard(delayViewer: Bool = false) async throws -> (DashboardViewModel, LoadingGate, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PullRequestStore(directory: root)
        var settings = AppSettings.default
        settings.refreshOnLaunch = false
        settings.refreshInterval = 0
        try await store.save(settings: settings)
        let client = LoadingGate(delayViewer: delayViewer)
        let dashboard = DashboardViewModel(client: client, store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while !dashboard.isReady { await Task.yield() }
        if !delayViewer { while dashboard.viewerLogin.isEmpty { await Task.yield() } }
        return (dashboard, client, root)
    }
}

@MainActor
private final class LoadingGate: GitHubClient {
    let delayViewer: Bool
    var firstPages = 0
    var page: CheckedContinuation<PullRequestPage, Error>?
    var viewer: CheckedContinuation<String, Error>?
    init(delayViewer: Bool) { self.delayViewer = delayViewer }
    nonisolated(nonsending) func fetchViewer() async throws -> String {
        if await MainActor.run(body: { self.delayViewer }) {
            return try await withCheckedThrowingContinuation { value in Task { @MainActor in self.viewer = value } }
        }
        return "alice"
    }
    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        guard tab == .mine else { return .init(items: [], cursor: nil, hasNextPage: false) }
        if cursor != nil {
            return try await withCheckedThrowingContinuation { value in Task { @MainActor in self.page = value } }
        }
        return await MainActor.run {
            self.firstPages += 1
            return .init(items: [Self.item(self.firstPages == 1 ? "old" : "fresh")], cursor: "next", hasNextPage: true)
        }
    }
    static func item(_ id: String) -> PullRequest {
        .init(id: id, number: 1, title: id, url: URL(string: "https://github.com/a/b/pull/1")!, repository: .init(nameWithOwner: "a/b"), author: .init(login: "alice"), createdAt: Date(), updatedAt: Date(), isDraft: false)
    }
}
