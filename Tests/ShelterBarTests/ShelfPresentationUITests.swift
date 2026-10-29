import AppKit
import ApplicationServices
import SwiftUI
import Testing
@testable import ShelterBar

private struct ShelfUIFixtureSource: ShelfItemSource {
    let entries: [ShelfItem]
    func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult {
        ShelfItemScanResult(items: entries, isComplete: true)
    }
}

@MainActor
private func fixtureModel(count: Int = 4) async -> (ShelfViewModel, UserDefaults, String) {
    let suite = "ShelterBarUIFixtures.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let names = ["网络", "音乐", "同步", "电池"]
    let symbols = ["network", "music.note", "arrow.triangle.2.circlepath", "battery.75percent"]
    let items = (0..<count).map { index in
        let name = names[index % names.count]
        return ShelfItem(id: "fixture-\(index)", title: name,
            icon: NSImage(systemSymbolName: symbols[index % symbols.count], accessibilityDescription: name)!,
            application: nil, menuBarReference: MenuBarItemReference(
                pid: getpid(), element: AXUIElementCreateApplication(getpid()),
                frame: CGRect(x: -100, y: 0, width: 24, height: 24)))
    }
    defaults.set(items.map(\.id), forKey: "shelf.collectedItems")
    let model = ShelfViewModel(source: ShelfUIFixtureSource(entries: items), defaults: defaults,
        isTrusted: { true }, isVisible: { _ in false })
    model.hasScreenCapturePermission = true
    await model.reload()
    model.applyMenuBarIcons(items.map {
        MenuBarIconSnapshot(id: $0.id, pid: getpid(), image: $0.icon)
    })
    return (model, defaults, suite)
}

@MainActor
private func makeFixtureView(_ model: ShelfViewModel, onActivate: @escaping (ShelfItem) -> Void = { _ in },
                             onReturn: @escaping (String, CGPoint) -> Void = { _, _ in }) -> ShelfView {
    ShelfView(model: model, onActivate: onActivate, onReturn: onReturn,
        onDragging: { model.isDraggingToMenuBar = $0 },
        onDragPosition: { _, _ in }, onPinChange: { model.setPinned($0) },
        onRevealAll: {}, onQuit: {})
}

@MainActor
private func iconViews(in view: NSView) -> [ShelfIconView] {
    (view as? ShelfIconView).map { [$0] } ?? view.subviews.flatMap { iconViews(in: $0) }
}

@MainActor
private func hostedFixture(_ model: ShelfViewModel, width: CGFloat = 560, height: CGFloat? = nil,
                           onActivate: @escaping (ShelfItem) -> Void = { _ in },
                           onReturn: @escaping (String, CGPoint) -> Void = { _, _ in }) async -> NSHostingView<ShelfView> {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: makeFixtureView(model, onActivate: onActivate, onReturn: onReturn))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = CGRect(x: 0, y: 0, width: width,
                        height: height ?? ShelfLayoutMetrics.panelHeight(notice: ShelfNotice.current(model)))
    host.layoutSubtreeIfNeeded()
    // Allow SwiftUI's deferred NSViewRepresentable installation to finish. No
    // production window, menu item, screen capture or input event is created.
    try? await Task.sleep(for: .milliseconds(80))
    host.layoutSubtreeIfNeeded()
    return host
}

@Test("render native shelf fixtures without opening the production application")
@MainActor
func exportShelfUIFixtures() async throws {
    guard let output = ProcessInfo.processInfo.environment["SHELTERBAR_UI_FIXTURE_DIRECTORY"] else { return }
    let dir = URL(fileURLWithPath: output, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for scenario in ["normal", "notice", "optional-permission", "dragging", "overflow", "narrow", "empty"] {
        let (model, defaults, suite) = await fixtureModel(count: scenario == "overflow" ? 40 : (scenario == "empty" ? 0 : 4))
        defer { defaults.removePersistentDomain(forName: suite) }
        if scenario == "notice" { model.message = "已自动收纳 1 个新增图标。" }
        if scenario == "optional-permission" { model.hasScreenCapturePermission = false; model.refresh() }
        if scenario == "dragging" { model.isDraggingToMenuBar = true }
        if scenario == "narrow" { model.hasScreenCapturePermission = false; model.refresh() }
        let host = await hostedFixture(model, width: scenario == "narrow" ? 320 : 560)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("\(scenario).png"))
        print("Shelf fixture \(scenario): \(iconViews(in: host).count) mounted icon controls, \(host.bounds)")
    }
}

