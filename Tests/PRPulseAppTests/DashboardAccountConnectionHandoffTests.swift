import XCTest
@testable import PRPulseApp

@MainActor
final class DashboardAccountConnectionHandoffTests: XCTestCase {
    func testStoredAccountConnectionClearsBootstrapFailureAndRefreshesTabs() async throws {
        let client = BootstrapFailingDashboardClient()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PullRequestStore(directory: directory)
        let scheduler = RefreshScheduler()
        let viewModel = DashboardViewModel(
            client: client,
            store: store,
            notifier: NotificationDispatcher(store: store),
            scheduler: scheduler,
            digestComputer: DigestComputer()
        )
        defer {
            Task { await scheduler.stop() }
            try? FileManager.default.removeItem(at: directory)
        }

        try await eventually {
            viewModel.connectionPresentation == .failed
        }
        let requestsBeforeHandoff = await client.pullRequestRequestCount

        viewModel.accountConnectionDidSucceed(login: "octocat")

        XCTAssertEqual(viewModel.viewerLogin, "octocat")
        XCTAssertEqual(viewModel.connectionPresentation, .connected(viewerLogin: "octocat"))
        XCTAssertTrue(viewModel.connectionErrors.isEmpty)
        try await eventually {
            await client.pullRequestRequestCount >= requestsBeforeHandoff + PullRequestTab.allCases.count
        }
    }

    private func eventually(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met before timeout")
    }
}

private final class BootstrapFailingDashboardClient: @unchecked Sendable, GitHubClient {
    private let requestCounter = RequestCounter()

    var pullRequestRequestCount: Int {
        get async { await requestCounter.value }
    }

    nonisolated(nonsending) func fetchViewer() async throws -> String {
        throw GitHubClientError.missingToken
    }

    nonisolated(nonsending) func fetchPullRequests(
        tab: PullRequestTab,
        cursor: String?
    ) async throws -> PullRequestPage {
        await requestCounter.increment()
        return PullRequestPage(items: [], cursor: nil, hasNextPage: false)
    }
}

private actor RequestCounter {
    private var count = 0

    var value: Int { count }

    func increment() {
        count += 1
    }
}
