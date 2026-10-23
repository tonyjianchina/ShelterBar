import AppKit
import OSLog
import ShelterBarCore

@MainActor
protocol MenuBarLayoutDriving: AnyObject {
    var isCollapsed: Bool { get }
    var transitionRegion: CGRect? { get }
    var movementFailureMessage: String? { get }
    func observedPlacement(of item: ShelfItem) -> MenuBarPlacement?
    /// True only when the host has an authoritative hidden-state record for
    /// a collected item that no longer appears in the live AX inventory.
    func confirmsMissingCollectedItem(_ item: ShelfItem) -> Bool
    func revealHiddenSection() async
    /// Reveals every item after a failed transaction and restores the host's
    /// intended hidden set to the collection already persisted by the model.
    func recoverVisibleLayout(collectedItems: [ShelfItem]) async
    func collapseHiddenSection() async
    func revealImmediately()
    func move(_ item: ShelfItem, to placement: MenuBarPlacement, dropPoint: CGPoint?) async -> Bool
    /// Diagnostic reason for the most recent rejected move, if known.
    var lastMoveFailure: String? { get }
    /// The active display's menu bar has slid away (e.g. a full-screen space).
    var isMenuBarAutoHidden: Bool { get }
    /// User-initiated work may briefly show an auto-hidden bar to move items.
    var mayRevealAutoHiddenMenuBar: Bool { get set }
    /// The item is on a visible menu bar right now, so a click can land on it.
    func isClickable(_ item: ShelfItem) -> Bool
    /// After revealing, make the item clickable (e.g. show an auto-hidden bar).
    func prepareForClick(_ item: ShelfItem) async -> Bool
    /// Shows an auto-hidden menu bar if needed; true when it is visible.
    func showMenuBarIfAutoHidden() async -> Bool
    /// IDs of collected items, left to right.
    func collectedOrder(_ items: [ShelfItem]) -> [String]
    /// Moves only this collected item into a visible slot by the handle.
    func borrowVisibleSlot(for item: ShelfItem) async -> MenuBarBorrowResult
    /// Returns a borrowed item to the left of its former right neighbour.
    func returnFromVisibleSlot(_ item: ShelfItem, before neighbor: ShelfItem?) async -> Bool
    /// Waits (bounded) while the user is moving the mouse or holding keys.
    func waitUntilUserIdle(maximum: Duration) async
    /// Rebuilds a host-level allow list when running applications change.
    /// Legacy per-item movement has no host state to refresh.
    func refreshHostVisibility() async -> Bool
}

extension MenuBarLayoutDriving {
    var lastMoveFailure: String? { nil }
    var isMenuBarAutoHidden: Bool { false }
    func confirmsMissingCollectedItem(_ item: ShelfItem) -> Bool { false }
    func recoverVisibleLayout(collectedItems: [ShelfItem]) async { await revealHiddenSection() }
    func waitUntilUserIdle(maximum: Duration) async {}
    func refreshHostVisibility() async -> Bool { true }
}

extension MenuBarLayoutDriving {
    var movementFailureMessage: String? { nil }
}

enum MenuBarReconcileReason: Equatable {
    case launch
    case poll
    case shelfOpened
    case userRefresh
    case screenChanged
}

enum MenuBarCollectionCommand {
    case reconcile(MenuBarReconcileReason)
    case setPlacement(id: String, placement: MenuBarPlacement, dropPoint: CGPoint? = nil)
    case activate(id: String)
    case refreshPresentation
    case revealAll
}

struct MenuBarCollectionOutcome: Equatable {
    var message: String?
    var didChangeLayout = false
    var shouldDismissShelf = false

    static let ignored = MenuBarCollectionOutcome()
}

@MainActor
final class MenuBarCollectionEngine {
    enum Phase: Equatable {
        case idle
        case observing
        case applying
        case degraded(String)

        var isBusy: Bool { self == .applying }
    }

    private(set) var phase: Phase = .idle {
        didSet { model.isBusy = phase.isBusy }
    }

