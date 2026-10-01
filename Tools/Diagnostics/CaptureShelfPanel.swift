import AppKit
import ScreenCaptureKit

// Read-only: captures only ShelterBar's own shelf window, never other windows
// or a fallback desktop rectangle. Hosted pixels are not an interaction test.
@main
struct CaptureShelfPanel {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        guard CGPreflightScreenCaptureAccess() else { print("BLOCKED: screen capture permission"); exit(2) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let panel = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == "com.jensen.shelterbar"
                && $0.windowLayer == Int(CGWindowLevelForKey(.popUpMenuWindow))
                && $0.frame.width >= 200 && $0.frame.height > 40 && $0.frame.height <= 100
        }) else { print("BLOCKED: no ShelterBar shelf window"); exit(2) }
        let filter = SCContentFilter(desktopIndependentWindow: panel)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(ceil(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        configuration.height = Int(ceil(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = false
        let pixels = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: pixels)
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: "/tmp/shelter-shelf-panel.png"))
        print("CAPTURE: own shelf \(panel.frame), saved /tmp/shelter-shelf-panel.png; inspect pixels before claiming success")
    }
}
