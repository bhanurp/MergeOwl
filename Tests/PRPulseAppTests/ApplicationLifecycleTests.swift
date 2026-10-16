import XCTest
@testable import PRPulseApp

final class ApplicationLifecycleTests: XCTestCase {
    func testDelegateKeepsTheStatusItemAliveAfterTheLastWindowCloses() throws {
        let delegateSource = try source(named: "Sources/PRPulseApp/App/PRPulseApplicationDelegate.swift")

        XCTAssertTrue(delegateSource.contains("func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool"))
        XCTAssertTrue(delegateSource.contains("applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {\n        false"))
    }

    @MainActor
    func testDashboardHostActionsInvokeEachProvidedClosure() {
        var settingsCalls = 0
        var errorWindowCalls = 0
        var quitCalls = 0
        let actions = DashboardHostActions(
            showSettings: { settingsCalls += 1 },
            showConnectionErrors: { errorWindowCalls += 1 },
            quit: { quitCalls += 1 }
        )

        actions.showSettings()
        actions.showConnectionErrors()
        actions.quit()

        XCTAssertEqual(settingsCalls, 1)
        XCTAssertEqual(errorWindowCalls, 1)
        XCTAssertEqual(quitCalls, 1)
    }

    private func source(named path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(path))
    }
}
