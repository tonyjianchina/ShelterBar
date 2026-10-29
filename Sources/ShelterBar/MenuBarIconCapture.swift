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
    /// Prefer one native status window. macOS 27 instead composites items in
    /// MenuBarAgent; that host is only eligible for a bounded item-region
    /// capture, never a whole-menu-bar or whole-display capture.
    static func match(frame: CGRect, pid: pid_t, windows: [MenuBarCaptureWindow]) -> CGWindowID? {
        guard frame.width > 1, frame.width <= 1024, frame.height > 1, frame.height <= 100,
              frame.origin.x.isFinite, frame.origin.y.isFinite else { return nil }
        let candidates = windows.compactMap { window -> MenuBarNativeWindow? in
            guard window.frame.width > 1, window.frame.height > 1 else { return nil }
            return MenuBarNativeWindow(id: window.id, pid: window.pid, layer: window.layer,
                                       frame: window.frame, ownerBundleID: window.ownerBundleID)
        }
        if let native = MenuBarNativeWindow.match(axFrame: frame, clientPID: pid, windows: candidates) {
            return native.id
        }
        guard pid > 0 else { return nil }
        let hosts = windows.filter {
            $0.ownerBundleID == "com.apple.MenuBarAgent"
                && [Int(CGWindowLevelForKey(.statusWindow)), Int(CGWindowLevelForKey(.statusWindow)) - 1].contains($0.layer)
                && $0.frame.width >= 512 && $0.frame.width <= 16384
                && $0.frame.height > 1 && $0.frame.height <= 60
                && $0.frame.contains(frame)
        }
        guard let host = hosts.first,
              hosts.dropFirst().allSatisfy({ $0.frame == host.frame }) else { return nil }
        return host.id
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

/// MenuBarAgent renders every third-party status item into one composite
/// window.  Immediately after a drag, an item's AX rectangle can already be
/// stable while that rectangle still contains the animated old and new menu
/// bar layouts.  Accept only two consecutive captures with identical pixels.
struct MenuBarCaptureStability {
    private struct Fingerprint: Equatable {
        let width: Int
        let height: Int
        let bitsPerPixel: Int
        let bytesPerRow: Int
        let pixels: Data

        init?(_ image: CGImage) {
            guard let data = image.dataProvider?.data else { return nil }
            width = image.width
            height = image.height
            bitsPerPixel = image.bitsPerPixel
            bytesPerRow = image.bytesPerRow
            pixels = data as Data
        }
    }

    private var previous: Fingerprint?

    mutating func observe(_ image: CGImage) -> Bool {
        guard let current = Fingerprint(image) else {
            previous = nil
            return false
        }
        defer { previous = current }
        return previous == current
    }
}

@MainActor
final class MenuBarIconCapture {
    private let isLogicallyHidden: @MainActor (ShelfItem) -> Bool

    init(isLogicallyHidden: @escaping @MainActor (ShelfItem) -> Bool = { _ in false }) {
        self.isLogicallyHidden = isLogicallyHidden
    }

    func capture(_ items: [ShelfItem]) async -> [MenuBarIconSnapshot] {
        guard !items.isEmpty, ScreenCapturePermission.isGranted, !Task.isCancelled else { return [] }
        let initialFrames = Dictionary(items.compactMap { item -> (String, CGRect)? in
            guard !isLogicallyHidden(item) else { return nil }
            return item.menuBarReference.currentFrame().map { (item.id, $0) }
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
            guard !Task.isCancelled else { return [] }
            guard !isLogicallyHidden(item),
                  let frame = initialFrames[item.id], item.menuBarReference.currentFrame() == frame,
                  let id = MenuBarIconMatcher.match(frame: frame, pid: item.menuBarReference.pid, windows: candidates),
                  let window = content.windows.first(where: { $0.windowID == id }) else { continue }
            if window.owningApplication?.bundleIdentifier == "com.apple.MenuBarAgent" {
                // A hidden item's AX rectangle can now belong to its neighbour.
                // Read only a currently exposed, full item rectangle. AX geometry
                // settles before MenuBarAgent's drag animation, so also require
                // two matching rendered frames before persisting the glyph.
                guard #available(macOS 15.2, *),
                      ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
                      MenuBarGeometry.visibleFrame(frame) == frame,
                      let pixels = await stableCompositeCapture(item: item, frame: frame),
                      !Task.isCancelled,
                      !isLogicallyHidden(item), item.menuBarReference.currentFrame() == frame,
                      let image = MenuBarCompositeGlyph.make(from: pixels, logicalSize: frame.size,
                          hasCount: item.hasNumericTitle) else { continue }
                snapshots.append(MenuBarIconSnapshot(id: item.id, pid: item.menuBarReference.pid, image: image))
                continue
            }
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
            if #available(macOS 15.0, *) {
                configuration.showMouseClicks = false
            }
            configuration.capturesAudio = false
            configuration.shouldBeOpaque = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
            if #available(macOS 14.2, *) {
                configuration.includeChildWindows = false
            }
            configuration.captureResolution = .best
            guard let pixels = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            ), !Task.isCancelled,
                  !isLogicallyHidden(item), item.menuBarReference.currentFrame() == frame,
                  let crop = MenuBarIconMatcher.pixelCrop(itemFrame: frame, windowFrame: window.frame,
                      pixelSize: CGSize(width: pixels.width, height: pixels.height)),
                  let cropped = pixels.cropping(to: crop) else { continue }
            let logicalSize = frame.intersection(window.frame).size
            let nativeImage = item.hasNumericTitle
                ? MenuBarCompositeGlyph.make(from: cropped, logicalSize: logicalSize, hasCount: true)
                : MenuBarGlyphImage.make(from: cropped, logicalSize: logicalSize)
            let image: NSImage?
            if let nativeImage {
                image = nativeImage
            } else if #available(macOS 15.2, *),
                      ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
                      MenuBarGeometry.visibleFrame(frame) == frame,
                      let composite = await stableCompositeCapture(item: item, frame: frame) {
                // Some Control Center-hosted status windows expose only a
                // full-width material strip in their private surface. Fall
                // back to the pixels the user actually sees before giving up.
                image = MenuBarCompositeGlyph.make(
                    from: composite, logicalSize: frame.size, hasCount: item.hasNumericTitle
                )
            } else {
                image = nil
            }
            guard let image else { continue }
            snapshots.append(MenuBarIconSnapshot(id: item.id, pid: item.menuBarReference.pid, image: image))
        }
        return snapshots
    }

    @available(macOS 15.2, *)
    private func stableCompositeCapture(item: ShelfItem, frame: CGRect) async -> CGImage? {
        var stability = MenuBarCaptureStability()
        let attempts = 6
        for attempt in 0..<attempts {
            guard !Task.isCancelled,
                  !isLogicallyHidden(item), item.menuBarReference.currentFrame() == frame,
                  let pixels = try? await SCScreenshotManager.captureImage(in: frame) else { return nil }
            if stability.observe(pixels) { return pixels }
            if attempt + 1 < attempts {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return nil
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
        guard let pixels = renderedPixels(from: source),
              !isFullWidthStatusChrome(pixels, width: width, height: height) else { return nil }
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

    /// A private hosted status surface can contain only its material strip,
    /// while the real glyph exists solely in the composited menu bar. Such a
    /// strip spans both crop edges and is almost a solid neutral rectangle.
    static func isStatusHostChrome(_ source: CGImage) -> Bool {
        guard let pixels = renderedPixels(from: source) else { return false }
        return isFullWidthStatusChrome(pixels, width: source.width, height: source.height)
    }

    private static func renderedPixels(from source: CGImage) -> [UInt8]? {
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? pixels : nil
    }

    private static func isFullWidthStatusChrome(_ pixels: [UInt8], width: Int, height: Int) -> Bool {
        guard width >= 8, height >= 8 else { return false }
        var visible = 0, colored = 0, maxAlpha = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha >= 12 else { continue }
            visible += 1
            maxAlpha = max(maxAlpha, alpha)
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            if (max(r, g, b) - min(r, g, b)) * 255 > 14 * alpha { colored += 1 }
        }
        guard visible > 0, maxAlpha > 0,
              Double(colored) <= Double(visible) * coloredFractionLimit else { return false }

        let solidAlpha = max(64, maxAlpha / 2)
        var left = width, right = -1, top = height, bottom = -1, solid = 0
        for y in 0..<height { for x in 0..<width {
            guard Int(pixels[(y * width + x) * 4 + 3]) >= solidAlpha else { continue }
            solid += 1
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
        } }
        guard right >= left, bottom >= top else { return false }
        let inkWidth = right - left + 1, inkHeight = bottom - top + 1
        let density = Double(solid) / Double(inkWidth * inkHeight)
        // One pixel of tolerance catches the Retina edge while retaining real
        // centered dash/progress glyphs that have normal status-item padding.
        return left <= 1 && right >= width - 2
            && top >= 2 && bottom <= height - 3
            && inkHeight * 4 >= height && inkHeight * 4 <= height * 3
            && density >= 0.98
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
