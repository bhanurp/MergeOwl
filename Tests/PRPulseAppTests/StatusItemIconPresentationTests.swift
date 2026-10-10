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

    @MainActor
    func testFlowerUsesMostOfTheMenuBarIconCanvas() {
        XCTAssertEqual(StatusItemIconRenderer.flowerRect.size, NSSize(width: 21, height: 21))
    }

    func testFlowerIsDrawnAsANativeVectorMark() throws {
        let source = try source(named: "Sources/PRPulseApp/App/StatusItemIconPresentation.swift")

        XCTAssertTrue(source.contains("private static func drawFlower()"))
        XCTAssertFalse(source.contains("Bundle.module.url"))
    }

    private func source(named path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(path))
    }
}
