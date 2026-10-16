import Foundation

actor AccountRegistry {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("accounts.json") }

    init(directory: URL) { self.directory = directory }

    func load() throws -> AccountRegistrySnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else { return AccountRegistrySnapshot() }
        let snapshot = try JSONDecoder().decode(AccountRegistrySnapshot.self, from: Data(contentsOf: file))
        try validate(snapshot)
        return snapshot
    }

    func save(_ snapshot: AccountRegistrySnapshot) throws {
        if FileManager.default.fileExists(atPath: file.path) { _ = try load() }
        try validate(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: file, options: .atomic)
    }

    private func validate(_ snapshot: AccountRegistrySnapshot) throws {
        let ids = Set(snapshot.profiles.map(\.id))
        guard ids.count == snapshot.profiles.count,
              Set(snapshot.profiles.map(\.githubUserID)).count == snapshot.profiles.count,
              snapshot.profiles.allSatisfy({ !$0.githubUserID.isEmpty && !$0.login.isEmpty }),
              snapshot.activeProfileID.map({ ids.contains($0) }) ?? true,
              (snapshot.pendingRemovalIDs ?? []).allSatisfy({ ids.contains($0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
