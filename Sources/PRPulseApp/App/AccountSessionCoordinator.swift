import Foundation

@MainActor
final class AccountSessionCoordinator: ObservableObject {
    @Published private(set) var profiles: [AccountProfile] = []
    @Published private(set) var activeProfileID: UUID?
    @Published private(set) var dashboard: DashboardViewModel
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var addingAccountRequested = false
    private let directory: URL
    private let credentials: any AccountCredentialStore
    private let registry: AccountRegistry
    private let globalPreferences: GlobalPreferencesStore
    private let validate: (String) async throws -> VerifiedGitHubIdentity
    private let makeClient: ((UUID?, String?) -> any GitHubClient)?
    private let removeNotifications: (UUID) async -> Void
    private var snapshot = AccountRegistrySnapshot()
    private var started = false
    private var storageReady = false

    init(directory: URL, credentials: any AccountCredentialStore = KeychainAccountCredentials(),
         validate: @escaping (String) async throws -> VerifiedGitHubIdentity = GitHubAccountValidator.validate,
         makeClient: ((UUID?, String?) -> any GitHubClient)? = nil,
         removeNotifications: @escaping (UUID) async -> Void = { await ProfileNotificationCleanup.remove(profileID: $0) }) {
        self.directory = directory
        self.credentials = credentials
        self.registry = AccountRegistry(directory: directory)
        let global = GlobalPreferencesStore(directory: directory)
        self.globalPreferences = global
        self.validate = validate
        self.makeClient = makeClient
        self.removeNotifications = removeNotifications
        self.dashboard = Self.makeDashboard(directory: directory, id: nil, cachedToken: nil, client: makeClient?(nil, nil), globalPreferences: global, allowLegacy: false)
    }

    func start() async {
        guard !started else { return }
        started = true
        isWorking = true
        defer { isWorking = false }
        do {
            snapshot = try await registry.load()
            storageReady = true
            profiles = snapshot.profiles
            if profiles.isEmpty, !snapshot.migrationComplete, let token = try credentials.read(profileID: nil) {
                let identity = try await validate(token)
                _ = try await AccountMigration(directory: directory, credentials: credentials).run(identity: identity, profileID: UUID())
                snapshot = try await registry.load()
                profiles = snapshot.profiles
            }
            // Recover interrupted removals without ever deleting another profile's data.
            for id in snapshot.pendingRemovalIDs ?? [] {
                try await finishRemoval(id)
            }
            let selected = profiles.first { $0.id == snapshot.activeProfileID } ?? profiles.first
            await activate(selected?.id, restoreSavedSelection: true)
        } catch {
            if storageReady, profiles.isEmpty, !snapshot.migrationComplete { await activate(nil) }
            errorMessage = "Account setup could not finish. Your existing data has been preserved. Retry after checking GitHub and Keychain access."
        }
    }

    func retrySetup() async {
        guard !isWorking else { return }
        started = false
        errorMessage = nil
        await start()
    }

