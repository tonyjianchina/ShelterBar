import AppKit
import ApplicationServices
import Testing
@testable import ShelterBar

@MainActor
private func iconInteractionView(_ id: String = "vpn") -> ShelfIconView {
    let view = ShelfIconView()
    view.item = ShelfItem(
        id: id, title: id, icon: NSImage(), application: nil,
        menuBarReference: MenuBarItemReference(
            pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: 800, y: 5, width: 24, height: 24)
        )
    )
    view.isSafeDrop = { $0.y < 30 }
    return view
}

@MainActor
private func iconInteractionWindow() -> (NSWindow, ShelfIconView) {
    let window = NSWindow(contentRect: CGRect(x: 400, y: 400, width: 200, height: 100),
                          styleMask: [.borderless], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    let content = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
    window.contentView = content
    let view = iconInteractionView()
    view.frame = CGRect(x: 20, y: 20, width: 32, height: 36)
    content.addSubview(view)
    // This window is never shown. NSEvents below are delivered directly to
    // the actual view methods; nothing is posted to the user's event stream.
    return (window, view)
}

@MainActor
private func pointerEvent(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                      windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                      clickCount: 1, pressure: 1)!
}

@MainActor
private func escapeEvent(window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
}

@Test("Escape at a valid menu bar destination never returns or activates the shelf item")
@MainActor
func shelfPointerEscapeCannotCommitReturn() {
    let view = iconInteractionView()
    var returned: [String] = []
    var activated = 0
    var dragging: [Bool] = []
    view.onReturn = { id, _ in returned.append(id) }
    view.onActivate = { activated += 1 }
    view.onDragging = { dragging.append($0) }

    view.beginPointerTracking(at: CGPoint(x: 888, y: 131))
    view.continuePointerTracking(at: CGPoint(x: 888, y: 1.5))
    // This is the same responder cancellation entry point used by Escape.
    // The completion point remains inside a valid menu bar destination.
    if view.responds(to: #selector(NSResponder.cancelOperation(_:))) {
        view.cancelOperation(nil)
    }
    view.endPointerTracking(at: CGPoint(x: 888, y: 1.5), isInsideSource: false)

    #expect(returned.isEmpty)
    #expect(activated == 0)
    #expect(dragging == [true, false])
}

@Test("an ordinary NSView mouse-up returns a dragged item exactly once without a system drag session")
@MainActor
func shelfPointerMouseUpReturnsExactlyOnce() {
    let (window, view) = iconInteractionWindow()
    defer { window.close() }
    let destination = CGPoint(x: 36, y: 150)
    let screenPoint = window.convertPoint(toScreen: destination)
    let expectedPoint = CGPoint(x: screenPoint.x, y: MenuBarGeometry.desktopTop - screenPoint.y)
    var returns: [CGPoint] = []
    var dragging: [Bool] = []
    var ghost: [CGPoint] = []
    view.isSafeDrop = { $0 == expectedPoint }
    view.onReturn = { _, point in returns.append(point) }
    view.onDragging = { dragging.append($0) }
    view.onDragPosition = { _, point in ghost.append(point) }

    view.mouseDown(with: pointerEvent(.leftMouseDown, at: CGPoint(x: 36, y: 38), window: window))
    view.mouseDragged(with: pointerEvent(.leftMouseDragged, at: destination, window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: destination, window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: destination, window: window))

    #expect(returns == [expectedPoint])
    #expect(ghost == [expectedPoint])
    #expect(dragging == [true, false])
}

@Test("small movement inside the source remains a single click")
@MainActor
func shelfPointerSmallMovementRemainsClick() {
    let (window, view) = iconInteractionWindow()
    defer { window.close() }
    var activated = 0
    var returned = 0
    var dragging: [Bool] = []
    view.onActivate = { activated += 1 }
    view.onReturn = { _, _ in returned += 1 }
    view.onDragging = { dragging.append($0) }

    view.mouseDown(with: pointerEvent(.leftMouseDown, at: CGPoint(x: 36, y: 38), window: window))
    view.mouseDragged(with: pointerEvent(.leftMouseDragged, at: CGPoint(x: 38, y: 39), window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: CGPoint(x: 38, y: 39), window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: CGPoint(x: 38, y: 39), window: window))

    #expect(activated == 1)
    #expect(returned == 0)
    #expect(dragging == [false])
}

