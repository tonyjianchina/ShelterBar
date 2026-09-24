import AppKit
import ShelterBarCore

@MainActor
final class MenuBarItemMover {
    static let separatorHelp = "ShelterBar 收纳分隔线"
    static let handleHelp = "ShelterBar · 打开收纳栏"
    private let separator: NSStatusItem
    private(set) var isCollapsed = false

    init(separator: NSStatusItem) { self.separator = separator }

    var separatorFrame: CGRect? {
        MenuBarGeometry.statusFrame(separator, help: Self.separatorHelp)
    }

    func revealHiddenSection() async {
        separator.length = 1
        isCollapsed = false
        try? await Task.sleep(for: .milliseconds(220))
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
              MenuBarGeometry.isOnMenuBar(frame),
              let region = MenuBarGeometry.menuBarRegion(containing: boundary),
              MenuBarGeometry.menuBarRegion(containing: frame) == region,
              abs(frame.midY - boundary.midY) < 8 else { return false }
        return frame.maxX <= boundary.minX + 1
    }

    /// Only returns true after observing the real item on the requested side.
    func move(_ item: ShelfItem, to placement: MenuBarPlacement, dropPoint: CGPoint? = nil) async -> Bool {
        guard AccessibilityPermission.isGranted, item.isMovable,
              let frame = item.menuBarReference.currentFrame(), MenuBarGeometry.isOnMenuBar(frame) else { return false }
        return await VerifiedMenuBarMove.perform(
            to: placement, readItem: item.menuBarReference.currentFrame,
            readDivider: { self.separatorFrame },
            menuBarRegion: MenuBarGeometry.menuBarRegion(containing:),
            readInsertionFrame: { self.nativeSeparator()?.frame },
            pickupPoint: { frame in
                MenuBarGeometry.visibleFrame(frame).map { CGPoint(x: $0.midX, y: frame.midY) }
            },
            requestedDropPoint: dropPoint,
            send: { frame, end in
                guard let region = MenuBarGeometry.menuBarRegion(containing: frame),
                      region.contains(end) else { return false }
                return await self.commandDrag(item, from: frame, to: end, placement: placement)
            }
        )
    }

    private func commandDrag(_ item: ShelfItem, from frame: CGRect, to end: CGPoint,
                             placement: MenuBarPlacement) async -> Bool {
        guard !Task.isCancelled, let source = CGEventSource(stateID: .hidSystemState),
              let exposed = MenuBarGeometry.visibleFrame(frame) else { return false }
        let start = CGPoint(x: exposed.midX, y: frame.midY)
        let windows = MenuBarNativeWindow.currentWindows()
        guard let nativeSource = MenuBarNativeWindow.match(axFrame: frame,
                  clientPID: item.menuBarReference.pid, windows: windows),
              let nativeDestination = nativeSeparator(windows: windows) else { return false }
        guard let region = MenuBarGeometry.menuBarRegion(containing: frame),
              MenuBarGeometry.menuBarRegion(containing: nativeSource.frame) == region,
              MenuBarGeometry.menuBarRegion(containing: nativeDestination.frame) == region,
              region.contains(end) else { return false }
        // A display/layout switch between planning and this snapshot must not
        // turn a safe insertion into an overlapping or cross-screen release.
        if placement == .collected {
            guard end.x + (frame.maxX - start.x) < nativeDestination.frame.minX else { return false }
        } else {
            guard end.x - (start.x - frame.minX) > nativeDestination.frame.maxX else { return false }
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
