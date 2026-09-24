import AppKit
import Testing
@testable import ShelterBar

@Test("Shadowrocket release targets the insertion window, not its original window")
@MainActor
func nativeDragReleaseTarget() throws {
    let source = try #require(CGEventSource(stateID: .privateState))
    let events = MenuBarDragEvents(source: source, sourceWindow: 12412, destinationWindow: 28175, ownerPID: 1141)
    let down = try #require(events.make(.leftMouseDown, at: CGPoint(x: 1008, y: 16.5)))
    let up = try #require(events.make(.leftMouseUp, at: CGPoint(x: 979, y: 16.5)))
    #expect(down.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 12412)
    #expect(up.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 28175)
    #expect(up.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) == 28175)
    #expect(up.getIntegerValueField(.eventSourceUserData) == MenuBarDragMonitor.syntheticEventTag)
    #expect(down.getIntegerValueField(.eventTargetUnixProcessID) == 1141)
    #expect(up.getIntegerValueField(.eventTargetUnixProcessID) == 1141)
    #expect(down.getIntegerValueField(MenuBarDragEvents.windowNumberField) == 12412)
    #expect(up.getIntegerValueField(MenuBarDragEvents.windowNumberField) == 28175)
    #expect(down.flags.contains(.maskCommand))
    #expect(!up.flags.contains(.maskCommand))
}
