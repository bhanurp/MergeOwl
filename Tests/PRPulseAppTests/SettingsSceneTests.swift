import XCTest
@testable import PRPulseApp

final class SettingsSceneTests: XCTestCase {
    @MainActor
    func testSettingsPresenterActivatesBeforeOpeningNativeSettings() {
        var events: [String] = []

        SettingsPresenter.open(
            activate: { events.append("activate") },
            open: { events.append("open") }
        )

        XCTAssertEqual(events, ["activate", "open"])
    }

    func testPackageRequiresMacOS14ForNativeSettings() throws {
        let packageManifest = try source(named: "Package.swift")

        XCTAssertTrue(packageManifest.contains(".macOS(.v14)"))
    }

    func testSettingsUseTheNativeSettingsScene() throws {
        let appSource = try source(named: "Sources/PRPulseApp/App/PRPulseApp.swift")

        XCTAssertTrue(appSource.contains("Settings {"))
        XCTAssertTrue(appSource.contains("SettingsShellView(viewModel: applicationDelegate.dependencies.dashboard)"))
        XCTAssertFalse(appSource.contains("Window(\"Settings\", id:"))
    }

    func testApplicationUsesTheNativeStatusItemDelegate() throws {
        let appSource = try source(named: "Sources/PRPulseApp/App/PRPulseApp.swift")

        XCTAssertTrue(appSource.contains("@NSApplicationDelegateAdaptor(PRPulseApplicationDelegate.self)"))
        XCTAssertFalse(appSource.contains("MenuBarExtra"))
    }

    func testSettingsGearUsesOpenSettings() throws {
        let contentSource = try source(named: "Sources/PRPulseApp/UI/ContentView.swift")

        XCTAssertTrue(contentSource.contains("@Environment(\\.openSettings) private var openSettings"))
        XCTAssertTrue(contentSource.contains("openSettings()"))
        XCTAssertFalse(contentSource.contains("openWindow(id: \"settings-window\")"))
        XCTAssertTrue(contentSource.contains("openWindow(id: \"connection-errors-window\")"))
    }

    func testNativeSettingsWindowSupportsContentMinimumWidthAndResizing() throws {
        let delegate = try source(named: "Sources/PRPulseApp/App/PRPulseApplicationDelegate.swift")
        XCTAssertTrue(delegate.contains(".resizable"))
        XCTAssertTrue(delegate.contains("frame(minWidth: 760, minHeight: 520)"))
        XCTAssertTrue(delegate.contains("window.contentMinSize = NSSize(width: 760, height: 520)"))
    }

    private func source(named path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(path))
    }
}
