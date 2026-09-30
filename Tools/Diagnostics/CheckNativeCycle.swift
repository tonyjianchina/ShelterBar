import AppKit
import ApplicationServices

// Run with a running third-party app's bundle ID. Requires ShelterBar open
// with an empty shelf. Uses ordinary mouse input and checks actual AX positions
// and UI membership, rather than calling the engine or changing preferences.
@main
struct CheckNativeCycle {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2,
              let target = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first,
              let shelter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jensen.shelterbar").first
        else { fail("Both ShelterBar and the target app must be running.") }
        let targetAX = AXUIElementCreateApplication(target.processIdentifier)
        let shelterAX = AXUIElementCreateApplication(shelter.processIdentifier)
        guard let sourceItem = menuItems(targetAX).first, let initial = frame(sourceItem),
              isVisible(initial), let handle = menuItems(shelterAX).first
        else { fail("Target must have one visible menu-bar item.") }
        if shelfWindow(shelterAX) == nil { AXUIElementPerformAction(handle, kAXPressAction as CFString) }
        guard awaitCondition({ shelfWindow(shelterAX) != nil && shelfCount(shelterAX) == 0 }),
              let panel = shelfWindow(shelterAX).flatMap(frame), let liveSource = frame(sourceItem)
        else { fail("Start with an empty open shelf.") }
        guard !texts(shelterAX).contains(where: { $0.contains("允许辅助功能") })
        else { fail("Installed ShelterBar requires Accessibility authorization.") }
        print("BEFORE source=\(liveSource) shelf=0")
        drag(from: CGPoint(x: liveSource.midX, y: liveSource.midY),
             to: CGPoint(x: panel.midX, y: panel.midY))
        guard awaitCondition({ shelfCount(shelterAX) == 1 && frame(sourceItem).map { !isVisible($0) } == true })
        else { fail("Collection did not hide the real icon and show one shelf item. \(texts(shelterAX))") }
        print("COLLECTED source=\(String(describing: frame(sourceItem))) shelf=1")
        // Let several polling cycles run; a stale helper must not be adopted.
        Thread.sleep(forTimeInterval: 4.5)
        guard shelfCount(shelterAX) == 1, let window = shelfWindow(shelterAX),
              let scroll = descendants(window).first(where: { role($0) == kAXScrollAreaRole }),
              let scrollFrame = frame(scroll), let boundary = frame(handle)
        else { fail("Collection did not remain stable through background polling. \(texts(shelterAX))") }
        drag(from: CGPoint(x: scrollFrame.minX + 24, y: scrollFrame.midY),
             to: CGPoint(x: boundary.maxX + 40, y: initial.midY))
        guard awaitCondition({ shelfCount(shelterAX) == 0 && frame(sourceItem).map(isVisible) == true })
        else { fail("Returning did not restore the real icon and empty the shelf. \(texts(shelterAX))") }
        print("RETURNED source=\(String(describing: frame(sourceItem))) shelf=0")
        print("PASS native collect → polling → return: \(target.localizedName ?? "target")")
    }

    static func value<T>(_ name: String, _ element: AXUIElement) -> T? {
        var out: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &out) == .success else { return nil }
        return out as? T
    }
    static func role(_ element: AXUIElement) -> String { value(kAXRoleAttribute, element) ?? "" }
    static func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 8 else { return [] }
        let children: [AXUIElement] = value(kAXChildrenAttribute, element) ?? []
        return children.flatMap { [$0] + descendants($0, depth: depth + 1) }
    }
    static func menuItems(_ app: AXUIElement) -> [AXUIElement] {
        guard let bar: AXUIElement = value(kAXExtrasMenuBarAttribute, app) else { return [] }
        return descendants(bar).filter { role($0) == kAXMenuBarItemRole }
    }
    static func shelfWindow(_ app: AXUIElement) -> AXUIElement? {
        let windows: [AXUIElement] = value(kAXWindowsAttribute, app) ?? []
        return windows.first { value(kAXTitleAttribute, $0) as String? == "ShelterBar 收纳栏" }
    }
    static func texts(_ app: AXUIElement) -> [String] {
        guard let window = shelfWindow(app) else { return [] }
        return descendants(window).filter { role($0) == kAXStaticTextRole }.compactMap { value(kAXValueAttribute, $0) }
    }
    static func shelfCount(_ app: AXUIElement) -> Int? { texts(app).compactMap(Int.init).first }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p: AXValue = value(kAXPositionAttribute, element), let s: AXValue = value(kAXSizeAttribute, element) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    @MainActor
    static func isVisible(_ frame: CGRect) -> Bool {
        let top = NSScreen.screens.first!.frame.maxY
        return NSScreen.screens.contains { screen in
            let row = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY,
                width: screen.frame.width, height: max(32, screen.safeAreaInsets.top))
            return row.intersects(frame) && frame.maxX > row.minX
        }
    }
    static func awaitCondition(_ condition: () -> Bool) -> Bool {
        for _ in 0..<80 {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
    static func drag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)!
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                mouseCursorPosition: point, mouseButton: .left)!
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, start)
        Thread.sleep(forTimeInterval: 0.1)
        post(.leftMouseDown, start)
        Thread.sleep(forTimeInterval: 0.1)
        for step in 1...20 {
            let t = Double(step) / 20
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            Thread.sleep(forTimeInterval: 0.035)
        }
        post(.leftMouseUp, end)
    }
    static func fail(_ message: String) -> Never { print("FAIL: \(message)"); exit(1) }
}
