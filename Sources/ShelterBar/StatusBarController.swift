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
    private let engine: MenuBarCollectionEngine
    private let monitor = MenuBarDragMonitor()
    private var presentation = ShelfPresentation()
    private var subscriptions = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var iconRefreshTask: Task<Void, Never>?
    private var screenChangeTask: Task<Void, Never>?
    private var screenChangeGeneration = 0
    private var shownAt = Date.distantPast
    private var shelfDragInProgress = false
    private let dragGhost = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

    init(source: any ShelfItemSource) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separator = NSStatusBar.system.statusItem(withLength: 1)
        let createdModel = ShelfViewModel(source: source)
        let createdMover = MenuBarItemMover(separator: separator)
        let createdCapture = MenuBarIconCapture()
        model = createdModel
        engine = MenuBarCollectionEngine(
            model: createdModel,
            driver: createdMover,
            capture: { await createdCapture.capture($0) },
            transitionShield: MenuBarTransitionShield()
        )
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
        model.onScreenCapturePermissionRequest = { [weak self] in
            guard let self else { return }
            model.screenCapturePermissionHint = ScreenCapturePermission.request().guidance
            refresh(.userRefresh)
        }
        model.onRefresh = { [weak self] in self?.refresh(.userRefresh) }
        monitor.onOutcome = { [weak self] outcome in
            guard let self else { return }
            dragGhost.orderOut(nil)
            model.isDropTargeted = false
            switch outcome {
            case let .collect(id): setPlacement(id, to: .collected)
            case let .click(id):
                activate(id)
            case .cancel: break
            }
        }
        monitor.onDrag = { [weak self] id, point in self?.showDragGhost(id: id, at: point) }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleScreenChange()
                }
            }.store(in: &subscriptions)
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                if operation == nil && !model.isBusy && !monitor.gesture.isTracking && !shelfDragInProgress {
                    refresh(.poll)
                }
            }
        }
    }

    func shutdown() {
        operation?.cancel()
        iconRefreshTask?.cancel()
        screenChangeTask?.cancel()
        pollTask?.cancel()
        monitor.stop()
        engine.cancelAndReveal()
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
            onActivate: { [weak self] in self?.activate($0.id) },
            onReturn: { [weak self] in self?.setPlacement($0, to: .resident, dropPoint: $1) },
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
        model.refresh()
        positionPanel()
        shownAt = Date()
        panel.makeKeyAndOrderFront(nil)
        refresh(.shelfOpened)
    }

    private func hideShelf() {
        iconRefreshTask?.cancel()
        panel.orderOut(nil)
        updateMonitor()
    }

    func requestAccessibilityPermissionIfNeeded() {
        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
            showShelf()
        } else { refresh(.launch) }
    }

    private func refresh(_ reason: MenuBarReconcileReason) {
        guard operation == nil, screenChangeTask == nil, !model.isBusy else { return }
        model.hasAccessibilityPermission = AccessibilityPermission.isGranted
        model.hasScreenCapturePermission = ScreenCapturePermission.isGranted
        if model.hasScreenCapturePermission { model.screenCapturePermissionHint = nil }
        if !model.hasAccessibilityPermission {
            iconRefreshTask?.cancel()
            monitor.stop()
        }
        let monitorStarted = !model.hasAccessibilityPermission || monitor.start()
        run(.reconcile(reason), clearMessage: reason != .poll)
        if !monitorStarted {
            model.message = "拖动监听未启动，请在辅助功能中重新开启 ShelterBar。"
        }
    }

    private func refreshMenuBarIcons() {
        guard panel.isVisible, !model.isBusy, iconRefreshTask == nil,
              model.hasAccessibilityPermission, model.hasScreenCapturePermission else { return }
        iconRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { iconRefreshTask = nil }
            _ = await engine.perform(.refreshPresentation)
            guard !Task.isCancelled, !model.isBusy else { return }
            if panel.isVisible { positionPanel() }
        }
    }

    private func positionPanel() {
        guard let cgAnchor = MenuBarGeometry.statusFrame(statusItem, help: MenuBarItemMover.handleHelp) else { return }
        let anchor = MenuBarGeometry.appKit(cgAnchor)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else { return }
        let ready = model.hasAccessibilityPermission
        let iconsWidth = model.items.reduce(CGFloat.zero) { $0 + MenuBarIconPresentation.shelfWidth(for: $1.icon) + 5 }
        let desired: CGFloat = ready ? max(440, iconsWidth + 230) : 680
        let width = min(760, min(desired, screen.frame.width - 24))
        let x = min(max(screen.frame.minX + 12, anchor.maxX - width), screen.frame.maxX - width - 12)
        panel.setFrame(
            CGRect(x: x,
                   y: anchor.minY - ShelfLayoutMetrics.panelHeight - ShelfLayoutMetrics.menuBarGap,
                   width: width,
                   height: ShelfLayoutMetrics.panelHeight),
            display: true
        )
        updateMonitor()
    }

    private func updateMonitor() {
        monitor.update(
            isEnabled: panel.isVisible && model.hasAccessibilityPermission && !model.isBusy
                && operation == nil && screenChangeTask == nil && !shelfDragInProgress,
            items: model.residentItems.filter(\.isMovable),
            shelfFrame: MenuBarGeometry.quartz(panel.frame)
        )
    }

    private func showDragGhost(id: String, at point: CGPoint) {
        guard let item = model.item(withID: id) else { return }
        let glyph = MenuBarIconPresentation.renderedImage(for: item.icon)
        let image = NSImageView(frame: CGRect(origin: .zero, size: glyph.size))
        image.image = glyph
        image.imageScaling = .scaleProportionallyDown
        dragGhost.contentView = image
        dragGhost.setFrame(CGRect(x: point.x + 10, y: MenuBarGeometry.desktopTop - point.y - glyph.size.height - 8,
                                 width: glyph.size.width, height: glyph.size.height), display: true)
        dragGhost.orderFrontRegardless()
        model.isDropTargeted = MenuBarGeometry.quartz(panel.frame).contains(point)
    }

    private func setPlacement(_ id: String, to placement: MenuBarPlacement, dropPoint: CGPoint? = nil) {
        run(.setPlacement(id: id, placement: placement, dropPoint: dropPoint))
    }

    private func activate(_ id: String) {
        run(.activate(id: id))
    }

    private func revealAll() {
        run(.revealAll)
    }

    private func run(_ command: MenuBarCollectionCommand, clearMessage: Bool = true) {
        guard operation == nil, screenChangeTask == nil, !model.isBusy else { return }
        let pendingIconRefresh = iconRefreshTask
        pendingIconRefresh?.cancel()
        if clearMessage { model.message = nil }
        operation = Task { @MainActor [weak self] in
            guard let self else { return }
            await pendingIconRefresh?.value
            guard !Task.isCancelled else {
                operation = nil
                updateMonitor()
                return
            }
            let outcome = await engine.perform(command)
            operation = nil
            guard !Task.isCancelled else {
                updateMonitor()
                return
            }
            if let message = outcome.message { model.message = message }
            if outcome.shouldDismissShelf {
                presentation.handle(.itemActivated)
                if !presentation.isVisible { hideShelf() }
            }
            model.refresh()
            if panel.isVisible { positionPanel() }
            updateMonitor()
            refreshMenuBarIcons()
        }
        updateMonitor()
    }

    private func scheduleScreenChange() {
        screenChangeGeneration += 1
        let generation = screenChangeGeneration
        screenChangeTask?.cancel()
        screenChangeTask = Task { @MainActor [weak self] in
            await self?.handleScreenChange(generation: generation)
        }
        updateMonitor()
    }

    private func handleScreenChange(generation: Int) async {
        let currentOperation = operation
        let currentIconRefresh = iconRefreshTask
        currentOperation?.cancel()
        currentIconRefresh?.cancel()
        await currentOperation?.value
        await currentIconRefresh?.value
        guard !Task.isCancelled, generation == screenChangeGeneration else { return }
        operation = nil
        engine.cancelAndReveal()
        screenChangeTask = nil
        refresh(.screenChanged)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !model.isBusy, !shelfDragInProgress, !monitor.gesture.isTracking,
              Date().timeIntervalSince(shownAt) > 0.4 else { return }
        presentation.handle(.outsideInteraction)
        if !presentation.isVisible { hideShelf() }
    }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
