import XCTest
@testable import PRPulseApp

final class SavedPRViewTests: XCTestCase {
    func testAwaitingReviewAndChangesRequestedPositiveRules() {
        var item = PullRequest(id: "review", number: 1, title: "Review this API", url: URL(string: "https://github.com/a/b/pull/1")!, repository: .init(nameWithOwner: "a/b"), author: .init(login: "bob"), createdAt: Date(), updatedAt: Date(), isDraft: false, detail: .init(mergeable: .mergeable, reviewDecision: .approved))
        let calculator = PullRequestStatusCalculator(currentUserLogin: "alice")
        item.detail.ci = CIStatus(headSHA: "head", revision: "head", checks: [])
        item.detail.mergeStateStatus = "CLEAN"
        var presentation = PullRequestPresentation(pullRequest: item, status: calculator.status(for: item))
        XCTAssertTrue(SavedPRViewMatcher.matches(presentation, view: .init(name: "Review", stateRule: .awaitingReview), viewerLogin: "alice"))
        XCTAssertFalse(SavedPRViewMatcher.matches(presentation, view: .init(name: "Unmatched", text: "unrelated"), viewerLogin: "alice"))
        item.detail.reviews = [.init(reviewer: "reviewer", state: .changesRequested, submittedAt: Date())]
        presentation = PullRequestPresentation(pullRequest: item, status: calculator.status(for: item))
        XCTAssertTrue(SavedPRViewMatcher.matches(presentation, view: .init(name: "Changes", stateRule: .changesRequested), viewerLogin: "alice"))
    }
    @MainActor
    func testRelaunchRestoresEnabledViewButAccountSwitchDoesNot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let view = SavedPRView(name: "Restored")
        let definitions = SavedPRViewStore(directory: root)
        try await definitions.save([view])
        try await definitions.select(view.id)
        for restore in [true, false] {
            let store = PullRequestStore(directory: root)
            let dashboard = DashboardViewModel(client: RepeatedPRClient(), store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer(), restoreSavedSelection: restore)
            while dashboard.viewerLogin.isEmpty { await Task.yield() }
            XCTAssertEqual(dashboard.selectedSavedViewID, restore ? view.id : nil)
            await dashboard.retire()
        }
    }
    @MainActor
    func testManagementPersistsOrderAndDisabledSelectionFallsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PullRequestStore(directory: root)
        let dashboard = DashboardViewModel(client: RepeatedPRClient(), store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while dashboard.viewerLogin.isEmpty { await Task.yield() }
        let first = SavedPRView(name: "First")
        var second = SavedPRView(name: "Second")
        try await dashboard.saveView(first)
        try await dashboard.saveView(second)
        try await dashboard.moveView(id: second.id, offset: -1)
        dashboard.selectSavedView(id: second.id)
        second.enabled = false
        try await dashboard.saveView(second)
        XCTAssertNil(dashboard.selectedSavedViewID)
        XCTAssertEqual(dashboard.selectedTab, .reviewRequested)
        let saved = try await SavedPRViewStore(directory: root).load()
        XCTAssertEqual(saved.map(\.name), ["Second", "First"])
        XCTAssertFalse(saved[0].enabled)
        try await dashboard.deleteView(id: first.id)
        let remaining = try await SavedPRViewStore(directory: root).load()
        XCTAssertEqual(remaining.map(\.name), ["Second"])
        let isolated = try await SavedPRViewStore(directory: root.appendingPathComponent("another-account")).load()
        XCTAssertTrue(isolated.isEmpty)
        await dashboard.retire()
    }
    @MainActor
    func testLoadedUnionDeduplicatesBadgeAndSavedViewAndExcludesSnoozed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PullRequestStore(directory: root)
        var preferences = AppSettings.default
        preferences.refreshOnLaunch = false
        preferences.refreshInterval = 0
        try await store.save(settings: preferences)
        try await store.saveOverride(.init(snoozedUntil: Date().addingTimeInterval(3600)), for: "snoozed")
        let dashboard = DashboardViewModel(client: RepeatedPRClient(), store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while dashboard.viewerLogin.isEmpty { await Task.yield() }
        await dashboard.refreshAllLoaded()
        XCTAssertEqual(dashboard.badgeCount, 1)
        XCTAssertEqual(dashboard.listStates[.mine]?.rawItems.count, 2)
        let view = SavedPRView(name: "Everything")
        try await dashboard.saveView(view)
        dashboard.selectSavedView(id: view.id)
        XCTAssertEqual(dashboard.currentItems.count, 2)
        XCTAssertEqual(dashboard.actionableCount(for: view), 1)
        dashboard.filterState.searchText = "not found"
        dashboard.filtersDidChange()
        XCTAssertTrue(dashboard.currentItems.isEmpty)
        XCTAssertEqual(dashboard.badgeCount, 1)
        await dashboard.retire()
    }
    func testRulesComposeAndRepositoryMatchingIsExactAndCaseInsensitive() throws {
        let pr = PullRequest(id: "1", number: 1, title: "Fix token", url: URL(string: "https://github.com/a/b/pull/1")!, repository: .init(nameWithOwner: "A/B"), author: .init(login: "Alice"), createdAt: Date(), updatedAt: Date(), isDraft: true, override: .init(state: .todo))
        let presentation = PullRequestPresentation(pullRequest: pr, status: PullRequestStatusCalculator(currentUserLogin: "alice").status(for: pr))
        for (rule, expected) in [(SavedPRStateRule.any, true), (.authored, true), (.draft, true), (.todo, true), (.changesRequested, false), (.awaitingReview, false)] {
            var view = SavedPRView(name: "Work", repositories: ["a/b"], stateRule: rule, text: "TOKEN")
            XCTAssertEqual(SavedPRViewMatcher.matches(presentation, view: view, viewerLogin: "alice"), expected)
            view.repositories = ["a/b-extra"]
            XCTAssertFalse(SavedPRViewMatcher.matches(presentation, view: view, viewerLogin: "alice"))
        }
    }

    func testValidationRejectsDuplicateAndBlankNamesWithoutOverwritingStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedPRViewStore(directory: root)
        try await store.save([SavedPRView(name: "Work")])
        do { try await store.save([SavedPRView(name: "Work"), SavedPRView(name: " work ")]); XCTFail("Duplicate") } catch {}
        do { try await store.save([SavedPRView(name: " ")]); XCTFail("Blank") } catch {}
        do { try await store.save([SavedPRView(name: String(repeating: "x", count: 41))]); XCTFail("Too long") } catch {}
        let restored = try await store.load()
        XCTAssertEqual(restored.map(\.name), ["Work"])
    }

    func testMissingStoreIsEmptyAndCorruptionIsPreserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedPRViewStore(directory: root)
        let empty = try await store.load()
        XCTAssertTrue(empty.isEmpty)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("saved-views.json")
        try Data("broken".utf8).write(to: file)
        do { _ = try await store.load(); XCTFail("Corrupt") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
    }
}

private struct RepeatedPRClient: GitHubClient {
    nonisolated(nonsending) func fetchViewer() async throws -> String { "alice" }
    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        let item = PullRequest(id: "shared", number: 1, title: "Shared PR", url: URL(string: "https://github.com/a/b/pull/1")!, repository: .init(nameWithOwner: "a/b"), author: .init(login: "bob"), createdAt: Date(), updatedAt: Date(), isDraft: false, detail: .init(mergeable: .mergeable, reviewDecision: .approved, ci: .init(headSHA: "head", revision: "head", checks: []), mergeStateStatus: "CLEAN"))
        var snoozed = item
        snoozed.id = "snoozed"
        return PullRequestPage(items: [item, item, snoozed], cursor: nil, hasNextPage: false)
    }
}
