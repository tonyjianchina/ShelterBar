import AppKit
import ApplicationServices
import Testing
@testable import ShelterBar

@MainActor
private final class FixtureSource: ShelfItemSource {
    var entries: [ShelfItem] = []
    func items() -> [ShelfItem] { entries }
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

@Test("a saved collected icon still visible on top must not be duplicated in the shelf")
@MainActor
func visibleCollectedItemIsNotDuplicated() {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["sync"], forKey: "shelf.collectedItems")
    let source = FixtureSource()
    source.entries = [fixture("sync")]
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minY < 30 })
    model.refresh()
    #expect(model.items.isEmpty)
    #expect(model.residentItems.map(\.id) == ["sync"])
    source.entries = [fixture("sync", hidden: true)]
    model.refresh()
    #expect(model.items.map(\.id) == ["sync"])
    #expect(model.residentItems.isEmpty)
}

@Test("anonymous multi-item identities are collected only for the current session")
@MainActor
func ambiguousIdentityIsNotPersisted() {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = FixtureSource()
    source.entries = [fixture("session-123", hidden: true, stable: false)]
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minY < 30 })
    model.refresh()
    model.setCollected(true, id: "session-123")
    model.refresh()
    #expect(model.items.map(\.id) == ["session-123"])
    #expect(defaults.stringArray(forKey: "shelf.collectedItems") == [])
}

@Test("revoking permission clears draggable items")
@MainActor
func permissionRevocationClearsItems() {
    let source = FixtureSource()
    source.entries = [fixture("sync")]
    var granted = true
    let model = ShelfViewModel(source: source, isTrusted: { granted }, isVisible: { $0.minY < 30 })
    model.refresh()
    #expect(model.residentItems.count == 1)
    granted = false
    model.refresh()
    #expect(model.items.isEmpty && model.residentItems.isEmpty)
    #expect(!model.hasAccessibilityPermission)
}

@Test("a captured menu glyph survives a fresh hidden-item scan without a Dock icon replacement")
@MainActor
func capturedGlyphSurvivesRefresh() {
    let suite = "ShelterBarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["sync"], forKey: "shelf.collectedItems")
    let source = FixtureSource()
    source.entries = [fixture("sync", hidden: true)]
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minY < 30 })
    model.hasScreenCapturePermission = true
    model.refresh()
    let originalGlyph = NSImage(size: NSSize(width: 20, height: 22))
    model.applyMenuBarIcons([MenuBarIconSnapshot(id: "sync", pid: getpid(), image: originalGlyph)])
    source.entries = [fixture("sync", hidden: true)]
    model.refresh()
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
func wrongProcessGlyphIsRejected() {
    let source = FixtureSource()
    source.entries = [fixture("sync")]
    let model = ShelfViewModel(source: source, isTrusted: { true }, isVisible: { _ in true })
    model.hasScreenCapturePermission = true
    model.refresh()
    let unrelatedImage = NSImage(size: NSSize(width: 20, height: 22))
    model.applyMenuBarIcons([MenuBarIconSnapshot(id: "sync", pid: getpid() + 1, image: unrelatedImage)])
    #expect(model.residentItems.first?.hasMenuBarIcon == false)
    #expect(model.residentItems.first?.icon !== unrelatedImage)
}
