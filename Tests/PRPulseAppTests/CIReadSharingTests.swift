import XCTest
@testable import PRPulseApp

final class CIReadSharingTests: XCTestCase {
    func testCancellingOneConsumerKeepsOtherConsumerAlive() async throws {
        let gate = GitHubRequestGate()
        let probe = CancelledReadProbe()
        let operation: @Sendable () async throws -> CIStatus = {
            try await probe.wait()
            return .unavailable
        }
        let first = Task { try await gate.sharedCIRead(for: "PR", operation: operation) }
        let second = Task { try await gate.sharedCIRead(for: "PR", operation: operation) }
        for _ in 0..<200 {
            if await gate.waitingCIReadCount == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let joined = await gate.waitingCIReadCount
        XCTAssertEqual(joined, 2)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled consumer must return promptly") }
        catch { XCTAssertTrue(error is CancellationError) }
        let remaining = await gate.waitingCIReadCount
        XCTAssertEqual(remaining, 1)
        second.cancel()
        _ = await second.result
        let empty = await gate.waitingCIReadCount
        XCTAssertEqual(empty, 0)
        for _ in 0..<100 {
            if await probe.cancelled { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let cancelled = await probe.cancelled
        XCTAssertTrue(cancelled, "Last consumer cancellation must stop underlying network work")
        let retry = try await gate.sharedCIRead(for: "PR") { .unavailable }
        XCTAssertEqual(retry.state, .unavailable)
    }
}

private actor CancelledReadProbe {
    var cancelled = false
    private var continuation: CheckedContinuation<Void, Error>?
    func wait() async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancel() }
        }
    }
    private func cancel() {
        cancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
