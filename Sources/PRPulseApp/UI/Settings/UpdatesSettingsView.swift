import SwiftUI

struct UpdatesSettingsView: View {
    @ObservedObject var service: AppUpdateService

    var body: some View {
        Form {
            Section {
                LabeledContent("PR Pulse", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build")
                Label(statusText, systemImage: statusSymbol)
                    .accessibilityIdentifier("prpulse.update-status")
                if case .downloading = service.state {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Downloading update")
                }
                if let date = service.lastCheckAt {
                    LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Check for Updates…") { service.checkForUpdates() }
                    .disabled(!service.canCheckForUpdates)
                    .accessibilityIdentifier("prpulse.check-updates")
                if case .ready = service.state {
                    Button("Install and Relaunch") { service.installAndRelaunch() }
                        .accessibilityIdentifier("prpulse.install-update")
                }
            } header: {
                Text("Software updates")
            }

            Section {
                Toggle("Automatically download updates", isOn: Binding(
                    get: { service.automaticUpdatesEnabled },
                    set: { service.setAutomaticUpdatesEnabled($0) }
                ))
                .disabled(isUnconfigured)
                .accessibilityIdentifier("prpulse.automatic-updates")
                Text("Verified updates install when you quit PR Pulse. Turning this off stops future checks and downloads; an update already prepared will still install on quit.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Link("View releases on GitHub", destination: URL(string: "https://github.com/bhanurp/prpulse/releases/latest")!)
                Text("Update downloads never use your GitHub account token.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var isUnconfigured: Bool {
        if case .unconfigured = service.state { return true }
        return false
    }

    private var statusText: String {
        switch service.state {
        case let .unconfigured(message), let .failed(message): message
        case .idle: "Ready to check for updates"
        case .checking: "Checking for updates…"
        case .downloading: "Downloading update…"
        case let .ready(version): "Version \(version) is ready to install on quit."
        case .upToDate: "You’re up to date"
        }
    }

    private var statusSymbol: String {
        switch service.state {
        case .unconfigured: "info.circle"
        case .failed: "exclamationmark.triangle"
        case .upToDate: "checkmark.circle"
        case .ready: "arrow.down.circle"
        default: "arrow.triangle.2.circlepath"
        }
    }
}
