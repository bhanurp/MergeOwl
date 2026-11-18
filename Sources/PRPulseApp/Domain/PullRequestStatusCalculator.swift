import Foundation

enum StatusComputationError: Error {
    case missingCurrentUser
}

struct PullRequestStatusCalculator {
    var currentUserLogin: String

    func status(for pullRequest: PullRequest) -> PullRequestStatus {
        let badge = badgeState(for: pullRequest)
        let (approvals, changesRequested) = approvalCounts(for: pullRequest)
        let readiness = readinessState(for: pullRequest, changesRequested: changesRequested)
        let actionable = computeActionability(for: pullRequest, readiness: readiness)

        return PullRequestStatus(
            badge: badge,
            approvals: approvals,
            changesRequested: changesRequested,
            readiness: readiness,
            isActionable: actionable
        )
    }

    // MARK: - Algorithm implementations

    private func badgeState(for pullRequest: PullRequest) -> PullRequestStatus.ReviewBadge {
        let detail = pullRequest.detail
        let myReviews = detail.reviews
            .filter { $0.reviewer.caseInsensitiveCompare(currentUserLogin) == .orderedSame }
            .sorted(by: { $0.submittedAt > $1.submittedAt })
        guard let latestReview = myReviews.first else {
            return .none
        }

        guard let latestCommit = detail.latestCommitAt else {
            return .reviewed
        }

        if latestCommit <= latestReview.submittedAt {
            return .reviewed
        } else {
            return .needsReReview
        }
    }

    private func approvalCounts(for pullRequest: PullRequest) -> (Int, Int) {
        var latestByReviewer: [String: PullRequestDetail.Review] = [:]
        for review in pullRequest.detail.reviews {
            let reviewer = review.reviewer.lowercased()
            if let existing = latestByReviewer[reviewer] {
                if review.submittedAt > existing.submittedAt {
                    latestByReviewer[reviewer] = review
                }
            } else {
                latestByReviewer[reviewer] = review
            }
        }

        var approvals = 0
        var changesRequested = 0
        for review in latestByReviewer.values {
            switch review.state {
            case .approved:
                approvals += 1
            case .changesRequested:
                changesRequested += 1
            default:
                continue
            }
        }

        return (approvals, changesRequested)
    }

    private func readinessState(for pullRequest: PullRequest, changesRequested: Int) -> PullRequestStatus.MergeReadiness {
        let detail = pullRequest.detail
        if detail.mergeable == .unknown {
            return .checking
        }

        guard !pullRequest.isDraft else {
            return .blocked(reason: "Draft")
        }

        guard detail.mergeable == .mergeable else {
            return .blocked(reason: "Conflicts")
        }

        guard changesRequested == 0 else {
            return .blocked(reason: "Changes requested")
        }

        guard let ci = detail.ci else { return .checking }
        if ci.state == .failed { return .blocked(reason: "CI failed") }
        guard ci.isComplete else { return .checking }
        switch ci.state {
        case .running, .queued, .unavailable: return .checking
        case .cancelled, .actionRequired: return .blocked(reason: "CI needs attention")
        default: break
        }

        if let decision = detail.reviewDecision, decision != .approved {
            return .pending
        }

        return detail.mergeStateStatus == "CLEAN" ? .ready : .pending
    }

    private func computeActionability(
        for pullRequest: PullRequest,
        readiness: PullRequestStatus.MergeReadiness
    ) -> Bool {
        guard pullRequest.override.state != .notApplicable,
              !pullRequest.override.isSnoozed else {
            return false
        }

        switch readiness {
        case .ready:
            return true
        case .blocked(let reason) where reason == "CI failed" || reason == "CI needs attention":
            return pullRequest.author.login.caseInsensitiveCompare(currentUserLogin) == .orderedSame
                || pullRequest.override.state == .todo
        case .pending, .blocked:
            return pullRequest.override.state == .todo
        case .checking:
            return false
        }
    }
}
