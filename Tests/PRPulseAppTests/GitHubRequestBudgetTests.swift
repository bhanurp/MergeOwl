import XCTest
@testable import PRPulseApp

final class GitHubRequestBudgetTests: XCTestCase {
    func testCIWindowRefillsWithoutBlockingDashboard() async throws {
        let gate = GitHubRequestGate()
        let now = Date()
        for _ in 0..<20 { try await gate.check(isCI: true, now: now) }
        for _ in 0..<10 { try await gate.check(isCI: true, isRevalidation: true, now: now) }
        do { try await gate.check(isCI: true, now: now); XCTFail("Expected CI-only deferral") }
        catch { guard case GitHubClientError.ciBudgetDeferred = error else { return XCTFail("Unexpected \(error)") } }
        try await gate.check(now: now)
        try await gate.check(isCI: true, now: now.addingTimeInterval(61))
    }

    func testServerQuotaReserveAppliesToAllCIReadsButNotDashboard() async throws {
        let gate = GitHubRequestGate()
        let now = Date()
        await gate.recordQuota(remaining: 500, reset: now.addingTimeInterval(3600))
        do { try await gate.check(isCI: true, now: now); XCTFail("Dashboard quota must be reserved") }
        catch { guard case GitHubClientError.ciBudgetDeferred = error else { return XCTFail("Unexpected \(error)") } }
        try await gate.check(now: now)
        try await gate.check(isCI: true, now: now.addingTimeInterval(3601))
    }

    func testUnrefreshedPRsTakePriorityWithoutChangingDisplayOrder() async {
        let gate = GitHubRequestGate()
        await gate.recordCIRefresh("first")
        let order = await gate.ciRefreshOrder(["first", "second"])
        XCTAssertEqual(order, ["second", "first"])
    }
}
