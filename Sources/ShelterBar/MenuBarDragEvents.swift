import AppKit

/// One native drag owns its source window until release. The window under the
/// release point is distinct from that source (the insertion target).
@MainActor
struct MenuBarDragEvents {
    let source: CGEventSource
    let sourceWindow: CGWindowID
    let destinationWindow: CGWindowID
    let ownerPID: pid_t

    // AppKit's window-number field is not exposed as a named CGEventField.
    // Keep this compatibility detail here, alongside the public routing fields.
    static let windowNumberField = CGEventField(rawValue: 0x33)!

    func make(_ type: CGEventType, at point: CGPoint) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = type == .leftMouseUp ? [] : .maskCommand
        event.setIntegerValueField(.eventSourceUserData, value: MenuBarDragMonitor.syntheticEventTag)
        let window = type == .leftMouseUp ? destinationWindow : sourceWindow
        // The receiver remains the source's native host even when released
        // beside another app. Never inherit the foreground app's PID.
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ownerPID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        event.setIntegerValueField(Self.windowNumberField, value: Int64(window))
        return event
    }
}
