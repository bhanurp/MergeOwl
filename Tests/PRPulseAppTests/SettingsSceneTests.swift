import AppKit
import XCTest
@testable import PRPulseApp

final class SettingsSceneTests: XCTestCase {
    @MainActor
    func testClosingAndReopeningSettingsReusesWindow() {
        _ = NSApplication.shared
        var creations = 0
        let owner = NativeWindowOwner {
            creations += 1
            return NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        }
        let first = owner.show()
        first.close()
        XCTAssertTrue(owner.show() === first)
        XCTAssertEqual(creations, 1)
        first.close()
    }
}
