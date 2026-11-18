import SwiftUI

struct ProfilesAccountSettingsView: View {
    @ObservedObject var accounts: AccountSessionCoordinator
    @ObservedObject var dashboard: DashboardViewModel
    @State private var editingID: UUID?
    @State private var token = ""
    @State private var enterprise = false
    @State private var serverAddress = ""
    @State private var message: String?
    @State private var busy = false
    @State private var confirmingRemoval = false

    var body: some View {
        Form {
            Section("Saved accounts") {
                ForEach(accounts.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.displayName).font(.headline).textSelection(.enabled)
                            if accounts.activeProfileID == profile.id { Text("Active account").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Manage") { selectProfile(profile.id) }
                            .accessibilityLabel("Manage \(profile.displayName)")
                    }
                }
                Button("Add account") { selectProfile(nil) }
            }
            Section(editingProfile.map { "Update \($0.login)" } ?? "Connect another GitHub account") {
                Picker("GitHub service", selection: $enterprise) {
                    Text("GitHub.com").tag(false)
                    Text("GitHub Enterprise Server").tag(true)
                }
                .disabled(editingID != nil)
                .accessibilityIdentifier("prpulse.github-service")
                if enterprise {
                    TextField("Server URL", text: $serverAddress, prompt: Text("https://github.example.com"))
                        .disabled(editingID != nil)
                        .accessibilityIdentifier("prpulse.server-url")
                    Text("Use your server's web address and a personal access token created there. Your Mac must trust the server's HTTPS certificate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecureField("Personal access token", text: $token)
                    .accessibilityIdentifier("prpulse.token-input")
                HStack {
                    Button(editingID == nil ? "Connect GitHub" : "Update token") { run(save: true) }
                        .buttonStyle(.borderedProminent).disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Test connection") { run(save: false) }
                        .disabled(token.isEmpty && editingID == nil)
                    if editingID != nil {
                        Button("Remove account", role: .destructive) { confirmingRemoval = true }
                    }
                }
                Text("Tokens are stored in macOS Keychain. The field stays blank after saving. Managing an account does not switch the dashboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).textSelection(.enabled).accessibilityIdentifier("prpulse.account-message") }
            if let error = accounts.errorMessage {
                Section("Account setup needs attention") {
                    Text(error).foregroundStyle(.orange)
                    Button("Retry account setup") { Task { await accounts.retrySetup() } }
                }
            }
            Text(accounts.profiles.isEmpty && accounts.errorMessage == nil ? "No account connected" : dashboard.connectionPresentation.statusText.replacingOccurrences(of: "@", with: "")).font(.callout)
            if !dashboard.accessWarnings.isEmpty {
                Section("Limited repository access") {
                    Label("Some PR data is unavailable. Showing accessible PRs.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    ForEach(dashboard.accessWarnings, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    Link("Manage GitHub token access", destination: activeServer.tokenURL)
                }
            }
            if let server = try? selectedServer() {
                Link("Create a GitHub token", destination: server.isDotCom
                     ? server.webURL.appendingPathComponent("settings/personal-access-tokens/new") : server.tokenURL)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectProfile(accounts.addingAccountRequested ? nil : accounts.activeProfileID)
            accounts.addingAccountRequested = false
        }
        .onChange(of: accounts.addingAccountRequested) {
            if accounts.addingAccountRequested {
                selectProfile(nil)
                accounts.addingAccountRequested = false
            }
        }
        .disabled(busy || accounts.isWorking)
        .confirmationDialog("Remove \(editingProfile?.login ?? "account")?", isPresented: $confirmingRemoval) {
            Button("Remove account", role: .destructive) {
                guard let id = editingID else { return }
                busy = true
                Task {
                    defer { busy = false }
                    do { try await accounts.removeAccount(id: id); editingID = nil; token = ""; message = "Account removed." }
                    catch { message = "Could not remove this account. Check Keychain access and retry." }
                }
            }
        } message: { Text("Removes only this profile’s local PR data and saved token. It does not delete your GitHub account or repositories.") }
    }

    private var editingProfile: AccountProfile? { accounts.profiles.first { $0.id == editingID } }
    private var activeServer: GitHubServer { accounts.profiles.first { $0.id == accounts.activeProfileID }?.server ?? .dotCom }
    private func selectedServer() throws -> GitHubServer { try enterprise ? GitHubServer(serverAddress) : .dotCom }
    private func selectProfile(_ id: UUID?) {
        editingID = id; token = ""; message = nil
        let server = accounts.profiles.first { $0.id == id }?.server ?? .dotCom
        enterprise = !server.isDotCom
        serverAddress = server.isDotCom ? "" : server.webURL.absoluteString
    }
    private func run(save: Bool) {
        busy = true
        let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false }
            do {
                let server = try selectedServer()
                if save {
                    let savedID = try await accounts.connect(token: candidate, replacing: editingID, server: server)
                    token = ""
                    selectProfile(savedID)
                    message = "Account saved securely in Keychain."
                } else {
                    let login = try await accounts.testConnection(token: candidate.isEmpty ? nil : candidate, profileID: editingID, server: server)
                    message = candidate.isEmpty ? "Connected as \(login)" : "Token verified — save to connect"
                }
            } catch { message = error.localizedDescription }
        }
    }
}
