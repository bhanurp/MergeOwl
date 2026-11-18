import XCTest
@testable import PRPulseApp

final class GitHubServerTests: XCTestCase {
    func testCanonicalEnterpriseEndpointsAndUnsafeInput() throws {
        let server = try GitHubServer("https://GIT.Example.test:8443/")
        XCTAssertEqual(server.webURL.absoluteString, "https://git.example.test:8443")
        XCTAssertEqual(server.restURL("user").absoluteString, "https://git.example.test:8443/api/v3/user")
        XCTAssertEqual(server.graphQLURL.absoluteString, "https://git.example.test:8443/api/graphql")
        XCTAssertEqual(try GitHubServer("https://github.com/").graphQLURL.absoluteString, "https://api.github.com/graphql")
        for invalid in ["http://git.example.test", "https://user:secret@git.example.test", "https://git.example.test/api/v3", "https://git.example.test?q=1", "https://git.example.test#token", ""] {
            XCTAssertThrowsError(try GitHubServer(invalid), invalid)
        }
    }
    func testCredentialRedirectsCannotLeaveOriginOrDowngrade() {
        let origin = URL(string: "https://enterprise.example.test/api/graphql")!
        XCTAssertTrue(GitHubRedirectPolicy.permits(original: origin, target: URL(string: "https://enterprise.example.test/api/other")!))
        for target in ["https://github.com/api/graphql", "http://enterprise.example.test/api/graphql", "https://enterprise.example.test:8443/api/graphql"] {
            XCTAssertFalse(GitHubRedirectPolicy.permits(original: origin, target: URL(string: target)!))
        }
    }
    func testLegacyProfileDefaultsToGitHubDotCom() throws {
        let data = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"githubUserID\":\"42\",\"login\":\"octocat\"}".utf8)
        let profile = try JSONDecoder().decode(AccountProfile.self, from: data)
        XCTAssertEqual(profile.server, .dotCom)
        let enterprise = AccountProfile(githubUserID: "42", login: "octocat", server: try GitHubServer("https://git.example.test"))
        XCTAssertNotEqual(profile.identityKey, enterprise.identityKey)
        XCTAssertEqual(try JSONDecoder().decode(AccountProfile.self, from: JSONEncoder().encode(enterprise)), enterprise)
    }
}

extension GitHubServerTests {
    @MainActor
    func testSameUserIDOnDifferentServersCreatesSeparateProfilesAndPersists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let enterprise = try GitHubServer("https://git.example.test")
        let coordinator = AccountSessionCoordinator(directory: root, credentials: MemoryCredentials(),
            validate: { _ in .init(id: "42", login: "octocat") },
            validateServer: { _, server in
                XCTAssertEqual(server, enterprise)
                return .init(id: "42", login: "octocat")
            }, makeClient: { _, _ in MockGitHubClient() })
        await coordinator.start()
        try await coordinator.connect(token: "cloud-fixture", replacing: nil)
        try await coordinator.connect(token: "enterprise-fixture", replacing: nil, server: enterprise)
        XCTAssertEqual(coordinator.profiles.count, 2)
        XCTAssertEqual(Set(coordinator.profiles.map(\.identityKey)).count, 2)
        let snapshot = try await AccountRegistry(directory: root).load()
        XCTAssertEqual(snapshot.profiles.count, 2)
        let profile = try XCTUnwrap(snapshot.profiles.first { $0.server == enterprise })
        do {
            try await coordinator.connect(token: "wrong-host-fixture", replacing: profile.id, server: .dotCom)
            XCTFail("Changing a profile's server must require adding another account")
        } catch {}
        await coordinator.dashboard.retire()
    }
}

extension GitHubServerTests {
    func testEnterpriseValidationRoutesBothIdentityRequestsToItsServer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EnterpriseIdentityProtocol.self]
        let server = try GitHubServer("https://enterprise.example.test:8443")
        let identity = try await GitHubAccountValidator.validate(token: "synthetic-ghes", server: server,
                                                               session: URLSession(configuration: config))
        XCTAssertEqual(identity.id, "42")
        XCTAssertEqual(identity.login, "octocat")
    }
}

