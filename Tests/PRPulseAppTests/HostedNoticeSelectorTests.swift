import XCTest

final class HostedNoticeSelectorTests: XCTestCase {
    func testPythonNetworkNoticeUsesNativeStaticTextValue() {
        XCTAssertTrue(HostedNoticeSelectors.pythonNotice.evaluate(with: ["label": "", "value": "Allow “Python” to find devices on local networks?"]))
        XCTAssertFalse(HostedNoticeSelectors.pythonNotice.evaluate(with: ["label": "", "value": "Allow “Other App” to find devices on local networks?"]))
        XCTAssertFalse(HostedNoticeSelectors.pythonNotice.evaluate(with: ["label": "", "value": "Allow “Python” to access the camera?"]))
    }
    func testDenialUsesNativeButtonTitleAndNeverMatchesAllow() {
        XCTAssertTrue(HostedNoticeSelectors.deny.evaluate(with: ["label": "", "title": "Don’t Allow"]))
        XCTAssertTrue(HostedNoticeSelectors.deny.evaluate(with: ["label": "", "title": "Don't Allow"]))
        XCTAssertFalse(HostedNoticeSelectors.deny.evaluate(with: ["label": "", "title": "Allow"]))
    }
}
