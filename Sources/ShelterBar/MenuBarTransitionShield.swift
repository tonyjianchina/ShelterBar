import AppKit
import CoreVideo
import ScreenCaptureKit

/// Keeps the visible menu bar stable while macOS temporarily lays out the
/// real status items needed for a verified native drag.
@MainActor
final class MenuBarTransitionShield {
    typealias Capture = @MainActor (CGRect) async -> NSImage?
    typealias Present = @MainActor (NSImage, CGRect) -> Void
    typealias Dismiss = @MainActor () -> Void

    private let capture: Capture
    private let present: Present
    private let dismiss: Dismiss

    init(
        capture: @escaping Capture,
        present: @escaping Present,
        dismiss: @escaping Dismiss
    ) {
        self.capture = capture
        self.present = present
        self.dismiss = dismiss
    }

    convenience init() {
        let window = MenuBarShieldWindow()
        self.init(
            capture: MenuBarScreenshot.capture,
            present: window.show,
            dismiss: window.hide
        )
    }

    /// The operation always runs. If a snapshot cannot be made, the transfer
    /// falls back to the existing visible layout transition.
    func perform<Value>(
        over region: CGRect?,
        _ operation: @MainActor () async throws -> Value
    ) async rethrows -> Value {
        guard let region, let snapshot = await capture(region) else {
            return try await operation()
        }
        present(snapshot, region)
        defer { dismiss() }
        return try await operation()
    }
}

@MainActor
private enum MenuBarScreenshot {
    static func capture(region: CGRect) async -> NSImage? {
        guard ScreenCapturePermission.isGranted, region.width > 0, region.height > 0 else { return nil }
        if #available(macOS 26.0, *),
           let image = await captureWithScreenshotConfiguration(region: region) {
            return image
        }
        // macOS 14–25 always use the display filter. On macOS 26 the rect
        // screenshot can also fail (observed as SCStreamError -3811), so fall
        // back there too instead of dropping the shield.
        return await captureWithDisplayFilter(region: region)
    }

    /// macOS 26 path. Returns nil on any failure so `capture` can fall back.
    @available(macOS 26.0, *)
    private static func captureWithScreenshotConfiguration(region: CGRect) async -> NSImage? {
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.displayIntent = .local
        configuration.dynamicRange = .sdr
        guard let output = try? await SCScreenshotManager.captureScreenshot(
            rect: region,
            configuration: configuration
        ), let image = output.sdrImage else { return nil }
        return NSImage(cgImage: image, size: region.size)
    }

    /// Fallback for `captureScreenshot(rect:configuration:)`.
    /// Capture the same display-space region through a display filter, at the
    /// display's backing scale, and present it at the region's point size so
    /// the shield matches the macOS 26 path.
    private static func captureWithDisplayFilter(region: CGRect) async -> NSImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ), let display = content.displays.first(where: {
            $0.frame.contains(CGPoint(x: region.midX, y: region.midY))
        }) else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        guard scale > 0, scale <= 4 else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = max(1, Int(ceil(region.width * scale)))
        configuration.height = max(1, Int(ceil(region.height * scale)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration
        ) else { return nil }
        return NSImage(cgImage: image, size: region.size)
    }
}

@MainActor
private final class MenuBarShieldWindow {
    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = true
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
    }

    func show(_ image: NSImage, over region: CGRect) {
        let frame = MenuBarGeometry.appKit(region)
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        panel.contentView = imageView
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
