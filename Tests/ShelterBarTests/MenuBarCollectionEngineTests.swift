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
    var failingIDs: Set<String> = []
    var failureReason = "destination is hidden by the camera housing"
    var isMenuBarAutoHidden = false
    var mayRevealAutoHiddenMenuBar = false
    var revealPermissionDuringMoves: [Bool] = []
    var notchHiddenIDs: Set<String> = []
    var events: [String] = []
    var recoveryHistory: [[String]] = []
    var canConfirmMissingCollectedItems = false
    var onMove: ((ShelfItem, MenuBarPlacement) -> Void)?
    func isClickable(_ item: ShelfItem) -> Bool {
        return placements[item.id] == .resident || (!isCollapsed && !notchHiddenIDs.contains(item.id))
    }

    func prepareForClick(_ item: ShelfItem) async -> Bool {
        !isCollapsed && !notchHiddenIDs.contains(item.id)
    }

    var hiddenOrder: [String] = []
    var borrowSucceeds = true
    var returnSucceeds = true
    var menuBarShows = true

    func showMenuBarIfAutoHidden() async -> Bool { menuBarShows }

    func collectedOrder(_ items: [ShelfItem]) -> [String] {
        hiddenOrder.filter { id in placements[id] == .collected && items.contains { $0.id == id } }
    }

    var borrowNoRoom = false
    func borrowVisibleSlot(for item: ShelfItem) async -> MenuBarBorrowResult {
        events.append("borrow \(item.id)")
        if borrowNoRoom { return .noRoom("notch") }
        guard borrowSucceeds else { return .failed("never appeared") }
        placements[item.id] = .resident
        return .borrowed
    }

    func returnFromVisibleSlot(_ item: ShelfItem, before neighbor: ShelfItem?) async -> Bool {
        events.append("return \(item.id) before \(neighbor?.id ?? "divider")")
        guard returnSucceeds else { return false }
        placements[item.id] = .collected
        return true
    }
    var lastMoveFailure: String?

    func observedPlacement(of item: ShelfItem) -> MenuBarPlacement? { placements[item.id] }

    func revealHiddenSection() async {
        revealCount += 1
        isCollapsed = false
        events.append("reveal")
    }

    func collapseHiddenSection() async {
        collapseCount += 1
        isCollapsed = true
        events.append("collapse")
        onCollapse?()
    }

    func revealImmediately() {
        revealCount += 1
        isCollapsed = false
    }

    func recoverVisibleLayout(collectedItems: [ShelfItem]) async {
        recoveryHistory.append(collectedItems.map(\.id).sorted())
        await revealHiddenSection()
    }

    func confirmsMissingCollectedItem(_ item: ShelfItem) -> Bool {
        canConfirmMissingCollectedItems && placements[item.id] == .collected
    }

    func move(_ item: ShelfItem, to placement: MenuBarPlacement, dropPoint: CGPoint?) async -> Bool {
        moves.append(PlannedMenuBarMove(id: item.id, placement: placement))
        revealPermissionDuringMoves.append(mayRevealAutoHiddenMenuBar)
        if shouldFailMove || failingIDs.contains(item.id) {
            lastMoveFailure = failureReason
            return false
        }
        placements[item.id] = placement
        if placement == .resident { notchHiddenIDs.remove(item.id) }
        events.append("move \(item.id) \(placement)")
        item.menuBarReference.frame.origin.x = placement == .collected ? -100 : 900
        onMove?(item, placement)
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

@Test("collection is not persisted if the driver cannot preserve the visible entry")
@MainActor
func engineRejectsUnsafeCollapse() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    source.entries = [engineFixture("vpn", hidden: false)]
    let model = ShelfViewModel(source: source, defaults: defaults,
                              isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.placements = ["vpn": .resident]
    driver.onCollapse = { [weak driver] in
        driver?.isCollapsed = false
        driver?.movementFailureMessage = "入口不可见，已展开菜单栏。"
    }
    let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false })
    let result = await engine.perform(.setPlacement(id: "vpn", placement: .collected))
    #expect(result.message == "入口不可见，已展开菜单栏。")
    #expect(model.collectedIDs.isEmpty)
    #expect(!driver.isCollapsed)
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

