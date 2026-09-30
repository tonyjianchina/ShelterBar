import AppKit

/// The native status window can include padding absent from its AX item.
/// On recent macOS versions Control Center may host another app's status item.
struct MenuBarNativeWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let frame: CGRect
    let ownerBundleID: String?

    /// AX commits reordered coordinates before WindowServer finishes its
    /// animation. Await a coherent pair instead of posting against stale
    /// geometry or failing the next item halfway through a transaction.
    @MainActor
    static func resolvePair(
        sourceFrame: () -> CGRect?, sourcePID: pid_t,
        destinationFrame: () -> CGRect?, destinationPID: pid_t,
        readWindows: () -> [MenuBarNativeWindow] = { currentWindows() },
        wait: () async -> Void = { try? await Task.sleep(for: .milliseconds(50)) }
    ) async -> (source: MenuBarNativeWindow, destination: MenuBarNativeWindow)? {
        for attempt in 0..<10 {
            guard !Task.isCancelled else { return nil }
            let windows = readWindows()
            if let sourceAX = sourceFrame(), let destinationAX = destinationFrame(),
               let source = match(axFrame: sourceAX, clientPID: sourcePID, windows: windows),
               let destination = match(axFrame: destinationAX, clientPID: destinationPID, windows: windows) {
                return (source, destination)
            }
            if attempt < 9 { await wait() }
        }
        return nil
    }

    @MainActor
    static func currentWindows(
        readWindowInfo: (CGWindowListOption) -> [[String: Any]] = {
            CGWindowListCopyWindowInfo($0, kCGNullWindowID) as? [[String: Any]] ?? []
        },
        ownerBundleID: (pid_t) -> String? = {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
    ) -> [MenuBarNativeWindow] {
        // macOS 26 can composite the menu bar while its individual Control
        // Center-hosted status windows are not marked on-screen. They still
        // own the live AX items and receive native drag events. Match the full
        // list against live AX geometry/owner/layer; do not infer visibility
        // from CGWindowIsOnscreen (or lose every draggable window).
        let windows = readWindowInfo(.optionAll)
        return windows.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return MenuBarNativeWindow(
                id: id, pid: pid, layer: layer, frame: frame,
                ownerBundleID: ownerBundleID(pid)
            )
        }
    }

    static func match(
        axFrame: CGRect,
        clientPID: pid_t,
        windows: [MenuBarNativeWindow]
    ) -> MenuBarNativeWindow? {
        guard hasStatusSize(axFrame), clientPID > 0 else { return nil }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let matches = windows.filter { window in
            window.layer == statusLayer
                && (window.pid == clientPID || window.ownerBundleID == "com.apple.controlcenter")
                && hasStatusSize(window.frame)
                && abs(window.frame.midX - axFrame.midX) <= 3
                && abs(window.frame.midY - axFrame.midY) <= 5
                && abs(window.frame.width - axFrame.width) <= 16
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func hasStatusSize(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite
            && frame.width > 0 && frame.width <= 1024
            && frame.height > 0 && frame.height <= 100
    }
}
