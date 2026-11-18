import XCTest
@testable import PRPulseApp

@MainActor
final class AppUpdateServiceTests: XCTestCase {
    func testUnconfiguredDriverCannotCheckOrInstall() {
        let driver = RecordingUpdateDriver(configured: false)
        let service = AppUpdateService(driver: driver)
        service.start()
        service.checkForUpdates()
        service.installAndRelaunch()
        XCTAssertFalse(service.canCheckForUpdates)
        XCTAssertEqual(driver.checks, 0)
        XCTAssertEqual(driver.installs, 0)
        guard case .unconfigured = service.state else { return XCTFail("Expected unconfigured") }
    }

    func testDuplicateChecksAreIgnoredUntilCycleFinishes() {
        let driver = RecordingUpdateDriver()
        let service = AppUpdateService(driver: driver)
        service.start()
        service.checkForUpdates()
        service.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
        driver.onStateChange?(.upToDate)
        service.checkForUpdates()
        XCTAssertEqual(driver.checks, 2)
    }

    func testManualCheckWorksWhenAutomaticUpdatesAreOff() {
        let driver = RecordingUpdateDriver()
        let service = AppUpdateService(driver: driver)
        service.start()
        service.setAutomaticUpdatesEnabled(false)
        service.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
        XCTAssertFalse(service.automaticUpdatesEnabled)
    }

    func testStagedUpdateRemainsReadyAfterDisablingFutureUpdates() {
        let driver = RecordingUpdateDriver()
        let service = AppUpdateService(driver: driver)
        service.start()
        driver.onStateChange?(.ready(version: "0.2.0"))
        service.setAutomaticUpdatesEnabled(false)
        XCTAssertEqual(service.state, .ready(version: "0.2.0"))
        XCTAssertFalse(service.automaticUpdatesEnabled)
        XCTAssertEqual(driver.installs, 0)
        service.installAndRelaunch()
        XCTAssertEqual(driver.installs, 1)
    }

    func testDownloadIsNotInstallableAndErrorAllowsRetry() {
        let driver = RecordingUpdateDriver()
        let service = AppUpdateService(driver: driver)
        service.start()
        driver.onStateChange?(.downloading(progress: nil))
        service.installAndRelaunch()
        service.checkForUpdates()
        XCTAssertEqual(driver.installs, 0)
        XCTAssertEqual(driver.checks, 0)
        driver.onStateChange?(.failed("Offline"))
        XCTAssertEqual(service.state, .failed("Offline"))
        service.checkForUpdates()
        XCTAssertEqual(driver.checks, 1)
    }

    func testStartIsIdempotentAndDoesNotResetPreference() {
        let driver = RecordingUpdateDriver()
        driver.automaticUpdatesEnabled = false
        let service = AppUpdateService(driver: driver)
        service.start()
        service.start()
        XCTAssertEqual(driver.starts, 1)
        XCTAssertFalse(service.automaticUpdatesEnabled)
    }
}

@MainActor
private final class RecordingUpdateDriver: UpdateDriver {
    let configurationError: String?
    var canCheckForUpdates = true
    var automaticUpdatesEnabled = true
    var lastCheckAt: Date?
    var onStateChange: ((UpdateState) -> Void)?
    var starts = 0
    var checks = 0
    var installs = 0
    init(configured: Bool = true) { configurationError = configured ? nil : "No signing key" }
    func start() throws { starts += 1 }
    func checkForUpdates() { checks += 1 }
    func setAutomaticUpdatesEnabled(_ enabled: Bool) { automaticUpdatesEnabled = enabled }
    func installAndRelaunch() { installs += 1 }
}
