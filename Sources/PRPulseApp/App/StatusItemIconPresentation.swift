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

        NSGraphicsContext.current?.saveGraphicsState()
        let flowerScale = NSAffineTransform()
        flowerScale.translateX(by: flowerRect.minX, yBy: flowerRect.minY)
        flowerScale.scaleX(by: flowerRect.width / 24, yBy: flowerRect.height / 24)
        flowerScale.concat()
        drawFlower()
        NSGraphicsContext.current?.restoreGraphicsState()

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

    private static func drawFlower() {
        let center = NSPoint(x: 12, y: 12)
        let primaryColors = [
            NSColor(red: 0.98, green: 0.63, blue: 0.16, alpha: 1),
            NSColor(red: 0.90, green: 0.39, blue: 0.08, alpha: 1),
            NSColor(red: 0.77, green: 0.25, blue: 0.06, alpha: 1),
            NSColor(red: 0.94, green: 0.49, blue: 0.10, alpha: 1)
        ]

        for index in 0..<4 {
            NSGraphicsContext.current?.saveGraphicsState()
            let rotation = NSAffineTransform()
            rotation.translateX(by: center.x, yBy: center.y)
            rotation.rotate(byDegrees: CGFloat(index * 90))
            rotation.translateX(by: -center.x, yBy: -center.y)
            rotation.concat()

            let petal = NSBezierPath()
            petal.move(to: NSPoint(x: 11.4, y: 11.1))
            petal.line(to: NSPoint(x: 21.7, y: 7.1))
            petal.line(to: NSPoint(x: 18.4, y: 15.7))
            petal.line(to: NSPoint(x: 12.7, y: 13.2))
            petal.close()
            primaryColors[index].setFill()
            petal.fill()

            let facet = NSBezierPath()
            facet.move(to: NSPoint(x: 11.4, y: 11.1))
            facet.line(to: NSPoint(x: 18.4, y: 15.7))
            facet.line(to: NSPoint(x: 12.7, y: 13.2))
            facet.close()
            NSColor.white.withAlphaComponent(0.24).setFill()
            facet.fill()

            NSGraphicsContext.current?.restoreGraphicsState()
        }

        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 10.75, y: 10.75, width: 2.5, height: 2.5)).fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