    private let model: ShelfViewModel
    private let driver: any MenuBarLayoutDriving
    private let capture: @MainActor ([ShelfItem]) async -> [MenuBarIconSnapshot]
    private let accessibilityGranted: @MainActor () -> Bool
    private let screenCaptureGranted: @MainActor () -> Bool
    private let press: @MainActor (ShelfItem) async -> Bool
    private let awaitMenuClosed: @MainActor (ShelfItem) async -> Void
    private let transitionShield: MenuBarTransitionShield?
    private var knownItemIDs = Set<String>()
    private var didSeedInventory = false
    private var suspendAutomaticReconciliation = false

    init(
        model: ShelfViewModel,
        driver: any MenuBarLayoutDriving,
        capture: @escaping @MainActor ([ShelfItem]) async -> [MenuBarIconSnapshot],
        accessibilityGranted: @escaping @MainActor () -> Bool = { AccessibilityPermission.isGranted },
        screenCaptureGranted: @escaping @MainActor () -> Bool = { ScreenCapturePermission.isGranted },
        press: @escaping @MainActor (ShelfItem) async -> Bool = { await MenuBarMenuOpener.open($0) },
        awaitMenuClosed: @escaping @MainActor (ShelfItem) async -> Void = { await MenuBarMenuOpener.waitUntilClosed($0) },
        transitionShield: MenuBarTransitionShield? = nil
    ) {
        self.model = model
        self.driver = driver
        self.capture = capture
        self.accessibilityGranted = accessibilityGranted
        self.screenCaptureGranted = screenCaptureGranted
        self.press = press
        self.awaitMenuClosed = awaitMenuClosed
        self.transitionShield = transitionShield
    }

    var isBusy: Bool { phase.isBusy }

    func perform(_ command: MenuBarCollectionCommand) async -> MenuBarCollectionOutcome {
        if case .degraded = phase {
            switch command {
            case .reconcile(.userRefresh), .setPlacement, .activate, .revealAll:
                phase = .idle
            case .reconcile, .refreshPresentation:
                return .ignored
            }
        }
        guard phase == .idle else { return .ignored }

        switch command {
        case let .reconcile(reason):
            return await reconcile(reason: reason)
        case let .setPlacement(id, placement, dropPoint):
            return await setPlacement(id: id, placement: placement, dropPoint: dropPoint)
        case let .activate(id):
            return await activate(id: id)
        case .refreshPresentation:
            return await refreshPresentation()
        case .revealAll:
            driver.revealImmediately()
            suspendAutomaticReconciliation = true
            model.refresh()
            return MenuBarCollectionOutcome(
                message: "已临时展开全部图标。点击刷新可恢复收纳。",
                didChangeLayout: true
            )
        }
    }

    func cancelAndReveal() {
        driver.revealImmediately()
        phase = .idle
        model.refresh()
    }

