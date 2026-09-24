import AppKit
import ApplicationServices
import Testing
@testable import ShelterBar

@Test("the event tap passes our synthetic moves through without consuming them")
@MainActor
func syntheticMoveIsNotCaptured() {
    let monitor = MenuBarDragMonitor()
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
