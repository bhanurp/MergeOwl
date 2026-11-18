import AppKit

/// Owns a reusable window even when its close button is pressed.
@MainActor
final class NativeWindowOwner {
    private var window: NSWindow?
    private let makeWindow: () -> NSWindow

    init(makeWindow: @escaping () -> NSWindow) { self.makeWindow = makeWindow }

    @discardableResult
    func show() -> NSWindow {
        let window = window ?? makeWindow()
        window.isReleasedWhenClosed = false
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
