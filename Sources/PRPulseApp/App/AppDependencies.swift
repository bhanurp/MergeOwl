import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let accounts: AccountSessionCoordinator
    var dashboard: DashboardViewModel { accounts.dashboard }

    init(useMockClient: Bool = false) {
        let useMockClient = useMockClient || Self.shouldUseMockClient
        #if E2E_TESTING
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["PRPULSE_E2E_INITIAL_TOKEN"] {
            try? KeychainTokenStore().setToken(token)
        }
        let directory = URL(fileURLWithPath: environment["PRPULSE_E2E_DATA_DIRECTORY"]!, isDirectory: true)
        #else
        let directory = useMockClient
            ? FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-unit-\(UUID().uuidString)")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("PRPulseApp")
        #endif
        if useMockClient {
            accounts = AccountSessionCoordinator(directory: directory, makeClient: { _, _ in MockGitHubClient() })
        } else {
            accounts = AccountSessionCoordinator(directory: directory)
            Task { await accounts.start() }
        }
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