@Test("a MenuBarAgent-hidden target may leave AX inventory after its move is confirmed")
@MainActor
func engineAcceptsConfirmedHiddenTargetMissingFromFreshScan() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let source = EngineFixtureSource()
    let target = engineFixture("muse", hidden: false)
    source.entries = [target]
    let model = ShelfViewModel(source: source, defaults: defaults,
                               isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.placements = ["muse": .resident]
    driver.canConfirmMissingCollectedItems = true
    var captureCount = 0
    let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in
        captureCount += 1
        // The target remains in the post-move scan, then MenuBarAgent removes
        // its AX entry while the second, post-move icon capture is in flight.
        if captureCount == 2 { source.entries = [] }
        return []
    }, accessibilityGranted: { true }, screenCaptureGranted: { true })

    let outcome = await engine.perform(.setPlacement(id: "muse", placement: .collected))

    #expect(outcome.message == nil)
    #expect(driver.placements["muse"] == .collected)
    #expect(driver.isCollapsed)
    #expect(model.collectedIDs == ["muse"])
}

@Test("the fourth collection survives the recording indicator ending after icon capture")
@MainActor
func engineAcceptsCaptureIndicatorDisappearing() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let previous = ["ollama", "codex", "uuremote"]
    defaults.set(previous, forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    let indicatorID = "ax:com.apple.MenuBarAgent:com.apple.menuextra.audiovideo"
    var indicator = engineFixture(indicatorID, hidden: false)
    indicator.isMovable = false
    source.entries = previous.map { engineFixture($0, hidden: true) }
        + [engineFixture("muse", hidden: false), engineFixture("resident", hidden: false)]
    let model = ShelfViewModel(source: source, defaults: defaults,
                               isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.placements = Dictionary(uniqueKeysWithValues: previous.map { ($0, MenuBarPlacement.collected) })
    driver.placements["muse"] = .resident
    driver.placements["resident"] = .resident
    driver.placements[indicatorID] = .resident
    var captures = 0
    let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in
        captures += 1
        if captures == 1 {
            // ScreenCaptureKit starts the system indicator before the
            // transaction takes its participant snapshot.
            source.entries.append(indicator)
        } else {
            // The indicator disappears normally when screenshot capture ends.
            source.entries.removeAll { $0.id == indicatorID }
        }
        return []
    }, accessibilityGranted: { true }, screenCaptureGranted: { true })

    let outcome = await engine.perform(.setPlacement(id: "muse", placement: .collected))

    #expect(captures == 2)
    #expect(outcome.message == nil)
    #expect(outcome.didChangeLayout)
    #expect(model.collectedIDs == Set(previous + ["muse"]))
    #expect(driver.isCollapsed)
    #expect(driver.placements["resident"] == .resident)
    #expect(driver.recoveryHistory.isEmpty)
}

@Test("ordinary missing residents are still rejected, including protected system items")
@MainActor
func engineRejectsMissingNontransientResident() async {
    for residentID in ["resident", "ax:com.apple.MenuBarAgent:com.apple.menuextra.wifi",
                       "ax:com.example.other:com.apple.menuextra.audiovideo"] {
        let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = EngineFixtureSource()
        var resident = engineFixture(residentID, hidden: false)
        resident.isMovable = false
        source.entries = [engineFixture("muse", hidden: false), resident]
        let model = ShelfViewModel(source: source, defaults: defaults,
                                   isTrusted: { true }, isVisible: { $0.minX >= 0 })
        let driver = EngineFixtureDriver()
        driver.placements = ["muse": .resident, residentID: .resident]
        var captures = 0
        let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in
            captures += 1
            if captures == 2 { source.entries.removeAll { $0.id == residentID } }
            return []
        }, accessibilityGranted: { true }, screenCaptureGranted: { true })

        let outcome = await engine.perform(.setPlacement(id: "muse", placement: .collected))

        #expect(outcome.message == "系统没有完成布局调整，已恢复显示全部图标。")
        #expect(!driver.isCollapsed)
        #expect(model.collectedIDs.isEmpty)
    }
}

