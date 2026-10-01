import AppKit

@MainActor
enum MenuBarStatusHandle {
    static func install(on button: NSStatusBarButton) {
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel("打开收纳栏")
        guard let glyph = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: nil) else { return }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let scale = min(rect.width / glyph.size.width, rect.height / glyph.size.height)
            let size = NSSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            glyph.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                 width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        button.image = image
    }
}
