import AppKit
import ApplicationServices
import Testing
@testable import ShelterBar

@Test("the event tap passes our synthetic moves through without consuming them")
@MainActor
func syntheticMoveIsNotCaptured() {
    let monitor = MenuBarDragMonitor(hasEventAccess: { true })
    #expect(monitor.refreshPermission())
    let item = ShelfItem(
        id: "test", title: "Test", icon: NSImage(), application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: 800, y: 5, width: 30, height: 24)
        )
    )
    monitor.update(isEnabled: true, items: [item], shelfFrame: CGRect(x: 500, y: 35, width: 400, height: 74))
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: CGPoint(x: 815, y: 16), mouseButton: .left)!
    down.flags = []
    down.setIntegerValueField(.eventSourceUserData, value: MenuBarDragMonitor.syntheticEventTag)
    #expect(!monitor.consume(.leftMouseDown, event: down))
    #expect(!monitor.gesture.isTracking)
    let physical = CGEvent(mouseEventSource: CGEventSource(stateID: .privateState),
                           mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 815, y: 16),
                           mouseButton: .left)!
    physical.flags = []
    #expect(monitor.consume(.leftMouseDown, event: physical))
    #expect(monitor.gesture.isTracking)
}

@Test("the event tap releases physical clicks as soon as input access is unavailable")
@MainActor
func revokedInputAccessDoesNotConsumePhysicalClick() {
    let monitor = MenuBarDragMonitor(hasEventAccess: { false })
    #expect(!monitor.start())
    let item = ShelfItem(
        id: "test", title: "Test", icon: NSImage(), application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: 800, y: 5, width: 30, height: 24)
        )
    )
    monitor.update(isEnabled: true, items: [item], shelfFrame: CGRect(x: 500, y: 35, width: 400, height: 74))
    let physical = CGEvent(
        mouseEventSource: CGEventSource(stateID: .privateState),
        mouseType: .leftMouseDown,
        mouseCursorPosition: CGPoint(x: 815, y: 16),
        mouseButton: .left
    )!
    physical.flags = []

    #expect(!monitor.consume(.leftMouseDown, event: physical))
    #expect(!monitor.gesture.isTracking)
}

@Test("revoking input access cancels an in-flight gesture and releases subsequent events")
@MainActor
func revokedInputAccessCancelsTrackedGesture() {
    var hasEventAccess = true
    let monitor = MenuBarDragMonitor(hasEventAccess: { hasEventAccess })
    #expect(monitor.refreshPermission())
    let item = ShelfItem(
        id: "test", title: "Test", icon: NSImage(), application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: 800, y: 5, width: 30, height: 24)
        )
    )
    monitor.update(isEnabled: true, items: [item], shelfFrame: CGRect(x: 500, y: 35, width: 400, height: 74))
    let down = CGEvent(
        mouseEventSource: CGEventSource(stateID: .privateState),
        mouseType: .leftMouseDown,
        mouseCursorPosition: CGPoint(x: 815, y: 16),
        mouseButton: .left
    )!
    let drag = CGEvent(
        mouseEventSource: CGEventSource(stateID: .privateState),
        mouseType: .leftMouseDragged,
        mouseCursorPosition: CGPoint(x: 820, y: 20),
        mouseButton: .left
    )!

    #expect(monitor.consume(.leftMouseDown, event: down))
    #expect(monitor.gesture.isTracking)
    hasEventAccess = false
    #expect(!monitor.refreshPermission())
    #expect(!monitor.consume(.leftMouseDragged, event: drag))
    #expect(!monitor.gesture.isTracking)
}

@Test("a stale off-menu-bar hit frame never consumes an ordinary desktop click")
@MainActor
func staleOffMenuBarHitFrameDoesNotConsumeDesktopClick() {
    let monitor = MenuBarDragMonitor(hasEventAccess: { true })
    #expect(monitor.refreshPermission())
    let item = ShelfItem(
        id: "stale", title: "Stale", icon: NSImage(), application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: 800, y: 488, width: 30, height: 24)
        )
    )
    monitor.update(
        isEnabled: true,
        items: [item],
        shelfFrame: CGRect(x: 500, y: 35, width: 400, height: 74)
    )
    let desktopClick = CGEvent(
        mouseEventSource: CGEventSource(stateID: .privateState),
        mouseType: .leftMouseDown,
        mouseCursorPosition: CGPoint(x: 815, y: 500),
        mouseButton: .left
    )!

    #expect(!monitor.consume(.leftMouseDown, event: desktopClick))
    #expect(!monitor.gesture.isTracking)
}

@Test("a system-disabled tap stays off without retrying a permission check",
      arguments: [CGEventType.tapDisabledByUserInput, .tapDisabledByTimeout])
@MainActor
func disabledTapFailsOpen(eventType: CGEventType) {
    var permissionReads = 0
    let monitor = MenuBarDragMonitor(hasEventAccess: {
        permissionReads += 1
        return true
    })
    #expect(monitor.refreshPermission())
    let event = CGEvent(source: nil)!

    #expect(!monitor.consume(eventType, event: event))
    #expect(!monitor.start())
    #expect(permissionReads == 1)
}

@Test("a desktop click never waits for the operating system permission check")
@MainActor
func desktopClickDoesNotWaitForPermissionCheck() {
    var permissionReads = 0
    let monitor = MenuBarDragMonitor(hasEventAccess: {
        permissionReads += 1
        return true
    })
    #expect(monitor.refreshPermission())
    monitor.update(isEnabled: true, items: [], shelfFrame: .zero)
    permissionReads = 0
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: CGPoint(x: 400, y: 400), mouseButton: .left)!

    #expect(!monitor.consume(.leftMouseDown, event: down))
    #expect(permissionReads == 0)
}
