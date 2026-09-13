import XCTest
@testable import PRPulseApp

final class AccountConnectionStateTests: XCTestCase {
    func testConnectedStateDescribesAuthenticatedAccount() {
        let state = AccountConnectionState.connected(login: "octocat")

        XCTAssertEqual(state.title, "Connected as octocat")
        XCTAssertEqual(state.detail, "Your token is stored securely in Keychain.")
        XCTAssertEqual(state.symbolName, "checkmark.circle.fill")
    }

    func testFailedStateOffersARecoveryMessage() {
        let state = AccountConnectionState.failed("Invalid token (401 Unauthorized).")

        XCTAssertEqual(state.title, "Couldn’t connect to GitHub")
        XCTAssertEqual(state.detail, "Invalid token (401 Unauthorized).")
    }

    func testUnsavedConnectedStatePromptsToSaveToken() {
        let state = AccountConnectionState.connected(login: "octocat", isStored: false)

        XCTAssertTrue(state.detail.localizedCaseInsensitiveContains("save"))
        XCTAssertFalse(state.detail.contains("stored securely in Keychain"))
    }

    func testTestingStateDisablesTokenMutations() {
        XCTAssertFalse(AccountConnectionState.testing.allowsTokenMutation)
    }

    func testNonTestingStatesAllowTokenMutations() {
        XCTAssertTrue(AccountConnectionState.disconnected.allowsTokenMutation)
        XCTAssertTrue(AccountConnectionState.connected(login: "octocat").allowsTokenMutation)
        XCTAssertTrue(AccountConnectionState.failed("Invalid token.").allowsTokenMutation)
    }
}