@Test("a failed transaction restores host intent to the persisted collection")
@MainActor
func engineRollsBackVisibilityIntentAfterFailure() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["old"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [
        engineFixture("old", hidden: true),
        engineFixture("target", hidden: false),
        engineFixture("resident", hidden: false),
    ]
    let model = ShelfViewModel(source: source, defaults: defaults,
                               isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.placements = ["old": .collected, "target": .resident, "resident": .resident]
    driver.onCollapse = { [weak driver] in driver?.placements.removeValue(forKey: "resident") }
    let engine = MenuBarCollectionEngine(model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false })

    let outcome = await engine.perform(.setPlacement(id: "target", placement: .collected))

    #expect(outcome.message == "系统没有完成布局调整，已恢复显示全部图标。")
    #expect(model.collectedIDs == ["old"])
    #expect(driver.recoveryHistory == [["old"]])
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
    // v0.5.7: a single rejected move restores the previous layout instead of
    // degrading (expanding every icon); the guidance is still shown.
    #expect(engine.phase == .idle)
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

@Test("an unmovable collected item activates without revealing the collected section")
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
    #expect(driver.revealCount == 1)
    #expect(driver.isCollapsed)
    #expect(activated.didChangeLayout == false)
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

@Test("collection keeps the original glyph when the host hides the item as soon as it moves")
@MainActor
func engineKeepsGlyphWhenCollectionImmediatelyHidesItem() async {
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
    let glyph = NSImage(size: NSSize(width: 20, height: 22))
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { items in
            // MenuBarAgent hides the pixels during move(.collected), not
            // later during collapse. No capture is possible after that.
            items.compactMap { item in
                guard driver.placements[item.id] == .resident else { return nil }
                return MenuBarIconSnapshot(id: item.id, pid: item.menuBarReference.pid, image: glyph)
            }
        },
        accessibilityGranted: { true },
        screenCaptureGranted: { true }
    )

    let outcome = await engine.perform(.setPlacement(id: "vpn", placement: .collected))

    #expect(outcome.message == nil)
    #expect(driver.placements["vpn"] == .collected)
    #expect(model.items.first?.hasMenuBarIcon == true)
    #expect(model.items.first?.icon === glyph)

    // The next presentation pass sees no pixels, but must retain the glyph
    // captured while the item was still resident.
    _ = await engine.perform(.refreshPresentation)
    #expect(model.items.first?.hasMenuBarIcon == true)
    #expect(model.items.first?.icon === glyph)
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

@Test("activating a hidden item reveals it, opens its menu, and restows after the menu closes")
@MainActor
func engineActivatesHiddenItemInPlace() async {
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

    #expect(activated.shouldDismissShelf)
    #expect(activated.didChangeLayout == false)
    #expect(pressedIDs == ["vpn"])
    #expect(driver.revealCount == 1)
    #expect(driver.events == ["reveal", "collapse"])
    #expect(driver.moves.isEmpty)
    #expect(poll == .ignored)
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
    // v0.5.7 opens a revealed item directly when it is clickable; the blocked
    // case is the revealed item still sitting under the camera housing.
    driver.notchHiddenIDs = ["vpn"]

    let outcome = await engine.perform(.activate(id: "vpn"))

    #expect(outcome.message == "ShelterBar 左侧空间被刘海遮挡，请向右移动收纳箱。")
    // v0.5.7: nothing was opened, so the collected layout is restored rather
    // than left expanded; the guidance is still shown.
    #expect(engine.phase == .idle)
    #expect(driver.isCollapsed)
}

@Test("a failed activation restores the collected layout")
@MainActor
func engineDoesNotRevealAfterDirectActivationFails() async {
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
        press: { _ in false }
    )
    _ = await engine.perform(.reconcile(.launch))

    let outcome = await engine.perform(.activate(id: "vpn"))

    #expect(outcome.message == "这个项目未响应点击，请在顶部打开。")
    #expect(outcome.didChangeLayout == false)
    #expect(outcome.shouldDismissShelf == false)
    #expect(driver.events == ["reveal", "collapse"])
    #expect(driver.moves.isEmpty)
    #expect(driver.isCollapsed)
    #expect(engine.phase == .idle)
}

