import AppKit
import ShelterBarCore

@MainActor
protocol MenuBarLayoutDriving: AnyObject {
    var isCollapsed: Bool { get }
    var transitionRegion: CGRect? { get }
    var movementFailureMessage: String? { get }
    func observedPlacement(of item: ShelfItem) -> MenuBarPlacement?
    func revealHiddenSection() async
    func collapseHiddenSection() async
    func revealImmediately()
    func move(_ item: ShelfItem, to placement: MenuBarPlacement, dropPoint: CGPoint?) async -> Bool
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
    private let press: @MainActor (ShelfItem) -> Bool
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
        press: @escaping @MainActor (ShelfItem) -> Bool = { $0.menuBarReference.press() },
        transitionShield: MenuBarTransitionShield? = nil
    ) {
        self.model = model
        self.driver = driver
        self.capture = capture
        self.accessibilityGranted = accessibilityGranted
        self.screenCaptureGranted = screenCaptureGranted
        self.press = press
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
        let items = model.allItems
        if !didSeedInventory {
            knownItemIDs = Set(items.map(\.id))
            didSeedInventory = true
        }
        let observed = items.map {
            ObservedMenuBarItem(
                id: $0.id,
                placement: driver.observedPlacement(of: $0),
                isMovable: $0.isMovable
            )
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
            if needsPhysicalChange {
                try await applyLayout(collected: plan.desiredCollectedIDs)
            }
            for id in previouslyCollectedIDs.subtracting(plan.desiredCollectedIDs) {
                model.setCollected(false, id: id)
            }
            for id in plan.adoptedCollectedIDs { model.setCollected(true, id: id) }
            knownItemIDs.formUnion(items.map(\.id))
            model.refresh()
            phase = .idle

            let adoptedCount = plan.adoptedCollectedIDs.count
            return MenuBarCollectionOutcome(
                message: adoptedCount == 0 ? nil : "已自动收纳 \(adoptedCount) 个新增图标。",
                didChangeLayout: needsPhysicalChange || adoptedCount > 0
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
        do {
            try await applyLayout(collected: desired, preferredMove: (id, placement, dropPoint))
            model.setCollected(placement == .collected, id: id)
            knownItemIDs.insert(id)
            model.refresh()
            phase = .idle
            return MenuBarCollectionOutcome(didChangeLayout: true)
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
        if driver.observedPlacement(of: item) == .resident {
            guard press(item) else {
                return MenuBarCollectionOutcome(message: "这个项目未响应点击，请在顶部打开。")
            }
            return MenuBarCollectionOutcome(shouldDismissShelf: true)
        }

        phase = .applying
        do {
            try await withTransition(over: transitionRegion(for: item)) {
                await self.driver.revealHiddenSection()
                guard let live = self.model.scan().first(where: { $0.id == id }) else {
                    throw CollectionEngineError.message("这个项目未响应点击，已展开顶部图标。")
                }
                if live.isMovable,
                   !(await self.driver.move(live, to: .resident, dropPoint: nil)) {
                    throw CollectionEngineError.message(
                        self.driver.movementFailureMessage ?? "这个项目未响应点击，已展开顶部图标。"
                    )
                }
                guard self.press(live) else {
                    throw CollectionEngineError.message("这个项目未响应点击，已展开顶部图标。")
                }
            }
            suspendAutomaticReconciliation = true
            model.refresh()
            phase = .idle
            return MenuBarCollectionOutcome(didChangeLayout: true, shouldDismissShelf: true)
        } catch {
            return await degrade(error)
        }
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
        collected desiredCollectedIDs: Set<String>,
        preferredMove: (id: String, placement: MenuBarPlacement, dropPoint: CGPoint?)?
    ) async throws {
        phase = .applying
        await driver.revealHiddenSection()
        try Task.checkCancellation()

        if let preferredMove {
            guard let item = model.scan().first(where: { $0.id == preferredMove.id }),
                  await driver.move(item, to: preferredMove.placement, dropPoint: preferredMove.dropPoint) else {
                throw CollectionEngineError.message(
                    driver.movementFailureMessage ?? "macOS 未接受这个图标的位置调整，已展开菜单栏。"
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
        for item in scan where item.isMovable && desiredCollectedIDs.contains(item.id)
            && driver.observedPlacement(of: item) != .collected {
            guard await driver.move(item, to: .collected, dropPoint: nil) else {
                throw CollectionEngineError.message(
                    driver.movementFailureMessage ?? "部分收纳图标未能移动，已展开菜单栏。"
                )
            }
            try Task.checkCancellation()
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
        }
        try Task.checkCancellation()

        let verified = model.scan().allSatisfy { item in
            let desired: MenuBarPlacement = desiredCollectedIDs.contains(item.id) ? .collected : .resident
            return driver.observedPlacement(of: item) == desired
        }
        guard verified else {
            throw CollectionEngineError.message("系统没有完成布局调整，已恢复显示全部图标。")
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
        if error is CancellationError || Task.isCancelled {
            driver.revealImmediately()
            phase = .idle
            model.refresh()
            return .ignored
        }
        await driver.revealHiddenSection()
        let message = (error as? CollectionEngineError)?.text ?? "操作未完成，图标已恢复显示。"
        phase = .degraded(message)
        model.message = message
        model.refresh()
        return MenuBarCollectionOutcome(message: message)
    }
}

private enum CollectionEngineError: Error {
    case message(String)
    var text: String { switch self { case let .message(text): text } }
}
