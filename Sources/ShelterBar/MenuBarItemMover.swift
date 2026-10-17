import AppKit
import OSLog
import ShelterBarCore

let menuBarMoveLog = Logger(subsystem: "com.jensen.shelterbar", category: "move")

@MainActor
final class MenuBarItemMover {
    static let separatorHelp = "ShelterBar 收纳分隔线"
    static let handleHelp = "ShelterBar · 打开收纳栏"
    private let separator: NSStatusItem
    private(set) var isCollapsed = false
    private(set) var lastMoveFailure: String?
    /// Only user-initiated work may nudge the cursor to show an auto-hidden bar.
    var mayRevealAutoHiddenMenuBar = false

    init(separator: NSStatusItem) { self.separator = separator }

    var separatorFrame: CGRect? {
        MenuBarGeometry.statusFrame(separator, help: Self.separatorHelp)
    }

    func revealHiddenSection() async {
        separator.length = 1
        isCollapsed = false
        // Every revealed item is re-laid out by the system host (Control
        // Center on macOS 26); the more items are collected, the longer that
        // takes. Wait until the divider's AX frame and native window agree
        // and stop moving instead of trusting a fixed delay.
        try? await Task.sleep(for: .milliseconds(160))
        var previous: CGRect?
        for _ in 0..<22 {
            guard !Task.isCancelled else { return }
            let frame = separatorFrame
            if let frame, frame.width <= 40, frame == previous,
               nativeSeparator() != nil || MenuBarGeometry.hiddenMenuBarRegion(containing: frame) != nil { return }
            previous = frame
            try? await Task.sleep(for: .milliseconds(50))
        }
        menuBarMoveLog.notice("reveal did not settle; divider \(String(describing: self.separatorFrame), privacy: .public)")
    }

    func collapseHiddenSection() async {
        let width = NSScreen.screens.map(\.frame.width).max() ?? 1440
        separator.length = max(500, min(width * 2, 10_000))
        isCollapsed = true
        try? await Task.sleep(for: .milliseconds(250))
    }

    func revealImmediately() {
        separator.length = 1
        isCollapsed = false
    }

    func isOnCollectedSide(_ item: ShelfItem) -> Bool {
        guard let boundary = separatorFrame, let frame = item.menuBarReference.currentFrame(),
              // A revealed item that the notch hides is still left of the divider.
              let region = MenuBarGeometry.menuBarRow(containing: boundary),
              MenuBarGeometry.menuBarRow(containing: frame) == region,
              abs(frame.midY - boundary.midY) < 8 else { return false }
        return frame.maxX <= boundary.minX + 1
    }

    /// Only returns true after observing the real item on the requested side.
    func move(_ item: ShelfItem, to placement: MenuBarPlacement, dropPoint: CGPoint? = nil) async -> Bool {
        lastMoveFailure = nil
        func fail(_ reason: String) -> Bool {
            lastMoveFailure = reason
            menuBarMoveLog.error("move \(item.id, privacy: .public) -> \(String(describing: placement), privacy: .public) failed: \(reason, privacy: .public)")
            return false
        }
        guard AccessibilityPermission.isGranted, item.isMovable else { return fail("not permitted or not movable") }
        guard var frame = item.menuBarReference.currentFrame() else { return fail("item frame unavailable") }
        if !MenuBarGeometry.isOnMenuBar(frame), MenuBarGeometry.hiddenMenuBarRegion(containing: frame) != nil {
            // The bar slid away (full-screen space) while the user dragged
            // into the shelf. Bring it back the way a person would.
            guard await revealAutoHiddenMenuBar(for: item, near: frame),
                  let shown = item.menuBarReference.currentFrame() else {
                return fail("menu bar is auto-hidden at \(frame)")
            }
            frame = shown
        }
        guard MenuBarGeometry.isOnMenuBar(frame) else {
            return fail(MenuBarGeometry.isOnMenuBarRow(frame)
                ? "item \(frame) is hidden by the camera housing" : "item \(frame) is not on a visible menu bar")
        }
        var reason: String?
        let moved = await VerifiedMenuBarMove.perform(
            to: placement, readItem: item.menuBarReference.currentFrame,
            readDivider: { self.separatorFrame },
            menuBarRegion: MenuBarGeometry.menuBarRegion(containing:),
            readInsertionFrame: { self.nativeSeparator()?.frame },
            pickupPoint: { frame in
                MenuBarGeometry.visibleFrame(frame).map { CGPoint(x: $0.midX, y: frame.midY) }
            },
            requestedDropPoint: dropPoint,
            isDropAllowed: { !MenuBarGeometry.isUnderCameraHousing($0) },
            report: { reason = $0 },
            send: { frame, end in
                guard let region = MenuBarGeometry.menuBarRegion(containing: frame),
                      region.contains(end) else { return false }
                return await self.commandDrag(item, from: frame, to: end, placement: placement)
            }
        )
        if !moved { return fail(lastMoveFailure ?? reason ?? "unknown") }
        menuBarMoveLog.info("move \(item.id, privacy: .public) -> \(String(describing: placement), privacy: .public) confirmed")
        return true
    }