    private func reconcile(reason: MenuBarReconcileReason) async -> MenuBarCollectionOutcome {
        if suspendAutomaticReconciliation {
            guard reason == .userRefresh || reason == .shelfOpened || reason == .screenChanged else {
                return .ignored
            }
            suspendAutomaticReconciliation = false
        }

        phase = .observing
        updatePermissions()
        guard model.hasAccessibilityPermission else {
            driver.revealImmediately()
            knownItemIDs.removeAll()
            didSeedInventory = false
            model.refresh()
            phase = .idle
            return MenuBarCollectionOutcome(message: "请允许辅助功能权限以管理菜单栏图标。")
        }

        model.refresh()
        guard await driver.refreshHostVisibility() else {
            return await degrade(CollectionEngineError.message(
                "系统未能刷新菜单栏显示状态，已恢复显示全部图标。"
            ))
        }
        if reason == .launch, let pending = model.pendingRestore {
            // A click reveal was interrupted (quit or crash): put the item
            // back before its former right neighbour first.
            model.pendingRestore = nil
            let scanned = model.scan()
            if let item = scanned.first(where: { $0.id == pending.id }), item.isMovable,
               driver.observedPlacement(of: item) == .resident {
                menuBarMoveLog.notice("restoring \(pending.id, privacy: .public) left visible by an interrupted click reveal")
                let neighbor = pending.rightNeighbor.flatMap { id in scanned.first { $0.id == id } }
                _ = await driver.returnFromVisibleSlot(item, before: neighbor)
                model.refresh()
            }
        }
        let items = model.allItems
        let observed = items.map {
            ObservedMenuBarItem(
                id: $0.id,
                placement: driver.observedPlacement(of: $0),
                isMovable: $0.isMovable
            )
        }
        let availableIDs = Set(observed.filter { $0.placement != nil }.map(\.id))
        if !didSeedInventory {
            knownItemIDs = availableIDs
            didSeedInventory = true
        }
        let previouslyCollectedIDs = model.collectedIDs
        let plan = MenuBarReconciliation.plan(MenuBarReconciliationRequest(
            items: observed,
            knownItemIDs: knownItemIDs,
            desiredCollectedIDs: previouslyCollectedIDs,
            newItemPolicy: .collect
        ))

        do {
            let needsPhysicalChange = !plan.moves.isEmpty
                || !plan.unresolvedItemIDs.isEmpty
                || (!plan.desiredCollectedIDs.isEmpty && !driver.isCollapsed)
                || (plan.desiredCollectedIDs.isEmpty && driver.isCollapsed)
            let userInitiated = reason == .userRefresh || reason == .shelfOpened
            // "刷新并恢复收纳" briefly reveals stowed items to capture glyphs that
            // are neither live nor persisted yet.
            let missingIcons = reason == .userRefresh && model.hasScreenCapturePermission
                && !plan.desiredCollectedIDs.isEmpty && !model.itemsMissingIcons.isEmpty
            if missingIcons, !needsPhysicalChange {
                let count = model.itemsMissingIcons.count
                menuBarMoveLog.notice("refresh: \(count) stowed icons have no image; revealing briefly to capture")
            }
            let needsMoves = !plan.moves.isEmpty || !plan.unresolvedItemIDs.isEmpty
            if needsPhysicalChange, needsMoves, !userInitiated, driver.isMenuBarAutoHidden {
                // Never move the cursor for background work; retry once the
                // menu bar is visible again instead of expanding everything.
                phase = .idle
                return .ignored
            }
            if needsPhysicalChange || missingIcons {
                driver.mayRevealAutoHiddenMenuBar = userInitiated
                defer { driver.mayRevealAutoHiddenMenuBar = false }
                try await applyLayout(collected: plan.desiredCollectedIDs)
            }
            for id in previouslyCollectedIDs.subtracting(plan.desiredCollectedIDs) {
                model.setCollected(false, id: id)
            }
            for id in plan.adoptedCollectedIDs { model.setCollected(true, id: id) }
            knownItemIDs.formUnion(availableIDs)
            model.refresh()
            phase = .idle

            let adoptedCount = plan.adoptedCollectedIDs.count
            return MenuBarCollectionOutcome(
                message: adoptedCount == 0 ? nil : "已自动收纳 \(adoptedCount) 个新增图标。",
                didChangeLayout: needsPhysicalChange || missingIcons || adoptedCount > 0
            )
        } catch {
            return await degrade(error)
        }
    }

    private func setPlacement(
        id: String,
        placement: MenuBarPlacement,
        dropPoint: CGPoint?
    ) async -> MenuBarCollectionOutcome {
        updatePermissions()
        guard model.hasAccessibilityPermission else {
            return MenuBarCollectionOutcome(message: "请允许辅助功能权限以管理菜单栏图标。")
        }
        phase = .applying
        model.refresh()
        guard model.item(withID: id) != nil || model.scan().contains(where: { $0.id == id }) else {
            return await degrade(CollectionEngineError.message("这个图标已退出或暂时不可用，已展开菜单栏。"))
        }
        var desired = model.collectedIDs
        if placement == .collected { desired.insert(id) } else { desired.remove(id) }
        driver.mayRevealAutoHiddenMenuBar = true
        defer { driver.mayRevealAutoHiddenMenuBar = false }
        do {
            try await applyLayout(collected: desired, preferredMove: (id, placement, dropPoint))
            model.setCollected(placement == .collected, id: id)
            knownItemIDs.insert(id)
            model.refresh()
            phase = .idle
            return MenuBarCollectionOutcome(didChangeLayout: true)
        } catch CollectionEngineError.preferredMoveRejected(let message) {
            // The rest of the layout was restored and verified; only this one
            // item keeps its previous side, so nothing else is unstowed.
            knownItemIDs.insert(id)
            model.message = message
            model.refresh()
            phase = .idle
            return MenuBarCollectionOutcome(message: message, didChangeLayout: true)
        } catch {
            return await degrade(error)
        }
    }

