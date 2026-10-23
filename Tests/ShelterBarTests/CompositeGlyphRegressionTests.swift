import AppKit
import Testing
@testable import ShelterBar

private func fixture(_ name: String) throws -> CGImage {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"))
    let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    return try #require(bitmap.cgImage)
}

@Test("real composite capture removes the wallpaper rectangle")
@MainActor
func compositeFixtureBackground() throws {
    let source = try fixture("composite-ollama")
    let image = try #require(MenuBarCompositeGlyph.make(from: source, logicalSize: CGSize(width: 34, height: 24)))
    #expect(image.isTemplate)
    let pixels = NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    #expect(try #require(pixels.colorAt(x: 0, y: 0)).alphaComponent == 0)
}

@Test("real overflow chevron captures cannot replace app icons", arguments: ["composite-mail-overflow", "composite-wechat-overflow", "composite-muse-overflow"])
@MainActor
func compositeFixtureOverflow(name: String) throws {
    let source = try fixture(name)
    #expect(MenuBarCompositeGlyph.make(from: source, logicalSize: CGSize(width: source.width / 2, height: source.height / 2)) == nil)
}

@Test("real mail and WeChat captures keep the icon without the count", arguments: [
    CGRect(x: 561, y: 48, width: 122, height: 44),
    CGRect(x: 931, y: 48, width: 118, height: 44)
])
@MainActor
func compositeFixtureCount(rect: CGRect) throws {
    let source = try #require(try fixture("shelf-before-corruption").cropping(to: rect))
    let image = try #require(MenuBarCompositeGlyph.make(from: source, logicalSize: CGSize(width: rect.width / 1.83, height: 24), hasCount: true))
    if let path = ProcessInfo.processInfo.environment["SHELTERBAR_GLYPH_PREVIEW_DIR"] {
        let raw = NSBitmapImageRep(cgImage: source)
        try raw.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path).appendingPathComponent("raw-\(Int(rect.minX)).png"))
        let rendered = NSImage(size: CGSize(width: 120, height: 96), flipped: false) { rect in
            NSColor(white: 0.94, alpha: 1).setFill()
            rect.fill()
            let glyph = MenuBarIconPresentation.renderedImage(for: image, tintColor: .black)
            glyph.draw(in: CGRect(x: 12, y: 12, width: image.size.width * 3, height: image.size.height * 3))
            return true
        }
        let preview = NSBitmapImageRep(cgImage: try #require(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        try preview.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path).appendingPathComponent("icon-\(Int(rect.minX)).png"))
    }
    #expect(image.size.width <= 30)
    #expect(image.isTemplate)
    #expect(image.size.height == 24)
}

@Test("legacy cached rectangles are decoded and corrupted strips are not restored")
@MainActor
func compositeFixtureCacheUpgrade() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShelterBarVisualUpgrade-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = MenuBarIconDiskCache(directory: directory)
    for name in ["composite-ollama", "composite-mail-overflow"] {
        let source = try fixture(name)
        cache.store(NSImage(cgImage: source, size: CGSize(width: source.width / 2, height: 24)), for: "ax:\(name):main")
    }
    let index = directory.appendingPathComponent("index.json")
    var records = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]])
    for i in records.indices { records[i].removeValue(forKey: "visualVersion") }
    try JSONSerialization.data(withJSONObject: records).write(to: index)
    let reloaded = MenuBarIconDiskCache(directory: directory)
    #expect(try #require(reloaded.image(for: "ax:composite-ollama:main")).isTemplate)
    #expect(reloaded.image(for: "ax:composite-mail-overflow:main") == nil)
}

@Test("a rejected refresh preserves the last valid icon on disk")
@MainActor
func compositeFixtureRejectPreservesCache() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShelterBarVisualRefresh-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = MenuBarIconDiskCache(directory: directory)
    let key = "ax:com.example.mail:main"
    let correct = try #require(try fixture("shelf-before-corruption").cropping(to: CGRect(x: 561, y: 48, width: 122, height: 44)))
    let image = try #require(MenuBarCompositeGlyph.make(from: correct, logicalSize: CGSize(width: 67, height: 24), hasCount: true))
    #expect(cache.store(image, for: key))
    let digest = cache.records[key]?.digest
    // Replay the production capture→optional snapshot→cache sequence. Failed
    // captures must not create replacement snapshots at all.
    for name in ["composite-mail-overflow", "composite-wechat-overflow", "composite-muse-overflow"] {
        let source = try fixture(name)
        if let bad = MenuBarCompositeGlyph.make(from: source, logicalSize: CGSize(width: source.width / 2, height: 24)) {
            cache.store(bad, for: key)
        }
    }
    #expect(cache.records[key]?.digest == digest)
    let restored = try #require(MenuBarIconDiskCache(directory: directory).image(for: key))
    #expect(restored.isTemplate)
    #expect(restored.size == image.size)
}

@Test("composite matting preserves coloured glyphs and wide non-count artwork", arguments: [
    [1.0, 0.0, 0.0], [0.45, 0.4, 0.95], [0.1, 0.8, 0.25]
])
@MainActor
func compositeFixtureColoredAndWide(color: [Double]) throws {
    let context = try #require(CGContext(data: nil, width: 128, height: 48, bitsPerComponent: 8,
        bytesPerRow: 128 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.35, green: 0.45, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 128, height: 48))
    context.setFillColor(CGColor(red: color[0], green: color[1], blue: color[2], alpha: 1))
    context.fillEllipse(in: CGRect(x: 10, y: 8, width: 30, height: 32))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 60, y: 12, width: 56, height: 24))
    let composite = try #require(context.makeImage())
    let image = try #require(MenuBarCompositeGlyph.make(from: composite, logicalSize: CGSize(width: 64, height: 24)))
    #expect(!image.isTemplate)
    #expect(image.size.width == 64) // No AX count: never truncate wide artwork.
    let bitmap = NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
    let red = try #require(bitmap.colorAt(x: 24, y: 24)?.usingColorSpace(.sRGB))
    let original = try #require(NSBitmapImageRep(cgImage: composite).colorAt(x: 24, y: 24)?.usingColorSpace(.sRGB))
    // Compare in a common colour space: Device RGB red is not numerically
    // (1, 0, 0) after ColorSync converts it to sRGB.
    #expect(abs(red.redComponent - original.redComponent) < 0.02)
    #expect(abs(red.greenComponent - original.greenComponent) < 0.02)
    #expect(abs(red.blueComponent - original.blueComponent) < 0.02)
    #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
}

@Test("a compact single-digit count is removed too")
@MainActor
func compositeFixtureSingleDigit() throws {
    let context = try #require(CGContext(data: nil, width: 72, height: 48, bitsPerComponent: 8,
        bytesPerRow: 72 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.35, green: 0.45, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 72, height: 48))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 14, y: 8, width: 28, height: 32))
    context.fill(CGRect(x: 48, y: 12, width: 10, height: 24))
    let source = try #require(context.makeImage())
    let image = try #require(MenuBarCompositeGlyph.make(from: source, logicalSize: CGSize(width: 36, height: 24), hasCount: true))
    #expect(image.size.width < 25)
}
