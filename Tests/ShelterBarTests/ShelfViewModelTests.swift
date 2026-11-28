import AppKit
import ApplicationServices
import Testing
import ShelterBarCore
@testable import ShelterBar

private final class FixtureSource: ShelfItemSource, @unchecked Sendable {
    var entries: [ShelfItem] = []
    var isComplete = true
    func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult {
        ShelfItemScanResult(items: entries, isComplete: isComplete)
    }
}

private final class SlowFixtureSource: ShelfItemSource, @unchecked Sendable {
    var entries: [ShelfItem] = []
    var delay: TimeInterval = 0
    private(set) var calls = 0
    private(set) var scannedOnMainThread = false

    func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult {
        calls += 1
        scannedOnMainThread = Thread.isMainThread
        Thread.sleep(forTimeInterval: delay)
        return ShelfItemScanResult(items: entries, isComplete: true)
    }
}

@Test("the shelf permission button keeps Settings closed and shows manual guidance")
@MainActor
func shelfInputPermissionButtonShowsFallbackGuidance() {
    let model = ShelfViewModel(source: FixtureSource(), isTrusted: { false })
    model.hasAccessibilityPermission = false
    var settingsAttempts = 0
    let operations = AccessibilityPermission.RequestOperations(
        requestAccessibility: {}, canListen: { false }, requestListening: { false },
        canPost: { false }, requestPosting: { false }, isGranted: { false },
        openSettings: { settingsAttempts += 1; return false }
    )
    let coordinator = PermissionOnboardingCoordinator(
        accessibilityGranted: { false }, screenCaptureGranted: { false },
        requestAccessibility: {
            model.inputPermissionHint = AccessibilityPermission.request(using: operations).guidance
        },
        requestScreenCapture: { Issue.record("Missing input access must not advance to recording") }
    )
    model.onPermissionRequest = { coordinator.requestAccessibility() }
    #expect(coordinator.advance() == .requestAccessibility)
    #expect(settingsAttempts == 0)
    model.requestAccessibilityPermission()
    model.refresh()
    #expect(settingsAttempts == 0)
    #expect(model.inputPermissionGuidance.contains("权限弹窗"))
    #expect(model.inputPermissionGuidance.contains("打开设置"))
    #expect(!model.hasAccessibilityPermission)
}

@MainActor
private func fixture(_ id: String, hidden: Bool = false, stable: Bool = true) -> ShelfItem {
    ShelfItem(
        id: id, title: id, icon: NSImage(), application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: hidden ? -1 : 900, y: hidden ? 980 : 5, width: 24, height: 24)
        ),
        hasPersistentIdentity: stable
    )
}

@Test("cached shelf presentation does not wait for a slow inventory scan")
@MainActor
func cachedShelfPresentationDoesNotWaitForSlowScan() async {
    let source = SlowFixtureSource()
    source.entries = [fixture("sync")]
    let model = ShelfViewModel(source: source, isTrusted: { true }, isVisible: { _ in true })
    await model.reload()
    source.delay = 0.2

    let started = ContinuousClock.now
    model.refresh()
    let elapsed = started.duration(to: .now)

    #expect(elapsed < .milliseconds(50))
    #expect(!source.scannedOnMainThread)
    #expect(model.residentItems.map(\.id) == ["sync"])
}

@Test("overlapping inventory requests share one serial AX scan")
@MainActor
func overlappingInventoryRequestsCoalesce() async {
    let source = SlowFixtureSource()
    source.entries = [fixture("sync")]
    source.delay = 0.1
    let model = ShelfViewModel(source: source, isTrusted: { true }, isVisible: { _ in true })

    let first = Task { @MainActor in await model.reload() }
    let second = Task { @MainActor in await model.reload() }
    await first.value
    await second.value

    #expect(source.calls == 1)
    #expect(model.residentItems.map(\.id) == ["sync"])
}