    private func activate(id: String) async -> MenuBarCollectionOutcome {
        updatePermissions()
        guard model.hasAccessibilityPermission else {
            return MenuBarCollectionOutcome(message: "请允许辅助功能权限以打开菜单栏图标。")
        }
        model.refresh()
        guard let item = model.item(withID: id) ?? model.scan().first(where: { $0.id == id }) else {
            return MenuBarCollectionOutcome(message: "这个图标已退出或暂时不可用。")
        }
        let notResponding = MenuBarCollectionOutcome(message: "这个项目未响应点击，请在顶部打开。")
        if driver.isClickable(item) {
            return await press(item) ? MenuBarCollectionOutcome(shouldDismissShelf: true) : notResponding
        }
        phase = .applying
        driver.mayRevealAutoHiddenMenuBar = true
        defer { driver.mayRevealAutoHiddenMenuBar = false }
        func fresh() -> ShelfItem { model.scan().first(where: { $0.id == id }) ?? item }
        // Preferred path: move only the clicked item into view, so the other
        // stowed icons never appear in the menu bar.
        let order = driver.collectedOrder(model.scan())
        if driver.isCollapsed, item.isMovable, let index = order.firstIndex(of: id),
           await driver.showMenuBarIfAutoHidden() {
            let neighborID = order.dropFirst(index + 1).first
            // Persist before moving: a quit mid-reveal is repaired at launch.
            model.pendingRestore = MenuBarPendingRestore(
                id: id, leftNeighbor: index > 0 ? order[index - 1] : nil, rightNeighbor: neighborID
            )
            defer { model.pendingRestore = nil }
            await driver.waitUntilUserIdle(maximum: .milliseconds(1500))
            let borrowed = await driver.borrowVisibleSlot(for: fresh())
            if case let .noRoom(reason) = borrowed {
                menuBarMoveLog.notice("no room to reveal \(id, privacy: .public) alone: \(reason, privacy: .public)")
                if driver.observedPlacement(of: fresh()) != .collected {
                    do { try await applyLayout(collected: model.collectedIDs) } catch { return await degrade(error) }
                }
                phase = .idle
                model.refresh()
                return MenuBarCollectionOutcome(message: "顶部菜单栏没有空位显示「\(item.title)」（可能被刘海遮挡）。请关闭一些菜单栏图标，或在外接显示器上打开。")
            }
            if borrowed == .borrowed {
                let target = fresh()
                let opened = await press(target)
                if opened { await awaitMenuClosed(target) }
                _ = await driver.showMenuBarIfAutoHidden()
                // The item is visible right now: refresh its persisted glyph.
                await recaptureVisible([fresh()])
                await driver.waitUntilUserIdle(maximum: .seconds(5))
                _ = await driver.showMenuBarIfAutoHidden()
                let neighbor = neighborID.flatMap { nid in model.scan().first(where: { $0.id == nid }) }
                let returned = await driver.returnFromVisibleSlot(fresh(), before: neighbor)
                if !(returned && driver.isCollapsed && driver.collectedOrder(model.scan()) == order) {
                    menuBarMoveLog.error("single-item restore of \(id, privacy: .public) incomplete; repairing layout")
                    do {
                        try await applyLayout(collected: model.collectedIDs)
                    } catch {
                        return await degrade(error)
                    }
                }
                phase = .idle
                model.refresh()
                return opened ? MenuBarCollectionOutcome(shouldDismissShelf: true) : notResponding
            }
            if driver.observedPlacement(of: fresh()) != .collected {
                // The borrow moved it but it is not usable (e.g. under the
                // notch): put the layout back before the fallback below.
                do {
                    try await applyLayout(collected: model.collectedIDs)
                } catch {
                    return await degrade(error)
                }
                phase = .applying
            }
        }
        menuBarMoveLog.notice("single-item reveal unavailable for \(id, privacy: .public) (collapsed \(self.driver.isCollapsed, privacy: .public), movable \(item.isMovable, privacy: .public), order \(order, privacy: .public)); falling back to expanding the hidden section")
        return await activateByRevealingAll(item: item, id: id, notResponding: notResponding)
    }

