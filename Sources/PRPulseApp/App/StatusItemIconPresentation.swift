import AppKit

enum StatusItemIconPresentation {
    static func normalizedCount(for actionableCount: Int) -> Int {
        max(0, actionableCount)
    }

    static func badgeText(for actionableCount: Int) -> String? {
        let count = normalizedCount(for: actionableCount)
        guard count > 0 else { return nil }
        return String(min(99, count))
    }

    static func accessibilityLabel(for actionableCount: Int) -> String {
        "MergeOwl, \(normalizedCount(for: actionableCount)) actionable"
    }
}

@MainActor
enum StatusItemIconRenderer {
    private static let imageSize = NSSize(width: 24, height: 24)
    private static let owlRect = NSRect(x: 0.5, y: 0.5, width: 23, height: 23)
    static let owlImage: NSImage? = {
        #if E2E_TESTING
        let url = Bundle.main.url(forResource: "MergeOwl", withExtension: "png")
        #else
        let installedBundleURL = Bundle.main.resourceURL?.appendingPathComponent("MergeOwl_PRPulseApp.bundle")
        let installedBundle = installedBundleURL.flatMap(Bundle.init(url:))
        let resourceBundle: Bundle?
        if let installedBundle {
            resourceBundle = installedBundle
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            // SwiftPM's generated accessor can fatalError when its build directory is absent.
            // An installed app with missing artwork must reach the visible fallback instead.
            resourceBundle = nil
        } else {
            resourceBundle = Bundle.module
        }
        let url = resourceBundle?.url(forResource: "MergeOwl", withExtension: "png")
        #endif
        return url.flatMap(NSImage.init(contentsOf:))
    }()
    private static let badgeColor = NSColor(red: 0.66, green: 0.16, blue: 0.18, alpha: 1)

    static func makeImage(actionableCount: Int) -> NSImage {
        let image = NSImage(size: imageSize)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        if let owlImage {
            owlImage.draw(in: owlRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            // Keep the status item reachable if packaging lost its artwork.
            NSImage(systemSymbolName: "eye", accessibilityDescription: "MergeOwl")?.draw(in: owlRect)
        }

        if let badgeText = StatusItemIconPresentation.badgeText(for: actionableCount) {
            let badgeRect = NSRect(x: 14, y: 14, width: 10, height: 10)
            badgeColor.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let textSize = (badgeText as NSString).size(withAttributes: attributes)
            let textRect = NSRect(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            (badgeText as NSString).draw(in: textRect, withAttributes: attributes)
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

}
