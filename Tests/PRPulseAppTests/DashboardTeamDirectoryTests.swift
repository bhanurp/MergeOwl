import XCTest
@testable import PRPulseApp

@MainActor
final class DashboardTeamDirectoryTests: XCTestCase {
    func testDirectoryIsReusedWithinAccountAndExplicitReloadReadsAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = TeamDirectoryClient()
        let store = PullRequestStore(directory: directory)
        let model = DashboardViewModel(client: client, store: store,
            notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        for _ in 0..<100 where !model.isReady { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.isReady)
        await model.loadTeams()
        await model.loadTeams()
        let initialCount = await client.requests
        XCTAssertEqual(initialCount, 1, "Reopening a picker must not refetch the whole organization directory")
        await model.loadTeams(force: true)
        let reloadedCount = await client.requests
        XCTAssertEqual(reloadedCount, 2)
        XCTAssertEqual(model.availableTeams.first?.id, "example/platform")
        await model.retire()
        XCTAssertTrue(model.availableTeams.isEmpty)
        await model.loadTeams(force: true)
        let retiredCount = await client.requests
        XCTAssertEqual(retiredCount, 2)
    }
}

private actor TeamDirectoryClient: GitHubClient {
    var requests = 0
    nonisolated(nonsending) func fetchViewer() async throws -> String { "octocat" }
    func fetchTeams() async throws -> [GitHubTeam] {
        requests += 1
        return [GitHubTeam(organization: "example", slug: "platform", name: "Platform")]
    }
    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        PullRequestPage(items: [], cursor: nil, hasNextPage: false)
    }
}
