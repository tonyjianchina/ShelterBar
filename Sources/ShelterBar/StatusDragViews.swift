import AppKit
import SwiftUI

/// Tracks the user's mouse within the source view. Returning an item changes
/// ShelterBar's placement; it does not drop data into another application.
struct ShelfIcon: NSViewRepresentable {
    let item: ShelfItem
    let onActivate: () -> Void
    let onReturn: (String, CGPoint) -> Void
    let onReorder: (String, String) -> Void
    let onDragging: (Bool) -> Void
    let onDragPosition: (String, CGPoint) -> Void

    func makeNSView(context: Context) -> ShelfIconView { ShelfIconView() }
    func updateNSView(_ view: ShelfIconView, context: Context) {
        view.item = item
        view.onActivate = onActivate
        view.onReturn = onReturn
        view.onReorder = onReorder
        view.onDragging = onDragging
        view.onDragPosition = onDragPosition
        view.toolTip = "\(item.title) · 拖到顶部菜单栏可移回"
        view.setAccessibilityLabel(item.title)
        view.needsDisplay = true
    }
}

@MainActor
final class ShelfIconView: NSView {
    var item: ShelfItem?
    var onActivate: (() -> Void)?
    var onReturn: ((String, CGPoint) -> Void)?
    var onReorder: ((String, String) -> Void)?
    var onDragging: ((Bool) -> Void)?
    var onDragPosition: ((String, CGPoint) -> Void)?
    var isSafeDrop: @MainActor (CGPoint) -> Bool = MenuBarGeometry.isSafeDrop
    var reorderTargetAtPoint: (@MainActor (CGPoint) -> String?)?
    private var trackedItemID: String?
    private var didDrag = false
    private var downPoint = CGPoint.zero

    init() {
        super.init(frame: .zero)
        setAccessibilityRole(.button)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let item { MenuBarIconPresentation.draw(item.icon, in: bounds) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = quartzPoint(for: event) else { return }
        window?.makeFirstResponder(self)
        beginPointerTracking(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = quartzPoint(for: event) else { cancelOperation(nil); return }
        continuePointerTracking(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard let point = quartzPoint(for: event) else { cancelOperation(nil); return }
        endPointerTracking(at: point, isInsideSource: containsQuartzPoint(point))
    }
    override func accessibilityPerformPress() -> Bool { onActivate?(); return true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, trackedItemID != nil { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        guard trackedItemID != nil else { return }
        clearPointerTracking()
    }

    override func resignFirstResponder() -> Bool {
        cancelOperation(nil)
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { cancelOperation(nil) }
        super.viewWillMove(toWindow: newWindow)
    }

    // This is the same policy seam used by the real NSView event adapters and
    // regression tests. All points here are in top-left Quartz coordinates.
    func beginPointerTracking(at point: CGPoint) {
        cancelOperation(nil)
        trackedItemID = item?.id
        downPoint = point
        didDrag = false
    }

    @discardableResult
    func continuePointerTracking(at point: CGPoint) -> Bool {
        guard let id = trackedItemID else { return false }
        let beganDragging = !didDrag && hypot(point.x - downPoint.x, point.y - downPoint.y) > 4
        if beganDragging {
            didDrag = true
            onDragging?(true)
        }
        if didDrag { onDragPosition?(id, point) }
        return beganDragging
    }

    func endPointerTracking(at point: CGPoint, isInsideSource: Bool) {
        guard let id = trackedItemID else { return }
        let wasDragging = didDrag
        clearPointerTracking()
        if wasDragging {
            if isSafeDrop(point) { onReturn?(id, point) }
            else if let target = reorderTargetAtPoint?(point) ?? shelfItem(at: point), target != id {
                onReorder?(id, target)
            }
        } else if isInsideSource {
            onActivate?()
        }
    }

    private func clearPointerTracking() {
        trackedItemID = nil
        didDrag = false
        onDragging?(false)
    }

    private func quartzPoint(for event: NSEvent) -> CGPoint? {
        guard let eventWindow = event.window ?? window else { return nil }
        let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
        return CGPoint(x: point.x, y: MenuBarGeometry.desktopTop - point.y)
    }

    private func windowPoint(from point: CGPoint) -> CGPoint? {
        window?.convertPoint(fromScreen: CGPoint(x: point.x, y: MenuBarGeometry.desktopTop - point.y))
    }

    private func containsQuartzPoint(_ point: CGPoint) -> Bool {
        guard let point = windowPoint(from: point) else { return false }
        return visibleRect.contains(convert(point, from: nil))
    }

    private func shelfItem(at point: CGPoint) -> String? {
        guard let point = windowPoint(from: point), let content = window?.contentView else { return nil }
        var target = content.hitTest(point)
        while let view = target {
            if let icon = view as? ShelfIconView { return icon.item?.id }
            target = view.superview
        }
        return nil
    }
}
