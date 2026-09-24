import Foundation
import CoreGraphics
import Testing
@testable import ShelterBarCore

private let shelfBounds = CGRect(x: 500, y: 35, width: 400, height: 74)

@Test("a real menu-bar gesture dropped into the shelf collects exactly once")
func dragIntoShelf() {
    var gesture = MenuBarDragGesture()
    gesture.begin(itemID: "sync", at: CGPoint(x: 800, y: 16))
    gesture.move(to: CGPoint(x: 760, y: 50))
    #expect(gesture.finish(at: CGPoint(x: 700, y: 60), shelf: shelfBounds) == .collect("sync"))
    #expect(gesture.finish(at: CGPoint(x: 700, y: 60), shelf: shelfBounds) == nil)
}

@Test("dropping outside the shelf cancels without opening the app")
func cancelledDragDoesNotClick() {
    var gesture = MenuBarDragGesture()
    gesture.begin(itemID: "sync", at: CGPoint(x: 800, y: 16))
    gesture.move(to: CGPoint(x: 760, y: 50))
    #expect(gesture.finish(at: CGPoint(x: 500, y: 400), shelf: shelfBounds) == .cancel)
    #expect(!gesture.isTracking)
}

@Test("a click remains a click while the shelf is open")
func ordinaryClickRemainsClick() {
    var gesture = MenuBarDragGesture()
    gesture.begin(itemID: "sync", at: CGPoint(x: 800, y: 16))
    #expect(gesture.finish(at: CGPoint(x: 802, y: 17), shelf: shelfBounds) == .click("sync"))
}
