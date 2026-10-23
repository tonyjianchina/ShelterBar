import AppKit
import ApplicationServices

/// One ordinary drag into the installed app, with a required final shelf count.
/// Usage: CheckNativeCollection <bundle-id> <expected-count> [repeat-count]
/// Repeat mode temporarily reveals the menu bar before each collection.
@main
struct CheckNativeCollection {
    @MainActor
    static func main() {
        do { try run() }
        catch { print("FAIL: \(error.localizedDescription)"); exit(1) }
    }

    @MainActor
    static func run() throws {
        guard AXIsProcessTrusted(), (3...4).contains(CommandLine.arguments.count),
              let expected = Int(CommandLine.arguments[2]),
              let target = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first,
              let shelter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jensen.shelterbar").first
        else { throw Failure("Requires existing Accessibility access, running apps, bundle ID and expected count.") }
        // User-requested scope: never drag system recording indicators, the
        // menu-bar overflow arrow, or arbitrary items selected by coordinates.
        let allowedTargets: Set<String> = [
            "com.electron.ollama", "com.openai.codex", "com.netease.uuremote", "com.meta.endo",
        ]
        guard let bundleID = target.bundleIdentifier, allowedTargets.contains(bundleID) else {
            throw Failure("Only Ollama, Codex, UU Remote and Muse are permitted test targets.")
        }
        let repeats = CommandLine.arguments.count == 4 ? Int(CommandLine.arguments[3]) ?? 1 : 1
        guard (1...20).contains(repeats) else { throw Failure("Repeat count must be 1...20.") }
        let targetAX = AXUIElementCreateApplication(target.processIdentifier)
        let shelterAX = AXUIElementCreateApplication(shelter.processIdentifier)
        var pinnedForTest = false
        defer {
            if pinnedForTest, let window = shelfWindow(shelterAX),
               let pin = descendants(window).first(where: { value(kAXHelpAttribute, $0) as String? == "取消固定" }) {
                AXUIElementPerformAction(pin, kAXPressAction as CFString)
            }
        }
        for iteration in 1...repeats {
            guard let handle = menuItems(shelterAX).first(where: {
                value(kAXIdentifierAttribute, $0) as String? == "shelterbar.handle"
            }) else { throw Failure("ShelterBar handle is unavailable.") }
            if shelfWindow(shelterAX) == nil { AXUIElementPerformAction(handle, kAXPressAction as CFString) }
            guard awaitCondition({ shelfWindow(shelterAX) != nil }) else { throw Failure("Shelf did not open.") }
            if let window = shelfWindow(shelterAX),
               let pin = descendants(window).first(where: { value(kAXHelpAttribute, $0) as String? == "固定收纳栏" }) {
                AXUIElementPerformAction(pin, kAXPressAction as CFString)
                pinnedForTest = true
            }
            if CommandLine.arguments.count == 4 {
                guard let window = shelfWindow(shelterAX),
                      let more = descendants(window).first(where: { value(kAXRoleAttribute, $0) as String? == kAXMenuButtonRole })
                else { throw Failure("Cannot find shelf menu.") }
                AXUIElementPerformAction(more, kAXPressAction as CFString)
                var reveal: AXUIElement?
                guard awaitCondition({
                    reveal = (descendants(more) + descendants(shelterAX)).first {
                        value(kAXTitleAttribute, $0) as String? == "显示全部顶部图标"
                    }
                    return reveal != nil
                }), let reveal else { throw Failure("Cannot find reveal command.") }
                AXUIElementPerformAction(reveal, kAXPressAction as CFString)
                guard awaitCondition({ texts(shelterAX).compactMap(Int.init).first == 0 })
                else { throw Failure("Reveal failed at iteration \(iteration): \(texts(shelterAX))") }
                Thread.sleep(forTimeInterval: 0.3)
            }
            guard let source = menuItems(targetAX).first,
                  let panel = shelfWindow(shelterAX).flatMap(frame), let liveSource = frame(source)
            else { throw Failure("Source or shelf frame is unavailable.") }
            let pickup = CGPoint(x: liveSource.midX, y: liveSource.midY)
            // AX frames can be stale while MenuBarAgent animates. Refuse a
            // pickup overlapping any exposed system control, even if the
            // requested application's cached frame still points there.
            for app in NSWorkspace.shared.runningApplications
                where app.bundleIdentifier?.hasPrefix("com.apple.") == true {
                let appAX = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(appAX, 0.1)
                if menuItems(appAX).contains(where: { frame($0)?.contains(pickup) == true }) {
                    throw Failure("Target overlaps a system control; no drag was sent.")
                }
            }
            print("BEFORE target=\(target.bundleIdentifier ?? "?") frame=\(liveSource) shelf=\(texts(shelterAX))")
            drag(from: pickup, to: CGPoint(x: panel.midX, y: panel.midY))
            let passed = awaitCondition {
                texts(shelterAX).compactMap(Int.init).first == expected && !hasFailure(shelterAX)
            }
            guard passed else { throw Failure("Expected shelf count \(expected); actual UI: \(texts(shelterAX))") }
            Thread.sleep(forTimeInterval: 2.5)
            guard texts(shelterAX).compactMap(Int.init).first == expected, !hasFailure(shelterAX)
            else { throw Failure("Collection did not survive polling: \(texts(shelterAX))") }
            print("PASS iteration=\(iteration) collection \(target.bundleIdentifier ?? "?") shelf=\(expected) after polling")
        }
    }

    static func value<T>(_ name: String, _ element: AXUIElement) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as? T
    }
    static func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 8 else { return [] }
        let children: [AXUIElement] = value(kAXChildrenAttribute, element) ?? []
        return children.flatMap { [$0] + descendants($0, depth: depth + 1) }
    }
    static func menuItems(_ app: AXUIElement) -> [AXUIElement] {
        guard let bar: AXUIElement = value(kAXExtrasMenuBarAttribute, app) else { return [] }
        return descendants(bar).filter { value(kAXRoleAttribute, $0) as String? == kAXMenuBarItemRole }
    }
    static func shelfWindow(_ app: AXUIElement) -> AXUIElement? {
        let windows: [AXUIElement] = value(kAXWindowsAttribute, app) ?? []
        return windows.first { value(kAXTitleAttribute, $0) as String? == "ShelterBar 收纳栏" }
    }
    static func texts(_ app: AXUIElement) -> [String] {
        guard let window = shelfWindow(app) else { return [] }
        return descendants(window).filter { value(kAXRoleAttribute, $0) as String? == kAXStaticTextRole }
            .compactMap { value(kAXValueAttribute, $0) }
    }
    static func hasFailure(_ app: AXUIElement) -> Bool {
        texts(app).contains { $0.contains("系统没有完成布局调整") || $0.contains("未能收纳") }
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p: AXValue = value(kAXPositionAttribute, element),
              let s: AXValue = value(kAXSizeAttribute, element) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
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
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t,
                                           y: start.y + (end.y - start.y) * t))
            Thread.sleep(forTimeInterval: 0.035)
        }
        post(.leftMouseUp, end)
    }
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
