import XCTest
@testable import PRPulseApp

final class BadgeIconTests: XCTestCase {
    func testBadgeTextCapsActionableCountAtNinetyNine() {
        XCTAssertEqual(BadgeIconPresentation.badgeText(for: -1), "0")
        XCTAssertEqual(BadgeIconPresentation.badgeText(for: 0), "0")
        XCTAssertEqual(BadgeIconPresentation.badgeText(for: 99), "99")
        XCTAssertEqual(BadgeIconPresentation.badgeText(for: 124), "99")
    }

    func testAccessibilityLabelDescribesActionableCount() {
        XCTAssertEqual(
            BadgeIconPresentation.accessibilityLabel(for: -1),
            "PRPulse 0 actionable"
        )
        XCTAssertEqual(
            BadgeIconPresentation.accessibilityLabel(for: 3),
            "PRPulse 3 actionable"
        )
    }
}
