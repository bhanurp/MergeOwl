import Foundation

actor AccountMigration {
    let directory: URL
    let credentials: any AccountCredentialStore

    init(directory: URL, credentials: any AccountCredentialStore) {
        self.directory = directory
        self.credentials = credentials
    }

    func run(identity: VerifiedGitHubIdentity, profileID: UUID, token verifiedToken: String? = nil) async throws -> AccountProfile {
        let registry = AccountRegistry(directory: directory)
        var snapshot = try await registry.load()
        if let existing = snapshot.profiles.first(where: { $0.githubUserID == identity.id }) { return existing }
        guard !snapshot.migrationComplete, snapshot.profiles.isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let token = try verifiedToken ?? credentials.read(profileID: nil), !token.isEmpty else { throw GitHubClientError.missingToken }
        // Decode every existing legacy file before copying anything. Never replace originals.
        let decoder = JSONDecoder()
        var files: [(String, Data)] = []
        for name in ["settings.json", "overrides.json", "ledger.json", "activity.json"] {
            let source = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            var data = try Data(contentsOf: source)
            switch name {
            case "settings.json":
                var settings = try decoder.decode(AppSettings.self, from: data)
                settings.token = ""
                data = try JSONEncoder().encode(settings)
            case "overrides.json": _ = try decoder.decode([String: PullRequestOverride].self, from: data)
            case "ledger.json": _ = try decoder.decode([String: Date].self, from: data)
            default: _ = try decoder.decode([ActivityEvent].self, from: data)
            }
            files.append((name, data))
        }
        let profileID = snapshot.migrationProfileID ?? profileID
        snapshot.migrationProfileID = profileID
        try await registry.save(snapshot)
        let destination = directory.appendingPathComponent("profiles/\(profileID.uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: destination.appendingPathComponent(name), options: .atomic)
        }
        try credentials.write(token, profileID: profileID)
        let profile = AccountProfile(id: profileID, githubUserID: identity.id, login: identity.login)
        snapshot = AccountRegistrySnapshot(profiles: [profile], activeProfileID: profileID, migrationComplete: true)
        try await registry.save(snapshot)
        return profile
    }
}
