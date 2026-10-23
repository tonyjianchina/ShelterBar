import AppKit

/// The macOS 27 region API returns composited screen pixels, not a transparent
/// status-window image. Decode that format before it can reach either cache.
enum MenuBarCompositeGlyph {
    static func make(from source: CGImage, logicalSize: CGSize, hasCount: Bool = false) -> NSImage? {
        let width = source.width, height = source.height
        guard width >= 8, height >= 8, width <= 4096, height <= 400,
              logicalSize.width > 0, logicalSize.height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }

        // Transparent native captures already have a matte; leave it alone.
        let opaque = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] >= 250 }.count
        if opaque > width * height * 9 / 10 {
            // Status items have empty top/bottom padding. Four corner samples
            // model the smooth wallpaper gradient without flood-filling holes
            // in a glyph (e.g. Ollama's eyes or a coloured notification badge).
            func corner(_ x0: Int, _ y0: Int) -> [Double] {
                (0..<3).map { channel in
                    var values: [UInt8] = []
                    for y in y0..<(y0 + 2) { for x in x0..<(x0 + 2) {
                        values.append(pixels[(y * width + x) * 4 + channel])
                    } }
                    return Double(values.sorted()[values.count / 2])
                }
            }
            let tl = corner(0, 0), tr = corner(width - 2, 0)
            let bl = corner(0, height - 2), br = corner(width - 2, height - 2)
            var foreground = [UInt8](repeating: 0, count: pixels.count)
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                let fx = Double(x) / Double(width - 1), fy = Double(y) / Double(height - 1)
                let bg = (0..<3).map { c in
                    (tl[c] * (1 - fx) + tr[c] * fx) * (1 - fy) + (bl[c] * (1 - fx) + br[c] * fx) * fy
                }
                let rgb = (0..<3).map { Double(pixels[i + $0]) }
                guard zip(rgb, bg).map({ abs($0 - $1) }).max()! > 8 else { continue }

                // Fit a neutral foreground first. This unmixes tinted edge
                // pixels rather than preserving a blue halo around white ink.
                func neutral(_ value: Double) -> (alpha: Double, error: Double) {
                    let axis = bg.map { value - $0 }
                    let norm = axis.map { $0 * $0 }.reduce(0, +)
                    let dot = (0..<3).map { (rgb[$0] - bg[$0]) * axis[$0] }.reduce(0, +)
                    let alpha = min(1, max(0, dot / max(1, norm)))
                    let error = (0..<3).map { abs(bg[$0] + alpha * axis[$0] - rgb[$0]) }.max()!
                    return (alpha, error)
                }
                let white = neutral(255), black = neutral(0)
                let light = white.error < black.error
                let fit = light ? white : black
                let alpha: Double
                let channels: [Double]
                if fit.error <= 8 {
                    alpha = fit.alpha
                    channels = Array(repeating: light ? 255 : 0, count: 3)
                } else {
                    // A single composite does not determine the alpha of
                    // genuinely coloured artwork. Preserve its sampled colour
                    // rather than guessing and changing badge saturation.
                    alpha = 1
                    channels = rgb
                }
                guard alpha > 0.04 else { continue }
                foreground[i + 3] = UInt8(min(255, max(0, (alpha * 255).rounded())))
                for c in 0..<3 {
                    foreground[i + c] = UInt8(min(Double(foreground[i + 3]), max(0, (channels[c] * alpha).rounded())))
                }
            } }
            pixels = foreground
        }

        func inkBounds() -> CGRect? {
            var left = width, right = -1, top = height, bottom = -1
            for y in 0..<height { for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 40 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            } }
            guard right >= left, bottom >= top else { return nil }
            return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        }
        guard let ink = inkBounds() else { return nil }
        // An overflowed item's stale AX rectangle can end at the system
        // chevron. Stable pixels are not proof of ownership. Reject that
        // mostly-empty, edge-clipped strip BEFORE cropping; a rejected
        // capture never overwrites the last usable app glyph.
        let left = ink.minX, right = CGFloat(width) - ink.maxX
        guard !(ink.width < CGFloat(width) * 0.65
            && abs(left - right) > max(6, CGFloat(width) * 0.18)) else { return nil }

        var removedCount = false
        if hasCount, logicalSize.width > logicalSize.height {
            // AX tells us whether this item carries a count. Keep its leading
            // pictogram, separated from the text by a clear vertical gap. Do
            // not impose this crop on ordinary wide logos or text-only items.
            let columns = (0..<width).map { x in
                (0..<height).contains { y in pixels[(y * width + x) * 4 + 3] > 40 }
            }
            let start = Int(ink.minX)
            let minIcon = Int(Double(height) * 0.5), maxIcon = Int(Double(height) * 1.3)
            let gap = max(2, Int(CGFloat(width) / logicalSize.width))
            let upper = min(width - gap, start + maxIcon)
            guard start + minIcon < upper else { return nil }
            let candidates = (start + minIcon)..<upper
            guard let split = candidates.first(where: { x in
                columns[x..<(x + gap)].allSatisfy { !$0 } && columns[(x + gap)...].contains(true)
            }) else { return nil }
            for y in 0..<height { for x in split..<width {
                    let i = (y * width + x) * 4
                    for c in 0..<4 { pixels[i + c] = 0 }
            } }
            removedCount = true
        }
        guard let remaining = inkBounds(),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let decoded = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        if removedCount {
            // Preserve original glyph scale and all vertical detail, then give
            // the icon symmetrical horizontal padding instead of an empty bar.
            let scale = CGFloat(width) / logicalSize.width
            let padded = CGRect(x: max(0, floor(remaining.minX - 3 * scale)), y: 0,
                                width: ceil(remaining.width + 6 * scale), height: CGFloat(height))
            let crop = padded.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard let icon = decoded.cropping(to: crop) else { return nil }
            return MenuBarGlyphImage.make(from: icon, logicalSize: CGSize(width: crop.width / scale, height: logicalSize.height))
        }
        return MenuBarGlyphImage.make(from: decoded, logicalSize: logicalSize)
    }

}
