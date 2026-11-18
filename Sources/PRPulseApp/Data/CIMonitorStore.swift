import Foundation

/// Owned by the serial account monitor. Corrupt data is preserved, never overwritten.
final class CIMonitorStore {
    private struct Observation: Codable {
        var revision: String
        var failures: Set<String>
    }
    private struct State: Codable {
        var muted: Set<String> = []
        var observations: [String: Observation] = [:]
    }
    private let file: URL
    private let lifetime: AccountSessionLifetime
    private var state: State

    init(directory: URL, lifetime: AccountSessionLifetime) throws {
        file = directory.appendingPathComponent("ci-monitor.json")
        self.lifetime = lifetime
        state = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode(State.self, from: Data(contentsOf: file)) : State()
    }
    func isMuted(_ id: String) -> Bool { state.muted.contains(id) }
    func setMuted(_ muted: Bool, for id: String) throws {
        var next = state
        if muted { next.muted.insert(id) } else { next.muted.remove(id) }
        next.observations.removeValue(forKey: id)
        try save(next)
    }
    func resetBaselines() throws {
        var next = state; next.observations = [:]; try save(next)
    }
    func retainOpen(_ ids: Set<String>) throws {
        var next = state
        next.observations = next.observations.filter { ids.contains($0.key) }
        try save(next)
    }
    func observe(pr: PullRequest, snapshot: CIStatus, deferReportable: Bool = false) throws -> [CICheck] {
        guard snapshot.isComplete, !snapshot.isStale, !snapshot.headSHA.isEmpty,
              !snapshot.checks.contains(where: { $0.state == .unknown }) else { return [] }
        let failures = snapshot.checks.filter { $0.state == .failure }
        let keys = Set(failures.map(\.failureKey))
        let old = state.observations[pr.id]
        let reportable = old.map { old in
            failures.filter { old.revision != snapshot.revision || !old.failures.contains($0.failureKey) }
        } ?? []
        if deferReportable, !state.muted.contains(pr.id), !reportable.isEmpty {
            return reportable
        }
        var next = state
        next.observations[pr.id] = Observation(revision: snapshot.revision, failures: keys)
        try save(next)
        guard !state.muted.contains(pr.id) else { return [] }
        return reportable
    }
    private func save(_ next: State) throws {
        guard lifetime.isActive else { throw CancellationError() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        state = next
    }
}
