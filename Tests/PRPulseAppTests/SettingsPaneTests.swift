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

    func testRepositoryAdditionValidatesGitHubOwnerNames() {
        let testCases: [(name: String, isValid: Bool)] = [
            ("owner/repo.name_1", true),
            ("-owner/repo", false),
            ("owner-/repo", false),
            ("owner--team/repo", false),
            ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/repo", false),
            ("owner", false),
            ("/repo", false),
            ("owner/", false),
            ("owner/repo is:closed", false),
            ("owner/repo/extra", false)
        ]

        for testCase in testCases {
            XCTAssertEqual(
                RepositoryPreferenceValidation.canAdd(testCase.name, to: []),
                testCase.isValid,
                "Unexpected validation result for \(testCase.name)"
            )
        }
    }
}
