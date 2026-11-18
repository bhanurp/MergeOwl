import AppKit
import SwiftUI
import Combine

@MainActor
final class PRPulseApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let dependencies = AppDependencies()
    private let statusItemController = PRPulseStatusItemController()
    private var sessionObserver: AnyCancellable?
    private lazy var settingsOwner = NativeWindowOwner { [unowned self] in
        let window = makeWindow(title: "MergeOwl Settings", content: AccountSettingsHost(accounts: dependencies.accounts, updates: dependencies.updates).frame(minWidth: 760, minHeight: 520))
        window.contentMinSize = NSSize(width: 760, height: 520)
        window.setContentSize(NSSize(width: 900, height: 600))
        window.center()
        return window
    }
    private var connectionErrorWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if E2E_TESTING
        if ProcessInfo.processInfo.environment["PRPULSE_E2E_APPEARANCE"] == "light" {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
        #endif
        dependencies.updates.start()
        installApplicationMenu()
        sessionObserver = dependencies.accounts.$dashboard.sink { [weak self] dashboard in
            guard let self else { return }
            statusItemController.install(
                with: dashboard,
                actions: DashboardHostActions(
                    showSettings: { [weak self] in self?.showSettings() },
                    showConnectionErrors: { [weak self] in self?.showConnectionErrors() },
                    quit: { NSApplication.shared.terminate(nil) }
                ), accounts: dependencies.accounts, updates: dependencies.updates
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController.tearDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func showSettings() {
        settingsOwner.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func checkForUpdates() { dependencies.updates.checkForUpdates() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(checkForUpdates) || dependencies.updates.canCheckForUpdates
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "MergeOwl")
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        applicationMenu.addItem(updatesItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit MergeOwl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        editItem.title = "Edit"
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
    }

    private func showConnectionErrors() {
        let window = connectionErrorWindow ?? makeWindow(title: "Connection Errors", content: AccountConnectionErrorsHost(accounts: dependencies.accounts).frame(width: 520, height: 340))
        connectionErrorWindow = window
        present(window)
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
