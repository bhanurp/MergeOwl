import XCTest
@testable import PRPulseApp

final class BadgeIconTests: XCTestCase {
    func testBadgeTextCapsActionableCountAtNinetyNine() {
        XCTAssertNil(StatusItemIconPresentation.badgeText(for: -1))
        XCTAssertNil(StatusItemIconPresentation.badgeText(for: 0))
        XCTAssertEqual(StatusItemIconPresentation.badgeText(for: 99), "99")
        XCTAssertEqual(StatusItemIconPresentation.badgeText(for: 124), "99")
    }

    func testAccessibilityLabelDescribesActionableCount() {
        XCTAssertEqual(
            StatusItemIconPresentation.accessibilityLabel(for: -1),
            "PR Pulse, 0 actionable"
        )
        XCTAssertEqual(
            StatusItemIconPresentation.accessibilityLabel(for: 3),
            "PR Pulse, 3 actionable"
        )
    }

}