@Test("one rejected collection keeps every other collected icon hidden")
@MainActor
func engineRejectedSingleMoveKeepsLayout() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let collected = ["uu", "ccswitch", "muse", "codex"]
    defaults.set(collected, forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = collected.map { engineFixture($0, hidden: true) } + [engineFixture("wechat", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    for id in collected { driver.placements[id] = .collected }
    driver.placements["wechat"] = .resident
    driver.failingIDs = ["wechat"]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))

    let outcome = await engine.perform(.setPlacement(id: "wechat", placement: .collected))

    #expect(driver.moves == [PlannedMenuBarMove(id: "wechat", placement: .collected)])
    #expect(driver.isCollapsed)
    #expect(model.collectedIDs == Set(collected))
    #expect(engine.phase == .idle)
    #expect(outcome.message?.contains("wechat") == true)
    #expect(outcome.message?.contains("刘海") == true)
    #expect(outcome.message?.contains("已展开") == false)

    // The next attempt is accepted normally once macOS allows the move.
    driver.failingIDs = []
    let retry = await engine.perform(.setPlacement(id: "wechat", placement: .collected))
    #expect(retry.message == nil)
    #expect(model.collectedIDs == Set(collected + ["wechat"]))
}

@Test("a rejected move still expands everything when the old layout cannot be verified")
@MainActor
func engineRejectedMoveFallsBackWhenRestoreFails() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["uu"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("uu", hidden: true), engineFixture("wechat", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    driver.placements = ["uu": .collected, "wechat": .resident]
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))
    driver.failingIDs = ["wechat"]
    // macOS dropped the collected item back onto the row during the attempt.
    driver.placements["uu"] = .resident

    let outcome = await engine.perform(.setPlacement(id: "wechat", placement: .collected))

    #expect(outcome.message == "macOS 未接受这个图标的位置调整，已展开菜单栏。")
    #expect(driver.isCollapsed == false)
    #expect(engine.phase == .degraded("macOS 未接受这个图标的位置调整，已展开菜单栏。"))
}

