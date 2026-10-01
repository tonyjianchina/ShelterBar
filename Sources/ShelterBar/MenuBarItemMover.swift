import AppKit
import ShelterBarCore

@MainActor
final class MenuBarItemMover {
    static let handleHelp = "ShelterBar · 打开收纳栏"
    static let boundaryHelp = "ShelterBar · 收纳边界"
    static let revealedBoundaryLength: CGFloat = 3
    private let boundary: NSStatusItem
    private let handle: NSStatusItem
    private(set) var isCollapsed = false
    private(set) var movementFailureMessage: String?

    init(boundary: NSStatusItem, handle: NSStatusItem) {
        self.boundary = boundary
        self.handle = handle
    }

    var boundaryFrame: CGRect? {
        MenuBarGeometry.statusFrame(boundary, help: Self.boundaryHelp)
    }

    private var handleFrame: CGRect? {
        MenuBarGeometry.statusFrame(handle, help: Self.handleHelp)
    }

    func revealHiddenSection() async {
        boundary.length = Self.revealedBoundaryLength
        isCollapsed = false
        try? await Task.sleep(for: .milliseconds(220))
    }

    func collapseHiddenSection() async {
        // Never widen the clickable entry: macOS 26 can omit an oversized
        // status window from the composited menu bar, including its tail.
        guard await ensureHandleOnResidentSide() else {
            movementFailureMessage = "ShelterBar 入口的位置不安全，已展开菜单栏。请按住 Command 将收纳箱向右拖动后重试。"
            revealImmediately()
            return
        }
        let width = NSScreen.screens.map(\.frame.width).max() ?? 1440
        boundary.length = max(500, min(width * 2, 10_000))
        isCollapsed = true
        try? await Task.sleep(for: .milliseconds(250))
        if !hasSafeHandle {
            movementFailureMessage = "ShelterBar 入口被遮挡，已展开菜单栏。"
            revealImmediately()
        }
    }

    func revealImmediately() {
        boundary.length = Self.revealedBoundaryLength
        isCollapsed = false
    }

    private var hasSafeHandle: Bool {
        guard handle.length == NSStatusItem.squareLength,
              let handleFrame, let boundaryFrame else { return false }
        return MenuBarGeometry.isFullyVisible(handleFrame)
            && MenuBarGeometry.isOnResidentSide(handle: handleFrame, boundary: boundaryFrame)
    }

    private func ensureHandleOnResidentSide() async -> Bool {
        if hasSafeHandle { return true }
        guard let native = await MenuBarNativeWindow.resolvePair(
            sourceFrame: { self.handleFrame }, sourcePID: getpid(),
            destinationFrame: { self.boundaryFrame }, destinationPID: getpid()
        ) else { return false }
        // An inverse notch-safe move can put the boundary after our entry.
        // Move the fixed entry to its right, then verify before hiding.
        let moved = await VerifiedMenuBarMove.perform(
            to: .resident, readItem: { self.handleFrame }, readDivider: { self.boundaryFrame },
            menuBarRegion: MenuBarGeometry.menuBarRegion(containing:),
            readInsertionFrame: { native.destination.frame }, readSourceFrame: { native.source.frame },
            pickupPoint: { frame in
                MenuBarGeometry.visibleFrame(frame).map { CGPoint(x: $0.midX, y: frame.midY) }
            },
            isDestinationFrameAllowed: MenuBarGeometry.isFullyVisible,
            send: { frame, end in
                guard let destination = self.boundaryFrame else { return false }
                return await self.commandDrag(from: frame, clientPID: getpid(), to: end,
                    placement: .resident, destination: destination, destinationPID: getpid())
            }
        )
        return moved && hasSafeHandle
    }

    func isOnCollectedSide(_ item: ShelfItem) -> Bool {
        guard let boundaryFrame, let frame = item.menuBarReference.currentFrame(),
              MenuBarGeometry.isOnMenuBar(frame),
              let region = MenuBarGeometry.menuBarRegion(containing: boundaryFrame),
              MenuBarGeometry.menuBarRegion(containing: frame) == region,
              abs(frame.midY - boundaryFrame.midY) < 8 else { return false }
        return frame.maxX <= boundaryFrame.minX + 1
    }

    /// Only returns true after observing the real item on the requested side.
    func move(_ item: ShelfItem, to placement: MenuBarPlacement, dropPoint: CGPoint? = nil) async -> Bool {
        movementFailureMessage = nil
        guard AccessibilityPermission.isGranted, item.isMovable,
              let frame = item.menuBarReference.currentFrame(), MenuBarGeometry.isOnMenuBar(frame) else { return false }
        guard let native = await MenuBarNativeWindow.resolvePair(
            sourceFrame: item.menuBarReference.currentFrame, sourcePID: item.menuBarReference.pid,
            destinationFrame: { self.boundaryFrame }, destinationPID: getpid()
        ) else { return false }
        var destinationWasObstructed = false
        let moved = await VerifiedMenuBarMove.perform(
            to: placement, readItem: item.menuBarReference.currentFrame,
            readDivider: { self.boundaryFrame },
            menuBarRegion: MenuBarGeometry.menuBarRegion(containing:),
            readInsertionFrame: { native.destination.frame },
            readSourceFrame: { native.source.frame },
            pickupPoint: { frame in
                MenuBarGeometry.visibleFrame(frame).map { CGPoint(x: $0.midX, y: frame.midY) }
            },
            isDestinationFrameAllowed: { frame in
                let allowed = MenuBarGeometry.isFullyVisible(frame)
                if !allowed { destinationWasObstructed = true }
                return allowed
            },
            requestedDropPoint: dropPoint,
            send: { frame, end in
                guard let region = MenuBarGeometry.menuBarRegion(containing: frame),
                      let destination = self.boundaryFrame,
                      region.contains(end) else { return false }
                return await self.commandDrag(from: frame, clientPID: item.menuBarReference.pid,
                    to: end, placement: placement, destination: destination, destinationPID: getpid())
            }
        )
        if destinationWasObstructed {
            // A leftmost boundary may sit next to the notch. Inserting another
            // full window on its left is impossible, but the equivalent order
            // can be reached by moving our own boundary to the item's right.
            // The engine subsequently restores intervening residents before
            // collapse, so none are silently adopted into the collected set.
            if placement == .collected, await moveBoundary(after: item) { return true }
            movementFailureMessage = "ShelterBar 左侧空间被刘海遮挡。请按住 Command 将收纳箱向右拖动，或先退出一个菜单栏应用，然后重试。"
        }
        return moved
    }

