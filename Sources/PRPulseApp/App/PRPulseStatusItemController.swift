import AppKit
import Combine
import SwiftUI

@MainActor
struct DashboardHostActions {
    var showSettings: @MainActor () -> Void
    var showConnectionErrors: @MainActor () -> Void
    var quit: @MainActor () -> Void

    static let noop = DashboardHostActions(
        showSettings: {},
        showConnectionErrors: {},
        quit: {}
    )
}

@MainActor
protocol StatusItemButtonHosting: AnyObject {
    var anchorView: NSView { get }
    func update(image: NSImage, accessibilityLabel: String)
}

@MainActor
protocol StatusBarHosting: AnyObject {
    func makeButton(onClick: @escaping @MainActor () -> Void) -> any StatusItemButtonHosting
    func removeButton(_ button: any StatusItemButtonHosting)
}

@MainActor
protocol PopoverHosting: AnyObject {
    var isShown: Bool { get }
    func configure(content: NSViewController)
    func show(relativeTo anchorView: NSView)
    func close()
}

@MainActor
final class PRPulseStatusItemController {
    private let statusBar: any StatusBarHosting
    private let popover: any PopoverHosting
    private var button: (any StatusItemButtonHosting)?
    private var badgeCountObserver: AnyCancellable?
    private weak var dashboard: DashboardViewModel?

    init(
        statusBar: any StatusBarHosting = AppKitStatusBarHost(),
        popover: any PopoverHosting = AppKitPopoverHost()
    ) {
        self.statusBar = statusBar
        self.popover = popover
    }

    func install(with dashboard: DashboardViewModel, actions: DashboardHostActions, accounts: AccountSessionCoordinator? = nil) {
        self.dashboard = dashboard
        if button == nil {
            button = statusBar.makeButton { [weak self] in self?.togglePopover() }
        }
        popover.configure(
            content: NSHostingController(rootView: ContentView(viewModel: dashboard, hostActions: actions, accounts: accounts))
        )
        update(actionableCount: dashboard.badgeCount)

        badgeCountObserver = dashboard.$badgeCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.update(actionableCount: count)
            }
    }

    func update(actionableCount: Int) {
        guard let button else { return }
        button.update(
            image: StatusItemIconRenderer.makeImage(actionableCount: actionableCount),
            accessibilityLabel: StatusItemIconPresentation.accessibilityLabel(for: actionableCount)
        )
    }

    func togglePopover() {
        guard let button else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.anchorView)
            Task { [weak dashboard] in await dashboard?.refreshForPopoverOpen() }
        }
    }

    func tearDown() {
        dashboard = nil
        badgeCountObserver = nil
        if let button {
            statusBar.removeButton(button)
        }
        button = nil
        popover.close()
    }
}

@MainActor
private final class AppKitStatusBarHost: StatusBarHosting {
    func makeButton(onClick: @escaping @MainActor () -> Void) -> any StatusItemButtonHosting {
        AppKitStatusItemButton(onClick: onClick)
    }

    func removeButton(_ button: any StatusItemButtonHosting) {
        guard let button = button as? AppKitStatusItemButton else { return }
        NSStatusBar.system.removeStatusItem(button.statusItem)
    }
}

@MainActor
private final class AppKitStatusItemButton: NSObject, StatusItemButtonHosting {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onClick: @MainActor () -> Void

    init(onClick: @escaping @MainActor () -> Void) {
        self.onClick = onClick
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(didClick)
        statusItem.button?.setAccessibilityIdentifier("prpulse.status-item")
    }

    var anchorView: NSView {
        statusItem.button ?? NSView()
    }

    func update(image: NSImage, accessibilityLabel: String) {
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = accessibilityLabel
        statusItem.button?.setAccessibilityLabel(accessibilityLabel)
    }

    @objc private func didClick() {
        onClick()
    }
}

@MainActor
private final class AppKitPopoverHost: PopoverHosting {
    private let popover = NSPopover()

    init() {
        popover.behavior = .transient
    }

    var isShown: Bool {
        popover.isShown
    }

    func configure(content: NSViewController) {
        popover.contentViewController = content
        popover.contentSize = NSSize(width: 420, height: 560)
    }

    func show(relativeTo anchorView: NSView) {
        #if E2E_TESTING
        // NSPopover can inherit the menu bar appearance instead of the app override.
        popover.appearance = NSApplication.shared.appearance
        #endif
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }
}
