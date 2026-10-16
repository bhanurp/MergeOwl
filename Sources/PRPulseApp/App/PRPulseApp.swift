import AppKit

@available(macOS 14.0, *)
@main
struct PRPulseApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = PRPulseApplicationDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