    private func activateByRevealingAll(item: ShelfItem, id: String,
                                        notResponding: MenuBarCollectionOutcome) async -> MenuBarCollectionOutcome {
        // Last resort: reveal the whole hidden section, open the menu, keep it
        // revealed until the menu closes, then stow everything again.
        phase = .applying
        let wasCollapsed = driver.isCollapsed
        let collected = model.collectedIDs
        await driver.revealHiddenSection()
        func fresh() -> ShelfItem { model.scan().first(where: { $0.id == id }) ?? item }
        var target = fresh()
        var movedOut = false
        var blockedGuidance: String?
        var ready = await driver.prepareForClick(target)
        if !ready, target.isMovable, driver.observedPlacement(of: target) == .collected {
            // The notch can still hide a revealed item; borrow a visible slot.
            movedOut = await driver.move(target, to: .resident, dropPoint: nil)
            if !movedOut { blockedGuidance = driver.movementFailureMessage }
            target = fresh()
            if movedOut { ready = await driver.prepareForClick(target) }
        }
        let opened = ready ? await press(target) : false
        if opened { await awaitMenuClosed(target) }
        await recaptureVisible(model.scan().filter { collected.contains($0.id) })
        do {
            if movedOut {
                target = fresh()
                guard await driver.move(target, to: .collected, dropPoint: nil) else {
                    throw CollectionEngineError.message("打开后未能把图标收回收纳栏，已展开菜单栏。")
                }
            }
            if wasCollapsed { try await restoreLayout(collected: collected) }
        } catch {
            return await degrade(error)
        }
        phase = .idle
        model.refresh()
        if opened { return MenuBarCollectionOutcome(shouldDismissShelf: true) }
        // The layout is restored; still tell the user why nothing opened.
        return blockedGuidance.map { MenuBarCollectionOutcome(message: $0) } ?? notResponding
    }

    /// Opportunistically captures items while they are on screen.
    private func recaptureVisible(_ items: [ShelfItem]) async {
        guard model.hasScreenCapturePermission, !items.isEmpty, !Task.isCancelled else { return }
        for item in items { model.remember(item) }
        let snapshots = await capture(items)
        guard !Task.isCancelled, !snapshots.isEmpty else { return }
        model.applyMenuBarIcons(snapshots)
    }

    private func refreshPresentation() async -> MenuBarCollectionOutcome {
        phase = .observing
        updatePermissions()
        model.refresh()
        guard model.hasAccessibilityPermission, model.hasScreenCapturePermission, !Task.isCancelled else {
            phase = .idle
            return .ignored
        }
        let snapshots = await capture(model.allItems)
        guard !Task.isCancelled else {
            phase = .idle
            return .ignored
        }
        model.applyMenuBarIcons(snapshots)
        phase = .idle
        return .ignored
    }

    private func applyLayout(
        collected desiredCollectedIDs: Set<String>,
        preferredMove: (id: String, placement: MenuBarPlacement, dropPoint: CGPoint?)? = nil
    ) async throws {
        let item = preferredMove.flatMap { move in
            model.item(withID: move.id) ?? model.scan().first(where: { $0.id == move.id })
        }
        let region = transitionRegion(for: item, dropPoint: preferredMove?.dropPoint)
        try await withTransition(over: region) {
            try await self.applyLayoutUnshielded(
                collected: desiredCollectedIDs,
                preferredMove: preferredMove
            )
        }
    }

