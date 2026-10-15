import SwiftUI

@available(macOS 14.0, *)
@main
struct PRPulseApp: App {
    @NSApplicationDelegateAdaptor(PRPulseApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        Settings {
            SettingsShellView(viewModel: applicationDelegate.dependencies.dashboard, updateService: applicationDelegate.dependencies.updates)
                .frame(minWidth: 720, minHeight: 520)
        }

        Window("Connection Errors", id: "connection-errors-window") {
            ConnectionErrorWindowView(viewModel: applicationDelegate.dependencies.dashboard)
                .frame(width: 520, height: 340)
        }
    }
}
