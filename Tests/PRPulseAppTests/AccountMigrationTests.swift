import XCTest
@testable import PRPulseApp

final class AccountMigrationTests: XCTestCase {
    func testLockedKeychainPreservesRetryableMigrationIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = FailingCredentials()
        let migration = AccountMigration(directory: root, credentials: credentials)
        do { _ = try await migration.run(identity: .init(id: "1", login: "octocat"), profileID: UUID()); XCTFail("Locked") } catch {}
        let pending = try await AccountRegistry(directory: root).load()
        XCTAssertFalse(pending.migrationComplete)
        let retainedID = try XCTUnwrap(pending.migrationProfileID)
        credentials.failWrite = false
        let profile = try await migration.run(identity: .init(id: "1", login: "octocat"), profileID: UUID())
        XCTAssertEqual(profile.id, retainedID)
        XCTAssertEqual(try credentials.read(profileID: nil), "legacy")
    }
    func testMigrationCopiesDataAndPreservesLegacyFilesAndCredential() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = PullRequestStore(directory: root)
        try await old.saveOverride(PullRequestOverride(state: .todo), for: "PR1")
        let credentials = MemoryCredentials()
        try credentials.write("secret", profileID: nil)
        let migration = AccountMigration(directory: root, credentials: credentials)
        let profile = try await migration.run(identity: VerifiedGitHubIdentity(id: "1", login: "octocat"), profileID: UUID())
        let registry = try await AccountRegistry(directory: root).load()
        XCTAssertEqual(registry.profiles, [profile])
        XCTAssertTrue(registry.migrationComplete)
        XCTAssertEqual(try credentials.read(profileID: profile.id), "secret")
        XCTAssertEqual(try credentials.read(profileID: nil), "secret")
        let original = try Data(contentsOf: root.appendingPathComponent("overrides.json"))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("profiles/\(profile.id.uuidString)/overrides.json")), original)
        let retry = try await migration.run(identity: VerifiedGitHubIdentity(id: "1", login: "octocat"), profileID: UUID())
        XCTAssertEqual(retry.id, profile.id)
    }

    func testMalformedLegacyDataDoesNotPublishMigration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("overrides.json"))
        let credentials = MemoryCredentials()
        try credentials.write("secret", profileID: nil)
        do {
            _ = try await AccountMigration(directory: root, credentials: credentials).run(identity: .init(id: "1", login: "octocat"), profileID: UUID())
            XCTFail("Corrupt data must be reported")
        } catch {}
        let state = try await AccountRegistry(directory: root).load()
        XCTAssertFalse(state.migrationComplete)
        XCTAssertEqual(try credentials.read(profileID: nil), "secret")
    }
}

private final class FailingCredentials: AccountCredentialStore, @unchecked Sendable {
    var failWrite = true
    private let memory = MemoryCredentials()
    func read(profileID: UUID?) throws -> String? { profileID == nil ? "legacy" : try memory.read(profileID: profileID) }
    func write(_ token: String, profileID: UUID?) throws {
        if failWrite { throw CocoaError(.fileWriteNoPermission) }
        try memory.write(token, profileID: profileID)
    }
    func remove(profileID: UUID?) throws { try memory.remove(profileID: profileID) }
}

final class MemoryCredentials: AccountCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String] = [:]
    private var reads: [String: Int] = [:]
    func readCount(profileID: UUID?) -> Int {
        lock.lock(); defer { lock.unlock() }
        return reads[ProfileCredentialKey.account(for: profileID), default: 0]
    }
    func read(profileID: UUID?) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        reads[ProfileCredentialKey.account(for: profileID), default: 0] += 1
        return tokens[ProfileCredentialKey.account(for: profileID)]
    }
    func write(_ token: String, profileID: UUID?) throws {
        lock.lock(); defer { lock.unlock() }
        tokens[ProfileCredentialKey.account(for: profileID)] = token
    }
    func remove(profileID: UUID?) throws {
        lock.lock(); defer { lock.unlock() }
        tokens.removeValue(forKey: ProfileCredentialKey.account(for: profileID))
    }
}