@Test("a shelf-internal drag reorders against the actual destination view")
@MainActor
func shelfPointerReordersWithinWindow() {
    let (window, view) = iconInteractionWindow()
    defer { window.close() }
    let target = iconInteractionView("chat")
    target.frame = CGRect(x: 80, y: 20, width: 32, height: 36)
    window.contentView?.addSubview(target)
    var reorders: [String] = []
    var activated = 0
    var returned = 0
    var dragging: [Bool] = []
    view.isSafeDrop = { _ in false }
    view.onReorder = { source, target in reorders.append("\(source)→\(target)") }
    view.onActivate = { activated += 1 }
    view.onReturn = { _, _ in returned += 1 }
    view.onDragging = { dragging.append($0) }

    view.mouseDown(with: pointerEvent(.leftMouseDown, at: CGPoint(x: 36, y: 38), window: window))
    view.mouseDragged(with: pointerEvent(.leftMouseDragged, at: CGPoint(x: 96, y: 38), window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: CGPoint(x: 96, y: 38), window: window))

    #expect(reorders == ["vpn→chat"])
    #expect(activated == 0)
    #expect(returned == 0)
    #expect(dragging == [true, false])
}

@Test("Escape before the threshold suppresses the click, and a new gesture can click normally")
@MainActor
func shelfPointerEscapeBeforeThresholdCancelsClick() {
    let (window, view) = iconInteractionWindow()
    defer { window.close() }
    var activated = 0
    var returned = 0
    var dragging: [Bool] = []
    view.onActivate = { activated += 1 }
    view.onReturn = { _, _ in returned += 1 }
    view.onDragging = { dragging.append($0) }
    let point = CGPoint(x: 36, y: 38)

    view.mouseDown(with: pointerEvent(.leftMouseDown, at: point, window: window))
    view.keyDown(with: escapeEvent(window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: point, window: window))
    #expect(activated == 0)
    #expect(returned == 0)
    #expect(dragging == [false])

    view.mouseDown(with: pointerEvent(.leftMouseDown, at: point, window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: point, window: window))
    #expect(activated == 1)
    #expect(returned == 0)
}

@Test("Escape during a real view drag cancels it without poisoning the next return gesture")
@MainActor
func shelfPointerEscapeThenNewReturn() {
    let (window, view) = iconInteractionWindow()
    defer { window.close() }
    var returned: [String] = []
    var activated = 0
    var dragging: [Bool] = []
    view.isSafeDrop = { _ in true }
    view.onReturn = { id, _ in returned.append(id) }
    view.onActivate = { activated += 1 }
    view.onDragging = { dragging.append($0) }
    let origin = CGPoint(x: 36, y: 38)
    let destination = CGPoint(x: 36, y: 150)

    view.mouseDown(with: pointerEvent(.leftMouseDown, at: origin, window: window))
    view.mouseDragged(with: pointerEvent(.leftMouseDragged, at: destination, window: window))
    view.keyDown(with: escapeEvent(window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: destination, window: window))
    #expect(returned.isEmpty)
    #expect(activated == 0)
    #expect(dragging == [true, false])

    view.mouseDown(with: pointerEvent(.leftMouseDown, at: origin, window: window))
    view.mouseDragged(with: pointerEvent(.leftMouseDragged, at: destination, window: window))
    view.mouseUp(with: pointerEvent(.leftMouseUp, at: destination, window: window))
    #expect(returned == ["vpn"])
    #expect(activated == 0)
    #expect(dragging == [true, false, true, false])
}

@Test("an invalid drop clears drag feedback and cannot turn into a later click")
@MainActor
func shelfPointerInvalidDropCleansUp() {
    let view = iconInteractionView()
    var returned = 0
    var activated = 0
    var reordered = 0
    var dragging: [Bool] = []
    var ghost: [CGPoint] = []
    view.isSafeDrop = { _ in false }
    view.onReturn = { _, _ in returned += 1 }
    view.onActivate = { activated += 1 }
    view.onReorder = { _, _ in reordered += 1 }
    view.onDragging = { dragging.append($0) }
    view.onDragPosition = { _, point in ghost.append(point) }
    let moved = CGPoint(x: 800, y: 200)
    let outside = CGPoint(x: 800, y: 300)

    view.beginPointerTracking(at: CGPoint(x: 800, y: 100))
    view.continuePointerTracking(at: moved)
    view.continuePointerTracking(at: outside)
    view.endPointerTracking(at: outside, isInsideSource: false)
    view.endPointerTracking(at: CGPoint(x: 800, y: 100), isInsideSource: true)

    #expect(returned == 0)
    #expect(activated == 0)
    #expect(reordered == 0)
    #expect(dragging == [true, false])
    #expect(ghost == [moved, outside])
}
