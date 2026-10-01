import AppKit
import Combine

@MainActor
enum MenuBarStatusHandle {
    @discardableResult
    static func install(on button: NSStatusBarButton) -> AnyCancellable {
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel("打开收纳栏")
        refresh(on: button)
        button.postsFrameChangedNotifications = true
        return NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: button)
            .sink { [weak button] _ in
                Task { @MainActor in refresh(on: button) }
            }
    }

    static func refresh(on button: NSStatusBarButton?) {
        guard let button else { return }
        // System-hosted buttons center image-only content. Put the glyph at
        // the trailing edge of the native template image itself; custom
        // subviews can leave stale content in the remote host after resizing.
        let size = NSSize(width: max(16, button.bounds.width - 8), height: 16)
        guard button.image?.size != size,
              let glyph = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: nil)
        else { return }
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = min(16 / glyph.size.width, 16 / glyph.size.height)
            let drawn = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            glyph.draw(in: CGRect(x: rect.maxX - drawn.width,
                y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
            return true
        }
        image.isTemplate = true
        button.image = image
        button.needsDisplay = true
    }
}
