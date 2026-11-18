import Foundation

struct AccountProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var githubUserID: String
    var login: String
    var server: GitHubServer = .dotCom
    var identityKey: String { "\(server.webURL.absoluteString)|\(githubUserID)" }
    var displayName: String { server.isDotCom ? login : "\(login) · \(server.label)" }

    init(id: UUID = UUID(), githubUserID: String, login: String, server: GitHubServer = .dotCom) {
        self.id = id; self.githubUserID = githubUserID; self.login = login; self.server = server
    }
    private enum CodingKeys: String, CodingKey { case id, githubUserID, login, server }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        githubUserID = try values.decode(String.self, forKey: .githubUserID)
        login = try values.decode(String.self, forKey: .login)
        server = values.contains(.server) ? try values.decode(GitHubServer.self, forKey: .server) : .dotCom
    }
}

struct AccountRegistrySnapshot: Codable, Equatable, Sendable {
    var profiles: [AccountProfile] = []
    var activeProfileID: UUID?
    var migrationComplete = false
    var pendingRemovalIDs: [UUID]?
    var migrationProfileID: UUID?
}

enum ProfileCredentialKey {
    static func account(for profileID: UUID?) -> String {
        profileID.map { "github-profile:\($0.uuidString)" } ?? "github-token"
    }
}