@Test("a budget-limited scan keeps live cached items until a complete scan removes them")
@MainActor
func incompleteInventoryScanPreservesLiveCache() async {
    let source = FixtureSource()
    source.entries = [fixture("a"), fixture("b")]
    let model = ShelfViewModel(source: source, isTrusted: { true }, isVisible: { _ in true })
    await model.reload()

    source.entries = [fixture("a")]
    source.isComplete = false
    await model.reload()
    #expect(Set(model.residentItems.map(\.id)) == ["a", "b"])

    source.isComplete = true
    await model.reload()
    #expect(model.residentItems.map(\.id) == ["a"])
}

@Test("the operation-level inventory budget caps an uncooperative source")
@MainActor
func inventoryBudgetCapsUncooperativeSource() async {
    let source = SlowFixtureSource()
    source.entries = [fixture("sync")]
    let model = ShelfViewModel(source: source, isTrusted: { true }, isVisible: { _ in true })
    await model.reload()
    source.delay = 0.2

    let started = ContinuousClock.now
    await model.reload(budget: .milliseconds(20))

    #expect(started.duration(to: .now) < .milliseconds(150))
    #expect(model.residentItems.map(\.id) == ["sync"])
}

@Test("a scan delivers discovered icons when its last AX request runs past the soft deadline")
@MainActor
func inventoryReturnsPartialResultsBeforeWatchdog() async {
    struct Source: ShelfItemSource {
        let entry: ShelfItem

        func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult {
            let remaining = ContinuousClock.now.duration(to: deadline + .milliseconds(40)).components
            let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
            Thread.sleep(forTimeInterval: max(0, seconds))
            return ShelfItemScanResult(items: [entry], isComplete: false)
        }
    }

    let source = Source(entry: fixture("wechat"))
    let model = ShelfViewModel(source: source, isTrusted: { true }, isVisible: { _ in true })

    await model.reload(budget: .milliseconds(500))

    #expect(model.residentItems.map(\.id) == ["wechat"])
}

@Test("a saved collected icon still visible on top must not be duplicated in the shelf")
@MainActor
func visibleCollectedItemIsNotDuplicated() async {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["sync"], forKey: "shelf.collectedItems")
    let source = FixtureSource()
    source.entries = [fixture("sync")]
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minY < 30 })
    await model.reload()
    #expect(model.items.isEmpty)
    #expect(model.residentItems.map(\.id) == ["sync"])
    source.entries = [fixture("sync", hidden: true)]
    await model.reload()
    #expect(model.items.map(\.id) == ["sync"])
    #expect(model.residentItems.isEmpty)
}

@Test("a MenuBarAgent-hidden item appears in the shelf even while AX reports its stale top-bar frame")
@MainActor
func logicallyHiddenItemOverridesStaleAXFrame() async {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["sync"], forKey: "shelf.collectedItems")
    let source = FixtureSource()
    source.entries = [fixture("sync")]
    var hidden = true
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minY < 30 },
        isLogicallyHidden: { _ in hidden }
    )

    await model.reload()
    #expect(model.items.map(\.id) == ["sync"])
    #expect(model.residentItems.isEmpty)

    hidden = false
    model.refresh()
    #expect(model.items.isEmpty)
    #expect(model.residentItems.map(\.id) == ["sync"])
}

@Test("anonymous multi-item identities are collected only for the current session")
@MainActor
func ambiguousIdentityIsNotPersisted() async {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = FixtureSource()
    source.entries = [fixture("session-123", hidden: true, stable: false)]
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minY < 30 })
    await model.reload()
    model.setCollected(true, id: "session-123")
    model.refresh()
    #expect(model.items.map(\.id) == ["session-123"])
    #expect(defaults.stringArray(forKey: "shelf.collectedItems") == [])
}

