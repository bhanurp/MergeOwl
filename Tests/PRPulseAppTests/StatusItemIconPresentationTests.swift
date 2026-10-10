import XCTest
@testable import PRPulseApp

final class StatusItemIconPresentationTests: XCTestCase {
    func testZeroOrNegativeCountHasNoBadge() {
        XCTAssertNil(StatusItemIconPresentation.badgeText(for: 0))
        XCTAssertNil(StatusItemIconPresentation.badgeText(for: -1))
    }

    func testBadgeTextCapsAtNinetyNine() {
        XCTAssertEqual(StatusItemIconPresentation.badgeText(for: 120), "99")
    }

    func testAccessibilityLabelDescribesNormalizedActionableCount() {
        XCTAssertEqual(
            StatusItemIconPresentation.accessibilityLabel(for: -2),
            "PR Pulse, 0 actionable"
        )
    }
}
