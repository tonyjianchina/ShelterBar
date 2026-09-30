import AppKit
import ApplicationServices
import ShelterBarCore
import Testing
@testable import ShelterBar

@MainActor
private final class EngineFixtureSource: ShelfItemSource {
    var entries: [ShelfItem] = []
    func items() -> [ShelfItem] { entries }
}

@MainActor
private final class EngineFixtureDriver: MenuBarLayoutDriving {
    var isCollapsed = false
    var transitionRegion: CGRect? = CGRect(x: 0, y: 0, width: 1200, height: 30)
    var placements: [String: MenuBarPlacement] = [:]
    var revealCount = 0
    var collapseCount = 0
    var moves: [PlannedMenuBarMove] = []
    var shouldFailMove = false
    var movementFailureMessage: String?
    var onCollapse: (() -> Void)?

    func observedPlacement(of item: ShelfItem) -> MenuBarPlacement? { placements[item.id] }

    func revealHiddenSection() async {
        revealCount += 1
        isCollapsed = false
    }

    func collapseHiddenSection() async {
        collapseCount += 1
        isCollapsed = true
        onCollapse?()
    }

    func revealImmediately() {
        revealCount += 1
        isCollapsed = false
    }

    func move(_ item: ShelfItem, to placement: MenuBarPlacement, dropPoint: CGPoint?) async -> Bool {
        moves.append(PlannedMenuBarMove(id: item.id, placement: placement))
        if shouldFailMove { return false }
        placements[item.id] = placement
        item.menuBarReference.frame.origin.x = placement == .collected ? -100 : 900
        return true
    }
}

@Test("unavailable uncollected AX remnants do not fail refresh or collection")
@MainActor
func engineIgnoresUnmanagedAXRemnant() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    let remnant = engineFixture("lark-remnant", hidden: true)
    remnant.menuBarReference.frame = CGRect(x: -1, y: 981, width: 56, height: 24)
    source.entries = [engineFixture("vpn", hidden: false), remnant]
    let model = ShelfViewModel(source: source, defaults: defaults,
                              isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.placements = ["vpn": .resident]
    let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false })

    let refreshed = await engine.perform(.reconcile(.userRefresh))
    #expect(refreshed.message == nil)
    #expect(driver.revealCount == 0)
    let collected = await engine.perform(.setPlacement(id: "vpn", placement: .collected))
    #expect(collected.didChangeLayout)
    #expect(engine.phase == .idle)
    #expect(model.collectedIDs == ["vpn"])
    #expect(driver.moves == [PlannedMenuBarMove(id: "vpn", placement: .collected)])

    // A previously unavailable item becoming visible is new to the managed
    // inventory, not permanently ignored because its stale AX entry was seen.
    driver.placements["lark-remnant"] = .resident
    remnant.menuBarReference.frame = CGRect(x: 950, y: 5, width: 56, height: 24)
    let appeared = await engine.perform(.reconcile(.poll))
    #expect(appeared.didChangeLayout)
    #expect(model.collectedIDs == ["vpn", "lark-remnant"])
}

@Test("a resident participating in a transaction cannot disappear during collapse")
@MainActor
func engineRejectsLostParticipatingResident() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: false), engineFixture("resident", hidden: false)]
    let model = ShelfViewModel(source: source, defaults: defaults,
                              isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.placements = ["vpn": .resident, "resident": .resident]
    driver.onCollapse = { [weak driver] in driver?.placements.removeValue(forKey: "resident") }
    let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false })
    let outcome = await engine.perform(.setPlacement(id: "vpn", placement: .collected))
    #expect(outcome.message == "系统没有完成布局调整，已恢复显示全部图标。")
    #expect(!driver.isCollapsed)
    #expect(model.collectedIDs.isEmpty)
}

@Test("saved collection for an app not running does not fail another icon's transaction")
@MainActor
func enginePreservesAbsentAppPreference() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["not-running"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: false)]
    let model = ShelfViewModel(source: source, defaults: defaults,
                              isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.placements = ["vpn": .resident]
    let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false })
    let outcome = await engine.perform(.setPlacement(id: "vpn", placement: .collected))
    #expect(outcome.didChangeLayout)
    #expect(model.collectedIDs == ["vpn", "not-running"])
}

@MainActor
private final class EngineTransitionRecorder {
    var presented = 0
    var dismissed = 0

    func shield() -> MenuBarTransitionShield {
        MenuBarTransitionShield(
            capture: { region in
                NSImage(size: region.size)
            },
            present: { [weak self] _, _ in self?.presented += 1 },
            dismiss: { [weak self] in self?.dismissed += 1 }
        )
    }
}

