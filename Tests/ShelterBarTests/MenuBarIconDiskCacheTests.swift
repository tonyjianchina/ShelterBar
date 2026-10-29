import AppKit
import ApplicationServices
import Testing
@testable import ShelterBar

private final class CacheFixtureSource: ShelfItemSource, @unchecked Sendable {
    var entries: [ShelfItem] = []
    func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult {
        ShelfItemScanResult(items: entries, isComplete: true)
    }
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

private func fullWidthStatusChromeData() -> Data {
    let context = CGContext(data: nil, width: 36, height: 24, bitsPerComponent: 8,
        bytesPerRow: 36 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 4, width: 36, height: 12))
    context.setFillColor(CGColor(gray: 0, alpha: 0.05))
    context.fill(CGRect(x: 0, y: 3, width: 36, height: 1))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
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

@Test("current disk and memory cached glyphs never query a foreign AX title")
@MainActor
func cachedGlyphDoesNotReadNumericTitle() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let key = "ax:com.example.slow:main"
    #expect(MenuBarIconDiskCache(directory: dir).store(glyph(red: 200), for: key))
    let cache = MenuBarIconDiskCache(directory: dir)
    var titleReads = 0
    func slowTitle() -> Bool {
        titleReads += 1
        Thread.sleep(forTimeInterval: 0.01)
        return false
    }
    let start = ContinuousClock.now
    for _ in 0..<20 {
        #expect(cache.image(for: key, hasCount: slowTitle()) != nil)
    }
    let duration = start.duration(to: .now)
    #expect(titleReads == 0, "known glyphs must not incur AX IPC during shelf presentation")
    print("CACHED_GLYPH_BENCH titleReads=\(titleReads) duration=\(duration)")
}

@Test("legacy glyph migration reads numeric-title metadata only when needed")
@MainActor
func legacyGlyphStillReadsNumericTitleForMigration() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let key = "ax:com.example.legacy:main"
    let original = MenuBarIconDiskCache(directory: dir)
    #expect(original.store(glyph(red: 0, template: true), for: key))
    var record = try #require(original.records[key])
    record.visualVersion = nil
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([record]).write(to: dir.appendingPathComponent(MenuBarIconDiskCache.indexName))
    let cache = MenuBarIconDiskCache(directory: dir)
    var titleReads = 0
    func title() -> Bool { titleReads += 1; return false }
    #expect(cache.image(for: key, hasCount: title()) != nil)
    #expect(titleReads == 1, "legacy migration must still distinguish numeric labels")
    #expect(cache.image(for: key, hasCount: title()) != nil)
    #expect(titleReads == 1, "a restored legacy glyph is memory cached")
}

