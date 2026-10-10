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

    func testMenuBarIconUsesTheAbstractWaveformMark() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/PRPulseApp/App/PRPulseApp.swift"
        )
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("PRPulseWaveformMark"))
        XCTAssertTrue(source.contains("LinearGradient"))
        XCTAssertFalse(source.contains("arrow.triangle.branch"))
    }
}