@MainActor
private func engineFixture(_ id: String, hidden: Bool, stable: Bool = true) -> ShelfItem {
    ShelfItem(
        id: id,
        title: id,
        icon: NSImage(),
        application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(),
            element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: hidden ? -100 : 900, y: 5, width: 24, height: 24)
        ),
        hasPersistentIdentity: stable
    )
}

@Test("the engine adopts a newly hidden item without revealing or moving the menu bar")
@MainActor
func engineAdoptsNewHiddenItemInPlace() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("resident", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["resident": .resident]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )

    _ = await engine.perform(.reconcile(.launch))
    driver.isCollapsed = true
    source.entries.append(engineFixture("new-chat", hidden: true))
    driver.placements["new-chat"] = .collected

    let outcome = await engine.perform(.reconcile(.poll))

    #expect(outcome.didChangeLayout)
    #expect(driver.revealCount == 0)
    #expect(driver.moves.isEmpty)
    #expect(model.collectedIDs == ["new-chat"])
    #expect(model.items.map(\.id) == ["new-chat"])
}

@Test("screen capture is optional when restoring a saved collected item")
@MainActor
func engineRestoresWithoutScreenCapture() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["sync"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("sync", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["sync": .resident]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in Issue.record("capture must not run without permission"); return [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )

    let outcome = await engine.perform(.reconcile(.launch))

    #expect(outcome.didChangeLayout)
    #expect(driver.moves == [PlannedMenuBarMove(id: "sync", placement: .collected)])
    #expect(driver.collapseCount == 1)
    #expect(engine.phase == .idle)
    #expect(model.items.map(\.id) == ["sync"])
    #expect(model.items.first?.hasMenuBarIcon == false)
}

@Test("a physical reconciliation is covered by one transition shield")
@MainActor
func engineShieldsPhysicalReconciliation() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["sync"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("sync", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["sync": .resident]
    let transition = EngineTransitionRecorder()
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false },
        transitionShield: transition.shield()
    )

    _ = await engine.perform(.reconcile(.launch))

    #expect(transition.presented == 1)
    #expect(transition.dismissed == 1)
}

@Test("a newly launched visible status item is moved into the collected section")
@MainActor
func engineCollectsNewVisibleItem() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("resident", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["resident": .resident]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))
    source.entries.append(engineFixture("new-vpn", hidden: false))
    driver.placements["new-vpn"] = .resident

    let outcome = await engine.perform(.reconcile(.poll))

    #expect(outcome.message == "已自动收纳 1 个新增图标。")
    #expect(driver.moves == [PlannedMenuBarMove(id: "new-vpn", placement: .collected)])
    #expect(driver.collapseCount == 1)
    #expect(model.collectedIDs == ["new-vpn"])
    #expect(model.items.map(\.id) == ["new-vpn"])
}

@Test("a failed automatic move reveals everything and does not persist collection")
@MainActor
func engineDoesNotPersistFailedAutomaticMove() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("resident", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["resident": .resident]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))
    source.entries.append(engineFixture("new-vpn", hidden: false))
    driver.placements["new-vpn"] = .resident
    driver.shouldFailMove = true

    let outcome = await engine.perform(.reconcile(.poll))

    #expect(outcome.message == "部分收纳图标未能移动，已展开菜单栏。")
    #expect(model.collectedIDs.isEmpty)
    #expect(driver.isCollapsed == false)
    #expect(engine.phase == .degraded("部分收纳图标未能移动，已展开菜单栏。"))

    driver.shouldFailMove = false
    let retry = await engine.perform(.setPlacement(id: "new-vpn", placement: .collected))

    #expect(retry.didChangeLayout)
    #expect(model.collectedIDs == ["new-vpn"])
    #expect(engine.phase == .idle)
}

@Test("a blocked notch destination reports actionable recovery guidance")
@MainActor
func engineReportsNotchRecoveryGuidance() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["vpn": .resident]
    driver.shouldFailMove = true
    driver.movementFailureMessage = "收纳目标被刘海遮挡，请向右移动 ShelterBar。"
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))

    let outcome = await engine.perform(.setPlacement(id: "vpn", placement: .collected))

    #expect(outcome.message == "收纳目标被刘海遮挡，请向右移动 ShelterBar。")
    #expect(engine.phase == .degraded("收纳目标被刘海遮挡，请向右移动 ShelterBar。"))
    #expect(model.collectedIDs.isEmpty)
}

@Test("reconciliation repairs a resident stranded on the collected side before collapse")
@MainActor
func engineRepairsResidentBeforeCollapse() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["hidden"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [
        engineFixture("hidden", hidden: true),
        engineFixture("resident", hidden: true),
    ]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    driver.placements = ["hidden": .collected, "resident": .collected]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )

    _ = await engine.perform(.reconcile(.launch))

    #expect(driver.moves == [PlannedMenuBarMove(id: "resident", placement: .resident)])
    #expect(driver.placements["hidden"] == .collected)
    #expect(driver.placements["resident"] == .resident)
    #expect(driver.isCollapsed)
    #expect(engine.phase == .idle)
}

