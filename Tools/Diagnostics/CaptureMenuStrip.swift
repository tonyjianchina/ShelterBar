import AppKit
import ScreenCaptureKit

// Read-only menu-bar-only capture with an explicit display filter.
@main
struct CaptureMenuStrip {
    @MainActor
    static func main() async throws {
        guard CGPreflightScreenCaptureAccess() else { print("BLOCKED: screen capture permission"); exit(2) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.frame.minY == 0 }) else { exit(2) }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        filter.includeMenuBar = true
        let rect = CGRect(x: max(0, display.frame.width - 540), y: 0, width: min(540, display.frame.width), height: 33)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(rect.height * CGFloat(filter.pointPixelScale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        let pixels = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try NSBitmapImageRep(cgImage: pixels).representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: "/tmp/shelter-menubar-display.png"))
        print("DISPLAY: \(display.frame) strip=\(rect) pixels=\(pixels.width)x\(pixels.height)")
    }
}
