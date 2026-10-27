import AppKit
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
            "MergeOwl, 0 actionable"
        )
    }

    @MainActor
    func testApprovedOwlIsVisibleOnTransparentCanvasAndBadgeChangesPixels() throws {
        let plain = StatusItemIconRenderer.makeImage(actionableCount: 0)
        let badged = StatusItemIconRenderer.makeImage(actionableCount: 3)
        XCTAssertEqual(plain.size, NSSize(width: 24, height: 24))
        XCTAssertFalse(plain.isTemplate)
        let data = try XCTUnwrap(plain.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertTrue(bitmap.hasAlpha)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)).alphaComponent, 0.8)
        XCTAssertNotEqual(data, badged.tiffRepresentation)
        XCTAssertNotNil(StatusItemIconRenderer.owlImage, "Approved owl must be present in the packaged resource bundle")
    }
}
