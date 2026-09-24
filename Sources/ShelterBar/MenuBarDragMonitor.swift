import AppKit
import ShelterBarCore

/// Registered on the main run loop; the callback does no AX queries or I/O.
@MainActor
final class MenuBarDragMonitor {
    static let syntheticEventTag: Int64 = 0x5348454C544552
    var onOutcome: ((MenuBarDragGesture.Outcome) -> Void)?
    var onDrag: ((String, CGPoint) -> Void)?
    private(set) var gesture = MenuBarDragGesture()
    private var activeID: String?
    private var itemFrames: [(id: String, frame: CGRect)] = []
    private var shelfFrame = CGRect.zero
    private var enabled = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> Bool {
        if let eventTap { return CGEvent.tapIsEnabled(tap: eventTap) }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated {
                    let monitor = Unmanaged<MenuBarDragMonitor>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        monitor.gesture.cancel()
                        monitor.onOutcome?(.cancel)
                        if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return false
                    }
                    return monitor.consume(type, event: event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        gesture.cancel()
    }

    func update(isEnabled: Bool, items: [ShelfItem], shelfFrame: CGRect) {
        enabled = isEnabled
        itemFrames = items.map { ($0.id, $0.menuBarReference.frame) }
        self.shelfFrame = shelfFrame
        // Preserve a swallowed down/up pair even when the panel loses focus.
    }

    @discardableResult
    func consume(_ type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticEventTag else { return false }
        let point = event.location
        switch type {
        case .leftMouseDown:
            guard enabled, !event.flags.contains(.maskCommand),
                  let item = itemFrames.first(where: { $0.frame.contains(point) }) else { return false }
            gesture.begin(itemID: item.id, at: point)
            activeID = item.id
            return true
        case .leftMouseDragged:
            guard gesture.isTracking else { return false }
            gesture.move(to: point)
            if gesture.isDragging, !gesture.isCancelled, let activeID { onDrag?(activeID, point) }
            return true
        case .leftMouseUp:
            guard let outcome = gesture.finish(at: point, shelf: shelfFrame) else { return false }
            activeID = nil
            // Let this mouse-up leave the tap before starting a new synthetic gesture.
            DispatchQueue.main.async { [weak self] in self?.onOutcome?(outcome) }
            return true
        case .keyDown:
            if gesture.isTracking, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                // Keep the pair tracked until mouse-up, but make collection impossible.
                gesture.cancelUntilRelease()
                onOutcome?(.cancel)
                return true
            }
            return false
        default:
            return false
        }
    }
}