@Test("status and optional recording notices retain all actionable shelf icons")
@MainActor
func shelfNoticesRetainIconControls() async throws {
    let (model, defaults, suite) = await fixtureModel()
    defer { defaults.removePersistentDomain(forName: suite) }
    var activated: [String] = []
    let host = await hostedFixture(model, onActivate: { activated.append($0.id) })
    let original = iconViews(in: host)
    #expect(original.count == 4)
    #expect(try #require(original.first).accessibilityLabel() == model.items.first?.title)
    #expect(try #require(original.first).accessibilityHelp()?.contains("空格") == true)
    for state in ["message", "permission", "dragging", "dismissed"] {
        model.message = state == "message" ? "已自动收纳 1 个新增图标。" : nil
        model.hasScreenCapturePermission = state != "permission"
        model.isDraggingToMenuBar = state == "dragging"
        model.refresh()
        host.frame.size.height = ShelfLayoutMetrics.panelHeight(notice: ShelfNotice.current(model))
        try? await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        let current = iconViews(in: host)
        #expect(current.count == 4, "\(state) must not remove the icon row")
        #expect(current.map(ObjectIdentifier.init) == original.map(ObjectIdentifier.init),
                "notice transitions must not replace native controls during a drag")
        #expect(try #require(current.first).accessibilityPerformPress())
    }
    #expect(activated.count == 4)
}

@Test("forty icons remain scrollable and actionable on a narrow shelf")
@MainActor
func shelfOverflowRemainsScrollable() async throws {
    let (model, defaults, suite) = await fixtureModel(count: 40)
    defer { defaults.removePersistentDomain(forName: suite) }
    model.hasScreenCapturePermission = false
    model.refresh()
    var activated: String?
    let host = await hostedFixture(model, width: 320, onActivate: { activated = $0.id })
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    try? await Task.sleep(for: .milliseconds(80))
    host.layoutSubtreeIfNeeded()
    let icons = iconViews(in: host)
    #expect(icons.count == 40)
    let last = try #require(icons.last)
    let scroll = try #require(last.enclosingScrollView)
    #expect(scroll.contentSize.width > 40, "the icon viewport must remain usable at 320 pt")
    #expect(try #require(scroll.documentView).bounds.width > scroll.contentSize.width)
    #expect(!last.visibleRect.intersects(last.bounds), "the last icon starts outside the narrow viewport")
    last.scrollToVisible(last.bounds)
    host.layoutSubtreeIfNeeded()
    #expect(last.visibleRect.intersects(last.bounds))
    #expect(last.accessibilityPerformPress())
    #expect(activated == last.item?.id)
}

@Test("focused shelf icons support space and return without repeating activation")
@MainActor
func shelfIconsSupportKeyboardActivation() throws {
    let view = ShelfIconView()
    var activations = 0
    view.onActivate = { activations += 1 }
    for (key, repeated) in [(UInt16(36), false), (UInt16(49), false), (UInt16(49), true)] {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: key == 36 ? "\r" : " ", charactersIgnoringModifiers: key == 36 ? "\r" : " ",
            isARepeat: repeated, keyCode: key))
        view.keyDown(with: event)
    }
    #expect(activations == 2)
}

@Test("a notice appearing mid-drag preserves the source and completes the return")
@MainActor
func shelfNoticePreservesActiveDrag() async throws {
    let (model, defaults, suite) = await fixtureModel()
    defer { defaults.removePersistentDomain(forName: suite) }
    var returned: String?
    let host = await hostedFixture(model, onReturn: { id, _ in returned = id })
    let source = try #require(iconViews(in: host).first)
    source.isSafeDrop = { _ in true }
    source.beginPointerTracking(at: CGPoint(x: 10, y: 10))
    #expect(source.continuePointerTracking(at: CGPoint(x: 30, y: 0)))
    model.message = "已自动收纳 1 个新增图标。"
    host.frame.size.height = ShelfLayoutMetrics.panelHeight(notice: ShelfNotice.current(model))
    try? await Task.sleep(for: .milliseconds(80))
    host.layoutSubtreeIfNeeded()
    #expect(ShelfNotice.current(model) == .dragHint)
    #expect(iconViews(in: host).first === source)
    source.endPointerTracking(at: CGPoint(x: 30, y: 0), isInsideSource: false)
    #expect(returned == source.item?.id)
    #expect(!model.isDraggingToMenuBar)
    #expect(ShelfNotice.current(model) == .message("已自动收纳 1 个新增图标。"))
}
