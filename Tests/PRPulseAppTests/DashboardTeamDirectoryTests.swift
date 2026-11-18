import XCTest
@testable import PRPulseApp

@MainActor
final class DashboardTeamDirectoryTests: XCTestCase {
    func testDirectoryReloadDoesNotClearMembershipFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = TeamDirectoryClient()
        await client.setFailures(membership: true, directory: false)
        let store = PullRequestStore(directory: directory)
        let model = DashboardViewModel(client: client, store: store,
            notifier: NotificationDispatcher(store: store), scheduler: RefreshScheduler(), digestComputer: DigestComputer())
        for _ in 0..<100 where !model.isReady { try await Task.sleep(for: .milliseconds(10)) }
        model.selectTeam(GitHubTeam(organization: "example", slug: "platform", name: "Platform"))
        for _ in 0..<100 where model.teamError == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(model.teamError?.contains("membership denied") == true)
        await model.loadTeams(force: true)
        XCTAssertTrue(model.teamError?.contains("membership denied") == true)
        await client.setFailures(membership: false, directory: true)
        await model.loadTeams(force: true)
        XCTAssertTrue(model.teamDirectoryError?.contains("directory denied") == true)
        model.selectedTab = .team
        await model.refreshActiveTab()
        XCTAssertNil(model.teamError)
        XCTAssertTrue(model.teamDirectoryError?.contains("directory denied") == true)
        await model.retire()
    }
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
    var membershipFails = false
    var directoryFails = false
    func setFailures(membership: Bool, directory: Bool) { membershipFails = membership; directoryFails = directory }
    nonisolated(nonsending) func fetchViewer() async throws -> String { "octocat" }
    func fetchTeams() async throws -> [GitHubTeam] {
        requests += 1
        if directoryFails { throw GitHubClientError.apiFailure("directory denied") }
        return [GitHubTeam(organization: "example", slug: "platform", name: "Platform")]
    }
    func fetchTeamPullRequests(team: GitHubTeam, cursor: String?) async throws -> PullRequestPage {
        if membershipFails { throw GitHubClientError.apiFailure("membership denied") }
        return PullRequestPage(items: [], cursor: nil, hasNextPage: false)
    }
    nonisolated(nonsending) func fetchPullRequests(tab: PullRequestTab, cursor: String?) async throws -> PullRequestPage {
        PullRequestPage(items: [], cursor: nil, hasNextPage: false)
    }
}
