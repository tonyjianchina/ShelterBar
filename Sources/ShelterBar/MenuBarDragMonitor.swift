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
    private let hasEventAccess: @MainActor () -> Bool

    init(hasEventAccess: @escaping @MainActor () -> Bool = { AccessibilityPermission.isGranted }) {
        self.hasEventAccess = hasEventAccess
    }

    func start() -> Bool {
        guard hasEventAccess() else {
            stop()
            return false
        }
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
                        if monitor.handleTapDisabled(type), let tap = monitor.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
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

    /// Returns whether Core Graphics should re-enable a disabled tap.
    @discardableResult
    func handleTapDisabled(_ type: CGEventType) -> Bool {
        gesture.cancel()
        activeID = nil
        onOutcome?(.cancel)
        switch type {
        case .tapDisabledByTimeout:
            // A slow callback may be retried when the input permission gate
            // still agrees. Core Graphics disables the tap before calling us.
            return hasEventAccess()
        case .tapDisabledByUserInput:
            // This is an explicit system/user request to disable taps (for
            // example while privacy permissions are changing). Never override
            // it from a preflight result that can remain stale in this process.
            return false
        default:
            return false
        }
    }

    func stop() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        gesture.cancel()
        activeID = nil
    }

    func update(isEnabled: Bool, items: [ShelfItem], shelfFrame: CGRect) {
        enabled = isEnabled
        itemFrames = items.compactMap { item in
            Self.safeHitFrame(item.menuBarReference.frame).map { (item.id, $0) }
        }
        self.shelfFrame = shelfFrame
        // Preserve a swallowed down/up pair even when the panel loses focus.
    }

    /// AX coordinates are cached outside the event callback and can become
    /// stale while permissions or displays change. A filtering event tap must
    /// never trust a rectangle that extends beyond a real menu-bar row.
    private static func safeHitFrame(_ frame: CGRect) -> CGRect? {
        guard frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 1, frame.height > 1,
              frame.height <= 64,
              let row = MenuBarGeometry.menuBarRow(containing: frame),
              frame.width <= min(row.width, 512) else { return nil }
        let clipped = frame.intersection(row)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return nil }
        return clipped
    }

    @discardableResult
    func consume(_ type: CGEventType, event: CGEvent) -> Bool {
        guard hasEventAccess() else {
            gesture.cancel()
            activeID = nil
            return false
        }
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