@Test("a previously accepted full-width status-host bar is evicted from the cache")
@MainActor
func iconCacheEvictsFullWidthStatusChrome() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let key = "ax:com.liguangming.Shadowrocket:main"
    let file = MenuBarIconDiskCache.fileName(for: key)
    let png = fullWidthStatusChromeData()
    try png.write(to: dir.appendingPathComponent(file))
    let record = MenuBarIconCacheRecord(
        key: key, file: file, width: 36, height: 24, isTemplate: true, tone: 0,
        byteCount: png.count, digest: "previously-accepted", updatedAt: Date(timeIntervalSince1970: 1_000),
        visualVersion: 1
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([record]).write(to: dir.appendingPathComponent(MenuBarIconDiskCache.indexName))

    let cache = MenuBarIconDiskCache(directory: dir)
    #expect(cache.keys == [key])
    #expect(cache.image(for: key) == nil)
    #expect(cache.keys.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(file).path))
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

@Test("a failed stable capture stays quiet across polls and launches until explicit retry")
@MainActor
func failedStableCaptureIsNegativelyCached() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let suite = "ShelterBarIconCacheTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = "ax:com.example.uncapturable:main"
    let source = CacheFixtureSource()
    source.entries = [cachedItem(id, hidden: false)]

    let first = ShelfViewModel(
        source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minX >= 0 },
        iconStore: MenuBarIconDiskCache(directory: dir)
    )
    first.hasScreenCapturePermission = true
    await first.reload()
    let initial = first.captureCandidates(from: first.allItems)
    #expect(initial.map(\.id) == [id])
    first.recordCaptureResults(for: initial, snapshots: [])
    #expect(first.captureCandidates(from: first.allItems).isEmpty,
            "a failed item must not be recorded again by the next poll")

    let reloadedStore = MenuBarIconDiskCache(directory: dir)
    #expect(reloadedStore.hasCaptureFailure(for: id))
    let second = ShelfViewModel(
        source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minX >= 0 },
        iconStore: reloadedStore
    )
    second.hasScreenCapturePermission = true
    await second.reload()
    #expect(second.captureCandidates(from: second.allItems).isEmpty,
            "the negative cache must survive a ShelterBar restart")

    second.retryMissingIconCaptures()
    #expect(second.captureCandidates(from: second.allItems).map(\.id) == [id])
    #expect(!reloadedStore.hasCaptureFailure(for: id))
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
func shelfShowsPersistedGlyphAfterRestart() async throws {
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
    await first.reload()
    first.applyMenuBarIcons([MenuBarIconSnapshot(id: id, pid: getpid(), image: glyph(red: 250, tone: .light))])

    // Relaunch: the item is off-screen, so nothing can be captured.
    source.entries = [cachedItem(id, hidden: true)]
    let second = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true },
                                isVisible: { $0.minX >= 0 }, iconStore: MenuBarIconDiskCache(directory: dir))
    second.hasScreenCapturePermission = true
    await second.reload()
    let shown = try #require(second.items.first)
    #expect(shown.hasMenuBarIcon)
    #expect(shown.icon.size == NSSize(width: 18, height: 22))
    #expect(second.itemsMissingIcons.isEmpty)

    // Without screen recording permission the persisted glyph is not shown.
    second.hasScreenCapturePermission = false
    second.refresh()
    #expect(second.items.first?.hasMenuBarIcon == false)

    // Returning an item keeps its stable app association. If it is collected
    // again later, ShelterBar can reuse the glyph without recording again.
    second.setCollected(false, id: id)
    second.refresh()
    #expect(MenuBarIconDiskCache(directory: dir).keys == [id])
}

@Test("the first capture of a resident app is persisted and reused after restart")
@MainActor
func residentGlyphIsCapturedOnlyOnceAcrossLaunches() async throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let suite = "ShelterBarIconCacheTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let id = "ax:com.example.resident:main"
    let source = CacheFixtureSource()
    source.entries = [cachedItem(id, hidden: false)]

    let firstStore = MenuBarIconDiskCache(directory: dir)
    let first = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true },
                               isVisible: { $0.minX >= 0 }, iconStore: firstStore)
    first.hasScreenCapturePermission = true
    await first.reload()
    first.applyMenuBarIcons([
        MenuBarIconSnapshot(id: id, pid: getpid(), image: glyph(red: 180, tone: .mixed))
    ])
    #expect(firstStore.keys == [id])

    let second = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true },
                                isVisible: { $0.minX >= 0 },
                                iconStore: MenuBarIconDiskCache(directory: dir))
    second.hasScreenCapturePermission = true
    await second.reload()
    #expect(second.residentItems.first?.hasMenuBarIcon == true)
    #expect(second.captureCandidates(from: second.allItems).isEmpty,
            "a persisted app glyph must not need another screen capture")
}

@Test("a neutral shaded glyph keeps adapting to light/dark after a cache reload")
@MainActor
func iconCacheKeepsAdaptiveNeutralGlyphs() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
        bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: 8, y: 8, width: 32, height: 32))
    context.setFillColor(CGColor(gray: 0.2, alpha: 1))
    context.fill(CGRect(x: 20, y: 16, width: 8, height: 16))
    let captured = try #require(MenuBarGlyphImage.make(from: context.makeImage()!,
                                                       logicalSize: CGSize(width: 24, height: 24)))
    #expect(MenuBarGlyphImage.isAdaptiveNeutral(captured))
    let cache = MenuBarIconDiskCache(directory: dir)
    #expect(cache.store(captured, for: "ax:com.example.neutral:main"))

    let reloaded = try #require(MenuBarIconDiskCache(directory: dir).image(for: "ax:com.example.neutral:main"))
    #expect(reloaded.isTemplate == false)
    #expect(MenuBarGlyphImage.isAdaptiveNeutral(reloaded))
    #expect(reloaded.size == NSSize(width: 24, height: 24))
}
