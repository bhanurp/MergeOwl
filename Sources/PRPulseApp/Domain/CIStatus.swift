import Foundation

struct CICheck: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case queued, running, success, failure, cancelled, actionRequired, skipped, neutral, unknown
        var label: String {
            switch self {
            case .queued: "Queued"
            case .running: "Running"
            case .success: "Passed"
            case .failure: "Failed"
            case .cancelled: "Cancelled"
            case .actionRequired: "Action required"
            case .skipped: "Skipped"
            case .neutral: "Neutral"
            case .unknown: "Unavailable"
            }
        }
    }
    var id: String
    var name: String
    var state: State
    var url: URL?
    var startedAt: Date?
    var attempt: String = ""
    var failureKey: String { "\(id):\(attempt)" }
}

struct CIStatus: Codable, Equatable, Hashable, Sendable {
    enum State: String { case queued, running, failed, passed, cancelled, actionRequired, skipped, noChecks, unavailable }
    var headSHA: String
    var revision: String
    var checks: [CICheck]
    var isComplete = true
    var checkedAt = Date()
    var warning: String?
    var isStale = false
    var state: State {
        if isStale { return .unavailable }
        if checks.contains(where: { $0.state == .failure }) { return .failed }
        if !isComplete || checks.contains(where: { $0.state == .unknown }) { return .unavailable }
        if checks.contains(where: { $0.state == .actionRequired }) { return .actionRequired }
        if checks.contains(where: { $0.state == .running }) { return .running }
        if checks.contains(where: { $0.state == .queued }) { return .queued }
        if checks.contains(where: { $0.state == .cancelled }) { return .cancelled }
        if checks.isEmpty { return .noChecks }
        if checks.allSatisfy({ $0.state == .skipped || $0.state == .neutral }) { return .skipped }
        return .passed
    }
    var label: String {
        switch state {
        case .queued: "CI queued"
        case .running: "CI running"
        case .failed: "CI failed"
        case .passed: "Checks passed"
        case .cancelled: "CI cancelled"
        case .actionRequired: "CI needs action"
        case .skipped: "Checks skipped / neutral"
        case .noChecks: "No checks reported"
        case .unavailable: "CI unavailable"
        }
    }
    static var unavailable: Self { .init(headSHA: "", revision: "", checks: [], isComplete: false) }
    static func retainingPrevious(_ previous: Self?, incoming: Self) -> Self {
        guard !incoming.isComplete, incoming.headSHA.isEmpty, var previous, !previous.headSHA.isEmpty else { return incoming }
        previous.isStale = true
        previous.warning = incoming.warning ?? "Could not refresh checks. These are the last successful results."
        return previous
    }
}
