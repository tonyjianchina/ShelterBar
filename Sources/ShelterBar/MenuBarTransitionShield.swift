import AppKit
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
