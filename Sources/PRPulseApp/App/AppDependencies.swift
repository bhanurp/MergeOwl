import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let dashboard: DashboardViewModel

    init() {
        #if E2E_TESTING
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["PRPULSE_E2E_INITIAL_TOKEN"] {
            try? KeychainTokenStore().setToken(token)
        }
        let directory = URL(fileURLWithPath: environment["PRPULSE_E2E_DATA_DIRECTORY"]!, isDirectory: true)
        let store = PullRequestStore(directory: directory)
        #else
        let store = PullRequestStore()
        #endif
        let notifier = NotificationDispatcher(store: store)
        let scheduler = RefreshScheduler()
        let digestComputer = DigestComputer()
        let client: GitHubClient
        if Self.shouldUseMockClient {
            client = MockGitHubClient()
        } else {
            client = GitHubAPIClient(
                watchedRepositoriesProvider: {
                    await store.loadSettings().watchedRepositories
                }
            )
        }

        self.dashboard = DashboardViewModel(
            client: client,
            store: store,
            notifier: notifier,
            scheduler: scheduler,
            digestComputer: digestComputer
        )
    }

    private static var shouldUseMockClient: Bool {
        #if E2E_TESTING
        return false
        #else
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["PRPULSE_USE_MOCK_CLIENT"] == "1"
        #endif
    }
}
