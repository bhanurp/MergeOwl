import XCTest
import Security

@MainActor
final class PRPulseUITests: XCTestCase {
    private var app: XCUIApplication!
    private var directory: URL!
    private var keychainService: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("prpulse-e2e-\(UUID().uuidString)")
        keychainService = "dev.prpulse.e2e.\(UUID().uuidString)"
        app = XCUIApplication(bundleIdentifier: "dev.prpulse.e2e")
        app.launchEnvironment = [
            "PRPULSE_E2E_API_URL": "http://127.0.0.1:8765",
            "PRPULSE_E2E_DATA_DIRECTORY": directory.path,
            "PRPULSE_E2E_KEYCHAIN_SERVICE": keychainService,
            "PRPULSE_E2E_INITIAL_TOKEN": "e2e-valid"
        ]
    }

    override func tearDownWithError() throws {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService!,
            kSecAttrAccount as String: "github-token"
        ] as CFDictionary)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func openDashboard() {
        let item = app.descendants(matching: .statusItem)["prpulse.status-item"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        item.click()
        XCTAssertTrue(app.textFields["Search title or repo"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func launch(token: String = "e2e-valid") {
        app.launchEnvironment["PRPULSE_E2E_INITIAL_TOKEN"] = token
        app.launch()
        openDashboard()
    }

    private func selectTab(_ name: String) {
        app.radioButtons[name].click()
    }

    private func settings() {
        app.buttons["prpulse.settings"].click()
        XCTAssertTrue(app.windows["PR Pulse Settings"].waitForExistence(timeout: 5))
        app.activate()
        let sceneWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        if sceneWindow.exists {
            sceneWindow.buttons[XCUIIdentifierCloseWindow].click()
        }
    }

    private func pane(_ name: String) {
        app.windows["PR Pulse Settings"].staticTexts[name].firstMatch.click()
    }

    private func preference(_ name: String) -> XCUIElement {
        let window = app.windows["PR Pulse Settings"]
        let control = window.groups.containing(.staticText, identifier: name).switches.firstMatch
        return control.exists ? control : window.checkBoxes[name]
    }

    private func enter(_ text: String, in field: XCUIElement) {
        field.click()
        // Let SwiftUI settle between keystrokes instead of dropping fast synthetic input.
        for character in text { field.typeText(String(character)) }
    }

    func testMenuBarPopoverBadgeSettingsAndQuit() {
        launch()
        XCTAssertTrue(app.staticTexts["Connected as @octocat"].waitForExistence(timeout: 10))
        let item = app.descendants(matching: .statusItem)["prpulse.status-item"]
        XCTAssertTrue(item.label.contains("actionable"))
        item.click()
        XCTAssertFalse(app.textFields["Search title or repo"].exists)
        openDashboard()
        settings()
        app.windows["PR Pulse Settings"].buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertNotEqual(app.state, .notRunning)
        openDashboard()
        app.buttons["prpulse.quit"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    func testTabsSearchRefreshAndPagination() {
        launch()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        selectTab("My PRs")
        XCTAssertTrue(app.staticTexts["Improve documentation"].waitForExistence(timeout: 10))
        let search = app.textFields["Search title or repo"]
        enter("token", in: search)
        XCTAssertTrue(app.staticTexts["Fix token handling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Improve documentation"].exists)
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        app.buttons["Load more"].click()
        XCTAssertTrue(app.staticTexts["Next page PR"].waitForExistence(timeout: 10))
        app.buttons["prpulse.refresh"].click()
        XCTAssertTrue(app.staticTexts["Improve documentation"].waitForExistence(timeout: 10))
    }

    func testReviewedFilterActionableFilterAndQuickActions() {
        launch()
        XCTAssertTrue(app.staticTexts["Already reviewed"].waitForExistence(timeout: 10))
        app.buttons["Hide reviewed"].click()
        XCTAssertFalse(app.staticTexts["Already reviewed"].exists)
        app.buttons["Hide reviewed"].click()
        app.buttons["Actionable"].click()
        XCTAssertFalse(app.staticTexts["Already reviewed"].exists)
        app.buttons["Actionable"].click()
        app.buttons["N/A"].firstMatch.click()
        app.buttons["Hide N/A"].click()
        XCTAssertFalse(app.staticTexts["Review API change"].exists)
    }

    func testSnoozeAndOverridePersistence() {
        launch()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["Snooze"].firstMatch.click()
        app.menuItems["1 hour"].click()
        app.buttons["Hide snoozed"].click()
        XCTAssertFalse(app.staticTexts["Review API change"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(app.staticTexts["Already reviewed"].waitForExistence(timeout: 10))
        app.buttons["Hide snoozed"].click()
        XCTAssertFalse(app.staticTexts["Review API change"].exists)
    }

    func testTokenUpdateAndKeychainPersistence() {
        launch(token: "invalid")
        settings()
        let token = app.windows["PR Pulse Settings"].descendants(matching: .any)["prpulse.token-input"].firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 5), app.debugDescription)
        enter("e2e-valid", in: token)
        app.windows["PR Pulse Settings"].buttons["Update token"].click()
        XCTAssertTrue(app.staticTexts["Connected as octocat"].waitForExistence(timeout: 10), app.debugDescription)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(app.staticTexts["Connected as @octocat"].waitForExistence(timeout: 10))
        settings()
        XCTAssertEqual(app.windows["PR Pulse Settings"].descendants(matching: .any)["prpulse.token-input"].firstMatch.value as? String, "")
        app.windows["PR Pulse Settings"].buttons["Test connection"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Connected as octocat"].waitForExistence(timeout: 10))
    }

    func testInvalidTokenShowsError() {
        launch(token: "invalid")
        XCTAssertTrue(app.buttons["Connection issue"].waitForExistence(timeout: 10))
        settings()
        app.windows["PR Pulse Settings"].buttons["Test connection"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Invalid token (401 Unauthorized)."].waitForExistence(timeout: 10))
    }

    func testPartialAccessKeepsAccountConnectedAndShowsPRs() {
        launch(token: "e2e-partial")
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connected as @octocat"].exists)
        XCTAssertTrue(app.staticTexts["Some PR data is unavailable. Showing accessible PRs."].exists)
        XCTAssertFalse(app.buttons["Connection issue"].exists)
        settings()
        XCTAssertTrue(app.staticTexts["Connected as octocat"].waitForExistence(timeout: 10))
    }

    func testEmptyStateAndDigest() {
        launch(token: "e2e-empty")
        XCTAssertTrue(app.staticTexts["No pull requests"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connected as @octocat"].exists)
        app.buttons["View digest"].click()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        app.buttons["Close"].click()
        XCTAssertTrue(app.textFields["Search title or repo"].exists)
    }

    func testSettingsPanesRepositoryAndPreferencesPersist() {
        launch()
        settings()
        pane("Refresh")
        let refresh = preference("Refresh on launch")
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), app.debugDescription)
        refresh.click()
        pane("Notifications")
        XCTAssertTrue(preference("Needs re-review").waitForExistence(timeout: 5), app.debugDescription)
        preference("Needs re-review").click()
        pane("Repositories")
        let input = app.windows["PR Pulse Settings"].textFields["prpulse.repository-input"]
        enter("example/repo", in: input)
        app.windows["PR Pulse Settings"].buttons["Add"].click()
        XCTAssertTrue(preference("example/repo").waitForExistence(timeout: 5), app.debugDescription)
        pane("Advanced")
        XCTAssertTrue(app.buttons["Refresh Now"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        settings()
        pane("Repositories")
        XCTAssertTrue(preference("example/repo").waitForExistence(timeout: 5), app.debugDescription)
        pane("Refresh")
        XCTAssertEqual(String(describing: preference("Refresh on launch").value!), "0")
        pane("Notifications")
        XCTAssertEqual(String(describing: preference("Needs re-review").value!), "0")
    }
}
