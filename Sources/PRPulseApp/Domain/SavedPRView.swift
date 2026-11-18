import Foundation

enum SavedPRStateRule: String, Codable, CaseIterable, Identifiable {
    case any = "Any PR"
    case awaitingReview = "Awaiting my review"
    case changesRequested = "Changes requested"
    case authored = "Authored by me"
    case todo = "TODO"
    case draft = "Draft"
    var id: String { rawValue }
}

struct SavedPRView: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var enabled = true
    var repositories: [String] = []
    var stateRule: SavedPRStateRule = .any
    var text = ""

    static func validated(_ values: [SavedPRView]) throws -> [SavedPRView] {
        var names = Set<String>()
        var ids = Set<UUID>()
        return try values.map { value in
            var value = value
            value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.name.isEmpty, value.name.count <= 40 else {
                throw GitHubClientError.apiFailure("Use a view name between 1 and 40 characters.")
            }
            guard names.insert(value.name.lowercased()).inserted, ids.insert(value.id).inserted else {
                throw GitHubClientError.apiFailure("A saved view with this name already exists.")
            }
            value.repositories = value.repositories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            value.text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value
        }
    }
}

enum SavedPRViewMatcher {
    static func matches(_ pr: PullRequestPresentation, view: SavedPRView, viewerLogin: String) -> Bool {
        let item = pr.pullRequest
        guard view.repositories.isEmpty || view.repositories.contains(where: { $0.caseInsensitiveCompare(item.repository.nameWithOwner) == .orderedSame }) else { return false }
        guard view.text.isEmpty || item.title.localizedCaseInsensitiveContains(view.text) || item.repository.nameWithOwner.localizedCaseInsensitiveContains(view.text) else { return false }
        switch view.stateRule {
        case .any: return true
        case .awaitingReview: return pr.status.isActionable && pr.status.badge != .reviewed && item.author.login.caseInsensitiveCompare(viewerLogin) != .orderedSame
        case .changesRequested: return pr.status.changesRequested > 0 || item.detail.reviewDecision == .changesRequested
        case .authored: return item.author.login.caseInsensitiveCompare(viewerLogin) == .orderedSame
        case .todo: return item.override.state == .todo
        case .draft: return item.isDraft
        }
    }
}
