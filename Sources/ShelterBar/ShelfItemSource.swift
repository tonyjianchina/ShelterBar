import AppKit
import ApplicationServices

@MainActor
final class MenuBarItemReference {
    let pid: pid_t
    let element: AXUIElement
    var frame: CGRect

    init(pid: pid_t, element: AXUIElement, frame: CGRect) {
        self.pid = pid
        self.element = element
        self.frame = frame
    }

    @discardableResult
    func press() -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    func currentFrame() -> CGRect? { MenuBarAX.frame(of: element) }
}

struct ShelfItem: Identifiable {
    let id: String
    let title: String
    let icon: NSImage
    let application: NSRunningApplication?
    let menuBarReference: MenuBarItemReference
    var hasPersistentIdentity = true
    var isMovable = true
}

@MainActor
protocol ShelfItemSource {
    func items() -> [ShelfItem]
}

@MainActor
struct AccessibilityMenuBarItemSource: ShelfItemSource {
    func items() -> [ShelfItem] {
        guard AXIsProcessTrusted() else { return [] }

        var output: [ShelfItem] = []
        var usedIDs = Set<String>()

        for application in NSWorkspace.shared.runningApplications where shouldInspect(application) {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.08)
            guard let extrasMenuBar: AXUIElement = attribute(kAXExtrasMenuBarAttribute, of: appElement) else {
                continue
            }

            var candidates: [AXUIElement] = []
            collectMenuBarItems(from: extrasMenuBar, depth: 0, into: &candidates)
            let identifierCounts = Dictionary(
                candidates.compactMap { firstNonemptyAttribute([kAXIdentifierAttribute], of: $0) }
                    .map { ($0, 1) }, uniquingKeysWith: +
            )
            for element in candidates {
                guard let frame = frame(of: element), frame.width > 1, frame.height > 1 else { continue }

                let rawTitle = firstNonemptyAttribute(
                    [kAXTitleAttribute, kAXHelpAttribute, kAXDescriptionAttribute],
                    of: element
                )
                let appName = application.localizedName ?? "菜单栏项"
                let title = rawTitle ?? appName
                let axIdentifier = firstNonemptyAttribute([kAXIdentifierAttribute], of: element)
                let uniqueIdentifier = axIdentifier.flatMap { identifierCounts[$0] == 1 ? $0 : nil }
                let persistent = uniqueIdentifier != nil || candidates.count == 1
                let identifier = uniqueIdentifier ?? (candidates.count == 1
                    ? "main" : "session-\(application.processIdentifier)-\(CFHash(element))")
                let owner = application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
                let id = "ax:\(owner):\(identifier)"
                guard usedIDs.insert(id).inserted else { continue }

                let icon = (application.icon?.copy() as? NSImage) ?? NSImage(
                    systemSymbolName: "menubar.rectangle",
                    accessibilityDescription: title
                )!
                icon.size = NSSize(width: 32, height: 32)
                output.append(ShelfItem(
                    id: id,
                    title: title,
                    icon: icon,
                    application: application,
                    menuBarReference: MenuBarItemReference(
                        pid: application.processIdentifier,
                        element: element,
                        frame: frame
                    ),
                    hasPersistentIdentity: persistent,
                    isMovable: ![
                        "com.apple.menuextra.clock",
                        "com.apple.menuextra.controlcenter",
                        "com.apple.menuextra.audiovideo"
                    ].contains(axIdentifier ?? "")
                ))
            }
        }

        return output.sorted { left, right in
            if left.menuBarReference.frame.minX != right.menuBarReference.frame.minX {
                return left.menuBarReference.frame.minX < right.menuBarReference.frame.minX
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    private func shouldInspect(_ application: NSRunningApplication) -> Bool {
        !application.isTerminated
            && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && application.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    private func collectMenuBarItems(
        from element: AXUIElement,
        depth: Int,
        into output: inout [AXUIElement]
    ) {
        guard depth <= 4 else { return }
        AXUIElementSetMessagingTimeout(element, 0.08)
        let role: String? = attribute(kAXRoleAttribute, of: element)
        if role == (kAXMenuBarItemRole as String) {
            output.append(element)
            return
        }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute, of: element) ?? []
        for child in children {
            collectMenuBarItems(from: child, depth: depth + 1, into: &output)
        }
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        MenuBarAX.frame(of: element)
    }

    private func firstNonemptyAttribute(
        _ names: [String],
        of element: AXUIElement
    ) -> String? {
        for name in names {
            if let value: String = attribute(name, of: element) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}

@MainActor
enum MenuBarAX {
    static func value<T>(_ name: String, of element: AXUIElement) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as? T
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let p: AXValue = value(kAXPositionAttribute, of: element),
              let s: AXValue = value(kAXSizeAttribute, of: element),
              AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func ownItemFrame(help: String) -> CGRect? {
        let app = AXUIElementCreateApplication(getpid())
        guard let bar: AXUIElement = value(kAXExtrasMenuBarAttribute, of: app),
              let children: [AXUIElement] = value(kAXChildrenAttribute, of: bar) else { return nil }
        return children.first(where: {
            let text: String? = value(kAXHelpAttribute, of: $0)
            return text == help
        }).flatMap { frame(of: $0) }
    }
}
