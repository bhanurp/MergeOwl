import AppKit
import XCTest
@testable import PRPulseApp

final class GitHubPullRequestIconTests: XCTestCase {
    @MainActor
    func testOfficialVectorLoadsAsReusableTemplate() throws {
        let image = try XCTUnwrap(GitHubPullRequestIconRenderer.image)
        XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
        XCTAssertTrue(image.isTemplate)
        XCTAssertTrue(image === GitHubPullRequestIconRenderer.image)
        XCTAssertNotNil(image.tiffRepresentation)
    }
}
