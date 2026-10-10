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

    func testVerifiedButUnsavedStateDoesNotClaimTheAccountIsConnected() {
        let state = AccountConnectionState.verifiedButNotSaved(login: "octocat")

        XCTAssertEqual(state.title, "Token verified — save to connect")
        XCTAssertFalse(state.title.localizedCaseInsensitiveContains("connected as"))
        XCTAssertTrue(state.detail.localizedCaseInsensitiveContains("save"))
        XCTAssertFalse(state.detail.contains("stored securely in Keychain"))
    }

    func testSavedTokenVerificationCreatesConnectedState() {
        let state = AccountConnectionState.verified(login: "octocat", source: .savedToken)

        XCTAssertEqual(state.title, "Connected as octocat")
        XCTAssertEqual(state.detail, "Your token is stored securely in Keychain.")
    }

    func testEnteredTokenVerificationDoesNotCreateConnectedState() {
        let state = AccountConnectionState.verified(login: "octocat", source: .enteredToken)

        XCTAssertEqual(state.title, "Token verified — save to connect")
        XCTAssertTrue(state.detail.localizedCaseInsensitiveContains("not been saved"))
    }

    func testTestingStateDisablesTokenMutations() {
        XCTAssertFalse(AccountConnectionState.testing.allowsTokenMutation)
    }

    func testNonTestingStatesAllowTokenMutations() {
        XCTAssertTrue(AccountConnectionState.disconnected.allowsTokenMutation)
        XCTAssertTrue(AccountConnectionState.connected(login: "octocat").allowsTokenMutation)
        XCTAssertTrue(AccountConnectionState.failed("Invalid token.").allowsTokenMutation)
    }

    func testDisconnectedStateGuidesAccountSetup() {
        let state = AccountConnectionState.disconnected

        XCTAssertEqual(state.title, "No GitHub account connected")
        XCTAssertEqual(state.detail, "Add a personal access token to get started.")
    }

    func testDisconnectedAccountViewIncludesOfficialTokenSetupLink() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/PRPulseApp/UI/Settings/AccountSettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Link("))
        XCTAssertTrue(source.contains("https://github.com/settings/personal-access-tokens/new"))
    }
}
