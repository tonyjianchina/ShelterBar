import AppKit
import os
import ShelterBarCore

@MainActor
final class MenuBarDragMonitor {
    nonisolated static let syntheticEventTag: Int64 = 0x5348454C544552
    var onOutcome: ((MenuBarDragGesture.Outcome) -> Void)?
    var onDrag: ((String, CGPoint) -> Void)?
    var gesture: MenuBarDragGesture { input.withLock { $0.gesture } }

    private let input = OSAllocatedUnfairLock(initialState: InputState())
    private var eventTap: EventTap?
    private var permissionCheck: Task<Void, Never>?
    private var stoppedBySystem = false
    private let hasEventAccess: @MainActor () -> Bool

    init(hasEventAccess: @escaping @MainActor () -> Bool = { AccessibilityPermission.isGranted }) {
        self.hasEventAccess = hasEventAccess
    }

    func beginShelfSession() {
        stoppedBySystem = false
    }

    func start() -> Bool {
        if stoppedBySystem { return false }
        if eventTap != nil { return true }
        guard refreshPermission() else { return false }

        let id = UUID()
        guard let tap = EventTap(id: id, input: input, deliver: { [weak self] action in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.eventTap?.id == id else { return }
                self.deliver(action)
            }
        }) else {
            stop()
            return false
        }
        eventTap = tap
        input.withLock { $0.tapID = id }
        tap.start()
        permissionCheck = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.eventTap?.id == id else { return }
                if !self.refreshPermission() { return }
            }
        }
        return true
    }

    @discardableResult
    func refreshPermission() -> Bool {
        let granted = hasEventAccess()
        input.withLock { $0.hasPermission = granted }
        if !granted { stop() }
        return granted
    }

    func stop() {
        permissionCheck?.cancel()
        permissionCheck = nil
        let tap = eventTap
        eventTap = nil
        let wasTracking = input.withLock { state in
            let wasTracking = state.gesture.isTracking
            state.tapID = nil
            state.reset()
            return wasTracking
        }
        tap?.stop()
        if wasTracking { onOutcome?(.cancel) }
    }

    func update(isEnabled: Bool, items: [ShelfItem], shelfFrame: CGRect) {
        let hitFrames = items.compactMap { item in
            Self.safeHitFrame(item.menuBarReference.frame).map { (item.id, $0) }
        }
        input.withLock { state in
            state.enabled = isEnabled
            state.itemFrames = hitFrames
            state.shelfFrame = shelfFrame
        }
    }

    func stopIfIdle() {
        if !gesture.isTracking { stop() }
    }

    @discardableResult
    func consume(_ type: CGEventType, event: CGEvent) -> Bool {
        let result = input.withLockUnchecked { $0.consume(type, event: event) }
        if let action = result.action { deliver(action) }
        return result.consumed
    }

    private func deliver(_ action: Action) {
        switch action {
        case let .drag(id, point):
            onDrag?(id, point)
        case let .outcome(outcome):
            onOutcome?(outcome)
            let isIdle = input.withLock { !$0.enabled && !$0.gesture.isTracking }
            if isIdle { stop() }
        case .disabled:
            stoppedBySystem = true
            stop()
            onOutcome?(.cancel)
        }
    }

    /// Only accept cached accessibility frames lying within a real menu-bar row.
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

    private enum Action: Sendable {
        case drag(String, CGPoint)
        case outcome(MenuBarDragGesture.Outcome)
        case disabled
    }

    /// The callback only uses this in-memory snapshot. Permission checks and
    /// UI updates run separately on the main actor.
    private struct InputState: Sendable {
        var gesture = MenuBarDragGesture()
        var tapID: UUID?
        var activeID: String?
        var itemFrames: [(id: String, frame: CGRect)] = []
        var shelfFrame = CGRect.zero
        var enabled = false
        var hasPermission = false

        mutating func reset() {
            hasPermission = false
            gesture.cancel()
            activeID = nil
        }

        mutating func consume(_ type: CGEventType, event: CGEvent) -> (consumed: Bool, action: Action?) {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                tapID = nil
                reset()
                return (false, .disabled)
            }
            guard hasPermission,
                  event.getIntegerValueField(.eventSourceUserData) != MenuBarDragMonitor.syntheticEventTag
            else { return (false, nil) }
            let point = event.location
            switch type {
            case .leftMouseDown:
                guard enabled, !event.flags.contains(.maskCommand),
                      let item = itemFrames.first(where: { $0.frame.contains(point) }) else { return (false, nil) }
                gesture.begin(itemID: item.id, at: point)
                activeID = item.id
                return (true, nil)
            case .leftMouseDragged:
                guard gesture.isTracking else { return (false, nil) }
                gesture.move(to: point)
                if gesture.isDragging, !gesture.isCancelled, let activeID { return (true, .drag(activeID, point)) }
                return (true, nil)
            case .leftMouseUp:
                guard let outcome = gesture.finish(at: point, shelf: shelfFrame) else { return (false, nil) }
                activeID = nil
                return (true, .outcome(outcome))
            case .keyDown:
                guard gesture.isTracking, event.getIntegerValueField(.keyboardEventKeycode) == 53 else { return (false, nil) }
                // Keep the swallowed mouse-down paired with its release.
                gesture.cancelUntilRelease()
                return (true, .outcome(.cancel))
            default:
                return (false, nil)
            }
        }
    }

    /// The run-loop thread retains the tap and callback context until it exits.
    /// Core Foundation's port and run-loop shutdown APIs support cross-thread use.
    private final class EventTap: @unchecked Sendable {
        private final class Context: Sendable {
            let id: UUID
            let input: OSAllocatedUnfairLock<InputState>
            let deliver: @Sendable (Action) -> Void

            init(id: UUID, input: OSAllocatedUnfairLock<InputState>, deliver: @escaping @Sendable (Action) -> Void) {
                self.id = id
                self.input = input
                self.deliver = deliver
            }
        }

        private struct Lifetime {
            var runLoop: CFRunLoop?
            var stopped = false
        }

        let id: UUID
        private let context: Context
        private let port: CFMachPort
        private let source: CFRunLoopSource
        private let lifetime = OSAllocatedUnfairLock(uncheckedState: Lifetime())
        init?(id: UUID, input: OSAllocatedUnfairLock<InputState>, deliver: @escaping @Sendable (Action) -> Void) {
            let context = Context(id: id, input: input, deliver: deliver)
            let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown]
            let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, pointer in
                    guard let pointer else { return Unmanaged.passUnretained(event) }
                    let context = Unmanaged<Context>.fromOpaque(pointer).takeUnretainedValue()
                    let result = context.input.withLockUnchecked { state in
                        guard state.tapID == context.id else { return (consumed: false, action: nil as Action?) }
                        return state.consume(type, event: event)
                    }
                    if let action = result.action { context.deliver(action) }
                    return result.consumed ? nil : Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(context).toOpaque()
            ) else { return nil }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                CFMachPortInvalidate(port)
                return nil
            }
            self.id = id
            self.context = context
            self.port = port
            self.source = source
        }

        func start() {
            let thread = Thread { [self] in
                let runLoop = CFRunLoopGetCurrent()!
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                let shouldRun = lifetime.withLockUnchecked { state in
                    guard !state.stopped else { return false }
                    state.runLoop = runLoop
                    return true
                }
                if shouldRun { CFRunLoopRun() }
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
            }
            thread.name = "ShelterBar mouse event tap"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        func stop() {
            CFMachPortInvalidate(port)
            let runLoop = lifetime.withLockUnchecked { state in
                state.stopped = true
                return state.runLoop
            }
            if let runLoop {
                CFRunLoopStop(runLoop)
                CFRunLoopWakeUp(runLoop)
            }
        }
    }
}
