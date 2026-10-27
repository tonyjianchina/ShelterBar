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