@Test("background reconciliation waits while a full-screen space hides the menu bar")
@MainActor
func engineDefersBackgroundWorkWhileMenuBarIsAutoHidden() async {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(["uu"], forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = [engineFixture("uu", hidden: false), engineFixture("wechat", hidden: false)]
    let model = ShelfViewModel(
        source: source,
        defaults: defaults,
        isTrusted: { true },
        isVisible: { $0.minX >= 0 }
    )
    let driver = EngineFixtureDriver()
    driver.placements = ["uu": .resident, "wechat": .resident]
    driver.isMenuBarAutoHidden = true
    let engine = MenuBarCollectionEngine(
        model: model,
        driver: driver,
        capture: { _ in [] },
        accessibilityGranted: { true },
        screenCaptureGranted: { false }
    )

    let launch = await engine.perform(.reconcile(.launch))
    #expect(launch == .ignored)
    #expect(driver.moves.isEmpty)
    #expect(driver.revealCount == 0)
    #expect(engine.phase == .idle)
    #expect(model.collectedIDs == ["uu"])

    // Opening the shelf is user-initiated, so the bar may be shown to move.
    _ = await engine.perform(.reconcile(.shelfOpened))
    #expect(driver.moves == [PlannedMenuBarMove(id: "uu", placement: .collected)])
    #expect(driver.revealPermissionDuringMoves == [true])
    #expect(driver.mayRevealAutoHiddenMenuBar == false)

    _ = await engine.perform(.setPlacement(id: "wechat", placement: .collected))
    #expect(driver.revealPermissionDuringMoves == [true, true])
    #expect(driver.mayRevealAutoHiddenMenuBar == false)
    #expect(model.collectedIDs == ["uu", "wechat"])
}

@MainActor
private func activationFixture(collected: [String], resident: [String] = []) -> (ShelfViewModel, EngineFixtureDriver, UserDefaults, String) {
    let suite = "ShelterBarEngineTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(collected, forKey: "shelf.collectedItems")
    let source = EngineFixtureSource()
    source.entries = collected.map { engineFixture($0, hidden: true) } + resident.map { engineFixture($0, hidden: false) }
    let model = ShelfViewModel(source: source, defaults: defaults, isTrusted: { true }, isVisible: { $0.minX >= 0 })
    let driver = EngineFixtureDriver()
    driver.isCollapsed = true
    for id in collected { driver.placements[id] = .collected }
    for id in resident { driver.placements[id] = .resident }
    driver.hiddenOrder = collected
    return (model, driver, defaults, suite)
}

@Test("clicking moves only that item into view and returns it to its slot after the menu closes")
@MainActor
func engineKeepsItemRevealedWhileMenuIsOpen() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["uu", "muse"])
    defer { defaults.removePersistentDomain(forName: suite) }
    var collapsedWhenPressed: Bool?
    var collapsedWhileOpen: Bool?
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false },
        press: { _ in
            collapsedWhenPressed = driver.isCollapsed
            driver.events.append("press")
            return true
        },
        awaitMenuClosed: { _ in
            collapsedWhileOpen = driver.isCollapsed
            driver.events.append("closed")
        }
    )
    _ = await engine.perform(.reconcile(.launch))

    let outcome = await engine.perform(.activate(id: "uu"))

    #expect(outcome.shouldDismissShelf)
    // The hidden section stays collapsed the whole time: nothing else shows.
    #expect(collapsedWhenPressed == true)
    #expect(collapsedWhileOpen == true)
    #expect(driver.events == ["borrow uu", "press", "closed", "return uu before muse"])
    #expect(driver.revealCount == 0)
    #expect(driver.collapseCount == 0)
    #expect(driver.moves.isEmpty)
    #expect(driver.placements["muse"] == .collected)
    #expect(driver.collectedOrder(model.scan()) == ["uu", "muse"])
    #expect(model.collectedIDs == ["uu", "muse"])
    #expect(engine.phase == .idle)
}

@Test("when the single-item move fails, expanding the hidden section is the last resort")
@MainActor
func engineBorrowsVisibleSlotUnderNotch() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["uu", "muse"], resident: ["wechat"])
    defer { defaults.removePersistentDomain(forName: suite) }
    driver.notchHiddenIDs = ["uu"]
    driver.borrowSucceeds = false
    var pressed: [String] = []
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false },
        press: { item in pressed.append(item.id); driver.events.append("press"); return true },
        awaitMenuClosed: { _ in driver.events.append("closed") }
    )
    _ = await engine.perform(.reconcile(.launch))

    let outcome = await engine.perform(.activate(id: "uu"))

    #expect(outcome.shouldDismissShelf)
    #expect(pressed == ["uu"])
    #expect(driver.events == ["borrow uu", "reveal", "move uu resident", "press", "closed", "move uu collected", "collapse"])
    #expect(driver.placements["uu"] == .collected)
    #expect(driver.isCollapsed)
    #expect(model.collectedIDs == ["uu", "muse"])
}

