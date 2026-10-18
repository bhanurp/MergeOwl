import XCTest
@testable import PRPulseApp

final class PopoverLayoutTests: XCTestCase {
    func testOlderSharedPreferencesDefaultToTabbedWithoutLosingOtherSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GlobalPreferencesStore(directory: root)
        var settings = AppSettings.default
        settings.refreshInterval = 900
        try await store.save(settings)
        let file = root.appendingPathComponent("preferences.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json.removeValue(forKey: "popoverLayout")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let restored = try await GlobalPreferencesStore(directory: root).load()
        XCTAssertEqual(restored.popoverLayout, .tabbed)
        XCTAssertEqual(restored.refreshInterval, 900)
    }

    func testLayoutPersistsAcrossStoresAndAccountsWithoutCopyingRepositories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let global = GlobalPreferencesStore(directory: root)
        let a = PullRequestStore(directory: root.appendingPathComponent("a"), globalPreferences: global)
        let b = PullRequestStore(directory: root.appendingPathComponent("b"), globalPreferences: global)
        var settings = await a.loadSettings()
        try await a.savePopoverLayout(.compact)
        settings.popoverLayout = .compact
        settings.watchedRepositories = [.init(nameWithOwner: "a/private", notificationsEnabled: true)]
        try await a.save(settings: settings)
        let loaded = await b.loadSettings()
        XCTAssertEqual(loaded.popoverLayout, .compact)
        XCTAssertTrue(loaded.watchedRepositories.isEmpty)
        let relaunched = try await GlobalPreferencesStore(directory: root).load()
        XCTAssertEqual(relaunched.popoverLayout, .compact)
        var next = loaded
        try await b.savePopoverLayout(.tabbed)
        next.popoverLayout = .tabbed
        try await b.save(settings: next)
        let updated = await a.loadSettings()
        XCTAssertEqual(updated.popoverLayout, .tabbed)
        XCTAssertEqual(updated.watchedRepositories.first?.nameWithOwner, "a/private")
    }

    func testLegacySettingsAndUnknownLayoutFallBackToTabbed() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.default)) as? [String: Any])
        json.removeValue(forKey: "popoverLayout")
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json)).popoverLayout, .tabbed)
        json["popoverLayout"] = "future-layout"
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json)).popoverLayout, .tabbed)
    }

    func testStaleGeneralSettingsSaveCannotUndoLayoutChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let global = GlobalPreferencesStore(directory: root)
        let store = PullRequestStore(directory: root.appendingPathComponent("profile"), globalPreferences: global)
        var stale = await store.loadSettings()
        stale.refreshInterval = 900
        try await store.savePopoverLayout(.compact)
        try await store.save(settings: stale)
        let restored = try await global.load()
        XCTAssertEqual(restored.popoverLayout, .compact)
        XCTAssertEqual(restored.refreshInterval, 900)
    }

    @MainActor
    func testLayoutWriteDoesNotTouchReadOnlyAccountRepositoryData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = root.appendingPathComponent("profile")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let repositoryFile = profile.appendingPathComponent("repositories.json")
        try Data("corrupt account repository data".utf8).write(to: repositoryFile)
        let global = GlobalPreferencesStore(directory: root)
        let store = PullRequestStore(directory: profile, globalPreferences: global)
        let dashboard = DashboardViewModel(client: MockGitHubClient(), store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while !dashboard.isReady { await Task.yield() }
        await dashboard.changePopoverLayout(to: .compact)
        XCTAssertEqual(dashboard.settings.popoverLayout, .compact)
        let restored = try await global.load()
        XCTAssertEqual(restored.popoverLayout, .compact)
        XCTAssertEqual(try String(contentsOf: repositoryFile, encoding: .utf8), "corrupt account repository data")
        await dashboard.retire()
    }

    @MainActor
    func testFailedLayoutWriteDoesNotClaimPreferenceChanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        let store = PullRequestStore(directory: root)
        let dashboard = DashboardViewModel(client: MockGitHubClient(), store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while !dashboard.isReady { await Task.yield() }
        await dashboard.changePopoverLayout(to: .compact)
        XCTAssertEqual(dashboard.settings.popoverLayout, .tabbed)
        XCTAssertNotNil(dashboard.errorMessage)
        XCTAssertFalse(dashboard.isChangingLayout)
        await dashboard.retire()
    }

    @MainActor
    func testChangingLayoutPreservesSelectedViewSearchAndFiltersAndPersistsBeforeReturning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PullRequestStore(directory: root)
        let dashboard = DashboardViewModel(client: MockGitHubClient(), store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while !dashboard.isReady { await Task.yield() }
        let view = SavedPRView(name: "API work", text: "API")
        try await dashboard.saveView(view)
        dashboard.selectSavedView(id: view.id)
        dashboard.filterState.searchText = "token"
        dashboard.filterState.hideReviewed = true
        await dashboard.changePopoverLayout(to: .compact)
        XCTAssertEqual(dashboard.selectedSavedViewID, view.id)
        XCTAssertEqual(dashboard.filterState.searchText, "token")
        XCTAssertTrue(dashboard.filterState.hideReviewed)
        let loaded = await store.loadSettings()
        XCTAssertEqual(loaded.popoverLayout, .compact)
        XCTAssertEqual(dashboard.settings.popoverLayout, .compact)
        await dashboard.retire()
    }
}
