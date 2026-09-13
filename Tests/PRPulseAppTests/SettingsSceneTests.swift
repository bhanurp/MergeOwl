import XCTest

final class SettingsSceneTests: XCTestCase {
    func testSettingsUseTheNativeSettingsScene() throws {
        let appSource = try source(named: "Sources/PRPulseApp/App/PRPulseApp.swift")

        XCTAssertTrue(appSource.contains("Settings {"))
        XCTAssertTrue(appSource.contains("SettingsShellView(viewModel: dependencies.dashboard)"))
        XCTAssertFalse(appSource.contains("Window(\"Settings\", id:"))
    }

    func testSettingsGearUsesOpenSettings() throws {
        let contentSource = try source(named: "Sources/PRPulseApp/UI/ContentView.swift")

        XCTAssertTrue(contentSource.contains("@Environment(\\.openSettings) private var openSettings"))
        XCTAssertTrue(contentSource.contains("openSettings()"))
        XCTAssertFalse(contentSource.contains("openWindow(id: \"settings-window\")"))
        XCTAssertTrue(contentSource.contains("openWindow(id: \"connection-errors-window\")"))
    }

    private func source(named path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(path))
    }
}
