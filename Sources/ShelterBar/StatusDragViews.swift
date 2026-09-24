import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    static let shelterItem = Self("com.jensen.shelterbar.item")
}

/// AppKit gives us the release position even if the destination is another
/// process's status bar, which cannot accept a SwiftUI dropDestination.
struct ShelfIcon: NSViewRepresentable {
    let item: ShelfItem
    let onActivate: () -> Void
    let onReturn: (String, CGPoint) -> Void
    let onReorder: (String, String) -> Void
    let onDragging: (Bool) -> Void

    func makeNSView(context: Context) -> ShelfIconView { ShelfIconView() }
    func updateNSView(_ view: ShelfIconView, context: Context) {
        view.item = item
        view.onActivate = onActivate
        view.onReturn = onReturn
        view.onReorder = onReorder
        view.onDragging = onDragging
        view.toolTip = "\(item.title) · 拖到顶部菜单栏可移回"
        view.setAccessibilityLabel(item.title)
        view.needsDisplay = true
    }
}

@MainActor
final class ShelfIconView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var onActivate: (() -> Void)?
    var onReturn: ((String, CGPoint) -> Void)?
    var onReorder: ((String, String) -> Void)?
    var onDragging: ((Bool) -> Void)?
    private var didDrag = false
    private var downPoint = CGPoint.zero
    private var escapeMonitor: Any?
    private var cancelled = false

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.shelterItem])
        setAccessibilityRole(.button)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        item?.icon.draw(in: bounds.insetBy(dx: 7, dy: 7),
                        from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: nil)
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let item,
              hypot(event.locationInWindow.x - downPoint.x, event.locationInWindow.y - downPoint.y) > 4 else { return }
        didDrag = true
        cancelled = false
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.cancelled = true }
            }
            return event
        }
        onDragging?(true)
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(item.id, forType: .shelterItem)
        let drag = NSDraggingItem(pasteboardWriter: pasteboard)
        drag.setDraggingFrame(bounds.insetBy(dx: 7, dy: 7), contents: item.icon)
        let session = beginDraggingSession(with: [drag], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag, bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?() }
    }
    override func accessibilityPerformPress() -> Bool { onActivate?(); return true }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint, operation: NSDragOperation) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        onDragging?(false)
        guard let item else { return }
        let quartzPoint = CGPoint(x: point.x, y: MenuBarGeometry.desktopTop - point.y)
        // Escape ends a session at the current pointer too; never treat that as a drop.
        if !cancelled, MenuBarGeometry.isSafeDrop(quartzPoint) { onReturn?(item.id, quartzPoint) }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: .shelterItem) == nil ? [] : .move
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let id = sender.draggingPasteboard.string(forType: .shelterItem), let item else { return false }
        onReorder?(id, item.id)
        return true
    }
}
