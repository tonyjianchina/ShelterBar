import AppKit

/// Keeps captured status items at their menu bar scale, including wide text items.
@MainActor
enum MenuBarIconPresentation {
    private static let maximumSize = NSSize(width: 106, height: 24)
    private static let padding: CGFloat = 7

    static func placeholder(accessibilityDescription: String? = nil) -> NSImage {
        let image = NSImage(
            systemSymbolName: "questionmark",
            accessibilityDescription: accessibilityDescription
        )!.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))!
        let nativeSize = image.size
        image.size = NSSize(width: 18 * nativeSize.width / nativeSize.height, height: 18)
        image.isTemplate = true
        return image
    }

    static func displaySize(for image: NSImage) -> NSSize {
        let nativeSize = image.size
        guard nativeSize.width.isFinite, nativeSize.height.isFinite,
              nativeSize.width > 0, nativeSize.height > 0 else { return .zero }
        let scale = min(1, maximumSize.width / nativeSize.width, maximumSize.height / nativeSize.height)
        return NSSize(width: nativeSize.width * scale, height: nativeSize.height * scale)
    }

    static func shelfWidth(for image: NSImage) -> CGFloat {
        min(120, max(32, ceil(displaySize(for: image).width + padding * 2)))
    }

    static func drawingRect(for image: NSImage, in bounds: NSRect) -> NSRect {
        let size = displaySize(for: image)
        guard size.width > 0, size.height > 0 else {
            return NSRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        }
        let availableWidth = max(0, bounds.width - padding * 2)
        let availableHeight = max(0, bounds.height - padding * 2)
        let scale = min(1, availableWidth / size.width, availableHeight / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    static func draw(_ image: NSImage, in bounds: NSRect, tintColor: NSColor = .labelColor) {
        drawPixels(image, in: drawingRect(for: image, in: bounds), tintColor: tintColor)
    }

    /// Dragging images are ordinary images so AppKit cannot reinterpret template colors.
    static func renderedImage(for image: NSImage, tintColor: NSColor = .labelColor) -> NSImage {
        let size = displaySize(for: image)
        guard size.width > 0, size.height > 0 else { return NSImage(size: .zero) }
        return NSImage(size: size, flipped: false) { rect in
            drawPixels(image, in: rect, tintColor: tintColor)
            return true
        }
    }

    private static func drawPixels(_ image: NSImage, in rect: NSRect, tintColor: NSColor) {
        guard rect.width > 0, rect.height > 0, let context = NSGraphicsContext.current else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        // Isolate the alpha mask so tinting never paints over the shelf background.
        if image.isTemplate { context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil) }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
        if image.isTemplate {
            tintColor.setFill()
            rect.fill(using: .sourceIn)
            context.cgContext.endTransparencyLayer()
        }
    }
}
