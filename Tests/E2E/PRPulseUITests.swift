import XCTest
import Security
import AppKit

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
            kSecAttrService as String: keychainService!
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
        app.buttons[name].click()
    }

    private func settings() {
        app.buttons["prpulse.settings"].click()
        XCTAssertTrue(app.windows["PR Pulse Settings"].waitForExistence(timeout: 5))
        app.activate()
        let sceneWindow = app.windows["com_apple_SwiftUI_Settings_window"]
        let sceneClose = sceneWindow.buttons[XCUIIdentifierCloseWindow]
        if sceneWindow.exists && sceneClose.isHittable {
            sceneClose.click()
        }
        // Hosted runners have small desktops; zoom the native window to avoid clipped controls.
        app.windows["PR Pulse Settings"].buttons[XCUIIdentifierZoomWindow].click()
    }

    private func pane(_ name: String) {
        app.windows["PR Pulse Settings"].staticTexts[name].firstMatch.click()
    }

    private func preference(_ name: String) -> XCUIElement {
        let window = app.windows["PR Pulse Settings"]
        let control = window.groups.containing(.staticText, identifier: name).switches.firstMatch
        return control.exists ? control : window.checkBoxes[name]
    }

    private func enter(_ text: String, in field: XCUIElement, clickToFocus: Bool = true) {
        app.activate()
        let pasteboard = NSPasteboard.general
        let original = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(original)
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if clickToFocus { field.click() }
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
    }

    func testSettingsWindowIsSingleton() throws {
        launch()
        XCTAssertFalse(app.windows["com_apple_SwiftUI_Settings_window"].exists)
        app.buttons["prpulse.settings"].click()
        let window = app.windows["PR Pulse Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            XCTAssertEqual(app.windows.matching(identifier: "PR Pulse Settings").count, 1)
            XCTAssertFalse(app.windows["com_apple_SwiftUI_Settings_window"].exists)
            window.buttons[XCUIIdentifierCloseWindow].click()
            app.typeKey(",", modifierFlags: [.command])
            XCTAssertTrue(window.waitForExistence(timeout: 5))
        }
        window.buttons[XCUIIdentifierCloseWindow].click()
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        reopen.arguments = ["-b", "dev.prpulse.e2e"]
        try reopen.run()
        reopen.waitUntilExit()
        XCTAssertEqual(reopen.terminationStatus, 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.matching(identifier: "PR Pulse Settings").count, 1)
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertNotEqual(app.state, .notRunning)
        openDashboard()
        XCTAssertTrue(app.buttons["prpulse.settings"].exists)
    }

    func testSavedViewCreationAndCancel() {
        launch()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        settings()
        pane("Saved Views")
        let window = app.windows["PR Pulse Settings"]
        window.buttons["Create saved view"].click()
        XCTAssertTrue(app.textFields["prpulse.view-name"].waitForExistence(timeout: 5), app.debugDescription)
        enter("API work", in: app.textFields["prpulse.view-name"])
        enter("API", in: app.textFields["prpulse.view-text"])
        app.buttons["Save view"].click()
        XCTAssertTrue(window.buttons["Edit API work"].waitForExistence(timeout: 5), app.debugDescription)
        window.buttons["Edit API work"].click()
        enter("Discard this edit", in: app.textFields["prpulse.view-name"])
        app.buttons["Cancel"].click()
        XCTAssertTrue(window.buttons["Edit API work"].waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["Edit Discard this edit"].exists)
        window.buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        let view = app.buttons["prpulse.saved-view.API work"]
        XCTAssertTrue(view.waitForExistence(timeout: 5))
        view.click()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Already reviewed"].exists)
        settings()
        window.buttons["Edit API work"].click()
        enter("API triage", in: app.textFields["prpulse.view-name"])
        app.buttons["Save view"].click()
        XCTAssertTrue(window.buttons["Edit API triage"].waitForExistence(timeout: 5))
        window.buttons["Create saved view"].click()
        enter("Everything", in: app.textFields["prpulse.view-name"])
        app.buttons["Save view"].click()
        XCTAssertTrue(window.buttons["Move Everything up"].waitForExistence(timeout: 5))
        window.buttons["Move Everything up"].click()
        let editButtons = window.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Edit '")).allElementsBoundByIndex
        XCTAssertEqual(editButtons.first?.label, "Edit Everything")
        window.descendants(matching: .any)["prpulse.view-enabled.API triage"].firstMatch.click()
        window.buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        XCTAssertFalse(app.buttons["prpulse.saved-view.API triage"].exists)
        XCTAssertTrue(app.staticTexts["Already reviewed"].waitForExistence(timeout: 10))
        settings()
        window.buttons["Delete API triage"].click()
        let confirm = app.sheets.buttons["Delete view"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertFalse(window.buttons["Edit API triage"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(app.buttons["prpulse.saved-view.Everything"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["prpulse.saved-view.API triage"].exists)
    }

    func testLightAppearanceLongViewName() {
        app.launchEnvironment["PRPULSE_E2E_APPEARANCE"] = "light"
        launch()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        settings()
        pane("Saved Views")
        app.windows["PR Pulse Settings"].buttons["Create saved view"].click()
        let name = "Release readiness and customer API work"
        XCTAssertTrue(app.textFields["prpulse.view-name"].waitForExistence(timeout: 5))
        enter(name, in: app.textFields["prpulse.view-name"])
        app.buttons["Save view"].click()
        XCTAssertTrue(app.buttons["Edit \(name)"].waitForExistence(timeout: 5))
    }

    func testPopoverControlsFitAndKeyboardShortcutsWork() {
        launch()
        let search = app.textFields["Search title or repo"]
        XCTAssertLessThanOrEqual(app.buttons["prpulse.quit"].frame.maxX, app.buttons["View digest"].frame.maxX + 1)
        app.typeKey("1", modifierFlags: [.command])
        XCTAssertTrue(app.staticTexts["Improve documentation"].waitForExistence(timeout: 10))
        app.typeKey("f", modifierFlags: [.command])
        enter("token", in: search, clickToFocus: false)
        XCTAssertEqual(search.value as? String, "token")
        XCTAssertTrue(app.staticTexts["Fix token handling"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Improve documentation"].exists)
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        app.typeKey("2", modifierFlags: [.command])
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
    }

    func testMultipleAccountsSwitchAndRestoreSelection() {
        launch()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        settings()
        let window = app.windows["PR Pulse Settings"]
        XCTAssertTrue(window.buttons["Manage octocat"].waitForExistence(timeout: 10))
        window.buttons["Add account"].click()
        enter("e2e-hubot", in: window.descendants(matching: .any)["prpulse.token-input"].firstMatch)
        window.buttons["Connect GitHub"].click()
        XCTAssertTrue(window.buttons["Manage hubot"].waitForExistence(timeout: 10), app.debugDescription)
        window.buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        app.descendants(matching: .any)["prpulse.account-selector"].firstMatch.click()
        app.menuItems["hubot"].click()
        XCTAssertTrue(app.staticTexts["Hubot private work"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Review API change"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(app.staticTexts["Hubot private work"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["prpulse.account-selector"].firstMatch.click()
        app.menuItems["octocat"].click()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Hubot private work"].exists)
    }

    func testAddAccountRequestLeavesRetainedSettingsPane() {
        launch()
        settings()
        pane("Refresh")
        let window = app.windows["PR Pulse Settings"]
        window.buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        app.descendants(matching: .any)["prpulse.account-selector"].firstMatch.click()
        app.menuItems["Add account…"].click()
        XCTAssertTrue(window.buttons["Connect GitHub"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(window.descendants(matching: .any)["prpulse.token-input"].firstMatch.exists)
        XCTAssertEqual(app.windows.matching(identifier: "PR Pulse Settings").count, 1)
    }

    func testAdvancedDoesNotOfferIgnoredSettingsFile() {
        launch()
        settings()
        pane("Advanced")
        let window = app.windows["PR Pulse Settings"]
        XCTAssertTrue(window.buttons["Export logs"].waitForExistence(timeout: 5))
        XCTAssertFalse(window.buttons["Open settings.json"].exists)
    }

    func testRemoveLastAccountDoesNotResurrectLegacyCredential() {
        launch()
        XCTAssertTrue(app.staticTexts["Review API change"].waitForExistence(timeout: 10))
        settings()
        let window = app.windows["PR Pulse Settings"]
        XCTAssertTrue(window.buttons["Remove account"].waitForExistence(timeout: 5))
        window.buttons["Remove account"].click()
        let confirm = app.sheets.buttons["Remove account"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.click()
        XCTAssertTrue(window.staticTexts["No account connected"].waitForExistence(timeout: 10))
        XCTAssertFalse(window.buttons["Manage octocat"].exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(app.buttons["Open account settings"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Review API change"].exists)
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
        app.windows["PR Pulse Settings"].buttons["Connect GitHub"].click()
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
        XCTAssertTrue(app.staticTexts["GitHub could not verify this token (HTTP 401). Check expiration and permissions."].waitForExistence(timeout: 10))
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
        app.windows["PR Pulse Settings"].buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        selectTab("Watched")
        app.buttons["prpulse.refresh"].click()
        XCTAssertTrue(app.staticTexts["Watched repository update"].waitForExistence(timeout: 10))
    }
}
