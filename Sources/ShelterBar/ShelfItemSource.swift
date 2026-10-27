import AppKit
import ApplicationServices

final class MenuBarItemReference: @unchecked Sendable {
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

struct ShelfItem: Identifiable, @unchecked Sendable {
    let id: String
    let title: String
    var icon: NSImage
    let application: NSRunningApplication?
    let menuBarReference: MenuBarItemReference
    var hasPersistentIdentity = true
    var isMovable = true
    var hasMenuBarIcon = false

    /// Read the status item's own title, not the app-name fallback (which can
    /// legitimately contain a digit, such as 1Password).
    @MainActor var hasNumericTitle: Bool {
        let title: String? = MenuBarAX.value(kAXTitleAttribute, of: menuBarReference.element)
        return title?.contains(where: \.isNumber) == true
    }

    /// ScreenCaptureKit can temporarily add this macOS 27 system item while
    /// reading a glyph. Its natural disappearance is not a lost resident app.
    /// Match the owning bundle as well as the AX identifier: an unrelated
    /// app or another system item must still participate in layout checks.
    var isTransientCaptureIndicator: Bool {
        !isMovable && id == "ax:com.apple.MenuBarAgent:com.apple.menuextra.audiovideo"
    }
}

struct ShelfItemScanResult: Sendable {
    let items: [ShelfItem]
    let isComplete: Bool
}

protocol ShelfItemSource: Sendable {
    func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult
}

extension ShelfItemSource {
    func items() -> [ShelfItem] {
        items(deadline: .now + .seconds(5)).items
    }
}

struct AccessibilityMenuBarItemSource: ShelfItemSource, @unchecked Sendable {
    private let placeholderImage: NSImage

    @MainActor
    init() {
        placeholderImage = MenuBarIconPresentation.placeholder()
    }

    func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult {
        guard AXIsProcessTrusted() else { return ShelfItemScanResult(items: [], isComplete: true) }

        var output: [ShelfItem] = []
        var usedIDs = Set<String>()

        for application in NSWorkspace.shared.runningApplications where shouldInspect(application) {
            guard ContinuousClock.now < deadline else { break }
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.08)
            guard let extrasMenuBar: AXUIElement = attribute(kAXExtrasMenuBarAttribute, of: appElement) else {
                continue
            }

            var candidates: [AXUIElement] = []
            collectMenuBarItems(from: extrasMenuBar, depth: 0, deadline: deadline, into: &candidates)
            let identifierCounts = Dictionary(
                candidates.compactMap {
                    firstNonemptyAttribute([kAXIdentifierAttribute], of: $0, deadline: deadline)
                }
                    .map { ($0, 1) }, uniquingKeysWith: +
            )
            for element in candidates {
                guard ContinuousClock.now < deadline else { break }
                guard let frame = frame(of: element, deadline: deadline),
                      frame.width > 1, frame.height > 1 else { continue }

                let rawTitle = firstNonemptyAttribute(
                    [kAXTitleAttribute, kAXHelpAttribute, kAXDescriptionAttribute],
                    of: element,
                    deadline: deadline
                )
                let appName = application.localizedName ?? "菜单栏项"
                let title = rawTitle ?? appName
                let axIdentifier = firstNonemptyAttribute(
                    [kAXIdentifierAttribute], of: element, deadline: deadline
                )
                let uniqueIdentifier = axIdentifier.flatMap { identifierCounts[$0] == 1 ? $0 : nil }
                let persistent = uniqueIdentifier != nil || candidates.count == 1
                let identifier = uniqueIdentifier ?? (candidates.count == 1
                    ? "main" : "session-\(application.processIdentifier)-\(CFHash(element))")
                let owner = application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
                let id = "ax:\(owner):\(identifier)"
                guard usedIDs.insert(id).inserted else { continue }

                output.append(ShelfItem(
                    id: id, title: title, icon: placeholderImage,
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
                        && (ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27
                            || MenuBarCollectionCapability.supports(
                                bundleID: application.bundleIdentifier,
                                ownBundleID: "com.jensen.shelterbar"
                            ))
                ))
            }
        }

        let sorted = output.sorted { left, right in
            if left.menuBarReference.frame.minX != right.menuBarReference.frame.minX {
                return left.menuBarReference.frame.minX < right.menuBarReference.frame.minX
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
        return ShelfItemScanResult(items: sorted, isComplete: ContinuousClock.now < deadline)
    }

    private func shouldInspect(_ application: NSRunningApplication) -> Bool {
        !application.isTerminated
            && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            && application.bundleIdentifier != Bundle.main.bundleIdentifier
    }

    private func collectMenuBarItems(
        from element: AXUIElement,
        depth: Int,
        deadline: ContinuousClock.Instant,
        into output: inout [AXUIElement]
    ) {
        guard depth <= 4, ContinuousClock.now < deadline else { return }
        AXUIElementSetMessagingTimeout(element, 0.08)
        let role: String? = attribute(kAXRoleAttribute, of: element)
        if role == (kAXMenuBarItemRole as String) {
            output.append(element)
            return
        }
        guard ContinuousClock.now < deadline else { return }
        let children: [AXUIElement] = attribute(kAXChildrenAttribute, of: element) ?? []
        for child in children {
            guard ContinuousClock.now < deadline else { return }
            collectMenuBarItems(from: child, depth: depth + 1, deadline: deadline, into: &output)
        }
    }

    private func frame(of element: AXUIElement, deadline: ContinuousClock.Instant) -> CGRect? {
        guard ContinuousClock.now < deadline else { return nil }
        var position: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &position
        ) == .success, ContinuousClock.now < deadline else { return nil }
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &size
        ) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let p = unsafeDowncast(position, to: AXValue.self)
        let s = unsafeDowncast(size, to: AXValue.self)
        guard
              AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point),
              AXValueGetValue(s, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func firstNonemptyAttribute(
        _ names: [String],
        of element: AXUIElement,
        deadline: ContinuousClock.Instant
    ) -> String? {
        for name in names {
            guard ContinuousClock.now < deadline else { return nil }
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

enum MenuBarAX {
    nonisolated static func value<T>(_ name: String, of element: AXUIElement) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as? T
    }

    nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        guard let p: AXValue = value(kAXPositionAttribute, of: element),
              let s: AXValue = value(kAXSizeAttribute, of: element),
              AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    nonisolated static func ownItemFrame(help: String) -> CGRect? {
        let app = AXUIElementCreateApplication(getpid())
        guard let bar: AXUIElement = value(kAXExtrasMenuBarAttribute, of: app),
              let children: [AXUIElement] = value(kAXChildrenAttribute, of: bar) else { return nil }
        return children.first(where: {
            let text: String? = value(kAXHelpAttribute, of: $0)
            return text == help
        }).flatMap { frame(of: $0) }
    }
}