@Test("revoking permission clears draggable items")
@MainActor
func permissionRevocationClearsItems() async {
    let source = FixtureSource()
    source.entries = [fixture("sync")]
    var granted = true
    let model = ShelfViewModel(source: source, isTrusted: { granted }, isVisible: { $0.minY < 30 })
    await model.reload()
    #expect(model.residentItems.count == 1)
    granted = false
    model.refresh()
    #expect(model.items.isEmpty && model.residentItems.isEmpty)
    #expect(!model.hasAccessibilityPermission)
}

@Test("a collected icon without a status glyph displays its app icon until a capture succeeds")
@MainActor
func capturedGlyphFallbackUsesOwningApp() async throws {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let app = try #require(NSWorkspace.shared.runningApplications.first { application in
        let image: NSImage? = application.icon
        return image.map { $0.size.width > 1 && $0.size.height > 1 } ?? false
    })
    let appIcon: NSImage? = app.icon
    let expected = try #require(appIcon)
    let id = "ax:org.erb.vortex:main"
    defaults.set([id], forKey: "shelf.collectedItems")
    let source = FixtureSource()
    source.entries = [ShelfItem(
        id: id, title: "SoCloud", icon: NSImage(), application: app,
        menuBarReference: MenuBarItemReference(
            pid: app.processIdentifier, element: AXUIElementCreateApplication(app.processIdentifier),
            frame: CGRect(x: 950, y: 5, width: 90, height: 24)
        )
    )]
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true },
                              isVisible: { _ in true }, isLogicallyHidden: { $0.id == id })
    model.hasScreenCapturePermission = false
    await model.reload()
    let fallback = try #require(model.items.first)
    #expect(!fallback.icon.isTemplate)
    #expect(fallback.icon.size == expected.size)
    #expect(!fallback.hasMenuBarIcon)

    model.hasScreenCapturePermission = true
    model.recordCaptureResults(for: [fallback], snapshots: [])
    #expect(model.captureCandidates(from: [fallback]).map(\.id) == [id])
    let glyph = NSImage(size: NSSize(width: 18, height: 20))
    model.applyMenuBarIcons([MenuBarIconSnapshot(id: id, pid: app.processIdentifier, image: glyph)])
    #expect(model.items.first?.icon === glyph)
    #expect(model.items.first?.hasMenuBarIcon == true)
}

@Test("collected QQ Music and other text strips display compact app icons from live and saved captures",
      arguments: [false, true])