    func connect(token: String, replacing id: UUID?) async throws {
        guard storageReady, !isWorking else { throw GitHubClientError.apiFailure("Account storage is not ready. Please reopen the app and retry.") }
        isWorking = true
        defer { isWorking = false }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GitHubClientError.missingToken }
        let identity = try await validate(token)
        if profiles.isEmpty, !snapshot.migrationComplete {
            _ = try await AccountMigration(directory: directory, credentials: credentials).run(identity: identity, profileID: UUID(), token: token)
            snapshot = try await registry.load()
            profiles = snapshot.profiles
            await activate(snapshot.activeProfileID, knownToken: token)
            errorMessage = nil
            return
        }
        if let id {
            guard let existing = profiles.first(where: { $0.id == id }), existing.githubUserID == identity.id else {
                throw GitHubClientError.apiFailure("This token belongs to a different GitHub account. Use Add account instead.")
            }
        }
        let existing = profiles.first { $0.githubUserID == identity.id }
        let profile = AccountProfile(id: existing?.id ?? UUID(), githubUserID: identity.id, login: identity.login)
        let previousToken = try credentials.read(profileID: profile.id)
        try credentials.write(token, profileID: profile.id)
        var next = snapshot
        if let index = next.profiles.firstIndex(where: { $0.id == profile.id }) { next.profiles[index] = profile }
        else { next.profiles.append(profile) }
        next.activeProfileID = next.activeProfileID ?? profile.id
        next.migrationComplete = true
        do { try await registry.save(next) }
        catch {
            if let previousToken { try? credentials.write(previousToken, profileID: profile.id) }
            else { try? credentials.remove(profileID: profile.id) }
            throw error
        }
        snapshot = next
        profiles = next.profiles
        if activeProfileID == nil || activeProfileID == profile.id { await activate(next.activeProfileID, restoreSavedSelection: true, knownToken: token) }
        errorMessage = nil
    }

    func testConnection(token: String?, profileID: UUID?) async throws -> String {
        let candidate = try token ?? credentials.read(profileID: profileID)
        guard let candidate, !candidate.isEmpty else { throw GitHubClientError.missingToken }
        return try await validate(candidate).login
    }

    func switchAccount(to id: UUID) async throws {
        guard !isWorking, profiles.contains(where: { $0.id == id }) else { return }
        isWorking = true
        defer { isWorking = false }
        var next = snapshot
        next.activeProfileID = id
        try await registry.save(next)
        snapshot = next
        await activate(id)
    }

    func removeAccount(id: UUID) async throws {
        guard !isWorking, profiles.contains(where: { $0.id == id }) else { return }
        isWorking = true
        defer { isWorking = false }
        var next = snapshot
        next.pendingRemovalIDs = Array(Set((next.pendingRemovalIDs ?? []) + [id]))
        try await registry.save(next)
        snapshot = next
        try await finishRemoval(id)
        if activeProfileID == id { await activate(snapshot.activeProfileID) }
    }

    private func finishRemoval(_ id: UUID) async throws {
        guard snapshot.profiles.contains(where: { $0.id == id }) else { return }
        // Credential failure leaves the profile visible and the tombstone retryable.
        try credentials.remove(profileID: id)
        if activeProfileID == id { await dashboard.retire() }
        await removeNotifications(id)
        let target = directory.appendingPathComponent("profiles/\(id.uuidString)")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        var next = snapshot
        next.profiles.removeAll { $0.id == id }
        next.pendingRemovalIDs?.removeAll { $0 == id }
        if next.activeProfileID == id { next.activeProfileID = next.profiles.first?.id }
        try await registry.save(next)
        snapshot = next
        profiles = next.profiles
    }

    private func activate(_ id: UUID?, restoreSavedSelection: Bool = false, knownToken: String? = nil) async {
        let tab = dashboard.selectedTab
        await dashboard.retire()
        activeProfileID = id
        errorMessage = nil
        let cachedToken: String?
        do {
            cachedToken = (id != nil || !snapshot.migrationComplete) ? try knownToken ?? credentials.read(profileID: id) : nil
        } catch {
            cachedToken = nil
            errorMessage = "Could not read the saved token from Keychain. Unlock your login Keychain or allow access, then retry account setup."
        }
        dashboard = Self.makeDashboard(directory: directory, id: id, cachedToken: cachedToken, client: makeClient?(id, cachedToken), globalPreferences: globalPreferences,
                                       allowLegacy: !snapshot.migrationComplete, restoreSavedSelection: restoreSavedSelection)
        dashboard.selectedTab = tab
    }

    private static func makeDashboard(directory: URL, id: UUID?, cachedToken: String?,
                                      client: (any GitHubClient)?, globalPreferences: GlobalPreferencesStore, allowLegacy: Bool = true, restoreSavedSelection: Bool = false) -> DashboardViewModel {
        let path = id.map { directory.appendingPathComponent("profiles/\($0.uuidString)") }
            ?? (allowLegacy ? directory : directory.appendingPathComponent("onboarding"))
        let store = PullRequestStore(directory: path, globalPreferences: globalPreferences)
        let api = client ?? GitHubAPIClient(tokenProvider: { cachedToken },
                                            watchedRepositoriesProvider: { await store.loadSettings().watchedRepositories })
        return DashboardViewModel(client: api, store: store, notifier: NotificationDispatcher(store: store, namespace: id?.uuidString ?? "legacy"), scheduler: RefreshScheduler(), digestComputer: DigestComputer(), restoreSavedSelection: restoreSavedSelection)
    }
}
