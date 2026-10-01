import AppKit

// AppKit-only check; --legacy reproduces the offscreen glyph from v0.5.4/10.
// This button is not inserted in the user's menu bar.
@main
struct CheckStatusHandle {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 3026, height: 24))
        if CommandLine.arguments.contains("--legacy") {
            button.title = ""
            button.image = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: "打开收纳栏")
            button.imagePosition = .imageRight
            button.imageHugsTitle = false
            button.imageScaling = .scaleProportionallyDown
        } else {
            MenuBarStatusHandle.install(on: button)
        }
        button.layoutSubtreeIfNeeded()
        guard let cell = button.cell, let source = button.image,
              let pixels = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { print("FAIL: no rendered button image"); exit(1) }
        let bitmap = NSBitmapImageRep(cgImage: pixels)
        var pixelBounds = CGRect.null
        for y in 0..<pixels.height {
            for x in 0..<pixels.width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                pixelBounds = pixelBounds.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let canvas = cell.imageRect(forBounds: button.bounds)
        let image = CGRect(x: canvas.minX + pixelBounds.minX * canvas.width / CGFloat(pixels.width),
            y: canvas.minY + pixelBounds.minY * canvas.height / CGFloat(pixels.height),
            width: pixelBounds.width * canvas.width / CGFloat(pixels.width),
            height: pixelBounds.height * canvas.height / CGFloat(pixels.height))
        let visible = CGRect(x: button.bounds.maxX - 24, y: 0, width: 24, height: 24)
        print("button=\(button.bounds) image=\(image) visible=\(visible)")
        guard visible.contains(image), !image.isEmpty else {
            print("FAIL: collapsed ShelterBar image is outside its visible handle")
            exit(1)
        }
        print("PASS: collapsed ShelterBar image stays in its visible handle")
    }
}
