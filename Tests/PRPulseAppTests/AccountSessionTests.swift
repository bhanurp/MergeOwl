import XCTest
@testable import PRPulseApp

final class AccountSessionTests: XCTestCase {
    @MainActor
    func testSessionReadsKeychainOnceInsteadOfForEachRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = MemoryCredentials()
        var capturedToken: String?
        let coordinator = AccountSessionCoordinator(directory: root, credentials: credentials,
            validate: { token in .init(id: token, login: token) },
            makeClient: { _, token in capturedToken = token; return MockGitHubClient() })
        await coordinator.start()
        try await coordinator.connect(token: "alice", replacing: nil)
        try await coordinator.connect(token: "bob", replacing: nil)
        let bob = try XCTUnwrap(coordinator.profiles.first { $0.login == "bob" })
        let before = credentials.readCount(profileID: bob.id)
        try await coordinator.switchAccount(to: bob.id)
        XCTAssertEqual(credentials.readCount(profileID: bob.id), before + 1)
        XCTAssertEqual(capturedToken, "bob")
        await coordinator.dashboard.refreshAllLoaded()
        await coordinator.dashboard.refreshAllLoaded()
        XCTAssertEqual(credentials.readCount(profileID: bob.id), before + 1)
        await coordinator.dashboard.retire()
    }
    @MainActor
    func testRemovingLastProfileDoesNotDisplayLegacyBackupRepositories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = PullRequestStore(directory: root)
        var settings = AppSettings.default
        settings.watchedRepositories = [.init(nameWithOwner: "legacy/private", notificationsEnabled: true)]
        try await legacy.save(settings: settings)
        let credentials = MemoryCredentials()
        try credentials.write("fixture", profileID: nil)
        let coordinator = AccountSessionCoordinator(directory: root, credentials: credentials,
            validate: { _ in .init(id: "1", login: "alice") }, makeClient: { _, _ in MockGitHubClient() })
        await coordinator.start()
        let id = try XCTUnwrap(coordinator.activeProfileID)
        try await coordinator.removeAccount(id: id)
        while !coordinator.dashboard.isReady { await Task.yield() }
        XCTAssertTrue(coordinator.dashboard.settings.watchedRepositories.isEmpty)
        XCTAssertNil(coordinator.activeProfileID)
        await coordinator.dashboard.retire()
    }
    @MainActor
    func testPreferencesLoadWhileIdentityLookupIsPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PullRequestStore(directory: root)
        var preferences = AppSettings.default
        preferences.refreshInterval = 900
        preferences.refreshOnLaunch = false
        try await store.save(settings: preferences)
        let client = SuspendedViewer()
        let dashboard = DashboardViewModel(client: client, store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while client.continuation == nil { await Task.yield() }
        XCTAssertEqual(dashboard.settings.refreshInterval, 900)
        XCTAssertFalse(dashboard.settings.refreshOnLaunch)
        await dashboard.retire()
        client.continuation?.resume(returning: "alice")
    }
    @MainActor
    func testAccountRoundTripDiscardsOldPagesAndTheirActivity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = AccountProfile(id: UUID(), githubUserID: "1", login: "alice")
        let b = AccountProfile(id: UUID(), githubUserID: "2", login: "bob")
        try await AccountRegistry(directory: root).save(.init(profiles: [a,b], activeProfileID: a.id, migrationComplete: true))
        var gates: [PageGate] = []
        let coordinator = AccountSessionCoordinator(directory: root, credentials: MemoryCredentials(), makeClient: { id, _ in
            guard id != nil else { return MockGitHubClient() }
            let gate = PageGate(login: id == a.id ? "alice" : "bob")
            gates.append(gate)
            return gate
        })
        await coordinator.start()
        while gates[0].continuation == nil { await Task.yield() }
        let oldDashboard = coordinator.dashboard
        try await coordinator.switchAccount(to: b.id)
        while gates[1].continuation == nil { await Task.yield() }
        try await coordinator.switchAccount(to: a.id)
        while gates[2].continuation == nil { await Task.yield() }
        let item = PullRequest(id: "late", number: 1, title: "Wrong session", url: URL(string: "https://github.com/a/b/pull/1")!, repository: .init(nameWithOwner: "a/b"), author: .init(login: "alice"), createdAt: Date(), updatedAt: Date(), isDraft: false)
        gates[0].continuation?.resume(returning: .init(items: [item], cursor: "late", hasNextPage: true))
        gates[1].continuation?.resume(throwing: GitHubClientError.missingToken)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(coordinator.dashboard.currentItems.isEmpty)
        XCTAssertTrue(coordinator.dashboard.connectionErrors.isEmpty)
        XCTAssertTrue(oldDashboard.currentItems.isEmpty)
        XCTAssertEqual(coordinator.dashboard.badgeCount, 0)
        gates[2].continuation?.resume(returning: .init(items: [], cursor: nil, hasNextPage: false))
        await coordinator.dashboard.retire()
    }
    @MainActor
    func testAddingDuplicateIdentityUpdatesTokenWithoutSwitchingOrDuplicating() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = MemoryCredentials()
        let coordinator = AccountSessionCoordinator(directory: root, credentials: credentials,
            validate: { token in .init(id: token.hasPrefix("a") ? "1" : "2", login: token.hasPrefix("a") ? "alice" : "bob") },
            makeClient: { _, _ in MockGitHubClient() })
        await coordinator.start()
        try await coordinator.connect(token: "a", replacing: nil)
        let first = try XCTUnwrap(coordinator.activeProfileID)
        try await coordinator.connect(token: "b", replacing: nil)
        XCTAssertEqual(coordinator.activeProfileID, first)
        try await coordinator.connect(token: "a-new", replacing: nil)
        XCTAssertEqual(coordinator.profiles.count, 2)
        XCTAssertEqual(try credentials.read(profileID: first), "a-new")
        do { try await coordinator.connect(token: "b", replacing: first); XCTFail("Identity mismatch must fail") } catch {}
        XCTAssertEqual(try credentials.read(profileID: first), "a-new")
        let second = coordinator.profiles[1].id
        try await coordinator.switchAccount(to: second)
        let restored = try await AccountRegistry(directory: root).load()
        XCTAssertEqual(restored.activeProfileID, second)
        try await coordinator.removeAccount(id: second)
        XCTAssertEqual(coordinator.activeProfileID, first)
        XCTAssertNil(try credentials.read(profileID: second))
        await coordinator.dashboard.retire()
    }
    @MainActor
    func testRetiredDashboardRejectsLateViewerResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = SuspendedViewer()
        let store = PullRequestStore(directory: root)
        let dashboard = DashboardViewModel(client: client, store: store, notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        while client.continuation == nil { await Task.yield() }
        await dashboard.retire()
        client.continuation?.resume(returning: "old-account")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(dashboard.viewerLogin, "")
        XCTAssertEqual(dashboard.badgeCount, 0)
        XCTAssertEqual(dashboard.connectionPresentation, .checking)
    }

    func testCredentialReplacementAndRemovalAreProfileScoped() throws {
        let credentials = MemoryCredentials()
        let a = UUID(), b = UUID()
        try credentials.write("legacy", profileID: nil)
        try credentials.write("a", profileID: a)
        try credentials.write("b", profileID: b)
        try credentials.write("new-a", profileID: a)
        XCTAssertEqual(try credentials.read(profileID: a), "new-a")
        try credentials.remove(profileID: a)
        XCTAssertNil(try credentials.read(profileID: a))
        XCTAssertEqual(try credentials.read(profileID: b), "b")
        XCTAssertEqual(try credentials.read(profileID: nil), "legacy")
    }
}

@MainActor
private final class PageGate: GitHubClient {
    let login: String
    var continuation: CheckedContinuation<PullRequestPage, Error>?
    init(login: String) { self.login = login }
    nonisolated(nonsending) func fetchViewer() async throws -> String { await MainActor.run { self.login } }
    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        try await withCheckedThrowingContinuation { value in Task { @MainActor in self.continuation = value } }
    }
}

@MainActor
private final class SuspendedViewer: GitHubClient {
    var continuation: CheckedContinuation<String, Error>?
    nonisolated(nonsending) func fetchViewer() async throws -> String {
        try await withCheckedThrowingContinuation { value in
            Task { @MainActor in self.continuation = value }
        }
    }
    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        PullRequestPage(items: [], cursor: nil, hasNextPage: false)
    }
}
