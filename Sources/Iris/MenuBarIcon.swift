import AppKit

/// A StreamCam-style webcam glyph for the menu bar: rounded body, lens and mount. Drawn as a template so it adapts like system icons.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Iris"
        return image
    }

    private static func draw() {
        NSColor.black.set()

        // Mount, separated from the body by a hairline gap like the StreamCam's hinge.
        NSBezierPath(roundedRect: NSRect(x: 6.5, y: 0.75, width: 5, height: 2.1), xRadius: 0.6, yRadius: 0.6).fill()

        // Solid body with a ring knocked out around the lens.
        let body = NSRect(x: 1.5, y: 3.5, width: 15, height: 12.5)
        let center = NSPoint(x: body.midX, y: body.midY)
        let shape = NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4)
        shape.append(circle(center, 4.3))
        shape.append(circle(center, 3))
        shape.windingRule = .evenOdd
        shape.fill()
    }

    private static func circle(_ center: NSPoint, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
