import AppKit
import ApplicationServices

/// Pure decisions of the menu opener, kept separate so they can be tested.
enum MenuBarPressPolicy {
    static func clickButton(bundleID: String?) -> CGMouseButton {
        // Its custom status view toggles the main window on left click and
        // exposes the playback menu on right click.
        bundleID == "com.tencent.QQMusicMac" ? .right : .left
    }

    static func clickPoint(in frame: CGRect, bundleID: String?) -> CGPoint {
        // QQ Music replaces the song title with playback controls on hover.
        // Use the trailing logo for the context-menu click: the wide control's
        // center is a play/skip button and AX actions are unsupported.
        if bundleID == "com.tencent.QQMusicMac", frame.width > frame.height * 2 {
            return CGPoint(x: frame.maxX - frame.height / 2, y: frame.midY)
        }
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    /// AXPress is used only when the AX element is on a visible menu bar and
    /// agrees with the on-screen native status window, so the menu opens
    /// where the user can see it. Anything else gets a real (synthesized)
    /// click on the visible glyph, and an off-screen item is never pressed.
    static func shouldUseAXPress(axFrame: CGRect?, windowFrame: CGRect?, axIsOnMenuBar: Bool) -> Bool {
        guard axIsOnMenuBar, let axFrame, let windowFrame else { return false }
        return abs(axFrame.midX - windowFrame.midX) <= 10 && abs(axFrame.midY - windowFrame.midY) <= 10
    }

    enum CloseState: Equatable { case open, closedWaitingGrace, restore }

    /// The menu is gone, the user is idle and the grace period (counted from
    /// the moment it closed) has passed; or the user switched apps.
    static func closeState(menuVisible: Bool, closedFor: Duration?, idleFor: Duration,
                           frontmostChanged: Bool, grace: Duration = .milliseconds(1000),
                           idle: Duration = .milliseconds(250)) -> CloseState {
        if frontmostChanged && !menuVisible { return .restore }
        if menuVisible { return .open }
        guard let closedFor, closedFor >= grace, idleFor >= idle else { return .closedWaitingGrace }
        return .restore
    }
}

/// Opens a status item's menu or popover once it is visible on a menu bar,
/// and reports when that UI has closed so the item can be stowed again.
@MainActor
enum MenuBarMenuOpener {
    private struct Session {
        let pids: [pid_t]
        var windows: Set<CGWindowID>
        let frontmost: pid_t?
        let baseline: Set<CGWindowID>
    }

    private static var session: Session?
    private static let pressExecutor = MenuBarAXPressExecutor()

    /// Inject only external effects; regression tests run the production
    /// activation sequence without sending input to the user's desktop.
    @MainActor
    struct Operations {
        var press: @MainActor (MenuBarItemReference) async -> AXError = { await pressExecutor.press($0) }
        var showMenu: @MainActor (MenuBarItemReference) async -> AXError = { await pressExecutor.showMenu($0) }
        var currentWindows: @MainActor ([pid_t]) -> [CGWindowID: Int] = { windows(of: $0) }
        var newWindows: @MainActor ([pid_t], [CGWindowID: Int], Duration) async -> [CGWindowID: Int]? = {
            await MenuBarMenuOpener.newWindows(of: $0, since: $1, within: $2)
        }
        var click: @MainActor (CGPoint, CGMouseButton) async -> Void = {
            await MenuBarMenuOpener.click(at: $0, button: $1)
        }
    }
    static var controlCenterPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
    }

    /// `target` is the live on-screen native window of the item, if known.
    static func open(_ item: ShelfItem, target: CGRect? = nil, operations: Operations = Operations()) async -> Bool {
        session = nil
        guard !Task.isCancelled else { return false }
        let pid = item.menuBarReference.pid
        let hostPIDs = [controlCenterPID,
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?.processIdentifier
        ].compactMap { $0 }
        let pids = [pid] + Set(hostPIDs).subtracting([pid]).sorted()
        // Re-read the live position right before clicking.
        let axFrame = item.menuBarReference.currentFrame()
        let axVisible = axFrame.map(MenuBarGeometry.isOnMenuBar) ?? false
        let window = target ?? axFrame.flatMap { frame in onScreenStatusWindow(near: frame, clientPID: pid)?.frame }
        let before = operations.currentWindows(pids)
        if MenuBarPressPolicy.shouldUseAXPress(axFrame: axFrame, windowFrame: window, axIsOnMenuBar: axVisible) {
            // AXPress on a status item runs the menu's tracking loop and only
            // returns when the menu closes, so a short timeout is expected to
            // report "cannot complete" even when the menu did open.
            let result = await operations.press(item.menuBarReference)
            guard !Task.isCancelled else { return false }
            if let opened = await operations.newWindows(pids, before, .milliseconds(700)) {
                return begin(pids: pids, opened: opened, baseline: Set(before.keys))
            }
            menuBarMoveLog.info("AXPress \(item.id, privacy: .public) gave \(result.rawValue) without a menu; trying AXShowMenu")
        }
        guard !Task.isCancelled else { return false }
        if axVisible {
            let result = await operations.showMenu(item.menuBarReference)
            guard !Task.isCancelled else { return false }
            if let opened = await operations.newWindows(pids, before, .milliseconds(400)) {
                return begin(pids: pids, opened: opened, baseline: Set(before.keys))
            }
            menuBarMoveLog.info("AXShowMenu \(item.id, privacy: .public) gave \(result.rawValue) without a menu; clicking instead")
        }
        guard !Task.isCancelled else { return false }
        // AX requests can time out during a host relayout. Never click the
        // cached pre-request position (or a stale borrowedTarget).
        guard let live = item.menuBarReference.currentFrame(),
              MenuBarGeometry.isOnMenuBar(live),
              let clickFrame = MenuBarGeometry.visibleFrame(
                onScreenStatusWindow(near: live, clientPID: pid)?.frame ?? live
              ) else {
            menuBarMoveLog.error("press \(item.id, privacy: .public): item is not visible; not pressing an off-screen item")
            return false
        }
        let bundleID = item.application?.bundleIdentifier
            ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        await operations.click(MenuBarPressPolicy.clickPoint(in: clickFrame, bundleID: bundleID),
                               MenuBarPressPolicy.clickButton(bundleID: bundleID))
        guard !Task.isCancelled else { return false }
        if let opened = await operations.newWindows(pids, before, .milliseconds(900)) {
            return begin(pids: pids, opened: opened, baseline: Set(before.keys))
        }
        guard !Task.isCancelled else { return false }
        // Posting input is not proof that the menu opened. In particular,
        // custom status controls can reject AXPress with actionUnsupported.
        menuBarMoveLog.notice("click on \(item.id, privacy: .public) opened no detectable window")
        return false
    }