@Test("a resident item that is already visible is pressed in place")
@MainActor
func engineActivatesVisibleItemInPlace() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["uu"], resident: ["wechat"])
    defer { defaults.removePersistentDomain(forName: suite) }
    var pressed: [String] = []
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false },
        press: { item in pressed.append(item.id); return true },
        awaitMenuClosed: { _ in Issue.record("in-place activation does not hold the layout") }
    )
    _ = await engine.perform(.reconcile(.launch))

    let outcome = await engine.perform(.activate(id: "wechat"))

    #expect(outcome.shouldDismissShelf)
    #expect(pressed == ["wechat"])
    #expect(driver.events.isEmpty)
    #expect(driver.isCollapsed)
}

@Test("a middle item returns before its original right neighbour; others never move")
@MainActor
func engineRestoresClickedItemToOriginalIndex() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["a", "b", "c"], resident: ["r"])
    defer { defaults.removePersistentDomain(forName: suite) }
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false },
        press: { _ in driver.events.append("press"); return true },
        awaitMenuClosed: { _ in driver.events.append("closed") }
    )
    _ = await engine.perform(.reconcile(.launch))

    _ = await engine.perform(.activate(id: "b"))
    _ = await engine.perform(.activate(id: "c"))

    #expect(driver.events == [
        "borrow b", "press", "closed", "return b before c",
        "borrow c", "press", "closed", "return c before divider",
    ])
    #expect(driver.collectedOrder(model.scan()) == ["a", "b", "c"])
    #expect(driver.placements["a"] == .collected && driver.placements["r"] == .resident)
    #expect(driver.revealCount == 0 && driver.moves.isEmpty)
}

@Test("a failed return is repaired by a verified relayout instead of leaving the item visible")
@MainActor
func engineRepairsFailedSingleItemReturn() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["a", "b"])
    defer { defaults.removePersistentDomain(forName: suite) }
    driver.returnSucceeds = false
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false },
        press: { _ in true }, awaitMenuClosed: { _ in }
    )
    _ = await engine.perform(.reconcile(.launch))

    let outcome = await engine.perform(.activate(id: "a"))

    #expect(outcome.shouldDismissShelf)
    #expect(driver.events == ["borrow a", "return a before b", "reveal", "move a collected", "collapse"])
    #expect(driver.placements["a"] == .collected)
    #expect(driver.isCollapsed)
    #expect(engine.phase == .idle)
}

@Test("refresh and restore briefly reveals stowed items whose glyphs are missing, then stows them again")
@MainActor
func engineUserRefreshRecapturesMissingIcons() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["uu", "muse"])
    defer { defaults.removePersistentDomain(forName: suite) }
    var captured: [[String]] = []
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver,
        capture: { items in
            captured.append(items.map(\.id).sorted())
            return items.map { MenuBarIconSnapshot(id: $0.id, pid: $0.menuBarReference.pid,
                                                   image: NSImage(size: NSSize(width: 18, height: 22))) }
        },
        accessibilityGranted: { true }, screenCaptureGranted: { true }
    )
    _ = await engine.perform(.reconcile(.launch))
    #expect(driver.revealCount == 0, "background work never reveals just for icons")

    _ = await engine.perform(.reconcile(.userRefresh))
    #expect(driver.events == ["reveal", "collapse"])
    #expect(captured.last == ["muse", "uu"])
    #expect(model.itemsMissingIcons.isEmpty)
    #expect(driver.isCollapsed)

    _ = await engine.perform(.reconcile(.userRefresh))
    #expect(driver.events == ["reveal", "collapse"], "nothing is revealed once glyphs exist")
}

