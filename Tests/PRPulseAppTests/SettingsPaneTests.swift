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

    func testRepositoryAdditionAcceptsValidOwnerAndRepositoryName() {
        XCTAssertTrue(RepositoryPreferenceValidation.canAdd("owner/repo.name_1", to: []))
    }

    func testRepositoryAdditionRejectsMalformedRepositoryNames() {
        for name in ["owner", "/repo", "owner/", "owner/repo is:closed", "owner/repo/extra"] {
            XCTAssertFalse(RepositoryPreferenceValidation.canAdd(name, to: []), "Expected \(name) to be rejected")
        }
    }
}