    private func applyLayoutUnshielded(
        collected requestedCollectedIDs: Set<String>,
        preferredMove: (id: String, placement: MenuBarPlacement, dropPoint: CGPoint?)?
    ) async throws {
        var desiredCollectedIDs = requestedCollectedIDs
        phase = .applying
        // Already revealed (e.g. at launch): nothing to expand. This also
        // lets an auto-hidden bar be collapsed without touching the cursor.
        let needsMoves = preferredMove != nil || model.scan().contains { item in
            item.isMovable && driver.observedPlacement(of: item)
                != (desiredCollectedIDs.contains(item.id) ? .collected : .resident)
        }
        if driver.isCollapsed || needsMoves { await driver.revealHiddenSection() }
        try Task.checkCancellation()

        // MenuBarAgent removes an item's pixels during move(.collected),
        // unlike the legacy divider which hides them only during collapse.
        // Keep its last visible glyph before any movement can hide it. The
        // existing post-move pass still supports legacy off-screen windows.
        await recaptureVisible(model.scan().filter {
            desiredCollectedIDs.contains($0.id) && driver.isClickable($0)
        })
        try Task.checkCancellation()

        // Protect every real participant, including residents displaced by
        // this transaction. Unmanaged AX remnants with no observable placement
        // cannot be required to reappear in a menu bar they never occupied.
        var participantItems = Dictionary(model.scan().filter {
            driver.observedPlacement(of: $0) != nil || desiredCollectedIDs.contains($0.id)
        }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let preferredMove, participantItems[preferredMove.id] == nil,
           let remembered = model.item(withID: preferredMove.id) {
            participantItems[preferredMove.id] = remembered
        }

        if let preferredMove {
            let item = model.scan().first(where: { $0.id == preferredMove.id })
            var moved = false
            if let item {
                moved = await driver.move(item, to: preferredMove.placement, dropPoint: preferredMove.dropPoint)
            }
            if !moved {
                try Task.checkCancellation()
                // Nothing else has changed yet: put the previous layout back
                // instead of expanding every collected icon.
                try await restoreLayout(collected: model.collectedIDs)
                let name = item?.title ?? model.item(withID: preferredMove.id)?.title ?? "这个图标"
                let side = preferredMove.placement == .collected ? "收纳" : "放回菜单栏"
                let hint = driver.lastMoveFailure.map { reason in
                    if reason.contains("camera housing") { return "（目标位置被刘海遮挡）" }
                    if reason.contains("auto-hidden") { return "（当前屏幕的菜单栏已自动隐藏，例如全屏应用）" }
                    return ""
                } ?? ""
                // Actionable guidance from the driver (e.g. the notch blocks
                // the slot left of ShelterBar) beats a generic explanation.
                throw CollectionEngineError.preferredMoveRejected(
                    driver.movementFailureMessage
                        ?? "macOS 未接受「\(name)」的位置调整\(hint)，未能\(side)；其它图标保持原状，可稍后重试。"
                )
            }
        }

        var scan = model.scan()
        for item in scan where item.isMovable && !desiredCollectedIDs.contains(item.id)
            && driver.observedPlacement(of: item) == .collected {
            guard await driver.move(item, to: .resident, dropPoint: nil) else {
                throw CollectionEngineError.message(
                    driver.movementFailureMessage ?? "无法安全整理当前菜单栏，已展开全部图标。"
                )
            }
            try Task.checkCancellation()
        }

        scan = model.scan()
        var refused: [ShelfItem] = []
        for item in scan where item.isMovable && desiredCollectedIDs.contains(item.id)
            && driver.observedPlacement(of: item) != .collected {
            if !(await driver.move(item, to: .collected, dropPoint: nil)) {
                try Task.checkCancellation()
                guard driver.observedPlacement(of: model.scan().first { $0.id == item.id } ?? item) != .collected else { continue }
                // Only a drag that was delivered but ignored by the host
                // means "this item cannot be stowed"; anything else (stale
                // geometry, notch, display change) is a transient failure.
                guard driver.lastMoveFailure?.contains("never observed") == true else {
                    throw CollectionEngineError.message(
                        driver.movementFailureMessage ?? "部分收纳图标未能移动，已展开菜单栏。"
                    )
                }
                // One item the host refuses to move (e.g. Now Playing) stays
                // in the menu bar instead of unstowing everything else.
                menuBarMoveLog.error("leaving \(item.id, privacy: .public) in the menu bar: \(self.driver.lastMoveFailure ?? "move refused", privacy: .public)")
                refused.append(item)
                desiredCollectedIDs.remove(item.id)
                if preferredMove?.id == item.id { throw CollectionEngineError.message("部分收纳图标未能移动，已展开菜单栏。") }
            }
            try Task.checkCancellation()
        }
        for item in refused { model.setCollected(false, id: item.id) }
        if let first = refused.first {
            model.message = "macOS 未允许移动「\(first.title)」，它已保留在菜单栏，其它图标照常收纳。"
        }

        scan = model.scan()
        let collectedItems = scan.filter { desiredCollectedIDs.contains($0.id) }
        if model.hasScreenCapturePermission, !collectedItems.isEmpty {
            for item in collectedItems { model.remember(item) }
            let snapshots = await capture(collectedItems)
            try Task.checkCancellation()
            model.applyMenuBarIcons(snapshots)
        }

        if desiredCollectedIDs.isEmpty {
            driver.revealImmediately()
        } else {
            await driver.collapseHiddenSection()
            guard driver.isCollapsed else {
                throw CollectionEngineError.message(
                    driver.movementFailureMessage ?? "无法安全保留 ShelterBar 入口，已展开菜单栏。"
                )
            }
        }
        try Task.checkCancellation()

        let liveItems = Dictionary(model.scan().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let failures = participantItems.filter { entry in
            let (id, transactionItem) = entry
            let desired: MenuBarPlacement = desiredCollectedIDs.contains(id) ? .collected : .resident
            if let liveItem = liveItems[id] {
                let observed = driver.observedPlacement(of: liveItem)
                if observed != desired {
                    menuBarMoveLog.error("layout verification failed: \(id, privacy: .public) wanted=\(String(describing: desired), privacy: .public) observed=\(String(describing: observed), privacy: .public)")
                }
                return observed != desired
            }
            if desired == .resident, transactionItem.isTransientCaptureIndicator {
                menuBarMoveLog.info("layout verification: capture indicator ended normally")
                return false
            }
            // MenuBarAgent legitimately removes a hidden app from AX. Only an
            // authoritative host record may verify that missing collected
            // target; a missing resident or a legacy stale frame still fails.
            guard desired == .collected else {
                menuBarMoveLog.error("layout verification failed: missing resident \(id, privacy: .public)")
                return true
            }
            let remembered = model.item(withID: id) ?? transactionItem
            let confirmed = driver.confirmsMissingCollectedItem(remembered)
            if !confirmed {
                menuBarMoveLog.error("layout verification failed: unconfirmed missing collected item \(id, privacy: .public)")
            }
            return !confirmed
        }
        guard failures.isEmpty else {
            throw CollectionEngineError.message("系统没有完成布局调整，已恢复显示全部图标。")
        }
    }

    /// Re-applies an already verified layout after a rejected single move.
    private func restoreLayout(collected desiredCollectedIDs: Set<String>) async throws {
        if desiredCollectedIDs.isEmpty {
            driver.revealImmediately()
        } else {
            await driver.collapseHiddenSection()
        }
        try Task.checkCancellation()
        let restored = model.scan().allSatisfy { item in
            let desired: MenuBarPlacement = desiredCollectedIDs.contains(item.id) ? .collected : .resident
            return driver.observedPlacement(of: item) == desired
        }
        guard restored else {
            throw CollectionEngineError.message("macOS 未接受这个图标的位置调整，已展开菜单栏。")
        }
    }

    private func transitionRegion(for item: ShelfItem? = nil, dropPoint: CGPoint? = nil) -> CGRect? {
        if let dropPoint,
           let region = MenuBarGeometry.menuBarRegions.first(where: { $0.contains(dropPoint) }) {
            return region
        }
        if let frame = item?.menuBarReference.currentFrame(),
           let region = MenuBarGeometry.menuBarRegion(containing: frame) {
            return region
        }
        return driver.transitionRegion
    }

    private func withTransition<Value>(
        over region: CGRect?,
        _ operation: @MainActor () async throws -> Value
    ) async rethrows -> Value {
        guard let transitionShield else { return try await operation() }
        return try await transitionShield.perform(over: region, operation)
    }

    private func updatePermissions() {
        model.hasAccessibilityPermission = accessibilityGranted()
        model.hasScreenCapturePermission = screenCaptureGranted()
        if model.hasScreenCapturePermission { model.screenCapturePermissionHint = nil }
    }

    private func degrade(_ error: Error) async -> MenuBarCollectionOutcome {
        let persisted = model.allItems.filter { model.collectedIDs.contains($0.id) }
        await driver.recoverVisibleLayout(collectedItems: persisted)
        if error is CancellationError || Task.isCancelled {
            phase = .idle
            model.refresh()
            return .ignored
        }
        let message = (error as? CollectionEngineError)?.text ?? "操作未完成，图标已恢复显示。"
        phase = .degraded(message)
        model.message = message
        model.refresh()
        return MenuBarCollectionOutcome(message: message)
    }
}

private enum CollectionEngineError: Error {
    case message(String)
    case preferredMoveRejected(String)
    var text: String {
        switch self {
        case let .message(text), let .preferredMoveRejected(text): text
        }
    }
}
