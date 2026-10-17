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

/// Overall lightness of a captured colored image, used to keep it legible on
/// a shelf whose appearance differs from the menu bar it was captured from.
enum MenuBarGlyphTone: Int {
    case mixed, light, dark
}

enum MenuBarGlyphImage {
    /// Fraction of visible pixels allowed to carry color before the capture is
    /// treated as a colored status item. Wallpaper bleed and vibrancy leave a
    /// handful of faintly tinted antialiasing pixels on otherwise white glyphs.
    static let coloredFractionLimit = 0.03
    /// Gray spread (2nd to 98th percentile) of the glyph body that still counts
    /// as a single-tone glyph. Real black-and-white artwork spans ~255.
    static let grayRangeLimit = 64

    nonisolated(unsafe) private static var toneKey: UInt8 = 0

    static func setTone(_ tone: MenuBarGlyphTone, on image: NSImage) {
        objc_setAssociatedObject(image, &toneKey, NSNumber(value: tone.rawValue), .OBJC_ASSOCIATION_RETAIN)
    }

    nonisolated(unsafe) private static var adaptiveKey: UInt8 = 0

    /// True for neutral shaded glyphs drawn per appearance (light/dark variant).
    static func isAdaptiveNeutral(_ image: NSImage) -> Bool {
        (objc_getAssociatedObject(image, &adaptiveKey) as? NSNumber)?.boolValue ?? false
    }

    static func tone(of image: NSImage) -> MenuBarGlyphTone {
        (objc_getAssociatedObject(image, &toneKey) as? NSNumber)
            .flatMap { MenuBarGlyphTone(rawValue: $0.intValue) } ?? .mixed
    }

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
        var visible = 0, colored = 0, transparent = 0, maxAlpha = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha < 12 { transparent += 1; continue }
            visible += 1
            maxAlpha = max(maxAlpha, alpha)
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            // Compare unpremultiplied channel differences so faint colored
            // status indicators cannot accidentally become monochrome.
            if (max(r, g, b) - min(r, g, b)) * 255 > 14 * alpha { colored += 1 }
        }
        guard visible > 0 else { return nil }
        // The glyph body is judged relative to its own peak opacity: vibrancy
        // renders menu bar glyphs partially transparent, and the thin
        // antialiased rim unpremultiplies to noisy, darker grays.
        let solidAlpha = max(64, maxAlpha / 2)
        var grays: [Int] = []
        var weightedGray = 0, totalWeight = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha >= solidAlpha else { continue }
            let sum = Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
            let gray = min(255, sum * 255 / (3 * alpha))
            grays.append(gray)
            weightedGray += gray * alpha
            totalWeight += alpha
        }
        grays.sort()
        let grayRange = grays.isEmpty ? Int.max
            : grays[(grays.count - 1) * 98 / 100] - grays[(grays.count - 1) * 2 / 100]
        let isTemplate = transparent > width * height / 5 &&
            Double(colored) <= Double(visible) * coloredFractionLimit &&
            grayRange <= grayRangeLimit
        let image: NSImage
        if isTemplate, maxAlpha < 250, let mask = normalizedMask(pixels, width: width, height: height,
                                                                 maxAlpha: maxAlpha) {
            // Only alpha matters for templates; restore full opacity so the
            // tinted glyph is as legible as a native one.
            image = NSImage(cgImage: mask, size: logicalSize)
        } else {
            image = NSImage(cgImage: source, size: logicalSize)
        }
        image.isTemplate = isTemplate
        guard !isTemplate, totalWeight > 0 else { return image }
        // Shading and captured shadows make real neutral glyphs multi-tone.
        // Keep those details, but choose a dark/light variant for the shelf
        // instead of leaving a captured white glyph white on a light panel.
        // A small colored status badge must not prevent the neutral body from
        // adapting. Preserve every chromatic pixel; never invert a color-led icon.
        if transparent > width * height / 5, colored * 8 <= visible,
           let adaptive = adaptiveNeutralImage(pixels, width: width, height: height, logicalSize: logicalSize,
                                               original: image,
                                               originallyLight: weightedGray > totalWeight * 127) {
            return adaptive
        }
        // Color-led captures keep their pixels; record their overall tone so
        // the shelf can add a contrast plate when needed.
        let mean = weightedGray / totalWeight
        let tone: MenuBarGlyphTone = mean >= 200 ? .light : mean <= 60 ? .dark : .mixed
        setTone(tone, on: image)
        return image
    }

    private static func adaptiveNeutralImage(_ source: [UInt8], width: Int, height: Int, logicalSize: CGSize,
                                             original image: NSImage, originallyLight: Bool) -> NSImage? {
        var pixels = source
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            let channels = [Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2])]
            guard (channels.max()! - channels.min()!) * 255 <= 14 * alpha else { continue }
            for channel in 0..<3 { pixels[index + channel] = UInt8(max(0, alpha - Int(pixels[index + channel]))) }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let inverse = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let inverseImage = NSImage(cgImage: inverse, size: logicalSize)
        let lightBackground = originallyLight ? inverseImage : image
        let darkBackground = originallyLight ? image : inverseImage
        let adaptive = NSImage(size: logicalSize, flipped: false) { rect in
            let appearance = NSAppearance.currentDrawing()
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (dark ? darkBackground : lightBackground).draw(in: rect, from: .zero,
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
        adaptive.cacheMode = .never
        objc_setAssociatedObject(adaptive, &adaptiveKey, NSNumber(value: true), .OBJC_ASSOCIATION_RETAIN)
        return adaptive
    }

    private static func normalizedMask(_ pixels: [UInt8], width: Int, height: Int, maxAlpha: Int) -> CGImage? {
        guard maxAlpha > 0 else { return nil }
        var mask = [UInt8](repeating: 0, count: pixels.count)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = UInt8(min(255, Int(pixels[index + 3]) * 255 / maxAlpha))
            mask[index] = alpha; mask[index + 1] = alpha; mask[index + 2] = alpha; mask[index + 3] = alpha
        }
        return mask.withUnsafeMutableBytes { bytes -> CGImage? in
            CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)?
                .makeImage()
        }
    }
}