    private func moveBoundary(after item: ShelfItem) async -> Bool {
        guard !Task.isCancelled, let target = item.menuBarReference.currentFrame(),
              MenuBarGeometry.isOnMenuBar(target) else { return false }
        guard let native = await MenuBarNativeWindow.resolvePair(
            sourceFrame: { self.boundaryFrame }, sourcePID: getpid(),
            destinationFrame: item.menuBarReference.currentFrame, destinationPID: item.menuBarReference.pid
        ) else { return false }
        let moved = await VerifiedMenuBarMove.perform(
            to: .resident, readItem: { self.boundaryFrame },
            readDivider: item.menuBarReference.currentFrame,
            menuBarRegion: MenuBarGeometry.menuBarRegion(containing:),
            readInsertionFrame: { native.destination.frame },
            readSourceFrame: { native.source.frame },
            isDestinationFrameAllowed: MenuBarGeometry.isFullyVisible,
            send: { frame, end in
                guard let destination = item.menuBarReference.currentFrame() else { return false }
                return await self.commandDrag(from: frame, clientPID: getpid(), to: end,
                    placement: .resident, destination: destination, destinationPID: item.menuBarReference.pid)
            }
        )
        return moved && isOnCollectedSide(item)
    }

    private func commandDrag(from frame: CGRect, clientPID: pid_t, to end: CGPoint,
                             placement: MenuBarPlacement, destination: CGRect,
                             destinationPID: pid_t) async -> Bool {
        guard !Task.isCancelled, let source = CGEventSource(stateID: .hidSystemState),
              let exposed = MenuBarGeometry.visibleFrame(frame) else { return false }
        let start = CGPoint(x: exposed.midX, y: frame.midY)
        let windows = MenuBarNativeWindow.currentWindows()
        guard let nativeSource = MenuBarNativeWindow.match(axFrame: frame,
                  clientPID: clientPID, windows: windows),
              let nativeDestination = MenuBarNativeWindow.match(axFrame: destination,
                  clientPID: destinationPID, windows: windows) else { return false }
        guard let region = MenuBarGeometry.menuBarRegion(containing: frame),
              MenuBarGeometry.menuBarRegion(containing: nativeSource.frame) == region,
              MenuBarGeometry.menuBarRegion(containing: nativeDestination.frame) == region,
              region.contains(end) else { return false }
        // A display/layout switch between planning and this snapshot must not
        // turn a safe insertion into an overlapping or cross-screen release.
        if placement == .collected {
            guard end.x + (nativeSource.frame.maxX - start.x) < nativeDestination.frame.minX else {
                return false
            }
        } else {
            guard end.x - (start.x - nativeSource.frame.minX) > nativeDestination.frame.maxX else {
                return false
            }
        }
        let events = MenuBarDragEvents(source: source, sourceWindow: nativeSource.id,
                                       destinationWindow: nativeDestination.id, ownerPID: nativeSource.pid)
        func event(_ type: CGEventType, _ point: CGPoint) -> CGEvent? {
            events.make(type, at: point)
        }
        // Allocate the release before pressing. Every exit after down releases,
        // including cancellation, so a failure cannot leave the mouse held.
        guard let down = event(.leftMouseDown, start), let up = event(.leftMouseUp, end) else { return false }
        down.post(tap: .cghidEventTap)
        defer { up.post(tap: .cghidEventTap) }
        try? await Task.sleep(for: .milliseconds(70))
        for step in 1...8 {
            guard !Task.isCancelled else { return false }
            let t = CGFloat(step) / 8
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y)
            guard let drag = event(.leftMouseDragged, point) else { return false }
            drag.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(22))
        }
        return true
    }
}

extension MenuBarItemMover: MenuBarLayoutDriving {
    var transitionRegion: CGRect? {
        boundaryFrame.flatMap(MenuBarGeometry.menuBarRegion(containing:))
    }

    func observedPlacement(of item: ShelfItem) -> MenuBarPlacement? {
        if isOnCollectedSide(item) { return .collected }
        guard let frame = item.menuBarReference.currentFrame() else { return nil }
        if MenuBarGeometry.isOnMenuBar(frame) { return .resident }
        // Real collapsed items move horizontally offscreen, retaining their
        // menu-bar row. A helper's stale bottom-of-screen AX rectangle is not
        // proof that ShelterBar collected it.
        return isCollapsed && MenuBarGeometry.isInMenuBarRow(frame, regions: MenuBarGeometry.menuBarRegions)
            ? .collected : nil
    }
}
