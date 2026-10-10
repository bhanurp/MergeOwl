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
        "PR Pulse, \(normalizedCount(for: actionableCount)) actionable"
    }
}

@MainActor
enum StatusItemIconRenderer {
    private static let imageSize = NSSize(width: 24, height: 24)
    static let flowerRect = NSRect(x: 1.5, y: 1.5, width: 21, height: 21)
    private static let badgeColor = NSColor(red: 0.66, green: 0.16, blue: 0.18, alpha: 1)

    static func makeImage(actionableCount: Int) -> NSImage {
        let image = NSImage(size: imageSize)
        image.lockFocus()

        flowerImage.draw(in: flowerRect)

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

    private static var flowerImage: NSImage {
        guard let url = Bundle.module.url(
            forResource: "PRPulseFlower@2x",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            assertionFailure("Missing PR Pulse flower asset")
            return NSImage(size: flowerRect.size)
        }

        return image
    }
}
