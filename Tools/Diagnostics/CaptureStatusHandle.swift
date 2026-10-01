import AppKit
import ApplicationServices
import ScreenCaptureKit

// Captures only ShelterBar's own hosted status window, then crops its visible
// trailing handle. Never captures the desktop or unrelated application windows.
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
        let handle = CGRect(x: frame.maxX - frame.height, y: frame.minY, width: frame.height, height: frame.height)
        guard let crop = MenuBarIconMatcher.pixelCrop(itemFrame: handle, windowFrame: window.frame,
                pixelSize: CGSize(width: pixels.width, height: pixels.height)),
              let cropped = pixels.cropping(to: crop) else { print("FAIL: invalid crop"); exit(1) }
        let bitmap = NSBitmapImageRep(cgImage: cropped)
        let output = URL(fileURLWithPath: "/tmp/shelter-status-handle-capture.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
        print("CAPTURE: \(output.path) native=\(window.frame) handle=\(handle)")
        guard MenuBarGlyphImage.make(from: cropped, logicalSize: handle.size) != nil else {
            print("FAIL: the visible status handle has no glyph pixels"); exit(1)
        }
        print("PASS: the visible status handle contains rendered pixels (inspect the PNG)")
    }
}
