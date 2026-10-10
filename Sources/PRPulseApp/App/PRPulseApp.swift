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

struct BadgeIconPresentation {
    static func normalizedCount(for actionableCount: Int) -> Int {
        max(0, actionableCount)
    }

    static func badgeText(for actionableCount: Int) -> String {
        String(min(99, normalizedCount(for: actionableCount)))
    }

    static func accessibilityLabel(for actionableCount: Int) -> String {
        "PRPulse \(normalizedCount(for: actionableCount)) actionable"
    }
}

private struct BadgeIcon: View {
    var badgeCount: Int

    var body: some View {
        let actionableCount = BadgeIconPresentation.normalizedCount(for: badgeCount)

        ZStack(alignment: .topTrailing) {
            PRPulseWaveformMark()
            if actionableCount > 0 {
                Text(BadgeIconPresentation.badgeText(for: actionableCount))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(red: 0.96, green: 0.36, blue: 0.35)))
                    .foregroundColor(.white)
                    .offset(x: 8, y: -8)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .accessibilityLabel(BadgeIconPresentation.accessibilityLabel(for: actionableCount))
    }
}

private struct PRPulseWaveformMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            PRPulseWaveform()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.39, blue: 0.58),
                            Color(red: 0.67, green: 0.44, blue: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .padding(4)
        }
        .frame(width: 24, height: 18)
        .accessibilityHidden(true)
    }
}

private struct PRPulseWaveform: Shape {
    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let peakY = rect.minY
        let valleyY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.24, y: peakY),
            control1: CGPoint(x: rect.minX + rect.width * 0.07, y: midY),
            control2: CGPoint(x: rect.minX + rect.width * 0.14, y: peakY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.48, y: midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.32, y: peakY),
            control2: CGPoint(x: rect.minX + rect.width * 0.40, y: midY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.72, y: valleyY),
            control1: CGPoint(x: rect.minX + rect.width * 0.56, y: midY),
            control2: CGPoint(x: rect.minX + rect.width * 0.63, y: valleyY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.80, y: valleyY),
            control2: CGPoint(x: rect.minX + rect.width * 0.91, y: midY)
        )
        return path
    }
}
