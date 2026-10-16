import AppKit
import XCTest
@testable import PRPulseApp

@MainActor
final class PRPulseStatusItemControllerTests: XCTestCase {
    func testInstallRetainsExactlyOneStatusItem() {
        let statusBar = FakeStatusBarHost()
        let popover = FakePopoverHost()
        let controller = PRPulseStatusItemController(statusBar: statusBar, popover: popover)
        let dashboard = AppDependencies(useMockClient: true).dashboard

        controller.install(with: dashboard, actions: .noop)
        controller.install(with: dashboard, actions: .noop)

        XCTAssertEqual(statusBar.createdItemCount, 1)
    }

    func testToggleAlternatesPopoverPresentation() {
        let statusBar = FakeStatusBarHost()
        let popover = FakePopoverHost()
        let controller = PRPulseStatusItemController(statusBar: statusBar, popover: popover)

        controller.install(with: AppDependencies(useMockClient: true).dashboard, actions: .noop)
        controller.togglePopover()
        controller.togglePopover()

        XCTAssertEqual(popover.events, [.show, .close])
    }
}

@MainActor
private final class FakeStatusBarHost: StatusBarHosting {
    private(set) var createdItemCount = 0
    private let button = FakeStatusItemButton()

    func makeButton(onClick: @escaping @MainActor () -> Void) -> any StatusItemButtonHosting {
        createdItemCount += 1
        button.onClick = onClick
        return button
    }

    func removeButton(_ button: any StatusItemButtonHosting) {}
}

@MainActor
private final class FakeStatusItemButton: StatusItemButtonHosting {
    let anchorView = NSView()
    var onClick: (@MainActor () -> Void)?

    func update(image: NSImage, accessibilityLabel: String) {}
}

@MainActor
private final class FakePopoverHost: PopoverHosting {
    enum Event: Equatable {
        case show
        case close
    }

    private(set) var events: [Event] = []
    var isShown = false

    func configure(content: NSViewController) {}

    func show(relativeTo anchorView: NSView) {
        isShown = true
        events.append(.show)
    }

    func close() {
        isShown = false
        events.append(.close)
    }
}
