import AppKit

/// The native status window can include padding absent from its AX item.
/// On recent macOS versions Control Center may host another app's status item.
struct MenuBarNativeWindow: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let frame: CGRect
    let ownerBundleID: String?

    @MainActor
    static func currentWindows() -> [MenuBarNativeWindow] {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return windows.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return MenuBarNativeWindow(
                id: id, pid: pid, layer: layer, frame: frame,
                ownerBundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
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