@MainActor
func shelfShowsOnlyIconsForTextItems(persisted: Bool) async throws {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { try? FileManager.default.removeItem(at: directory) }
    let app = try #require(NSWorkspace.shared.runningApplications.first { application in
        let image: NSImage? = application.icon
        return image.map { $0.size.width > 1 && $0.size.height > 1 } ?? false
    })
    let icon: NSImage? = app.icon
    let appIcon = try #require(icon)
    let cases = [
        (id: "ax:com.tencent.QQMusicMac:main", width: CGFloat(150), text: "A song title", hasTitle: false),
        (id: "ax:com.tencent.QQMusicMac:hover", width: CGFloat(24), text: "▶", hasTitle: false),
        (id: "ax:com.example.player:main", width: CGFloat(95), text: "Radio station", hasTitle: false),
        (id: "ax:com.example.timer:main", width: CGFloat(28), text: "12s", hasTitle: true),
        (id: "ax:com.example.vpn:main", width: CGFloat(34), text: "", hasTitle: false),
    ]
    defaults.set(cases.map(\.id), forKey: "shelf.collectedItems")
    let source = FixtureSource()
    let store = MenuBarIconDiskCache(directory: directory)
    var snapshots: [MenuBarIconSnapshot] = []
    for testCase in cases {
        let size = NSSize(width: testCase.width, height: 24)
        let ref = MenuBarItemReference(
            pid: app.processIdentifier, element: AXUIElementCreateApplication(app.processIdentifier),
            frame: CGRect(x: 900, y: 980, width: size.width, height: size.height)
        )
        source.entries.append(ShelfItem(id: testCase.id, title: testCase.text, icon: NSImage(),
                                       application: app, menuBarReference: ref, hasStatusText: testCase.hasTitle))
        let capture = NSImage(size: size, flipped: false) { _ in
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: NSRect(x: size.width - 19, y: 4, width: 16, height: 16)).fill()
            (testCase.text as NSString).draw(at: NSPoint(x: 2, y: 5), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor
            ])
            return true
        }
        if persisted {
            #expect(store.store(capture, for: testCase.id))
        } else {
            snapshots.append(MenuBarIconSnapshot(id: testCase.id, pid: app.processIdentifier, image: capture))
        }
    }
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true },
                              isVisible: { $0.minY < 30 },
                              iconStore: MenuBarIconDiskCache(directory: directory))
    model.hasScreenCapturePermission = true
    await model.reload()
    if !persisted { model.applyMenuBarIcons(snapshots) }

    for testCase in cases {
        let shown = try #require(model.items.first { $0.id == testCase.id })
        let original = try #require(model.item(withID: testCase.id))
        #expect(shown.menuBarReference === original.menuBarReference)
        #expect(original.icon.size.width == testCase.width)
        if testCase.text.isEmpty {
            #expect(shown.icon === original.icon)
        } else {
            #expect(shown.icon.size == appIcon.size)
            #expect(MenuBarIconPresentation.shelfWidth(for: shown.icon) <= 38)
            #expect(!shown.icon.isTemplate)
        }
    }

    let qqMusicID = "ax:com.tencent.QQMusicMac:main"
    let restored = try #require(model.item(withID: qqMusicID))
    restored.menuBarReference.frame.origin.y = 5
    model.setCollected(false, id: qqMusicID)
    model.refresh()
    #expect(!model.items.contains { $0.id == qqMusicID })
    #expect(model.residentItems.first { $0.id == qqMusicID }?.icon.size.width == 150)
}

@Test("a captured menu glyph survives a fresh hidden-item scan without a Dock icon replacement")
@MainActor
func capturedGlyphSurvivesRefresh() async {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["sync"], forKey: "shelf.collectedItems")
    let source = FixtureSource()
    source.entries = [fixture("sync", hidden: true)]
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minY < 30 })
    model.hasScreenCapturePermission = true
    await model.reload()
    let originalGlyph = NSImage(size: NSSize(width: 20, height: 22))
    model.applyMenuBarIcons([MenuBarIconSnapshot(id: "sync", pid: getpid(), image: originalGlyph)])
    source.entries = [fixture("sync", hidden: true)]
    await model.reload()
    #expect(model.items.first?.icon === originalGlyph)
    #expect(model.items.first?.hasMenuBarIcon == true)
    // A failed offscreen recapture returns no images and keeps the last good glyph.
    model.applyMenuBarIcons([])
    #expect(model.items.first?.icon === originalGlyph)
    model.hasScreenCapturePermission = false
    model.refresh()
    #expect(model.items.first?.hasMenuBarIcon == false)
    #expect(model.items.first?.icon !== originalGlyph)
}

@Test("a delayed snapshot from another process cannot replace a current item's glyph")
@MainActor
func wrongProcessGlyphIsRejected() async {
    let source = FixtureSource()
    source.entries = [fixture("sync")]
    let model = ShelfViewModel(source: source, isTrusted: { true }, isVisible: { _ in true })
    model.hasScreenCapturePermission = true
    await model.reload()
    let unrelatedImage = NSImage(size: NSSize(width: 20, height: 22))
    model.applyMenuBarIcons([MenuBarIconSnapshot(id: "sync", pid: getpid() + 1, image: unrelatedImage)])
    #expect(model.residentItems.first?.hasMenuBarIcon == false)
    #expect(model.residentItems.first?.icon !== unrelatedImage)
}
