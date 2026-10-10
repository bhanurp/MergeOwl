import Foundation

enum DashboardConnectionPresentation: Equatable {
    case checking
    case connected(viewerLogin: String)
    case failed

    var statusText: String {
        switch self {
        case .checking:
            "Checking GitHub connection"
        case .connected(let viewerLogin):
            "Connected as @\(viewerLogin)"
        case .failed:
            "Connection issue"
        }
    }

    var errorMessage: String? {
        switch self {
        case .failed:
            "GitHub connection failed"
        case .checking, .connected:
            nil
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

struct PullRequestPresentation: Identifiable, Equatable {
    var pullRequest: PullRequest
    var status: PullRequestStatus

    var id: String { pullRequest.id }

    var subtitle: String {
        "#\(pullRequest.number) · \(pullRequest.repository.nameWithOwner)"
    }

    var actionableBadgeText: String {
        switch status.badge {
        case .none:
            return ""
        case .reviewed:
            return "Reviewed"
        case .needsReReview:
            return "Needs re-review"
        }
    }

    var linkedReferencesSummary: String {
        let refs = pullRequest.detail.linkedReferences
        guard !refs.isEmpty else { return "" }

        let labels = refs.prefix(3).map { ref in
            let kind = ref.type == .issue ? "Issue" : "PR"
            return "\(kind) #\(ref.number)"
        }
        let extra = refs.count > 3 ? " +\(refs.count - 3)" : ""
        return "Linked: " + labels.joined(separator: " • ") + extra
    }
}
