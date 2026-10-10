import XCTest
@testable import PRPulseApp

final class BadgeIconTests: XCTestCase {
    func testBadgeTextCapsActionableCountAtNinetyNine() {
        XCTAssertEqual(BadgeIconPresentation.badgeText(for: 124), "99")
    }

    func testAccessibilityLabelDescribesActionableCount() {
        XCTAssertEqual(
            BadgeIconPresentation.accessibilityLabel(for: 3),
            "PRPulse 3 actionable"
        )
    }
}
