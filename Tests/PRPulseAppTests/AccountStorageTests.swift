import XCTest
@testable import PRPulseApp

final class AccountStorageTests: XCTestCase {
    func testSynchronousSessionInvalidationRejectsQueuedWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PullRequestStore(directory: root)
        store.lifetime.invalidate()
        do { try await store.saveOverride(.init(state: .todo), for: "late"); XCTFail("Retired write") } catch {}
        let value = await store.override(for: "late")
        XCTAssertEqual(value.state, .none)
    }
    func testRegistryRejectsDuplicateIdentityAndDoesNotOverwriteCorruptData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry(directory: root)
        let first = AccountProfile(id: UUID(), githubUserID: "1", login: "alice")
        let second = AccountProfile(id: UUID(), githubUserID: "1", login: "alice")
        do { try await registry.save(.init(profiles: [first, second], migrationComplete: true)); XCTFail("Duplicate identity") } catch {}
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("accounts.json")
        try Data("broken".utf8).write(to: file)
        do { try await registry.save(.init()); XCTFail("Preserve corruption") } catch {}
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
    }
    func testFailedOverrideWriteDoesNotChangeInMemoryTriage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PullRequestStore(directory: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("overrides.json"), withIntermediateDirectories: true)
        do { try await store.saveOverride(.init(state: .todo), for: "1"); XCTFail("Write must fail") } catch {}
        let value = await store.override(for: "1")
        XCTAssertEqual(value.state, .none)
    }
    func testRealKeychainProfileReplacementDoesNotChangeOtherItems() throws {
        let service = "dev.prpulse.unit.\(UUID().uuidString)"
        let credentials = KeychainAccountCredentials(service: service)
        let a = UUID(), b = UUID()
        defer { try? credentials.remove(profileID: a); try? credentials.remove(profileID: b); try? credentials.remove(profileID: nil) }
        try credentials.write("legacy-fixture", profileID: nil)
        try credentials.write("a-fixture", profileID: a)
        try credentials.write("b-fixture", profileID: b)
        XCTAssertEqual(try credentials.read(profileID: a), "a-fixture")
        try credentials.write("new-a-fixture", profileID: a)
        XCTAssertEqual(try credentials.read(profileID: a), "new-a-fixture")
        try credentials.remove(profileID: a)
        XCTAssertNil(try credentials.read(profileID: a))
        XCTAssertEqual(try credentials.read(profileID: b), "b-fixture")
        XCTAssertEqual(try credentials.read(profileID: nil), "legacy-fixture")
    }
    func testGlobalPreferencesShareRefreshButNotRepositories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let global = GlobalPreferencesStore(directory: root)
        let a = PullRequestStore(directory: root.appendingPathComponent("a"), globalPreferences: global)
        let b = PullRequestStore(directory: root.appendingPathComponent("b"), globalPreferences: global)
        var settings = AppSettings.default
        settings.refreshInterval = 900
        settings.watchedRepositories = [RepositorySubscription(nameWithOwner: "a/repo", notificationsEnabled: true)]
        try await a.save(settings: settings)
        let loaded = await b.loadSettings()
        XCTAssertEqual(loaded.refreshInterval, 900)
        XCTAssertTrue(loaded.watchedRepositories.isEmpty)
        let aLoaded = await a.loadSettings()
        XCTAssertEqual(aLoaded.watchedRepositories.first?.nameWithOwner, "a/repo")
        let publicData = try String(contentsOf: root.appendingPathComponent("preferences.json"), encoding: .utf8)
        XCTAssertFalse(publicData.contains("token"))
        XCTAssertFalse(publicData.contains("watchedRepositories"))
    }
    func testRegistryRoundTripAndActiveSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = AccountRegistry(directory: root)
        let a = AccountProfile(id: UUID(), githubUserID: "1", login: "octocat")
        let b = AccountProfile(id: UUID(), githubUserID: "2", login: "hubot")
        try await registry.save(AccountRegistrySnapshot(profiles: [a, b], activeProfileID: b.id, migrationComplete: true))
        let restored = try await AccountRegistry(directory: root).load()
        XCTAssertEqual(restored.profiles, [a, b])
        XCTAssertEqual(restored.activeProfileID, b.id)
        let publicData = try String(contentsOf: root.appendingPathComponent("accounts.json"), encoding: .utf8)
        XCTAssertFalse(publicData.contains("token"))
    }

    func testCorruptRegistryIsNotOverwrittenWithDefaults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("accounts.json")
        try Data("broken".utf8).write(to: file)
        do { _ = try await AccountRegistry(directory: root).load(); XCTFail("Must report corruption") }
        catch { XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8)) }
    }

    func testProfileCredentialKeysCannotCollideWithEachOtherOrLegacy() {
        let a = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let b = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        XCTAssertEqual(ProfileCredentialKey.account(for: nil), "github-token")
        XCTAssertEqual(ProfileCredentialKey.account(for: a), "github-profile:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        XCTAssertNotEqual(ProfileCredentialKey.account(for: a), ProfileCredentialKey.account(for: b))
    }
}
