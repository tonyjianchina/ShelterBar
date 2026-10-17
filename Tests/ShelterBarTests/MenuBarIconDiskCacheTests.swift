import AppKit
import ApplicationServices
import Testing
@testable import ShelterBar

@MainActor
private final class CacheFixtureSource: ShelfItemSource {
    var entries: [ShelfItem] = []
    func items() -> [ShelfItem] { entries }
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ShelterBarIconCacheTests-\(UUID().uuidString)", isDirectory: true)
}

private func glyph(red: UInt8, width: Int = 36, height: Int = 44, template: Bool = false,
                   tone: MenuBarGlyphTone? = nil) -> NSImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 8..<36 { for x in 6..<30 {
        let i = (y * width + x) * 4
        pixels[i] = red; pixels[i + 1] = template ? red : 40; pixels[i + 2] = template ? red : 200; pixels[i + 3] = 255
    } }
    let cg = pixels.withUnsafeMutableBytes { bytes in
        CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    let image = NSImage(cgImage: cg, size: NSSize(width: width / 2, height: height / 2))
    image.isTemplate = template
    if let tone { MenuBarGlyphImage.setTone(tone, on: image) }
    return image
}

@MainActor
private func cachedItem(_ id: String, hidden: Bool) -> ShelfItem {
    ShelfItem(
        id: id, title: id, icon: NSImage(), application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: hidden ? -100 : 900, y: 5, width: 24, height: 24)
        )
    )
}

@Test("a persisted glyph round-trips with its size, template flag and tone")
@MainActor
func iconCacheRoundTrip() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = MenuBarIconDiskCache(directory: dir)
    #expect(cache.store(glyph(red: 250, tone: .light), for: "ax:com.example.muse:main"))
    #expect(cache.store(glyph(red: 0, template: true), for: "ax:com.example.uu:status"))

    let reloaded = MenuBarIconDiskCache(directory: dir)
    #expect(reloaded.keys == ["ax:com.example.muse:main", "ax:com.example.uu:status"])
    let colored = try #require(reloaded.image(for: "ax:com.example.muse:main"))
    #expect(colored.size == NSSize(width: 18, height: 22))
    #expect(colored.isTemplate == false)
    #expect(MenuBarGlyphImage.tone(of: colored) == .light)
    let rep = try #require(colored.representations.first as? NSBitmapImageRep)
    #expect(rep.pixelsWide == 36 && rep.pixelsHigh == 44)
    let template = try #require(reloaded.image(for: "ax:com.example.uu:status"))
    #expect(template.isTemplate)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.json").path))
}

@Test("cache keys are stable across launches and session-only identities are never persisted")
@MainActor
func iconCacheKeyStability() {
    let key = "ax:com.example.muse:endo-menu-bar-item"
    #expect(MenuBarIconDiskCache.fileName(for: key) == MenuBarIconDiskCache.fileName(for: key))
    #expect(MenuBarIconDiskCache.fileName(for: key) != MenuBarIconDiskCache.fileName(for: "ax:com.example.muse:main"))
    #expect(MenuBarIconDiskCache.fileName(for: key).hasSuffix(".png"))
    #expect(MenuBarIconDiskCache.isCacheable(key: key))
    #expect(MenuBarIconDiskCache.isCacheable(key: "ax:com.example.uu:main"))
    #expect(!MenuBarIconDiskCache.isCacheable(key: "ax:pid:4242:main"))
    #expect(!MenuBarIconDiskCache.isCacheable(key: "ax:com.example.app:session-4242-99"))

    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = MenuBarIconDiskCache(directory: dir)
    #expect(!cache.store(glyph(red: 200), for: "ax:pid:4242:main"))
    #expect(!cache.store(NSImage(size: NSSize(width: 18, height: 22)), for: key), "empty captures are not stored")
    #expect(cache.keys.isEmpty)
}

@Test("pruning drops untracked items and the size cap evicts the oldest entries")
@MainActor
func iconCachePruneAndCap() {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = MenuBarIconDiskCache(directory: dir, maxEntries: 2)
    let base = Date(timeIntervalSince1970: 1_000)
    cache.store(glyph(red: 10), for: "ax:a:main", now: base)
    cache.store(glyph(red: 20), for: "ax:b:main", now: base + 1)
    cache.store(glyph(red: 30), for: "ax:c:main", now: base + 2)
    #expect(cache.keys == ["ax:b:main", "ax:c:main"])

    cache.prune(keeping: ["ax:c:main"])
    #expect(cache.keys == ["ax:c:main"])
    let pngs = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.filter { $0.hasSuffix(".png") }
    #expect(pngs == [MenuBarIconDiskCache.fileName(for: "ax:c:main")])
    #expect(MenuBarIconDiskCache(directory: dir).keys == ["ax:c:main"])

    let tiny = MenuBarIconDiskCache(directory: tempDirectory(), maxBytes: 1)
    defer { try? FileManager.default.removeItem(at: tiny.directory) }
    #expect(!tiny.store(glyph(red: 40), for: "ax:d:main"))
    #expect(tiny.keys.isEmpty)
}

@Test("after a restart the shelf shows the persisted glyph of an off-screen stowed item")
@MainActor
func shelfShowsPersistedGlyphAfterRestart() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let suite = "ShelterBarIconCacheTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = "ax:com.example.muse:main"
    defaults.set([id], forKey: "shelf.collectedItems")
    let source = CacheFixtureSource()
    source.entries = [cachedItem(id, hidden: false)]

    let first = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true },
                               isVisible: { $0.minX >= 0 }, iconStore: MenuBarIconDiskCache(directory: dir))
    first.hasScreenCapturePermission = true
    first.refresh()
    first.applyMenuBarIcons([MenuBarIconSnapshot(id: id, pid: getpid(), image: glyph(red: 250, tone: .light))])

    // Relaunch: the item is off-screen, so nothing can be captured.
    source.entries = [cachedItem(id, hidden: true)]
    let second = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true },
                                isVisible: { $0.minX >= 0 }, iconStore: MenuBarIconDiskCache(directory: dir))
    second.hasScreenCapturePermission = true
    second.refresh()
    let shown = try #require(second.items.first)
    #expect(shown.hasMenuBarIcon)
    #expect(shown.icon.size == NSSize(width: 18, height: 22))
    #expect(second.itemsMissingIcons.isEmpty)

    // Without screen recording permission the persisted glyph is not shown.
    second.hasScreenCapturePermission = false
    second.refresh()
    #expect(second.items.first?.hasMenuBarIcon == false)

    // Unstowing the item prunes its cache entry.
    second.setCollected(false, id: id)
    second.refresh()
    #expect(MenuBarIconDiskCache(directory: dir).keys.isEmpty)
}
