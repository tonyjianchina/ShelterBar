import AppKit
import Combine
import ShelterBarCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let separator: NSStatusItem
    private let panel: ShelfPanel
    private let model: ShelfViewModel
    private let mover: MenuBarItemMover
    private let monitor = MenuBarDragMonitor()
    private var presentation = ShelfPresentation()
    private var subscriptions = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var didRestore = false
    private var restoreOnNextOpen = false
    private var knownIDsAtCollapse = Set<String>()
    private var shownAt = Date.distantPast
    private var shelfDragInProgress = false
    private let dragGhost = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

    init(source: any ShelfItemSource) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separator = NSStatusBar.system.statusItem(withLength: 1)
        model = ShelfViewModel(source: source)
        mover = MenuBarItemMover(separator: separator)
        panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        statusItem.autosaveName = "ShelterBar.Handle"
        separator.autosaveName = "ShelterBar.Divider"
        separator.button?.toolTip = MenuBarItemMover.separatorHelp
        separator.button?.setAccessibilityIdentifier("shelterbar.divider")
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "archivebox.fill", accessibilityDescription: "打开收纳栏")
            button.image?.isTemplate = true
            button.toolTip = MenuBarItemMover.handleHelp
            button.setAccessibilityIdentifier("shelterbar.handle")
            button.target = self
            button.action = #selector(toggleShelf)
            button.sendAction(on: .leftMouseUp)
        }
        configurePanel()
        presentation.handle(.setPinned(model.isPinned))
        model.onPermissionRequest = { [weak self] in self?.requestAccessibilityPermissionIfNeeded() }
        model.onRefresh = { [weak self] in
            self?.didRestore = false
            self?.refresh()
        }
        monitor.onOutcome = { [weak self] outcome in
            guard let self else { return }
            dragGhost.orderOut(nil)
            model.isDropTargeted = false
            switch outcome {
            case let .collect(id): transfer(id, to: .collected)
            case let .click(id):
                if let item = model.item(withID: id) { activate(item) }
            case .cancel: break
            }
        }
        monitor.onDrag = { [weak self] id, point in self?.showDragGhost(id: id, at: point) }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.operation?.cancel()
                    self.mover.revealImmediately()
                    self.didRestore = false
                    self.refresh()
                }
            }.store(in: &subscriptions)
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                if !model.isBusy && !monitor.gesture.isTracking && !shelfDragInProgress { refresh() }
            }
        }
    }

    func shutdown() {
        operation?.cancel()
        pollTask?.cancel()
        monitor.stop()
        mover.revealImmediately()
    }

    private func configurePanel() {
        panel.title = "ShelterBar 收纳栏"
        panel.delegate = self
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: ShelfView(
            model: model,
            onActivate: { [weak self] in self?.activate($0) },
            onReturn: { [weak self] in self?.transfer($0, to: .resident, dropPoint: $1) },
            onDragging: { [weak self] in
                self?.shelfDragInProgress = $0
                self?.model.isDraggingToMenuBar = $0
                self?.updateMonitor()
            },
            onPinChange: { [weak self] value in
                self?.model.setPinned(value)
                self?.presentation.handle(.setPinned(value))
            },
            onRevealAll: { [weak self] in self?.revealAll() },
            onQuit: { NSApp.terminate(nil) }
        ))
        dragGhost.isOpaque = false
        dragGhost.backgroundColor = .clear
        dragGhost.ignoresMouseEvents = true
        dragGhost.level = .screenSaver
        dragGhost.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    @objc private func toggleShelf() {
        guard !model.isBusy else { return }
        presentation.handle(.toggle)
        if presentation.isVisible { showShelf() } else { hideShelf() }
    }

    func showShelf() {
        if !presentation.isVisible { presentation.handle(.toggle) }
        if restoreOnNextOpen {
            restoreOnNextOpen = false
            didRestore = false
        }
        model.refresh()
        positionPanel()
        shownAt = Date()
        panel.makeKeyAndOrderFront(nil)
        refresh()
    }

    private func hideShelf() {
        panel.orderOut(nil)
        updateMonitor()
    }

    func requestAccessibilityPermissionIfNeeded() {
        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
            showShelf()
        } else { refresh() }
    }

    private func refresh() {
        guard !model.isBusy else { return }
        let granted = AccessibilityPermission.isGranted
        model.hasAccessibilityPermission = granted
        guard granted else {
            mover.revealImmediately()
            didRestore = false
            monitor.stop()
            model.refresh()
            if panel.isVisible { positionPanel() }
            return
        }
        if !monitor.start() { model.message = "拖动监听未启动，请在辅助功能中重新开启 ShelterBar。" }
        model.refresh()
        if mover.isCollapsed,
           model.allItems.contains(where: {
               !knownIDsAtCollapse.contains($0.id) && !model.collectedIDs.contains($0.id)
                   && !MenuBarGeometry.isOnMenuBar($0.menuBarReference.frame)
           }) {
            mover.revealImmediately()
            model.message = "检测到新的顶部图标，已展开菜单栏。点击刷新可恢复收纳。"
            model.refresh()
        }
        if !didRestore {
            didRestore = true
            restoreSavedLayout()
        }
        if panel.isVisible { positionPanel() }
        updateMonitor()
    }

    private func positionPanel() {
        guard let cgAnchor = MenuBarGeometry.statusFrame(statusItem, help: MenuBarItemMover.handleHelp) else { return }
        let anchor = MenuBarGeometry.appKit(cgAnchor)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return }
        let desired: CGFloat = model.hasAccessibilityPermission ? max(440, CGFloat(model.items.count * 47 + 230)) : 650
        let width = min(760, min(desired, screen.frame.width - 24))
        let x = min(max(screen.frame.minX + 12, anchor.maxX - width), screen.frame.maxX - width - 12)
        panel.setFrame(CGRect(x: x, y: anchor.minY - 79, width: width, height: 74), display: true)
        updateMonitor()
    }

    private func updateMonitor() {
        monitor.update(
            isEnabled: panel.isVisible && !model.isBusy && !shelfDragInProgress,
            items: model.residentItems.filter(\.isMovable),
            shelfFrame: MenuBarGeometry.quartz(panel.frame)
        )
    }

    private func showDragGhost(id: String, at point: CGPoint) {
        guard let item = model.item(withID: id) else { return }
        let image = NSImageView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        image.image = item.icon
        image.imageScaling = .scaleProportionallyDown
        dragGhost.contentView = image
        dragGhost.setFrame(CGRect(x: point.x + 10, y: MenuBarGeometry.desktopTop - point.y - 38, width: 30, height: 30), display: true)
        dragGhost.orderFrontRegardless()
        model.isDropTargeted = MenuBarGeometry.quartz(panel.frame).contains(point)
    }

    private func transfer(_ id: String, to placement: MenuBarPlacement, dropPoint: CGPoint? = nil) {
        guard !model.isBusy, model.hasAccessibilityPermission else { return }
        runOperation { [self] in
            await mover.revealHiddenSection()
            try Task.checkCancellation()
            guard let item = model.scan().first(where: { $0.id == id }) else {
                throw TransferError.message("这个图标已退出或暂时不可用，已展开菜单栏。")
            }
            model.remember(item)
            guard await mover.move(item, to: placement, dropPoint: dropPoint) else {
                throw TransferError.message("macOS 未接受“\(item.title)”的位置调整，已保留顶部图标。")
            }
            var desired = model.collectedIDs
            if placement == .collected { desired.insert(id) } else { desired.remove(id) }
            try await settleLayout(collected: desired)
            model.setCollected(placement == .collected, id: id)
        }
    }

    private func restoreSavedLayout() {
        guard !model.collectedIDs.isEmpty else { return }
        runOperation { [self] in
            await mover.revealHiddenSection()
            try Task.checkCancellation()
            let ids = model.scan().filter { model.collectedIDs.contains($0.id) }.map(\.id)
            for id in ids {
                guard !Task.isCancelled, let item = model.scan().first(where: { $0.id == id }),
                      await mover.move(item, to: .collected) else {
                    throw TransferError.message("部分收纳图标未能恢复，已展开菜单栏，可重新拖动。")
                }
            }
            try await settleLayout(collected: model.collectedIDs)
        }
    }

    /// Every resident must be on the visible side before the spacer expands.
    /// Failed repair leaves everything revealed and never claims success.
    private func settleLayout(collected: Set<String>) async throws {
        let scan = model.scan()
        for candidate in scan where candidate.isMovable && !collected.contains(candidate.id) && mover.isOnCollectedSide(candidate) {
            guard !Task.isCancelled,
                  let live = model.scan().first(where: { $0.id == candidate.id }),
                  await mover.move(live, to: .resident) else {
                throw TransferError.message("无法安全整理当前菜单栏，已展开全部图标。")
            }
        }
        let before = model.scan()
        let hidden = before.filter { collected.contains($0.id) }
        guard !hidden.isEmpty else { return }
        guard hidden.allSatisfy({ mover.isOnCollectedSide($0) }) else {
            throw TransferError.message("位置确认失败，已展开菜单栏；请重试。")
        }
        let visible = before.filter { !collected.contains($0.id) && MenuBarGeometry.isOnMenuBar($0.menuBarReference.frame) }
        try Task.checkCancellation()
        knownIDsAtCollapse = Set(before.map(\.id))
        await mover.collapseHiddenSection()
        guard !Task.isCancelled,
              hidden.allSatisfy({ item in
                  guard let rect = item.menuBarReference.currentFrame() else { return false }
                  return !MenuBarGeometry.isOnMenuBar(rect)
              }),
              visible.allSatisfy({ item in
                  guard let rect = item.menuBarReference.currentFrame() else { return false }
                  return MenuBarGeometry.isOnMenuBar(rect)
              }) else {
            throw TransferError.message("系统没有完成隐藏，已恢复显示全部图标。")
        }
    }

    private func runOperation(_ body: @escaping @MainActor () async throws -> Void) {
        guard !model.isBusy else { return }
        model.isBusy = true
        model.message = nil
        updateMonitor()
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await body() }
            catch {
                await mover.revealHiddenSection()
                model.message = (error as? TransferError)?.text ?? "操作未完成，图标已恢复显示。"
            }
            model.isBusy = false
            operation = nil
            model.refresh()
            if panel.isVisible { positionPanel() }
            updateMonitor()
        }
    }

    private func revealAll() {
        guard !model.isBusy else { return }
        mover.revealImmediately()
        model.message = "已临时展开全部图标。点击刷新可恢复收纳。"
        model.refresh()
        updateMonitor()
    }

    private func activate(_ item: ShelfItem) {
        guard !model.isBusy else { return }
        if MenuBarGeometry.isOnMenuBar(item.menuBarReference.frame) {
            if !item.menuBarReference.press() { model.message = "这个项目未响应点击，请在顶部打开。" }
            presentation.handle(.itemActivated)
            if !presentation.isVisible { hideShelf() }
            return
        }
        // Reveal before AXPress, then keep icons reachable while the original
        // app's menu is open. Reconcile when the shelf is opened again.
        runOperation { [self] in
            await mover.revealHiddenSection()
            try Task.checkCancellation()
            guard let live = model.scan().first(where: { $0.id == item.id }),
                  await mover.move(live, to: .resident), live.menuBarReference.press() else {
                throw TransferError.message("这个项目未响应点击，已展开顶部图标。")
            }
            restoreOnNextOpen = true
            presentation.handle(.itemActivated)
            if !presentation.isVisible { hideShelf() }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !model.isBusy, !shelfDragInProgress, !monitor.gesture.isTracking,
              Date().timeIntervalSince(shownAt) > 0.4 else { return }
        presentation.handle(.outsideInteraction)
        if !presentation.isVisible { hideShelf() }
    }
}

private enum TransferError: Error {
    case message(String)
    var text: String { switch self { case let .message(text): text } }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
