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

    /// Icon to draw when no status-item glyph has been captured. Prefer the
    /// owning application's icon — it stays recognizable for third-party items
    /// whose menu-bar pixels cannot be captured — and only then the question mark.
    static func unresolvedIcon(
        application: NSRunningApplication?, accessibilityDescription: String? = nil
    ) -> NSImage {
        applicationIcon(for: application) ?? placeholder(accessibilityDescription: accessibilityDescription)
    }

    /// Dock/app icon of a running owner. Copied so later drawing cannot mutate
    /// the shared system image. Not a captured status glyph: callers must not
    /// persist it as one or stop trying to capture the real menu-bar artwork.
    static func applicationIcon(for application: NSRunningApplication?) -> NSImage? {
        guard let application, !application.isTerminated,
              let icon = reportedApplicationIcon(application),
              icon.size.width > 1, icon.size.height > 1,
              let copy = icon.copy() as? NSImage else { return nil }
        copy.isTemplate = false
        if (copy.accessibilityDescription ?? "").isEmpty {
            copy.accessibilityDescription = application.localizedName
        }
        return copy
    }

    /// `NSRunningApplication.icon` is a non-optional `NSImage` in SDKs before
    /// macOS 27.2 and `NSImage?` in the 27.2 SDK. Returning `NSImage?` compiles
    /// against both; callers unwrap the result.
    static func reportedApplicationIcon(_ application: NSRunningApplication) -> NSImage? {
        application.icon
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
        // Resolve captured neutral variants against this view's label tint,
        // not the appearance of the menu bar when its pixels were captured.
        let color = tintColor.usingColorSpace(.deviceRGB)
        let brightness = color.map { $0.redComponent * 0.2126 + $0.greenComponent * 0.7152 + $0.blueComponent * 0.0722 } ?? 0
        let appearance = NSAppearance(named: brightness > 0.5 ? .darkAqua : .aqua)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !image.isTemplate, let backdrop = contrastBackdrop(for: image, appearance: appearance ?? .currentDrawing()) {
            // Colored captures keep their pixels; a light icon taken from a dark
            // menu bar (or the reverse) gets a soft plate so it stays legible.
            backdrop.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -2), xRadius: 5, yRadius: 5).fill()
        }
        // Isolate the alpha mask so tinting never paints over the shelf background.
        if image.isTemplate { context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil) }
        let drawImage = {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
        if let appearance { appearance.performAsCurrentDrawingAppearance(drawImage) }
        else { drawImage() }
        if image.isTemplate {
            tintColor.setFill()
            rect.fill(using: .sourceIn)
            context.cgContext.endTransparencyLayer()
        }
    }

    static func contrastBackdrop(for image: NSImage,
                                 appearance: NSAppearance = .currentDrawing()) -> NSColor? {
        guard !image.isTemplate else { return nil }
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        switch MenuBarGlyphImage.tone(of: image) {
        case .light where !isDark: return NSColor(white: 0, alpha: 0.42)
        case .dark where isDark: return NSColor(white: 1, alpha: 0.5)
        default: return nil
        }
    }
}
