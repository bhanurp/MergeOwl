import SwiftUI

struct ProfilesAccountSettingsView: View {
    @ObservedObject var accounts: AccountSessionCoordinator
    @ObservedObject var dashboard: DashboardViewModel
    @State private var editingID: UUID?
    @State private var token = ""
    @State private var message: String?
    @State private var busy = false
    @State private var confirmingRemoval = false

    var body: some View {
        Form {
            Section("Saved accounts") {
                ForEach(accounts.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.login).font(.headline).textSelection(.enabled)
                            if accounts.activeProfileID == profile.id { Text("Active account").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Manage") { editingID = profile.id; token = ""; message = nil }
                            .accessibilityLabel("Manage \(profile.login)")
                    }
                }
                Button("Add account") { editingID = nil; token = ""; message = nil }
            }
            Section(editingProfile.map { "Update \($0.login)" } ?? "Connect another GitHub account") {
                SecureField("Personal access token", text: $token)
                    .accessibilityIdentifier("prpulse.token-input")
                HStack {
                    Button(editingID == nil ? "Connect GitHub" : "Update token") { run(save: true) }
                        .buttonStyle(.borderedProminent).disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Test connection") { run(save: false) }
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
                    Link("Manage GitHub token access", destination: URL(string: "https://github.com/settings/tokens")!)
                }
            }
            Link("Create a GitHub token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
        }
        .formStyle(.grouped)
        .onAppear {
            editingID = accounts.addingAccountRequested ? nil : accounts.activeProfileID
            accounts.addingAccountRequested = false
        }
        .onChange(of: accounts.addingAccountRequested) {
            if accounts.addingAccountRequested {
                editingID = nil; token = ""; message = nil
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
    private func run(save: Bool) {
        busy = true
        let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false }
            do {
                if save {
                    try await accounts.connect(token: candidate, replacing: editingID)
                    token = ""
                    editingID = accounts.activeProfileID
                    message = "Account saved securely in Keychain."
                } else {
                    let login = try await accounts.testConnection(token: candidate.isEmpty ? nil : candidate, profileID: editingID ?? accounts.activeProfileID)
                    message = candidate.isEmpty ? "Connected as \(login)" : "Token verified — save to connect"
                }
            } catch { message = error.localizedDescription }
        }
    }
}
