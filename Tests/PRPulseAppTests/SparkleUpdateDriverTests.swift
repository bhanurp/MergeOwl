#if canImport(Sparkle)
import Sparkle
import XCTest
@testable import PRPulseApp

@MainActor
final class SparkleUpdateDriverTests: XCTestCase {
    func testScheduledAttentionUsesPassiveReminderInsteadOfTakingFocus() throws {
        let driver = SparkleUpdateDriver()
        let gentle = driver as? any SPUStandardUserDriverDelegate
        XCTAssertEqual(gentle?.supportsGentleScheduledUpdateReminders, true)
        let item = try XCTUnwrap(SUAppcastItem(dictionary: ["sparkle:version": "2", "sparkle:shortVersionString": "0.0.2", "enclosure": ["url": "https://example.com/update.zip", "sparkle:version": "2"]]))
        XCTAssertEqual(gentle?.standardUserDriverShouldHandleShowingScheduledUpdate?(item, andInImmediateFocus: true), false)
    }

    func testEnablingFromOptOutEnablesDownloadsAsWellAsChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("updater-preferences-" + UUID().uuidString).appendingPathExtension("app")
        let identity = "test.mergeowl.preferences." + UUID().uuidString
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: identity)
            try? FileManager.default.removeItem(at: directory)
        }
        let info: [String: Any] = ["CFBundleIdentifier": identity, "CFBundleVersion": "1", "SUEnableAutomaticChecks": false, "SUAutomaticallyUpdate": false]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent("Contents/Info.plist"))
        let host = try XCTUnwrap(Bundle(url: directory))
        let userDriver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
        let updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: userDriver, delegate: nil)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(updater.automaticallyDownloadsUpdates)
        SparkleUpdateDriver.setAutomaticUpdatesEnabled(true, updater: updater)
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        XCTAssertTrue(updater.automaticallyDownloadsUpdates, "Sparkle ignores download changes while automatic updates are disallowed")
        SparkleUpdateDriver.setAutomaticUpdatesEnabled(false, updater: updater)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(updater.automaticallyDownloadsUpdates)
    }

    func testNoUpdateResultSurvivesSuccessfulCycleCompletion() {
        // Construct but never start Sparkle: no networking, helper launch or installation.
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let driver = SparkleUpdateDriver()
        var states: [UpdateState] = []
        driver.onStateChange = { states.append($0) }
        driver.updaterDidNotFindUpdate(controller.updater, error: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)))
        driver.updater(controller.updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
        XCTAssertEqual(states.last, .upToDate)
    }
}
#endif