    /// Returns once the opened menu/popover is gone, the user has been idle
    /// for 250ms and ~1s has passed since it closed (so an accidental close
    /// can be reopened), or the frontmost app changed. Bounded in time.
    static func waitUntilClosed(_ item: ShelfItem) async {
        guard var current = session else { return }
        defer { session = nil }
        let start = ContinuousClock.now
        let deadline = start + .seconds(180)
        var closedAt: ContinuousClock.Instant?
        while ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(60))
            let now = windows(of: current.pids)
            var visible = !current.windows.isDisjoint(with: now.keys)
            if !visible, closedAt != nil {
                // Reopened during the grace period: follow the new menu.
                let reopened = now.filter { !current.baseline.contains($0.key) && $0.value != 0 }
                if !reopened.isEmpty {
                    current.windows = Set(reopened.keys)
                    visible = true
                }
            }
            if visible { closedAt = nil } else if closedAt == nil { closedAt = ContinuousClock.now }
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let state = MenuBarPressPolicy.closeState(
                menuVisible: visible,
                closedFor: closedAt.map { ContinuousClock.now - $0 },
                idleFor: userIdleDuration(),
                frontmostChanged: front != current.frontmost && front != current.pids.first
            )
            if state == .restore {
                menuBarMoveLog.info("menu of \(item.id, privacy: .public) closed; restoring")
                return
            }
        }
    }

    /// Time since the last real mouse/keyboard activity, or zero while a
    /// button or modifier key is held.
    static func userIdleDuration() -> Duration {
        if NSEvent.pressedMouseButtons != 0 { return .zero }
        if !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty { return .zero }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel, .keyDown]
        let seconds = types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 10
        return .milliseconds(Int(max(0, seconds) * 1000))
    }

    /// Waits until the user stops moving the mouse / holding modifiers.
    static func waitUntilUserIdle(minimum: Duration = .milliseconds(150), maximum: Duration) async {
        let deadline = ContinuousClock.now + maximum
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if userIdleDuration() >= minimum { return }
            try? await Task.sleep(for: .milliseconds(30))
        }
        menuBarMoveLog.notice("user still active after \(String(describing: maximum), privacy: .public); continuing")
    }

    private static func begin(pids: [pid_t], opened: [CGWindowID: Int], baseline: Set<CGWindowID>) -> Bool {
        // A normal app window is not tied to the menu bar item; only menus,
        // popovers and panels keep the item revealed while they are open.
        let floating = Set(opened.filter { $0.value != 0 }.keys)
        session = floating.isEmpty ? nil : Session(
            pids: pids, windows: floating,
            frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier, baseline: baseline
        )
        return true
    }

    private static func newWindows(of pids: [pid_t], since before: [CGWindowID: Int],
                                   within timeout: Duration) async -> [CGWindowID: Int]? {
        let deadline = ContinuousClock.now + timeout
        repeat {
            let now = windows(of: pids).filter { before[$0.key] == nil }
            if !now.isEmpty { return now }
            try? await Task.sleep(for: .milliseconds(30))
        } while ContinuousClock.now < deadline && !Task.isCancelled
        return nil
    }

    /// On-screen windows of the item's app and of Control Center (which
    /// hosts many status items and their menus on macOS 26), except status
    /// item windows themselves.
    private static func windows(of pids: [pid_t]) -> [CGWindowID: Int] {
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        var result: [CGWindowID: Int] = [:]
        for window in info {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(owner),
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer != statusLayer,
                  // Control Center's menu bar backdrop windows are not menus.
                  layer != Int(CGWindowLevelForKey(.mainMenuWindow)) else { continue }
            result[id] = layer
        }
        return result
    }

    static func onScreenStatusWindow(near frame: CGRect, clientPID: pid_t) -> MenuBarNativeWindow? {
        MenuBarNativeWindow.match(axFrame: frame, clientPID: clientPID,
                                 windows: MenuBarNativeWindow.onScreenWindows())
    }

    /// A real click on the visible glyph; the pointer is put back afterwards.
    private static func click(at point: CGPoint, button: CGMouseButton) async {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        CGDisplayHideCursor(CGMainDisplayID())
        defer {
            if let original { CGWarpMouseCursorPosition(original) }
            CGDisplayShowCursor(CGMainDisplayID())
        }
        let down: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        for type in [CGEventType.mouseMoved, down, up] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: button) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: MenuBarDragMonitor.syntheticEventTag)
            event.flags = []
            event.post(tap: .cghidEventTap)
            // Give the foreign tracking loop time to receive down/up before
            // warping the pointer back, without blocking AppKit's main actor.
            try? await Task.sleep(for: .milliseconds(type == up ? 80 : 30))
        }
    }
}
