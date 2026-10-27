import XCTest
@testable import PRPulseApp

final class CIMonitoringTests: XCTestCase {
    func testFailedRefreshRetainsLastSuccessfulChecksButCannotImplyReady() {
        let previous = snapshot([.success])
        let merged = CIStatus.retainingPrevious(previous, incoming: .unavailable)
        XCTAssertEqual(merged.checks, previous.checks)
        XCTAssertEqual(merged.checkedAt, previous.checkedAt)
        XCTAssertTrue(merged.isStale)
        XCTAssertEqual(merged.state, .unavailable)
    }
    func testAggregationDoesNotConfuseSkippedUnknownOrPendingWithSuccess() {
        XCTAssertEqual(snapshot([.success, .skipped]).state, .passed)
        XCTAssertEqual(snapshot([.skipped]).state, .skipped)
        XCTAssertEqual(snapshot([.success, .unknown]).state, .unavailable)
        XCTAssertEqual(snapshot([.running, .failure]).state, .failed)
        XCTAssertEqual(snapshot([.queued, .success]).state, .queued)
        XCTAssertEqual(snapshot([]).state, .noChecks)
        var partial = snapshot([.success]); partial.isComplete = false
        XCTAssertEqual(partial.state, .unavailable)
    }

    func testFailedAndUnknownCICannotBeReadyToMerge() {
        var pr = makePR()
        pr.detail.ci = snapshot([.failure])
        let calculator = PullRequestStatusCalculator(currentUserLogin: "me")
        XCTAssertEqual(calculator.status(for: pr).readiness, .blocked(reason: "CI failed"))
        XCTAssertTrue(calculator.status(for: pr).isActionable, "Own CI failures must remain in the Actionable filter and badge")
        pr.author.login = "someone-else"
        XCTAssertFalse(calculator.status(for: pr).isActionable)
        pr.author.login = "me"
        pr.detail.ci = nil
        XCTAssertEqual(calculator.status(for: pr).readiness, .checking)
        pr.detail.ci = snapshot([.success])
        XCTAssertEqual(calculator.status(for: pr).readiness, .pending, "Passing checks do not establish branch rules")
        pr.detail.mergeStateStatus = "CLEAN"
        XCTAssertEqual(calculator.status(for: pr).readiness, .ready)
    }

    func testSilentBaselineThenNewFailureAndRerunButNoDuplicateAfterRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var store = try CIMonitorStore(directory: directory, lifetime: AccountSessionLifetime())
        let pr = makePR()
        XCTAssertTrue(try store.observe(pr: pr, snapshot: snapshot([.failure])).isEmpty)
        XCTAssertTrue(try store.observe(pr: pr, snapshot: snapshot([.running])).isEmpty)
        XCTAssertEqual(try store.observe(pr: pr, snapshot: snapshot([.failure])).count, 1)
        store = try CIMonitorStore(directory: directory, lifetime: AccountSessionLifetime())
        XCTAssertTrue(try store.observe(pr: pr, snapshot: snapshot([.failure])).isEmpty)
        var rerun = snapshot([.failure]); rerun.checks[0].id = "rerun-2"
        XCTAssertEqual(try store.observe(pr: pr, snapshot: rerun).count, 1)
    }

    func testMuteAndNewRevisionEstablishFreshBaselineAndRetirementPreventsWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lifetime = AccountSessionLifetime()
        let store = try CIMonitorStore(directory: directory, lifetime: lifetime)
        let pr = makePR()
        _ = try store.observe(pr: pr, snapshot: snapshot([.success]))
        try store.setMuted(true, for: pr.id)
        XCTAssertTrue(try store.observe(pr: pr, snapshot: snapshot([.failure])).isEmpty)
        try store.setMuted(false, for: pr.id)
        XCTAssertTrue(try store.observe(pr: pr, snapshot: snapshot([.failure])).isEmpty)
        var changed = snapshot([.failure]); changed.headSHA = "new"; changed.revision = "new"
        XCTAssertEqual(try store.observe(pr: pr, snapshot: changed).count, 1)
        lifetime.invalidate()
        XCTAssertThrowsError(try store.setMuted(true, for: pr.id))
    }

    func testPartialCIKeepsBaselineAndQuietHoursSuppressDelivery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CIMonitorStore(directory: directory, lifetime: AccountSessionLifetime())
        let pr = makePR()
        _ = try store.observe(pr: pr, snapshot: snapshot([.running]))
        var partial = snapshot([.failure]); partial.isComplete = false
        XCTAssertTrue(try store.observe(pr: pr, snapshot: partial).isEmpty)
        XCTAssertEqual(try store.observe(pr: pr, snapshot: snapshot([.failure])).count, 1)
        XCTAssertTrue(CIMonitor.isQuiet(hour: 23, hours: QuietHours(startHour: 22, endHour: 7)))
        XCTAssertFalse(CIMonitor.isQuiet(hour: 12, hours: QuietHours(startHour: 22, endHour: 7)))
    }

    private func snapshot(_ states: [CICheck.State]) -> CIStatus {
        CIStatus(headSHA: "head", revision: "head", checks: states.enumerated().map {
            CICheck(id: "check-\($0.offset)", name: "Tests \($0.offset)", state: $0.element)
        })
    }

    private func makePR() -> PullRequest {
        PullRequest(id: "PR_1", number: 1, title: "Tests", url: URL(string: "https://github.com/example/repo/pull/1")!,
                    repository: .init(nameWithOwner: "example/repo"), author: .init(login: "me"),
                    createdAt: Date(), updatedAt: Date(), isDraft: false,
                    detail: .init(mergeable: .mergeable, reviewDecision: .approved))
    }
}