    private func revealAutoHiddenMenuBar(for item: ShelfItem, near frame: CGRect) async -> Bool {
        guard mayRevealAutoHiddenMenuBar,
              let region = MenuBarGeometry.hiddenMenuBarRegion(containing: frame) else { return false }
        let point = CGPoint(x: min(max(frame.midX, region.minX + 1), region.maxX - 1), y: region.minY + 1)
        let source = CGEventSource(stateID: .hidSystemState)
        menuBarMoveLog.notice("revealing auto-hidden menu bar at \(String(describing: point), privacy: .public)")
        for attempt in 0..<30 {
            guard !Task.isCancelled else { return false }
            if attempt % 6 == 0 { CGWarpMouseCursorPosition(point) }
            if let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                   mouseCursorPosition: point, mouseButton: .left) {
                moved.setIntegerValueField(.eventSourceUserData, value: MenuBarDragMonitor.syntheticEventTag)
                moved.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(50))
            if let shown = item.menuBarReference.currentFrame(), MenuBarGeometry.isOnMenuBar(shown),
               let divider = separatorFrame, MenuBarGeometry.menuBarRegion(containing: divider) != nil,
               nativeSeparator() != nil {
                // Let the slide-in animation finish before reading geometry.
                try? await Task.sleep(for: .milliseconds(120))
                return true
            }
        }
        return false
    }

    // MARK: Single-item temporary reveal (clicking a stowed icon)

    private var handleFrame: CGRect? { MenuBarAX.ownItemFrame(help: Self.handleHelp) }

    /// The collapsed divider is thousands of points wide, so it is matched
    /// without the normal status-size limit, including off-screen windows.
    private func dividerWindow(in windows: [MenuBarNativeWindow]) -> (ax: CGRect, window: MenuBarNativeWindow)? {
        guard let ax = MenuBarAX.ownItemFrame(help: Self.separatorHelp),
              let window = MenuBarNativeWindow.match(axFrame: ax, clientPID: getpid(), windows: windows,
                                                     maximumWidth: 20_000) else { return nil }
        return (ax, window)
    }

    func showMenuBarIfAutoHidden() async -> Bool {
        guard let handle = handleFrame else { return false }
        if MenuBarGeometry.menuBarRegion(containing: handle) != nil { return true }
        guard mayRevealAutoHiddenMenuBar,
              let region = MenuBarGeometry.hiddenMenuBarRegion(containing: handle) else { return false }
        let point = CGPoint(x: min(max(handle.midX, region.minX + 1), region.maxX - 1), y: region.minY + 1)
        let source = CGEventSource(stateID: .hidSystemState)
        menuBarMoveLog.notice("showing auto-hidden menu bar at \(String(describing: point), privacy: .public)")
        for attempt in 0..<30 {
            guard !Task.isCancelled else { return false }
            if attempt % 6 == 0 { CGWarpMouseCursorPosition(point) }
            if let moved = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                   mouseCursorPosition: point, mouseButton: .left) {
                moved.setIntegerValueField(.eventSourceUserData, value: MenuBarDragMonitor.syntheticEventTag)
                moved.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(50))
            if let shown = handleFrame, MenuBarGeometry.menuBarRegion(containing: shown) != nil {
                try? await Task.sleep(for: .milliseconds(120))
                return true
            }
        }
        return false
    }

    func collectedOrder(_ items: [ShelfItem]) -> [String] {
        items.filter { observedPlacement(of: $0) == .collected }
            .compactMap { item in item.menuBarReference.currentFrame().map { (item.id, $0.minX) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Moves one collected item from the off-screen hidden section into the
    /// visible slot next to ShelterBar's handle without expanding the section.
    /// The slot just right of the divider is preferred; if the notch covers
    /// it, the slot on the other side of the handle is tried.
    func borrowVisibleSlot(for item: ShelfItem) async -> MenuBarBorrowResult {
        lastMoveFailure = nil
        borrowedTarget = nil
        func fail(_ reason: String, noRoom: Bool = false) -> MenuBarBorrowResult {
            lastMoveFailure = reason
            menuBarMoveLog.error("borrow \(item.id, privacy: .public) failed: \(reason, privacy: .public)")
            return noRoom ? .noRoom(reason) : .failed(reason)
        }
        guard AccessibilityPermission.isGranted, item.isMovable, isCollapsed else { return fail("not collapsed or not movable") }
        guard let frame = item.menuBarReference.currentFrame(), let handle = handleFrame,
              let region = MenuBarGeometry.menuBarRegion(containing: handle) else { return fail("menu bar not visible") }
        let windows = MenuBarNativeWindow.allWindows()
        guard let source = MenuBarNativeWindow.match(axFrame: frame, clientPID: item.menuBarReference.pid,
                                                     windows: windows) else {
            return fail("no unique native window for \(frame)")
        }
        guard let divider = dividerWindow(in: windows),
              let handleWindow = MenuBarNativeWindow.match(axFrame: handle, clientPID: getpid(), windows: windows),
              abs(divider.window.frame.midY - handle.midY) < 8 else { return fail("divider window unavailable") }
        // Insertion follows the release point relative to the neighbours'
        // midpoints: just inside the handle's left edge lands between the
        // divider and the handle; just inside its right edge lands after it.
        let slots = MenuBarBorrowPlanner.candidateDrops(handle: handleWindow.frame, itemWidth: source.frame.width,
                                                        region: region, notches: MenuBarGeometry.cameraHousingRegions)
        guard !slots.isEmpty else {
            return fail("no visible room next to the handle (notch or screen edge)", noRoom: true)
        }
        var current = source
        var lastReason = "item never appeared next to the handle"
        for slot in slots {
            let start = CGPoint(x: current.frame.midX, y: current.frame.midY)
            guard await postDrag(source: current, from: start, to: slot.drop,
                                 destination: slot.afterHandle ? handleWindow : divider.window) else {
                return fail("drag could not be posted")
            }
            // Fast path: poll the live frame instead of waiting a fixed time.
            let before = item.menuBarReference.currentFrame() == frame ? frame : current.frame
            let deadline = ContinuousClock.now + .milliseconds(900)
            var shown: CGRect?
            while ContinuousClock.now < deadline, !Task.isCancelled {
                if let live = item.menuBarReference.currentFrame(), abs(live.minX - before.minX) > 1,
                   MenuBarGeometry.menuBarRegion(containing: live) == region, abs(live.midY - handle.midY) < 8 {
                    shown = live
                    break
                }
                try? await Task.sleep(for: .milliseconds(15))
            }
            guard let shown else { break }
            // Let the host finish laying out, then re-read.
            try? await Task.sleep(for: .milliseconds(40))
            let settled = item.menuBarReference.currentFrame() ?? shown
            if let exposed = MenuBarGeometry.visibleFrame(settled), exposed.width >= settled.width - 2 {
                borrowedTarget = MenuBarMenuOpener.onScreenStatusWindow(near: settled)?.frame ?? settled
                menuBarMoveLog.info("borrowed visible slot for \(item.id, privacy: .public) at \(String(describing: settled), privacy: .public) (\(slot.afterHandle ? "after" : "before", privacy: .public) handle)")
                return .borrowed
            }
            lastReason = "slot \(settled) is hidden by the notch"
            menuBarMoveLog.notice("borrow \(item.id, privacy: .public): \(lastReason, privacy: .public); trying the other side")
            guard let next = MenuBarNativeWindow.match(axFrame: settled, clientPID: item.menuBarReference.pid,
                                                       windows: MenuBarNativeWindow.allWindows()) else { break }
            current = next
        }
        return fail(lastReason, noRoom: lastReason.contains("notch"))
    }

    /// The on-screen frame of the borrowed item, for clicking it.
    private(set) var borrowedTarget: CGRect?

    func clickTarget(for item: ShelfItem) -> CGRect? { borrowedTarget }

    /// Puts a borrowed item back exactly left of its former right neighbour
    /// (or of the divider when it was the last collected item).
    func returnFromVisibleSlot(_ item: ShelfItem, before neighbor: ShelfItem?) async -> Bool {
        lastMoveFailure = nil
        borrowedTarget = nil
        func fail(_ reason: String) -> Bool {
            lastMoveFailure = reason
            menuBarMoveLog.error("return \(item.id, privacy: .public) failed: \(reason, privacy: .public)")
            return false
        }
        guard let frame = item.menuBarReference.currentFrame(),
              MenuBarGeometry.visibleFrame(frame) != nil else { return fail("borrowed item not visible") }
        let windows = MenuBarNativeWindow.allWindows()
        guard let source = MenuBarNativeWindow.match(axFrame: frame, clientPID: item.menuBarReference.pid,
                                                     windows: windows) else { return fail("no native window for \(frame)") }
        func anchorAX() -> CGRect? {
            if let neighbor { return neighbor.menuBarReference.currentFrame() }
            return MenuBarAX.ownItemFrame(help: Self.separatorHelp)
        }
        let anchorWindow: MenuBarNativeWindow?
        if let neighbor, let ax = neighbor.menuBarReference.currentFrame() {
            anchorWindow = MenuBarNativeWindow.match(axFrame: ax, clientPID: neighbor.menuBarReference.pid, windows: windows)
        } else {
            anchorWindow = neighbor == nil ? dividerWindow(in: windows)?.window : nil
        }
        guard let anchor = anchorWindow else { return fail("no native window for the original neighbour") }
        let start = CGPoint(x: source.frame.midX, y: source.frame.midY)
        let end = MenuBarBorrowPlanner.returnDrop(anchor: anchor.frame, anchorIsDivider: neighbor == nil)
        guard await postDrag(source: source, from: start, to: end, destination: anchor) else {
            return fail("drag could not be posted")
        }
        let deadline = ContinuousClock.now + .milliseconds(1200)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if let back = item.menuBarReference.currentFrame(), let ax = anchorAX(),
               MenuBarBorrowPlanner.isBack(item: back, before: ax),
               !isCollapsed || !MenuBarGeometry.isOnMenuBar(back) {
                menuBarMoveLog.info("returned \(item.id, privacy: .public) to its hidden slot")
                return true
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
        return fail("item never observed back in its hidden slot (now \(String(describing: item.menuBarReference.currentFrame())), anchor \(String(describing: anchorAX())), drop \(end), anchor window \(anchor.frame))")
    }

    func waitUntilUserIdle(maximum: Duration) async {
        await MenuBarMenuOpener.waitUntilUserIdle(maximum: maximum)
    }

    /// Posts a Command-drag addressed to the source window's owner (Control
    /// Center on macOS 26). The pointer is hidden and put back afterwards.
    private func postDrag(source native: MenuBarNativeWindow, from start: CGPoint, to end: CGPoint,
                          destination: MenuBarNativeWindow) async -> Bool {
        guard !Task.isCancelled, let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let events = MenuBarDragEvents(source: source, sourceWindow: native.id,
                                       destinationWindow: destination.id, ownerPID: native.pid)
        guard let down = events.make(.leftMouseDown, at: start),
              let up = events.make(.leftMouseUp, at: end) else { return false }
        let original = CGEvent(source: nil)?.location
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            if let original { CGWarpMouseCursorPosition(original) }
            CGDisplayShowCursor(CGMainDisplayID())
        }
        down.post(tap: .cghidEventTap)
        defer { up.post(tap: .cghidEventTap) }
        try? await Task.sleep(for: .milliseconds(40))
        for step in 1...5 {
            guard !Task.isCancelled else { return false }
            let t = CGFloat(step) / 5
            guard let drag = events.make(.leftMouseDragged,
                                         at: CGPoint(x: start.x + (end.x - start.x) * t, y: end.y)) else { return false }
            drag.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(14))
        }
        return true
    }

    private func commandDrag(_ item: ShelfItem, from frame: CGRect, to end: CGPoint,
                             placement: MenuBarPlacement) async -> Bool {
        func fail(_ reason: String) -> Bool {
            lastMoveFailure = reason
            return false
        }
        guard !Task.isCancelled, let source = CGEventSource(stateID: .hidSystemState),
              let exposed = MenuBarGeometry.visibleFrame(frame) else { return fail("no visible pickup") }
        let start = CGPoint(x: exposed.midX, y: frame.midY)
        let windows = MenuBarNativeWindow.currentWindows()
        guard let nativeSource = MenuBarNativeWindow.match(axFrame: frame,
                  clientPID: item.menuBarReference.pid, windows: windows) else {
            return fail("no unique native window for item \(frame)")
        }
        guard let nativeDestination = nativeSeparator(windows: windows) else {
            return fail("no unique native window for divider \(String(describing: separatorFrame))")
        }
        guard let region = MenuBarGeometry.menuBarRegion(containing: frame),
              MenuBarGeometry.menuBarRegion(containing: nativeSource.frame) == region,
              MenuBarGeometry.menuBarRegion(containing: nativeDestination.frame) == region,
              region.contains(end) else { return fail("native windows changed display") }
        // A display/layout switch between planning and this snapshot must not
        // turn a safe insertion into an overlapping or cross-screen release.
        if placement == .collected {
            guard end.x + (frame.maxX - start.x) < nativeDestination.frame.minX else {
                return fail("divider moved before release (\(nativeDestination.frame))")
            }
        } else {
            guard end.x - (start.x - frame.minX) > nativeDestination.frame.maxX else {
                return fail("divider moved before release (\(nativeDestination.frame))")
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

    private func nativeSeparator(windows: [MenuBarNativeWindow]? = nil) -> MenuBarNativeWindow? {
        guard let frame = separatorFrame else { return nil }
        return MenuBarNativeWindow.match(axFrame: frame, clientPID: getpid(),
                                         windows: windows ?? MenuBarNativeWindow.currentWindows())
    }
}

extension MenuBarItemMover: MenuBarLayoutDriving {
    var transitionRegion: CGRect? {
        separatorFrame.flatMap(MenuBarGeometry.menuBarRegion(containing:))
    }

    func isClickable(_ item: ShelfItem) -> Bool {
        guard let frame = item.menuBarReference.currentFrame() else { return false }
        return MenuBarGeometry.isOnMenuBar(frame)
    }

    /// Makes a revealed item clickable, showing an auto-hidden bar if allowed.
    func prepareForClick(_ item: ShelfItem) async -> Bool {
        guard let frame = item.menuBarReference.currentFrame() else { return false }
        if MenuBarGeometry.isOnMenuBar(frame) { return true }
        guard MenuBarGeometry.hiddenMenuBarRegion(containing: frame) != nil else {
            menuBarMoveLog.notice("item \(item.id, privacy: .public) at \(String(describing: frame), privacy: .public) is not clickable")
            return false
        }
        guard await revealAutoHiddenMenuBar(for: item, near: frame),
              let shown = item.menuBarReference.currentFrame() else { return false }
        return MenuBarGeometry.isOnMenuBar(shown)
    }

    var isMenuBarAutoHidden: Bool {
        guard let handle = MenuBarAX.ownItemFrame(help: Self.handleHelp) else { return false }
        return MenuBarGeometry.menuBarRegion(containing: handle) == nil
            && MenuBarGeometry.hiddenMenuBarRegion(containing: handle) != nil
    }

    func observedPlacement(of item: ShelfItem) -> MenuBarPlacement? {
        if isOnCollectedSide(item) { return .collected }
        guard let frame = item.menuBarReference.currentFrame() else { return nil }
        if MenuBarGeometry.isOnMenuBar(frame) { return .resident }
        // Collapsed items are pushed far off the row; anything still laid out
        // on an auto-hidden row (and not left of the divider) is a resident.
        if MenuBarGeometry.hiddenMenuBarRegion(containing: frame) != nil,
           MenuBarGeometry.menuBarRegion(containing: frame) == nil { return .resident }
        return isCollapsed ? .collected : nil
    }
}
