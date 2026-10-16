import Foundation

struct AccountProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var githubUserID: String
    var login: String
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
