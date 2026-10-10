import XCTest
@testable import PRPulseApp

final class DashboardConnectionPresentationTests: XCTestCase {
    func testCheckingDoesNotClaimGitHubConnectionSucceeded() {
        let presentation = DashboardConnectionPresentation.checking

        XCTAssertEqual(presentation.statusText, "Checking GitHub connection")
        XCTAssertFalse(presentation.isConnected)
    }

    func testFailedConnectionShowsNonSecretError() {
        let presentation = DashboardConnectionPresentation.failed

        XCTAssertEqual(presentation.statusText, "Connection issue")
        XCTAssertEqual(presentation.errorMessage, "GitHub connection failed")
        XCTAssertFalse(presentation.isConnected)
    }

    func testConnectedConnectionIdentifiesViewerInFooter() {
        let presentation = DashboardConnectionPresentation.connected(viewerLogin: "octocat")

        XCTAssertEqual(presentation.statusText, "Connected as @octocat")
        XCTAssertTrue(presentation.isConnected)
    }
}
