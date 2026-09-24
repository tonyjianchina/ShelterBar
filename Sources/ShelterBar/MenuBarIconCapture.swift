import AppKit
import CoreVideo
import ScreenCaptureKit

struct MenuBarIconSnapshot {
    let id: String
    let pid: pid_t
    let image: NSImage
}

struct MenuBarCaptureWindow {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let frame: CGRect
    let ownerBundleID: String?

    init(id: CGWindowID, pid: pid_t, layer: Int, frame: CGRect, ownerBundleID: String? = nil) {
        self.id = id
        self.pid = pid
        self.layer = layer
        self.frame = frame
        self.ownerBundleID = ownerBundleID
    }
}

enum MenuBarIconMatcher {
    /// Never capture a whole application or display as a fallback. The AX item
    /// must identify exactly one small status window belonging to its process
    /// or hosted by the system's verified Control Center process.
    static func match(frame: CGRect, pid: pid_t, windows: [MenuBarCaptureWindow]) -> CGWindowID? {
        guard frame.width > 1, frame.width <= 1024, frame.height > 1, frame.height <= 100,
              frame.origin.x.isFinite, frame.origin.y.isFinite else { return nil }
        let candidates = windows.compactMap { window -> MenuBarNativeWindow? in
            guard window.frame.width > 1, window.frame.height > 1 else { return nil }
            return MenuBarNativeWindow(id: window.id, pid: window.pid, layer: window.layer,
                                       frame: window.frame, ownerBundleID: window.ownerBundleID)
        }
        return MenuBarNativeWindow.match(axFrame: frame, clientPID: pid, windows: candidates)?.id
    }

    static func pixelCrop(itemFrame: CGRect, windowFrame: CGRect, pixelSize: CGSize) -> CGRect? {
        guard windowFrame.width > 0, windowFrame.height > 0 else { return nil }
        let content = itemFrame.intersection(windowFrame)
        guard !content.isNull, content.width > 1, content.height > 1 else { return nil }
        let xScale = pixelSize.width / windowFrame.width, yScale = pixelSize.height / windowFrame.height
        return CGRect(x: (content.minX - windowFrame.minX) * xScale,
                      y: (content.minY - windowFrame.minY) * yScale,
                      width: content.width * xScale, height: content.height * yScale).integral
    }
}

@MainActor
final class MenuBarIconCapture {
    func capture(_ items: [ShelfItem]) async -> [MenuBarIconSnapshot] {
        guard !items.isEmpty, ScreenCapturePermission.isGranted, !Task.isCancelled else { return [] }
        let initialFrames = Dictionary(items.compactMap { item -> (String, CGRect)? in
            item.menuBarReference.currentFrame().map { (item.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else { return [] }
        let candidates = content.windows.compactMap { window -> MenuBarCaptureWindow? in
            guard let owner = window.owningApplication else { return nil }
            return MenuBarCaptureWindow(id: window.windowID, pid: owner.processID,
                                        layer: window.windowLayer, frame: window.frame,
                                        ownerBundleID: owner.bundleIdentifier)
        }
        var snapshots: [MenuBarIconSnapshot] = []
        for item in items {
            guard !Task.isCancelled, ScreenCapturePermission.isGranted else { return [] }
            guard let frame = initialFrames[item.id], item.menuBarReference.currentFrame() == frame,
                  let id = MenuBarIconMatcher.match(frame: frame, pid: item.menuBarReference.pid, windows: candidates),
                  let window = content.windows.first(where: { $0.windowID == id }) else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let size = filter.contentRect.size
            let scale = CGFloat(filter.pointPixelScale)
            guard size.width > 0, size.width <= 1024, size.height > 0, size.height <= 100,
                  abs(size.width - window.frame.width) <= 1, abs(size.height - window.frame.height) <= 1,
                  scale > 0, scale <= 4 else { continue }
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(ceil(size.width * scale)))
            configuration.height = max(1, Int(ceil(size.height * scale)))
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = false
            configuration.showMouseClicks = false
            configuration.capturesAudio = false
            configuration.shouldBeOpaque = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
            configuration.includeChildWindows = false
            configuration.captureResolution = .best
            guard let pixels = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            ), !Task.isCancelled, ScreenCapturePermission.isGranted,
                  item.menuBarReference.currentFrame() == frame,
                  let crop = MenuBarIconMatcher.pixelCrop(itemFrame: frame, windowFrame: window.frame,
                      pixelSize: CGSize(width: pixels.width, height: pixels.height)),
                  let cropped = pixels.cropping(to: crop),
                  let image = MenuBarGlyphImage.make(from: cropped,
                      logicalSize: frame.intersection(window.frame).size) else { continue }
            snapshots.append(MenuBarIconSnapshot(id: item.id, pid: item.menuBarReference.pid, image: image))
        }
        return snapshots
    }
}

enum MenuBarGlyphImage {
    /// Empty off-screen captures must not replace the last usable image.
    /// Template tinting applies only to transparent, monochrome glyphs; colored
    /// status indicators retain their original pixels.
    static func make(from source: CGImage, logicalSize: CGSize) -> NSImage? {
        let width = source.width, height = source.height
        guard width > 0, height > 0, width <= 4096, height <= 400 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        var visible = 0, colored = 0, transparent = 0
        var darkest = 255, lightest = 0, solidPixels = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha < 12 { transparent += 1; continue }
            visible += 1
            let channels = [Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2])]
            // Compare unpremultiplied channel differences so faint colored
            // status indicators cannot accidentally become monochrome.
            if (channels.max()! - channels.min()!) * 255 > 14 * alpha { colored += 1 }
            if alpha >= 64 {
                let gray = channels.reduce(0, +) * 255 / (3 * alpha)
                darkest = min(darkest, gray)
                lightest = max(lightest, gray)
                solidPixels += 1
            }
        }
        guard visible > 0 else { return nil }
        let image = NSImage(cgImage: source, size: logicalSize)
        image.isTemplate = transparent > width * height / 5 && colored == 0 &&
            solidPixels > 0 && lightest - darkest <= 16
        return image
    }
}
