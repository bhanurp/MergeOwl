import SwiftUI

struct SettingsShellView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var updateService: AppUpdateService
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
                        AccountSettingsView(viewModel: viewModel)
                    case .refresh:
                        RefreshSettingsView(viewModel: viewModel)
                    case .notifications:
                        NotificationSettingsView(viewModel: viewModel)
                    case .repositories:
                        RepositoriesSettingsView(viewModel: viewModel)
                    case .updates:
                        UpdatesSettingsView(service: updateService)
                    case .advanced:
                        AdvancedSettingsView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 520)
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
        case .refresh:
            "Choose when PRPulse checks for updates."
        case .notifications:
            "Control alerts and digest delivery."
        case .repositories:
            "Select the repositories PRPulse watches."
        case .updates:
            "Keep PR Pulse up to date, on your terms."
        case .advanced:
            "Inspect status and access diagnostic tools."
        }
    }
}
