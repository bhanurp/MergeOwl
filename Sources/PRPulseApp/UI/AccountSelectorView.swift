import SwiftUI

struct AccountSelectorView: View {
    @ObservedObject var accounts: AccountSessionCoordinator
    var showSettings: () -> Void
    var body: some View {
        HStack {
            Menu {
                ForEach(accounts.profiles) { profile in
                    Button {
                        Task { do { try await accounts.switchAccount(to: profile.id) }
                            catch { accounts.errorMessage = "Could not switch accounts. Please retry." } }
                    } label: {
                        if accounts.activeProfileID == profile.id { Label(profile.login, systemImage: "checkmark") }
                        else { Text(profile.login) }
                    }
                }
                Divider()
                Button("Add account…") { accounts.addingAccountRequested = true; showSettings() }
            } label: {
                Label(accounts.profiles.first(where: { $0.id == accounts.activeProfileID })?.login ?? "Connect GitHub", systemImage: "person.crop.circle")
                    .lineLimit(1)
            }
            .accessibilityIdentifier("prpulse.account-selector")
            .help(accounts.profiles.first(where: { $0.id == accounts.activeProfileID })?.login ?? "Connect a GitHub account")
            .disabled(accounts.isWorking)
            Spacer()
        }
    }
}

struct AccountSettingsHost: View {
    @ObservedObject var accounts: AccountSessionCoordinator
    var body: some View {
        SettingsShellView(viewModel: accounts.dashboard, accounts: accounts)
            .id(accounts.activeProfileID)
    }
}

struct AccountConnectionErrorsHost: View {
    @ObservedObject var accounts: AccountSessionCoordinator
    var body: some View { ConnectionErrorWindowView(viewModel: accounts.dashboard) }
}
