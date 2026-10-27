import XCTest
@testable import PRPulseApp

final class PullRequestStatusTests: XCTestCase {
    func testReviewedBadgeWhenReviewLatest() throws {
        let now = Date()
        let detail = PullRequestDetail(
            mergeable: .mergeable,
            reviewDecision: .approved,
            latestCommitAt: now.addingTimeInterval(-60),
            reviews: [
                .init(reviewer: "me", state: .approved, submittedAt: now)
            ]
        )
        let pr = PullRequest(
            id: "1",
            number: 1,
            title: "Test",
            url: URL(string: "https://example.com")!,
            repository: .init(nameWithOwner: "owner/repo"),
            author: .init(login: "me"),
            createdAt: now,
            updatedAt: now,
            isDraft: false,
            detail: detail
        )

        let calculator = PullRequestStatusCalculator(currentUserLogin: "me")
        let status = calculator.status(for: pr)

        XCTAssertEqual(status.badge, .reviewed)
        XCTAssertEqual(status.readiness, .checking, "Review approval cannot establish CI or branch-rule readiness")
    }

    func testNeedsReReviewWhenCommitAfterReview() throws {
        let now = Date()
        let detail = PullRequestDetail(
            mergeable: .mergeable,
            reviewDecision: .reviewRequired,
            latestCommitAt: now.addingTimeInterval(100),
            reviews: [
                .init(reviewer: "me", state: .approved, submittedAt: now)
            ]
        )
        let pr = PullRequest(
            id: "1",
            number: 1,
            title: "Test",
            url: URL(string: "https://example.com")!,
            repository: .init(nameWithOwner: "owner/repo"),
            author: .init(login: "author"),
            createdAt: now,
            updatedAt: now,
            isDraft: false,
            detail: detail
        )

        let calculator = PullRequestStatusCalculator(currentUserLogin: "me")
        let status = calculator.status(for: pr)

        XCTAssertEqual(status.badge, .needsReReview)
    }

    func testMergeBlockedWithChangesRequested() {
        let now = Date()
        let detail = PullRequestDetail(
            mergeable: .mergeable,
            reviewDecision: .approved,
            latestCommitAt: now,
            reviews: [
                .init(reviewer: "reviewer", state: .changesRequested, submittedAt: now)
            ]
        )
        let pr = PullRequest(
            id: "1",
            number: 1,
            title: "Test",
            url: URL(string: "https://example.com")!,
            repository: .init(nameWithOwner: "owner/repo"),
            author: .init(login: "author"),
            createdAt: now,
            updatedAt: now,
            isDraft: false,
            detail: detail
        )

        let calculator = PullRequestStatusCalculator(currentUserLogin: "me")
        let status = calculator.status(for: pr)

        if case .blocked(let reason) = status.readiness {
            XCTAssertEqual(reason, "Changes requested")
        } else {
            XCTFail("Expected blocked readiness")
        }
    }
}
