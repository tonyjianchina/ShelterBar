import AppKit
import ApplicationServices
import ScreenCaptureKit

// Captures ShelterBar's own status window. --composite additionally checks the
// actual menu-bar strip (no desktop/application contents) and a Wi-Fi control.
@main
struct CaptureStatusHandle {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
            print("BLOCKED: existing diagnostic permissions required"); exit(2)
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jensen.shelterbar").first,
              let bar: AXUIElement = MenuBarAX.value(kAXExtrasMenuBarAttribute,
                  of: AXUIElementCreateApplication(app.processIdentifier)),
              let children: [AXUIElement] = MenuBarAX.value(kAXChildrenAttribute, of: bar),
              let item = children.first(where: {
                  MenuBarAX.value(kAXIdentifierAttribute, of: $0) as String? == "shelterbar.handle"
              }), let frame = MenuBarAX.frame(of: item)
        else { print("FAIL: no ShelterBar status handle"); exit(1) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let matches = content.windows.filter {
            ($0.owningApplication?.bundleIdentifier == "com.apple.controlcenter"
                || $0.owningApplication?.processID == app.processIdentifier)
                && $0.windowLayer == Int(CGWindowLevelForKey(.statusWindow))
                && abs($0.frame.midX - frame.midX) <= 3
                && abs($0.frame.midY - frame.midY) <= 5
                && abs($0.frame.width - frame.width) <= 16
        }
        guard matches.count == 1, let window = matches.first else {
            print("FAIL: status window match count=\(matches.count) AX=\(frame)"); exit(1)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(ceil(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        configuration.height = Int(ceil(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.includeChildWindows = false
        let pixels = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        print("SURFACE: native=\(window.frame) content=\(filter.contentRect) pixels=\(pixels.width)x\(pixels.height)")
        if CommandLine.arguments.contains("--inspect-surface") {
            let bitmap = NSBitmapImageRep(cgImage: pixels)
            try bitmap.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: "/tmp/shelter-status-full.png"))
            var bounds = CGRect.null
            for y in 0..<pixels.height {
                for x in 0..<pixels.width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            print("PIXEL_BOUNDS: \(bounds)")
        }
        let handle = CGRect(x: frame.maxX - frame.height, y: frame.minY, width: frame.height, height: frame.height).integral
        guard let crop = MenuBarIconMatcher.pixelCrop(itemFrame: handle, windowFrame: window.frame,
                pixelSize: CGSize(width: pixels.width, height: pixels.height)),
              let cropped = pixels.cropping(to: crop) else { print("FAIL: invalid crop"); exit(1) }
        let bitmap = NSBitmapImageRep(cgImage: cropped)
        if CommandLine.arguments.contains("--composite") {
            guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first,
                  let controls: AXUIElement = MenuBarAX.value(kAXExtrasMenuBarAttribute,
                    of: AXUIElementCreateApplication(controlCenter.processIdentifier)),
                  let entries: [AXUIElement] = MenuBarAX.value(kAXChildrenAttribute, of: controls),
                  let wifi = entries.first(where: {
                      MenuBarAX.value(kAXIdentifierAttribute, of: $0) as String? == "com.apple.menuextra.wifi"
                  }), let wifiFrame = MenuBarAX.frame(of: wifi),
                  content.displays.contains(where: { $0.frame.contains(wifiFrame) }) else {
                print("BLOCKED: no on-display Wi-Fi positive control"); exit(2)
            }
            let control = try await SCScreenshotManager.captureImage(in: wifiFrame.integral)
            let controlBitmap = NSBitmapImageRep(cgImage: control)
            var controlMin: CGFloat = 1, controlMax: CGFloat = 0
            for y in 0..<control.height {
                for x in 0..<control.width {
                    guard let color = controlBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let value = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                    controlMin = min(controlMin, value); controlMax = max(controlMax, value)
                }
            }
            guard controlMax - controlMin > 0.2 else {
                print("BLOCKED: system Wi-Fi positive control is also blank; menu-bar capture is unavailable"); exit(2)
            }
            if let display = content.displays.first(where: { $0.frame.contains(handle) }) {
                let stripRect = CGRect(x: handle.minX, y: display.frame.minY,
                    width: display.frame.maxX - handle.minX, height: 34)
                let strip = try await SCScreenshotManager.captureImage(in: stripRect)
                try NSBitmapImageRep(cgImage: strip).representation(using: .png, properties: [:])!.write(
                    to: URL(fileURLWithPath: "/tmp/shelter-status-strip-composite.png"))
            }
            let screen = try await SCScreenshotManager.captureImage(in: handle)
            let composite = NSBitmapImageRep(cgImage: screen)
            try composite.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: "/tmp/shelter-status-handle-composite.png"))
            guard screen.width == cropped.width, screen.height == cropped.height else {
                print("BLOCKED: composite=\(screen.width)x\(screen.height) mask=\(cropped.width)x\(cropped.height)"); exit(2)
            }
            var foreground: [CGFloat] = [], background: [CGFloat] = []
            for y in 0..<screen.height {
                for x in 0..<screen.width {
                    guard let color = composite.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent else { continue }
                    let luminance = color.redComponent * 0.2126 + color.greenComponent * 0.7152 + color.blueComponent * 0.0722
                    if alpha > 0.8 { foreground.append(luminance) }
                    if alpha < 0.01 { background.append(luminance) }
                }
            }
            guard !foreground.isEmpty, !background.isEmpty else {
                print("FAIL: no usable native glyph mask"); exit(1)
            }
            let difference = abs(foreground.reduce(0, +) / CGFloat(foreground.count)
                - background.reduce(0, +) / CGFloat(background.count))
            print("COMPOSITE: handle=\(handle) glyph/background contrast=\(difference)")
            guard difference > 0.15 else {
                print("FAIL: native glyph exists but is absent from the composited screen"); exit(1)
            }
            print("PASS: archive glyph has contrast on the actual composited screen")
        }
        let output = URL(fileURLWithPath: "/tmp/shelter-status-handle-capture.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
        print("CAPTURE: \(output.path) native=\(window.frame) handle=\(handle)")
        guard MenuBarGlyphImage.make(from: cropped, logicalSize: handle.size) != nil else {
            print("FAIL: the visible status handle has no glyph pixels"); exit(1)
        }
        print("PASS: hosted status window contains glyph pixels; this alone does not prove screen visibility")
    }
}