@Test("a single-item click reveal recaptures the clicked item while it is visible")
@MainActor
func engineRecapturesBorrowedItem() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["uu", "muse"])
    defer { defaults.removePersistentDomain(forName: suite) }
    var captured: [[String]] = []
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver,
        capture: { items in captured.append(items.map(\.id)); return [] },
        accessibilityGranted: { true }, screenCaptureGranted: { true },
        press: { _ in driver.events.append("press"); return true },
        awaitMenuClosed: { _ in driver.events.append("closed") }
    )
    _ = await engine.perform(.activate(id: "muse"))
    #expect(captured == [["muse"]])
    #expect(driver.events == ["borrow muse", "press", "closed", "return muse before divider"])
}


@Test("a click reveal is persisted before anything moves and cleared after the item is back")
@MainActor
func enginePersistsPendingRestoreDuringReveal() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["a", "b", "c"])
    defer { defaults.removePersistentDomain(forName: suite) }
    var pendingWhileOpen: MenuBarPendingRestore?
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false },
        press: { _ in pendingWhileOpen = model.pendingRestore; return true },
        awaitMenuClosed: { _ in }
    )
    _ = await engine.perform(.activate(id: "b"))
    #expect(pendingWhileOpen == MenuBarPendingRestore(id: "b", leftNeighbor: "a", rightNeighbor: "c"))
    #expect(model.pendingRestore == nil)
    #expect(driver.collectedOrder(model.scan()) == ["a", "b", "c"])
}

@Test("an interrupted reveal is restored before its right neighbour at the next launch")
@MainActor
func engineRestoresInterruptedRevealAtLaunch() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["a", "b", "c"])
    defer { defaults.removePersistentDomain(forName: suite) }
    driver.placements["b"] = .resident
    model.pendingRestore = MenuBarPendingRestore(id: "b", leftNeighbor: "a", rightNeighbor: "c")
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))
    #expect(driver.events.first == "return b before c")
    #expect(driver.placements["b"] == .collected)
    #expect(model.pendingRestore == nil)
    #expect(driver.moves.isEmpty)
}

@Test("with no visible room next to the handle the user gets a message and nothing expands")
@MainActor
func engineReportsNoRoomInsteadOfExpanding() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["a", "b"])
    defer { defaults.removePersistentDomain(forName: suite) }
    driver.borrowNoRoom = true
    var pressed = 0
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false },
        press: { _ in pressed += 1; return true }, awaitMenuClosed: { _ in }
    )
    let outcome = await engine.perform(.activate(id: "a"))
    #expect(outcome.message?.contains("刘海") == true)
    #expect(pressed == 0)
    #expect(driver.revealCount == 0)
    #expect(driver.events == ["borrow a"])
    #expect(model.pendingRestore == nil)
}

@Test("launch collapses an already-revealed layout without needing a visible menu bar")
@MainActor
func engineCollapsesAtLaunchWhileMenuBarIsAutoHidden() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["a"], resident: ["r"])
    defer { defaults.removePersistentDomain(forName: suite) }
    driver.isCollapsed = false
    driver.isMenuBarAutoHidden = true
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.launch))
    #expect(driver.isCollapsed)
    #expect(driver.events == ["collapse"])
    #expect(driver.moves.isEmpty)
}

@Test("an item macOS refuses to move stays in the menu bar without unstowing the others")
@MainActor
func engineKeepsRefusedItemResidentInsteadOfDegrading() async {
    let (model, driver, defaults, suite) = activationFixture(collected: ["a", "np"], resident: [])
    defer { defaults.removePersistentDomain(forName: suite) }
    driver.placements["np"] = .resident
    driver.failingIDs = ["np"]
    driver.failureReason = "item never observed on the collected side"
    let engine = MenuBarCollectionEngine(
        model: model, driver: driver, capture: { _ in [] },
        accessibilityGranted: { true }, screenCaptureGranted: { false }
    )
    _ = await engine.perform(.reconcile(.userRefresh))
    #expect(engine.phase == .idle)
    #expect(driver.isCollapsed)
    #expect(driver.placements["a"] == .collected)
    #expect(model.collectedIDs == ["a"])
    #expect(model.message?.contains("np") == true)
}
