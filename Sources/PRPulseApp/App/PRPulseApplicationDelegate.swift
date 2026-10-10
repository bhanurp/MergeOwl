import AppKit
import SwiftUI

@MainActor
final class PRPulseApplicationDelegate: NSObject, NSApplicationDelegate {
    let dependencies = AppDependencies()
    private let statusItemController = PRPulseStatusItemController()
    private var settingsWindow: NSWindow?
    private var connectionErrorWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.install(
            with: dependencies.dashboard,
            actions: DashboardHostActions(
                showSettings: { [weak self] in self?.showSettings() },
                showConnectionErrors: { [weak self] in self?.showConnectionErrors() },
                quit: { NSApplication.shared.terminate(nil) }
            )
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController.tearDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showSettings() {
        let window = settingsWindow ?? makeWindow(title: "PR Pulse Settings", content: SettingsShellView(viewModel: dependencies.dashboard).frame(minWidth: 720, minHeight: 520))
        settingsWindow = window
        present(window)
    }

    private func showConnectionErrors() {
        let window = connectionErrorWindow ?? makeWindow(title: "Connection Errors", content: ConnectionErrorWindowView(viewModel: dependencies.dashboard).frame(width: 520, height: 340))
        connectionErrorWindow = window
        present(window)
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
