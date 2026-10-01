import AppKit
import ApplicationServices

// Reads only specified apps' native status icons, then renders those exact
// pixels through the production shelf renderer on a light/dark test background.
@main
struct CheckShelfContrast {
    @MainActor
    static func main() async throws {
        guard AXIsProcessTrusted(), ScreenCapturePermission.isGranted else {
            print("BLOCKED: existing diagnostic permissions required"); exit(2)
        }
        let bundles = Set(CommandLine.arguments.dropFirst())
        let items = AccessibilityMenuBarItemSource().items().filter {
            $0.application?.bundleIdentifier.map(bundles.contains) == true
        }
        let snapshots = await MenuBarIconCapture().capture(items)
        guard snapshots.count == bundles.count else {
            print("BLOCKED: expected \(bundles.count) status icons, captured \(snapshots.count)"); exit(2)
        }
        var failed = false
        for (index, snapshot) in snapshots.enumerated() {
            let source = snapshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            try NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: "/tmp/shelter-contrast-source-\(index).png"))
            let bitmap = NSBitmapImageRep(cgImage: source)
            var tones: [Int: Int] = [:], colored = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.25 else { continue }
                    let hi = max(c.redComponent, c.greenComponent, c.blueComponent)
                    let lo = min(c.redComponent, c.greenComponent, c.blueComponent)
                    if hi - lo > 0.055 { colored += 1 }
                    tones[Int((c.redComponent + c.greenComponent + c.blueComponent) / 3 * 10), default: 0] += 1
                }
            }
            let rendered = MenuBarIconPresentation.renderedImage(for: snapshot.image, tintColor: .black)
            let pixels = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let output = NSBitmapImageRep(cgImage: pixels)
            var core = 0, dark = 0
            for y in 0..<output.pixelsHigh {
                for x in 0..<output.pixelsWide {
                    guard let c = output.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.8 else { continue }
                    core += 1
                    if (c.redComponent + c.greenComponent + c.blueComponent) / 3 < 0.55 { dark += 1 }
                }
            }
            print("\(snapshot.id) template=\(snapshot.image.isTemplate) tones=\(tones.sorted { $0.key < $1.key }) colored=\(colored) darkCore=\(dark)/\(core)")
            if core == 0 || dark * 2 < core { failed = true }
        }
        print(failed ? "FAIL: captured white glyph stays light on the light shelf" : "PASS: captured glyphs have dark foreground on the light shelf")
        exit(failed ? 1 : 0)
    }
}
