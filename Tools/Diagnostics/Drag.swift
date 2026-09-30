import CoreGraphics
import Foundation

// Unmodified user-style mouse input for exercising the app's real event tap
// and AppKit dragging source. Coordinates must come from a fresh AX snapshot.
guard CommandLine.arguments.count == 5,
      let x1 = Double(CommandLine.arguments[1]), let y1 = Double(CommandLine.arguments[2]),
      let x2 = Double(CommandLine.arguments[3]), let y2 = Double(CommandLine.arguments[4]),
      let source = CGEventSource(stateID: .hidSystemState) else { exit(2) }
let start = CGPoint(x: x1, y: y1), end = CGPoint(x: x2, y: y2)
func post(_ type: CGEventType, at point: CGPoint) {
    let event = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: point, mouseButton: .left)!
    event.flags = []
    event.post(tap: .cghidEventTap)
}
post(.mouseMoved, at: start)
Thread.sleep(forTimeInterval: 0.1)
post(.leftMouseDown, at: start)
Thread.sleep(forTimeInterval: 0.1)
for step in 1...20 {
    let t = Double(step) / 20
    post(.leftMouseDragged, at: CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t))
    Thread.sleep(forTimeInterval: 0.035)
}
post(.leftMouseUp, at: end)
