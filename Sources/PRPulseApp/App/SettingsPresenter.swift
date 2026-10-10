import AppKit

@MainActor
enum SettingsPresenter {
    static func open(
        activate: () -> Void,
        open: () -> Void
    ) {
        activate()
        open()
    }

    static func showNativeSettings(openSettings: @escaping @MainActor () -> Void) {
        open(
            activate: {
                NSApplication.shared.activate(ignoringOtherApps: true)
            },
            open: {
                Task { @MainActor in
                    openSettings()

                    Task { @MainActor in
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        NSApplication.shared.windows
                            .first(where: { $0.title == "Settings" })?
                            .makeKeyAndOrderFront(nil)
                    }
                }
            }
        )
    }
}
