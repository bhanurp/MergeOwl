import SwiftUI

@available(macOS 14.0, *)
@main
struct PRPulseApp: App {
    @StateObject private var dependencies = AppDependencies()

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: dependencies.dashboard)
                .frame(width: 420, height: 560)
                .task {
                    await dependencies.dashboard.requestNotificationAuthorization()
                }
        } label: {
            BadgeIcon(badgeCount: dependencies.dashboard.badgeCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsShellView(viewModel: dependencies.dashboard)
                .frame(minWidth: 720, minHeight: 520)
        }

        Window("Connection Errors", id: "connection-errors-window") {
            ConnectionErrorWindowView(viewModel: dependencies.dashboard)
                .frame(width: 520, height: 340)
        }
    }
}

private struct BadgeIcon: View {
    var badgeCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "arrow.triangle.branch")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.green)
            if badgeCount > 0 {
                Text("\(min(99, badgeCount))")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .foregroundColor(.white)
                    .offset(x: 8, y: -8)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .accessibilityLabel("PRPulse \(badgeCount) actionable")
    }
}
