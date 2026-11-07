import ApplicationServices
import Foundation

/// AXPress may remain in a foreign application's menu tracking loop until its
/// messaging timeout. Keep that bounded wait off the AppKit main thread while
/// preserving ordering: callers still await completion before checking menus.
final class MenuBarAXPressExecutor: @unchecked Sendable {
    typealias Action = @Sendable (MenuBarItemReference) -> AXError

    private let queue = DispatchQueue(label: "com.jensen.shelterbar.ax-press", qos: .userInitiated)
    private let action: Action
    private let menuAction: Action

    private static func perform(_ reference: MenuBarItemReference, action: CFString) -> AXError {
        let element = reference.element
        AXUIElementSetMessagingTimeout(element, 0.25)
        defer { AXUIElementSetMessagingTimeout(element, 0) }
        return AXUIElementPerformAction(element, action)
    }

    init(
        action: @escaping Action = { perform($0, action: kAXPressAction as CFString) },
        menuAction: @escaping Action = { perform($0, action: kAXShowMenuAction as CFString) }
    ) {
        self.action = action
        self.menuAction = menuAction
    }

    func press(_ reference: MenuBarItemReference) async -> AXError {
        await enqueue(reference, action: action)
    }

    func showMenu(_ reference: MenuBarItemReference) async -> AXError {
        await enqueue(reference, action: menuAction)
    }

    private func enqueue(_ reference: MenuBarItemReference, action: @escaping Action) async -> AXError {
        guard !Task.isCancelled else { return .failure }
        return await withCheckedContinuation { continuation in
            queue.async { [action] in
                // A fresh executor owns one serial queue; the engine also
                // serializes menu activation, so two presses never overlap.
                continuation.resume(returning: action(reference))
            }
        }
    }
}