@Test("an unmovable collected item stays reachable beside another collected item")
@MainActor
func engineKeepsUnmovableCollectionReachable() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["clock", "vpn"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    var clock = engineFixture("clock", hidden: true)
    clock.isMovable = false
    source.entries = [clock, engineFixture("vpn", hidden: true)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    driver.placements = ["clock": .collected, "vpn": .collected]
    var pressedIDs: [String] = []
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false },
        press: { item in pressedIDs.append(item.id); return true }
    )

    _ = await engine.perform(.reconcile(.launch))
    let activated = await engine.perform(.activate(id: "clock"))

    #expect(model.collectedIDs == ["clock", "vpn"])
    #expect(driver.moves.isEmpty)
    #expect(driver.isCollapsed == false)
    #expect(activated.shouldDismissShelf)
    #expect(pressedIDs == ["clock"])
    #expect(engine.phase == .idle)
}

@Test("presentation icon refresh is serialized through the collection engine")
@MainActor
func engineRefreshesPresentationIcons() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("resident", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["resident": .resident]
    var capturedIDs: [String] = []
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { items in
            capturedIDs = items.map(\.id)
            return items.map {
                MenuBarIconSnapshot(id: $0.id, pid: $0.menuBarReference.pid, image: NSImage())
            }
        },
        accessibilityGranted: { true },
        screenCaptureGranted: { true }
    )
    _ = await engine.perform(.reconcile(.launch))

    _ = await engine.perform(.refreshPresentation)

    #expect(capturedIDs == ["resident"])
    #expect(model.item(withID: "resident")?.hasMenuBarIcon == true)
    #expect(engine.phase == .idle)
}

@Test("manual collection and return share the verified engine transaction")
@MainActor
func engineSetsPlacementInBothDirections() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["vpn": .resident]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))

    let collected = await engine.perform(.setPlacement(id: "vpn", placement: .collected))
    let returned = await engine.perform(.setPlacement(id: "vpn", placement: .resident))

    #expect(collected.didChangeLayout && returned.didChangeLayout)
    #expect(driver.moves == [
        PlannedMenuBarMove(id: "vpn", placement: .collected),
        PlannedMenuBarMove(id: "vpn", placement: .resident),
    ])
    #expect(model.collectedIDs.isEmpty)
    #expect(driver.isCollapsed == false)
}

@Test("show all pauses polling until an explicit refresh restores collection")
@MainActor
func engineRevealAllThenRestore() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["vpn"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: true)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    driver.placements = ["vpn": .collected]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))

    _ = await engine.perform(.revealAll)
    let poll = await engine.perform(.reconcile(.poll))
    let restored = await engine.perform(.reconcile(.userRefresh))

    #expect(poll == .ignored)
    #expect(restored.didChangeLayout)
    #expect(driver.isCollapsed)
    #expect(model.collectedIDs == ["vpn"])
}

@Test("activating a hidden item defers recollection until the shelf opens again")
@MainActor
func engineActivatesHiddenItemThenRestores() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["vpn"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: true)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    driver.placements = ["vpn": .collected]
    var pressedIDs: [String] = []
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false },
        press: { item in pressedIDs.append(item.id); return true }
    )
    _ = await engine.perform(.reconcile(.launch))

    let activated = await engine.perform(.activate(id: "vpn"))
    let poll = await engine.perform(.reconcile(.poll))
    let restored = await engine.perform(.reconcile(.shelfOpened))

    #expect(activated.shouldDismissShelf)
    #expect(pressedIDs == ["vpn"])
    #expect(poll == .ignored)
    #expect(restored.didChangeLayout)
    #expect(driver.placements["vpn"] == .collected)
    #expect(driver.isCollapsed)
}

@Test("activating a hidden item reports notch guidance when its return is blocked")
@MainActor
func engineReportsNotchGuidanceDuringActivation() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["vpn"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: true)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    driver.placements = ["vpn": .collected]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false },
        press: { _ in Issue.record("A blocked item must not be pressed."); return true }
    )
    _ = await engine.perform(.reconcile(.launch))
    driver.shouldFailMove = true
    driver.movementFailureMessage = "ShelterBar 左侧空间被刘海遮挡，请向右移动收纳箱。"

    let outcome = await engine.perform(.activate(id: "vpn"))

    #expect(outcome.message == "ShelterBar 左侧空间被刘海遮挡，请向右移动收纳箱。")
    #expect(engine.phase == .degraded("ShelterBar 左侧空间被刘海遮挡，请向右移动收纳箱。"))
    #expect(driver.isCollapsed == false)
}
