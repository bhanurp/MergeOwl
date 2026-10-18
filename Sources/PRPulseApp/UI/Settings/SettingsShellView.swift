import SwiftUI

struct SettingsShellView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var accounts: AccountSessionCoordinator
    @State private var selection = SettingsPane.defaultPane

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.rawValue, systemImage: pane.symbolName)
                        .tag(pane)
                }
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header(for: selectedPane)

                Group {
                    switch selectedPane {
                    case .account:
                        ProfilesAccountSettingsView(accounts: accounts, dashboard: viewModel)
                    case .appearance:
                        AppearanceSettingsView(viewModel: viewModel)
                    case .refresh:
                        RefreshSettingsView(viewModel: viewModel)
                    case .notifications:
                        NotificationSettingsView(viewModel: viewModel)
                    case .repositories:
                        if accounts.activeProfileID == nil {
                            ContentUnavailableView("Connect an account first", systemImage: "person.crop.circle", description: Text("Watched repositories belong to a GitHub account. Connect one in Account settings."))
                        } else { RepositoriesSettingsView(viewModel: viewModel) }
                    case .savedViews:
                        if accounts.activeProfileID == nil {
                            ContentUnavailableView("Connect an account first", systemImage: "person.crop.circle", description: Text("Saved views belong to a GitHub account. Connect one in Account settings."))
                        } else { SavedViewsSettingsView(viewModel: viewModel) }
                    case .advanced:
                        AdvancedSettingsView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(!viewModel.isReady && selectedPane != .account)
                if let message = viewModel.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).textSelection(.enabled).padding(12)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: accounts.addingAccountRequested) {
            if accounts.addingAccountRequested { selection = .account }
        }
    }

    private var selectedPane: SettingsPane {
        selection
    }

    private var selectionBinding: Binding<SettingsPane?> {
        Binding(
            get: { selection },
            set: { newSelection in
                if let newSelection {
                    selection = newSelection
                }
            }
        )
    }

    private func header(for pane: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pane.rawValue)
                .font(.title2.weight(.semibold))
            Text(subtitle(for: pane))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func subtitle(for pane: SettingsPane) -> String {
        switch pane {
        case .account:
            "Connect and manage your GitHub account."
        case .appearance:
            "Choose how your menu-bar popover is arranged."
        case .refresh:
            "Choose when PRPulse checks for updates."
        case .notifications:
            "Control alerts and digest delivery."
        case .repositories:
            "Select the repositories PRPulse watches."
        case .savedViews:
            "Group this account’s loaded PRs with reusable rules."
        case .advanced:
            "Inspect status and access diagnostic tools."
        }
    }
}
