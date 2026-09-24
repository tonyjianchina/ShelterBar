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
            requestedDropPoint: dropPoint,
            send: { frame, end in
                guard let region = MenuBarGeometry.menuBarRegion(containing: frame),
                      region.contains(end) else { return false }
                return await self.commandDrag(item, from: frame, to: end)
            }
        )
    }

    private func commandDrag(_ item: ShelfItem, from frame: CGRect, to end: CGPoint) async -> Bool {
        guard !Task.isCancelled, let source = CGEventSource(stateID: .hidSystemState),
              let exposed = MenuBarGeometry.visibleFrame(frame) else { return false }
        let start = CGPoint(x: exposed.midX, y: frame.midY)
        let windowID = matchingWindow(frame: frame)
        func event(_ type: CGEventType, _ point: CGPoint) -> CGEvent? {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.setIntegerValueField(.eventSourceUserData, value: MenuBarDragMonitor.syntheticEventTag)
            if let windowID {
                event?.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
                event?.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
            }
            return event
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

    private func matchingWindow(frame: CGRect) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.first(where: { info in
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
            return abs(bounds.midX - frame.midX) < 3 && abs(bounds.midY - frame.midY) < 4
                && abs(bounds.width - frame.width) < 8
        })?[kCGWindowNumber as String] as? CGWindowID
    }
}