private final class EnterpriseIdentityProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "enterprise.example.test", request.url?.port == 8443,
              request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-ghes",
              request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == nil,
              ["/api/v3/user", "/api/graphql"].contains(request.url?.path ?? "") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let body = request.url!.path == "/api/v3/user" ? "{\"id\":42,\"login\":\"octocat\"}"
            : "{\"data\":{\"viewer\":{\"login\":\"octocat\"}}}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["X-GitHub-Enterprise-Version": "3.99.0"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension GitHubServerTests {
    @MainActor
    func testEnterpriseFirstDoesNotStrandLegacyCloudDataOrReplaceActiveToken() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PullRequestStore(directory: root)
        try await store.saveOverride(.init(state: .todo), for: "legacy-PR")
        let credentials = MemoryCredentials()
        try credentials.write("expired-fixture", profileID: nil)
        var tokenUsed: String?
        let coordinator = AccountSessionCoordinator(directory: root, credentials: credentials,
            validate: { token in
                if token == "expired-fixture" { throw GitHubClientError.missingToken }
                return .init(id: "42", login: "cloud")
            }, validateServer: { _, _ in .init(id: "42", login: "enterprise") },
            makeClient: { _, token in tokenUsed = token; return MockGitHubClient() })
        await coordinator.start()
        let enterprise = try GitHubServer("https://enterprise.example.test")
        try await coordinator.connect(token: "enterprise-fixture", replacing: nil, server: enterprise)
        let enterpriseID = coordinator.activeProfileID
        try await coordinator.connect(token: "cloud-fixture", replacing: nil)
        let cloud = try XCTUnwrap(coordinator.profiles.first { $0.server.isDotCom })
        let migrated = PullRequestStore(directory: root.appendingPathComponent("profiles/\(cloud.id.uuidString)"))
        let mark = await migrated.override(for: "legacy-PR")
        XCTAssertEqual(mark.state, .todo)
        XCTAssertEqual(coordinator.activeProfileID, enterpriseID)
        XCTAssertEqual(tokenUsed, "enterprise-fixture")
        XCTAssertEqual(coordinator.profiles.count, 2)
        await coordinator.dashboard.retire()
    }
}

extension GitHubServerTests {
    @MainActor
    func testReconnectReturnsTheUpdatedProfileRatherThanLastProfileOnServer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = AccountSessionCoordinator(directory: root, credentials: MemoryCredentials(),
            validateServer: { token, _ in .init(id: token, login: token) },
            makeClient: { _, _ in MockGitHubClient() })
        await coordinator.start()
        let server = try GitHubServer("https://enterprise.example.test")
        let first = try await coordinator.connect(token: "first-fixture", replacing: nil, server: server)
        let second = try await coordinator.connect(token: "second-fixture", replacing: nil, server: server)
        let reconnected = try await coordinator.connect(token: "first-fixture", replacing: nil, server: server)
        XCTAssertEqual(first, reconnected)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(coordinator.profiles.count, 2)
        await coordinator.dashboard.retire()
    }
}

extension GitHubServerTests {
    @MainActor
    func testStartupCleanupFailureNeverActivatesEnterpriseWithNewCloudToken() async throws {
        for migrationComplete in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let credentials = RemovalBlockedCredentials()
            let server = try GitHubServer("https://enterprise.example.test")
            let active = AccountProfile(githubUserID: "1", login: "enterprise", server: server)
            let removing = AccountProfile(githubUserID: "2", login: "removing", server: server)
            try credentials.write("enterprise-fixture", profileID: active.id)
            try await AccountRegistry(directory: root).save(.init(profiles: [active, removing], activeProfileID: active.id,
                migrationComplete: migrationComplete, pendingRemovalIDs: [removing.id]))
            var suppliedToken: String?
            let coordinator = AccountSessionCoordinator(directory: root, credentials: credentials,
                validate: { _ in .init(id: "42", login: "cloud") },
                makeClient: { _, token in suppliedToken = token; return MockGitHubClient() })
            await coordinator.start()
            XCTAssertNil(coordinator.activeProfileID)
            try await coordinator.connect(token: "new-cloud-fixture", replacing: nil)
            XCTAssertEqual(coordinator.activeProfileID, active.id)
            XCTAssertEqual(suppliedToken, "enterprise-fixture", "Never send the newly verified cloud token to an enterprise profile")
            await coordinator.dashboard.retire()
        }
    }
}

private final class RemovalBlockedCredentials: AccountCredentialStore, @unchecked Sendable {
    private let memory = MemoryCredentials()
    func read(profileID: UUID?) throws -> String? { try memory.read(profileID: profileID) }
    func write(_ token: String, profileID: UUID?) throws { try memory.write(token, profileID: profileID) }
    func remove(profileID: UUID?) throws { throw CocoaError(.fileWriteNoPermission) }
}
