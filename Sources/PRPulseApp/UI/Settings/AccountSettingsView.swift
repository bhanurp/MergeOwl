import Foundation
import SwiftUI

enum AccountConnectionState {
    case disconnected
    case testing
    case connected(login: String, isStored: Bool = true)
    case failed(String)

    var title: String {
        switch self {
        case .disconnected:
            "No GitHub account connected"
        case .testing:
            "Checking your GitHub account"
        case let .connected(login, _):
            "Connected as \(login)"
        case .failed:
            "Couldn’t connect to GitHub"
        }
    }

    var detail: String {
        switch self {
        case .disconnected:
            "Add a personal access token to get started."
        case .testing:
            "Verifying your token with GitHub."
        case let .connected(_, isStored):
            isStored
                ? "Your token is stored securely in Keychain."
                : "This token is only being tested. Save or update it to store it securely in Keychain."
        case let .failed(message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .disconnected:
            "person.crop.circle.badge.questionmark"
        case .testing:
            "arrow.triangle.2.circlepath.circle"
        case .connected:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disconnected:
            .secondary
        case .testing:
            .accentColor
        case .connected:
            .green
        case .failed:
            .red
        }
    }

    var allowsTokenMutation: Bool {
        if case .testing = self {
            return false
        }
        return true
    }
}

struct AccountSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var tokenInput = ""
    @State private var hasStoredToken = false
    @State private var connectionState: AccountConnectionState = .disconnected
    @State private var isTestingConnection = false
    @State private var showsRemovalConfirmation = false

    private let tokenStore = KeychainTokenStore()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 42, height: 42)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PRPulse")
                            .font(.headline)
                        Text("GitHub account")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("GitHub access") {
                SecureField("Personal access token", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)

                Text("Use a fine-grained token with access to the repositories you want to follow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(hasStoredToken ? "Update token" : "Connect GitHub") {
                        saveToken()
                    }
                    .disabled(trimmedTokenInput.isEmpty || !connectionState.allowsTokenMutation)

                    Button(isTestingConnection ? "Testing connection…" : "Test connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTestingConnection)

                    Spacer()

                    if hasStoredToken {
                        Button("Remove token", role: .destructive) {
                            showsRemovalConfirmation = true
                        }
                        .disabled(!connectionState.allowsTokenMutation)
                    }
                }
            }

            Section("Connection status") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: connectionState.symbolName)
                        .font(.title3)
                        .foregroundStyle(connectionState.color)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(connectionState.title)
                            .fontWeight(.medium)
                        Text(connectionState.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if case .disconnected = connectionState {
                            Link(
                                "Create a GitHub personal access token",
                                destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!
                            )
                            .font(.footnote)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasStoredToken = tokenStore.getToken() != nil
            tokenInput = ""
        }
        .onChange(of: tokenInput) { _ in
            if case .failed = connectionState {
                connectionState = .disconnected
            }
        }
        .confirmationDialog(
            "Remove GitHub token?",
            isPresented: $showsRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove token", role: .destructive) {
                removeToken()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PRPulse will no longer be able to load your GitHub pull requests.")
        }
    }

    private var trimmedTokenInput: String {
        tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveToken() {
        guard !trimmedTokenInput.isEmpty else { return }

        do {
            try tokenStore.setToken(trimmedTokenInput)
            hasStoredToken = true
            tokenInput = ""
            Task { await testConnection() }
        } catch {
            connectionState = .failed("Unable to save your token. Please try again.")
        }
    }

    private func removeToken() {
        do {
            try tokenStore.clearToken()
            hasStoredToken = false
            tokenInput = ""
            connectionState = .disconnected
        } catch {
            connectionState = .failed("Unable to remove your token. Please try again.")
        }
    }

    @MainActor
    private func testConnection() async {
        let hasTypedToken = !trimmedTokenInput.isEmpty
        guard let token = tokenCandidate() else {
            connectionState = .failed("Enter a token or connect your account first.")
            return
        }

        isTestingConnection = true
        connectionState = .testing
        defer { isTestingConnection = false }

        do {
            let restViewer = try await validateTokenWithREST(token)
            let client = GitHubAPIClient(
                tokenProvider: { token },
                watchedRepositoriesProvider: { [] }
            )
            let graphQLViewer = try await client.fetchViewer()
            let login = graphQLViewer.isEmpty ? restViewer : graphQLViewer
            let isStoredToken = !hasTypedToken
            connectionState = .connected(login: login, isStored: isStoredToken)
            if isStoredToken {
                viewModel.accountConnectionDidSucceed(login: login)
            }
        } catch {
            connectionState = .failed(recoveryMessage(for: error))
        }
    }

    private func tokenCandidate() -> String? {
        if !trimmedTokenInput.isEmpty {
            return trimmedTokenInput
        }
        return tokenStore.getToken()
    }

    private func recoveryMessage(for error: Error) -> String {
        if case let .apiFailure(message) = error as? GitHubClientError {
            return message
        }
        return "GitHub could not verify this connection. Check your network and token permissions, then try again."
    }

    private func validateTokenWithREST(_ token: String) async throws -> String {
        struct AuthenticatedUser: Decodable {
            let login: String
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }

        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401:
                throw GitHubClientError.apiFailure("Invalid token (401 Unauthorized).")
            case 403:
                throw GitHubClientError.apiFailure("Token rejected (403 Forbidden). Check token type and repository access.")
            default:
                throw GitHubClientError.apiFailure("GitHub auth check failed (\(http.statusCode)).")
            }
        }

        let user = try JSONDecoder().decode(AuthenticatedUser.self, from: data)
        return user.login
    }
}
