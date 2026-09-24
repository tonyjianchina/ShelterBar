import CoreGraphics
import Testing
@testable import ShelterBarCore

@Test("Escape before crossing the drag threshold cancels the click too")
func escapeBeforeDrag() {
    var gesture = MenuBarDragGesture()
    gesture.begin(itemID: "sync", at: CGPoint(x: 800, y: 16))
    gesture.cancelUntilRelease()
    #expect(gesture.isTracking)
    #expect(gesture.finish(at: CGPoint(x: 800, y: 16), shelf: .zero) == .cancel)
    #expect(!gesture.isTracking)
}

@Test("movement after Escape cannot revive a cancelled collection")
func escapeDuringDrag() {
    var gesture = MenuBarDragGesture()
    gesture.begin(itemID: "sync", at: CGPoint(x: 800, y: 16))
    gesture.move(to: CGPoint(x: 700, y: 60))
    gesture.cancelUntilRelease()
    gesture.move(to: CGPoint(x: 600, y: 60))
    #expect(gesture.finish(at: CGPoint(x: 600, y: 60),
                           shelf: CGRect(x: 500, y: 35, width: 400, height: 74)) == .cancel)
}
