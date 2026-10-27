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
        let hostedCI = ProcessInfo.processInfo.environment["PRPULSE_E2E_HOSTED_CI"]
        XCTAssertTrue(hostedCI == "true" || hostedCI == "false", "Test scheme must resolve the hosted-runner flag explicitly.")
        if hostedCI == "true" {
            addUIInterruptionMonitor(withDescription: "Hosted Python local-network notice") { dialog in
                let notice = dialog.staticTexts.matching(HostedNoticeSelectors.pythonNotice).firstMatch
                let deny = dialog.buttons.matching(HostedNoticeSelectors.deny).firstMatch
                guard notice.exists, deny.exists else { return false }
                // Fixtures use loopback only; never grant Python LAN access.
                deny.click()
                return true
            }
        }
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
        app.descendants(matching: .any)["prpulse.more"].firstMatch.click()
        app.menuItems["prpulse.settings"].click()
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

    private func toggleFilter(_ name: String) {
        app.descendants(matching: .any)["prpulse.filters"].firstMatch.click()
        app.menuItems[name].click()
    }

    private func prTitle(_ title: String) -> XCUIElement { app.buttons[title] }

    private func attachPopover(_ name: String) {
        let popover = app.descendants(matching: .popover).firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: popover.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    private func chooseLayout(_ title: String) {
        app.activate()
        app.descendants(matching: .any)["prpulse.more"].firstMatch.click()
        app.menuItems["Layout"].click()
        XCTAssertTrue(app.menuItems[title].waitForExistence(timeout: 5))
        app.menuItems[title].click()
    }

    func testCIMonitoringInBothLayoutsAndMutePersists() {
        launch()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(prTitle("Improve documentation").waitForExistence(timeout: 10))
        app.descendants(matching: .any)["prpulse.actionable"].firstMatch.click()
        XCTAssertTrue(prTitle("Improve documentation").exists, "Own failed CI is actionable")
        XCTAssertFalse(prTitle("Fix token handling").exists, "Running CI does not require action")
        app.descendants(matching: .any)["prpulse.actionable"].firstMatch.click()
        let ci = app.buttons["prpulse.ci.PR_1"]
        XCTAssertTrue(ci.waitForExistence(timeout: 10))
        XCTAssertTrue(ci.label.contains("CI failed"))
        ci.click()
        XCTAssertTrue(app.staticTexts["Unit tests"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["Open check"].exists)
        app.typeKey(.escape, modifierFlags: [])
        chooseLayout("Compact")
        XCTAssertTrue(app.buttons["prpulse.ci.PR_1"].label.contains("CI failed"))
        attachPopover("Compact CI status")
        chooseLayout("Tabbed")
        attachPopover("Tabbed CI status")
        settings()
        pane("Notifications")
        let toggle = app.switches["prpulse.ci-alerts"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        XCTAssertTrue(app.staticTexts["Monitoring 3 open My PRs"].waitForExistence(timeout: 15))
        let interval = app.popUpButtons["prpulse.ci-interval"]
        interval.click()
        app.menuItems["15 min"].click()
        app.windows["PR Pulse Settings"].buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        app.descendants(matching: .any)["prpulse.pr-more.PR_1"].firstMatch.click()
        app.menuItems["Mute CI failure alerts"].click()
        XCTAssertTrue(app.staticTexts["CI alerts muted"].waitForExistence(timeout: 5))
        chooseLayout("Compact")
        let monitoredCI = app.buttons["prpulse.ci.PR_1"]
        XCTAssertTrue(monitoredCI.exists)
        // Enabling alerts and immediately rescheduling can consume the bounded CI allowance.
        // A deferred refresh must keep the previous check details and explicitly mark them stale.
        if monitoredCI.label.contains("CI unavailable") {
            monitoredCI.click()
            XCTAssertTrue(app.staticTexts["Unit tests"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] %@ OR label CONTAINS[c] %@", "request budget", "request budget")).firstMatch.exists)
            app.typeKey(.escape, modifierFlags: [])
        } else {
            XCTAssertTrue(monitoredCI.label.contains("CI failed"))
        }
        chooseLayout("Tabbed")
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch(); openDashboard()
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["CI alerts muted"].waitForExistence(timeout: 15))
        app.descendants(matching: .any)["prpulse.pr-more.PR_1"].firstMatch.click()
        app.menuItems["Unmute CI failure alerts"].click()
        XCTAssertFalse(app.staticTexts["CI alerts muted"].exists)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
        app.descendants(matching: .any)["prpulse.pr-more.PR_3"].firstMatch.click()
        XCTAssertFalse(app.menuItems["Mute CI failure alerts"].exists, "Failure subscriptions are restricted to authored PRs")
        app.typeKey(.escape, modifierFlags: [])
        settings(); pane("Notifications")
        XCTAssertEqual(app.popUpButtons["prpulse.ci-interval"].value as? String, "15 min")
    }

    func testSearchCoverageIsSeparateFromTokenAccessWarnings() {
        launch(token: "e2e-cap")
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
        let coverage = app.staticTexts["prpulse.coverage-warning"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 5))
        XCTAssertTrue((coverage.value as? String ?? coverage.label).contains("Reviews"))
        XCTAssertFalse(app.links["Manage GitHub token access"].exists)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(prTitle("Improve documentation").waitForExistence(timeout: 10))
        XCTAssertTrue((coverage.value as? String ?? coverage.label).contains("My PRs"))
        XCTAssertFalse(app.links["Manage GitHub token access"].exists)
    }

    func testLayoutsPreserveSavedViewSearchFiltersAndRestoreAfterRelaunch() {
        launch()
        XCTAssertTrue(app.buttons["My PRs"].exists, "Tabbed must be the default")
        settings()
        pane("Saved Views")
        let window = app.windows["PR Pulse Settings"]
        window.buttons["Create saved view"].click()
        XCTAssertTrue(app.textFields["prpulse.view-name"].waitForExistence(timeout: 5))
        enter("API work", in: app.textFields["prpulse.view-name"])
        enter("API", in: app.textFields["prpulse.view-text"])
        app.buttons["Save view"].click()
        XCTAssertTrue(window.buttons["Edit API work"].waitForExistence(timeout: 5))
        window.buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        app.buttons["prpulse.saved-view.API work"].click()
        let search = app.textFields["Search title or repo"]
        enter("API", in: search)
        app.descendants(matching: .any)["prpulse.filters"].firstMatch.click()
        app.menuItems["Hide reviewed"].click()
        attachPopover("Tabbed dark")
        chooseLayout("Compact")
        let picker = app.descendants(matching: .any)["prpulse.view-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["My PRs"].exists)
        XCTAssertEqual(search.value as? String, "API")
        XCTAssertTrue(prTitle("Review API change").exists)
        XCTAssertTrue(app.descendants(matching: .any)["prpulse.filters"].firstMatch.label.contains("1"))
        attachPopover("Compact dark")
        picker.click()
        XCTAssertTrue(app.menuItems["My PRs"].exists)
        XCTAssertTrue(app.menuItems["API work"].exists)
        app.menuItems["API work"].click()
        app.descendants(matching: .any)["prpulse.pr-more.PR_3"].firstMatch.click()
        app.menuItems["Mark to do"].click()
        XCTAssertTrue(app.staticTexts["To do"].waitForExistence(timeout: 5))
        chooseLayout("Tabbed")
        XCTAssertTrue(app.buttons["My PRs"].waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "API")
        XCTAssertTrue(app.descendants(matching: .any)["prpulse.filters"].firstMatch.label.contains("1"))
        XCTAssertTrue(app.staticTexts["To do"].exists)
        chooseLayout("Compact")
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["My PRs"].exists)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(prTitle("Improve documentation").waitForExistence(timeout: 10))
    }

    func testAppearanceLayoutIsSharedAcrossAccountsAndCanReturnToTabbed() {
        app.launchEnvironment["PRPULSE_E2E_APPEARANCE"] = "light"
        launch()
        settings()
        let window = app.windows["PR Pulse Settings"]
        XCTAssertTrue(window.buttons["Manage octocat"].waitForExistence(timeout: 10))
        window.buttons["Add account"].click()
        enter("e2e-hubot", in: window.descendants(matching: .any)["prpulse.token-input"].firstMatch)
        window.buttons["Connect GitHub"].click()
        XCTAssertTrue(window.buttons["Manage hubot"].waitForExistence(timeout: 10))
        pane("Appearance")
        window.buttons["prpulse.appearance.compact"].click()
        XCTAssertTrue(window.staticTexts["Current layout: Compact"].waitForExistence(timeout: 5))
        window.buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        app.descendants(matching: .any)["prpulse.account-selector"].firstMatch.click()
        app.menuItems["hubot"].click()
        XCTAssertTrue(prTitle("Hubot private work").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["prpulse.view-picker"].firstMatch.exists)
        attachPopover("Compact light")
        settings()
        pane("Appearance")
        window.buttons["prpulse.appearance.tabbed"].click()
        XCTAssertTrue(window.staticTexts["Current layout: Tabbed"].waitForExistence(timeout: 5))
        window.buttons[XCUIIdentifierCloseWindow].click()
        openDashboard()
        XCTAssertTrue(app.buttons["My PRs"].exists)
        attachPopover("Tabbed light")
    }

    func testSettingsWindowIsSingleton() throws {
        launch()
        XCTAssertFalse(app.windows["com_apple_SwiftUI_Settings_window"].exists)
        app.descendants(matching: .any)["prpulse.more"].firstMatch.click()
        app.menuItems["prpulse.settings"].click()
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
        XCTAssertTrue(app.descendants(matching: .any)["prpulse.more"].firstMatch.exists)
    }

    func testSavedViewCreationAndCancel() {
        launch()
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
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
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
        XCTAssertFalse(prTitle("Already reviewed").exists)
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
        XCTAssertTrue(prTitle("Already reviewed").waitForExistence(timeout: 10))
        settings()
        window.buttons["Delete API triage"].click()
        let confirm = app.sheets.buttons["Delete view"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(window.buttons["Edit API triage"].waitForNonExistence(timeout: 5), "Wait for the asynchronous saved-view deletion to finish")
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
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
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
        XCTAssertLessThanOrEqual(app.descendants(matching: .any)["prpulse.more"].firstMatch.frame.maxX, app.buttons["Activity"].frame.maxX + 1)
        app.typeKey("1", modifierFlags: [.command])
        XCTAssertTrue(prTitle("Improve documentation").waitForExistence(timeout: 10))
        app.typeKey("f", modifierFlags: [.command])
        enter("token", in: search, clickToFocus: false)
        XCTAssertEqual(search.value as? String, "token")
        XCTAssertTrue(prTitle("Fix token handling").waitForExistence(timeout: 5))
        XCTAssertFalse(prTitle("Improve documentation").exists)
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        app.typeKey("2", modifierFlags: [.command])
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
    }

    func testMultipleAccountsSwitchAndRestoreSelection() {
        launch()
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
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
        XCTAssertTrue(prTitle("Hubot private work").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(prTitle("Review API change").exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(prTitle("Hubot private work").waitForExistence(timeout: 10))
        app.descendants(matching: .any)["prpulse.account-selector"].firstMatch.click()
        app.menuItems["octocat"].click()
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
        XCTAssertFalse(prTitle("Hubot private work").exists)
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
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
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
        XCTAssertFalse(prTitle("Review API change").exists)
    }

    func testMenuBarPopoverBadgeSettingsAndQuit() {
        launch()
        XCTAssertTrue(app.descendants(matching: .any)["Connected as @octocat"].firstMatch.waitForExistence(timeout: 10))
        let item = app.descendants(matching: .statusItem)["prpulse.status-item"]
        XCTAssertTrue(item.label.contains("actionable"))
        item.click()
        XCTAssertFalse(app.textFields["Search title or repo"].exists)
        openDashboard()
        settings()
        app.windows["PR Pulse Settings"].buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertNotEqual(app.state, .notRunning)
        openDashboard()
        app.descendants(matching: .any)["prpulse.more"].firstMatch.click()
        app.menuItems["prpulse.quit"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    func testTabsSearchRefreshAndPagination() {
        launch()
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
        selectTab("My PRs")
        XCTAssertTrue(prTitle("Improve documentation").waitForExistence(timeout: 10))
        let search = app.textFields["Search title or repo"]
        enter("token", in: search)
        XCTAssertTrue(prTitle("Fix token handling").waitForExistence(timeout: 5))
        XCTAssertFalse(prTitle("Improve documentation").exists)
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        app.buttons["Load more"].click()
        XCTAssertTrue(prTitle("Next page PR").waitForExistence(timeout: 10))
        app.buttons["prpulse.refresh"].click()
        XCTAssertTrue(prTitle("Improve documentation").waitForExistence(timeout: 10))
    }

    func testReviewedFilterActionableFilterAndQuickActions() {
        launch()
        XCTAssertTrue(prTitle("Already reviewed").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Reviewed"].exists)
        XCTAssertTrue(app.staticTexts["Pending"].exists, "Review status must not hide merge readiness")
        toggleFilter("Hide reviewed")
        XCTAssertFalse(prTitle("Already reviewed").exists)
        toggleFilter("Hide reviewed")
        app.descendants(matching: .any)["prpulse.actionable"].firstMatch.click()
        XCTAssertFalse(prTitle("Already reviewed").exists)
        app.descendants(matching: .any)["prpulse.actionable"].firstMatch.click()
        app.descendants(matching: .any)["prpulse.pr-more.PR_3"].firstMatch.click()
        app.menuItems["Mark not relevant"].click()
        toggleFilter("Hide N/A")
        XCTAssertFalse(prTitle("Review API change").exists)
    }

    func testSnoozeAndOverridePersistence() {
        launch()
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
        app.descendants(matching: .any)["Snooze"].firstMatch.click()
        app.menuItems["1 hour"].click()
        toggleFilter("Hide snoozed")
        XCTAssertFalse(prTitle("Review API change").exists)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PRPULSE_E2E_INITIAL_TOKEN")
        app.launch()
        openDashboard()
        XCTAssertTrue(prTitle("Already reviewed").waitForExistence(timeout: 10))
        toggleFilter("Hide snoozed")
        XCTAssertFalse(prTitle("Review API change").exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["Connected as @octocat"].firstMatch.waitForExistence(timeout: 10))
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
        XCTAssertTrue(prTitle("Review API change").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["Connected as @octocat"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Some PR data is unavailable. Showing accessible PRs."].exists)
        XCTAssertFalse(app.buttons["Connection issue"].exists)
        settings()
        XCTAssertTrue(app.staticTexts["Connected as octocat"].waitForExistence(timeout: 10))
    }

    func testEmptyStateAndDigest() {
        launch(token: "e2e-empty")
        XCTAssertTrue(app.staticTexts["No pull requests"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["Connected as @octocat"].firstMatch.exists)
        app.buttons["Activity"].click()
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
        XCTAssertTrue(prTitle("Watched repository update").waitForExistence(timeout: 10))
    }
}
