import XCTest
@testable import PRPulseApp

final class UpdateConfigurationTests: XCTestCase {
    func testMissingTrustConfigurationDisablesUpdates() {
        XCTAssertNotNil(UpdateConfiguration.validationError(info: [:]))
    }

    func testRejectsInsecureOrCredentialBearingFeed() {
        for feed in ["http://example.com/appcast.xml", "https://user:secret@example.com/appcast.xml", "https:///appcast.xml"] {
            XCTAssertNotNil(UpdateConfiguration.validationError(info: [
                "PRPulseUpdatesEnabled": true, "SUFeedURL": feed,
                "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
                "SUVerifyUpdateBeforeExtraction": true
            ]))
        }
    }

    func testRequiresExplicitEnablementAndFullLengthKey() {
        var info: [String: Any] = [
            "PRPulseUpdatesEnabled": true, "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
            "SUVerifyUpdateBeforeExtraction": true
        ]
        XCTAssertNil(UpdateConfiguration.validationError(info: info))
        info["SUPublicEDKey"] = "invalid"
        XCTAssertNotNil(UpdateConfiguration.validationError(info: info))
        info["SUPublicEDKey"] = Data(repeating: 1, count: 32).base64EncodedString()
        info["PRPulseUpdatesEnabled"] = false
        XCTAssertNotNil(UpdateConfiguration.validationError(info: info))
    }
}
