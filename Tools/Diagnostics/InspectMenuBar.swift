import AppKit
import ApplicationServices

@main
struct InspectMenuBar {
    @MainActor
    static func main() {
        print("AX trusted: \(AXIsProcessTrusted())")
        for screen in NSScreen.screens {
            print("SCREEN \(screen.frame) safe=\(screen.safeAreaInsets) right=\(String(describing: screen.auxiliaryTopRightArea))")
        }
        let windows = MenuBarNativeWindow.currentWindows()
        for window in windows where window.layer == Int(CGWindowLevelForKey(.statusWindow)) {
            print("NATIVE \(window.id) pid=\(window.pid) owner=\(window.ownerBundleID ?? "?") frame=\(window.frame)")
        }
        for app in NSWorkspace.shared.runningApplications {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            guard let bar: AXUIElement = value(kAXExtrasMenuBarAttribute, element) else { continue }
            inspect(bar, app: app, windows: windows, depth: 0)
        }
    }

    @MainActor
    static func inspect(_ element: AXUIElement, app: NSRunningApplication, windows: [MenuBarNativeWindow], depth: Int) {
        guard depth < 5 else { return }
        if let role: String = value(kAXRoleAttribute, element), role == kAXMenuBarItemRole,
           let p: AXValue = value(kAXPositionAttribute, element), let s: AXValue = value(kAXSizeAttribute, element) {
            var point = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(p, .cgPoint, &point)
            AXValueGetValue(s, .cgSize, &size)
            let frame = CGRect(origin: point, size: size)
            let title: String = value(kAXTitleAttribute, element) ?? value(kAXHelpAttribute, element) ?? value(kAXDescriptionAttribute, element) ?? ""
            let identifier: String = value(kAXIdentifierAttribute, element) ?? ""
            let match = MenuBarNativeWindow.match(axFrame: frame, clientPID: app.processIdentifier, windows: windows)
            print("AX \(app.localizedName ?? "?") pid=\(app.processIdentifier) id=\(identifier) title=\(title) frame=\(frame) MATCH=\(match.map { String($0.id) } ?? "NONE")")
            return
        }
        let children: [AXUIElement] = value(kAXChildrenAttribute, element) ?? []
        for child in children { inspect(child, app: app, windows: windows, depth: depth + 1) }
    }

    static func value<T>(_ name: String, _ element: AXUIElement) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as? T
    }
}
