import XCTest
@testable import PRPulseApp

final class SettingsPaneTests: XCTestCase {
    func testDefaultPaneAndCaseOrder() {
        XCTAssertEqual(SettingsPane.defaultPane, .account)
        XCTAssertEqual(
            SettingsPane.allCases,
            [.account, .refresh, .notifications, .repositories, .advanced]
        )
    }

    func testRepositoryAdditionRejectsTrimmedCaseInsensitiveDuplicate() {
        XCTAssertFalse(
            RepositoryPreferenceValidation.canAdd(
                "owner/repo",
                to: [RepositorySubscription(nameWithOwner: " owner/Repo ", notificationsEnabled: true)]
            )
        )
    }
}
