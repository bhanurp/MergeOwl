import Foundation

protocol AccountCredentialStore: Sendable {
    func read(profileID: UUID?) throws -> String?
    func write(_ token: String, profileID: UUID?) throws
    func remove(profileID: UUID?) throws
}

struct KeychainAccountCredentials: AccountCredentialStore {
    var service: String?
    func read(profileID: UUID?) throws -> String? {
        try store(profileID).readToken()
    }
    func write(_ token: String, profileID: UUID?) throws { try store(profileID).setToken(token) }
    func remove(profileID: UUID?) throws { try store(profileID).clearToken() }
    private func store(_ id: UUID?) -> KeychainTokenStore {
        KeychainTokenStore(service: service, account: ProfileCredentialKey.account(for: id))
    }
}

struct VerifiedGitHubIdentity: Equatable, Sendable {
    var id: String
    var login: String
}
