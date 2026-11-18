import Foundation

actor SavedPRViewStore {
    private let file: URL
    private let selectionFile: URL
    private var retired = false
    private let lifetime: AccountSessionLifetime
    init(directory: URL, lifetime: AccountSessionLifetime = AccountSessionLifetime()) {
        self.lifetime = lifetime
        file = directory.appendingPathComponent("saved-views.json")
        selectionFile = directory.appendingPathComponent("selected-view.json")
    }
    func retire() { retired = true }
    func load() throws -> [SavedPRView] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try SavedPRView.validated(JSONDecoder().decode([SavedPRView].self, from: Data(contentsOf: file)))
    }
    func save(_ views: [SavedPRView]) throws {
        guard !retired, lifetime.isActive else { throw CancellationError() }
        _ = try load()
        let validated = try SavedPRView.validated(views)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(validated).write(to: file, options: .atomic)
    }
    func selectedID() -> UUID? {
        guard let data = try? Data(contentsOf: selectionFile) else { return nil }
        return try? JSONDecoder().decode(UUID.self, from: data)
    }
    func select(_ id: UUID?) throws {
        guard !retired, lifetime.isActive else { throw CancellationError() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(id).write(to: selectionFile, options: .atomic)
    }
}
