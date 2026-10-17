import CoreGraphics
import Testing
@testable import ShelterBar

private let region = CGRect(x: 0, y: 0, width: 1512, height: 33)
private let notch = CGRect(x: 665, y: 0, width: 185, height: 33)

@Test("the preferred slot is between the divider and the handle, then the far side of the handle")
func borrowSlotsPreferDividerSide() {
    let handle = CGRect(x: 1000, y: 0, width: 38, height: 30)
    let slots = MenuBarBorrowPlanner.candidateDrops(handle: handle, itemWidth: 34, region: region, notches: [notch])
    #expect(slots.map(\.afterHandle) == [false, true])
    #expect(slots[0].landing == CGRect(x: 966, y: 0, width: 34, height: 30))
    #expect(slots[0].drop.x > handle.minX && slots[0].drop.x < handle.midX)
    #expect(slots[1].drop.x > handle.midX && slots[1].drop.x < handle.maxX)
}

@Test("a slot that would land under the notch is skipped; no room at all yields no slot")
func borrowSlotsAvoidTheNotch() {
    let nearNotch = CGRect(x: 860, y: 0, width: 38, height: 30)
    let slots = MenuBarBorrowPlanner.candidateDrops(handle: nearNotch, itemWidth: 34, region: region, notches: [notch])
    #expect(slots.map(\.afterHandle) == [true])
    let tight = CGRect(x: 851, y: 0, width: 20, height: 30)
    #expect(MenuBarBorrowPlanner.candidateDrops(handle: tight, itemWidth: 34, region: region, notches: [notch]).isEmpty)
    let edge = CGRect(x: 10, y: 0, width: 20, height: 30)
    #expect(MenuBarBorrowPlanner.candidateDrops(handle: edge, itemWidth: 34, region: region, notches: []).map(\.afterHandle) == [])
}

@Test("returning drops inside the right neighbour's left edge, or just left of the divider")
func returnDropTargetsOriginalNeighbour() {
    let neighbour = CGRect(x: -2900, y: 0, width: 36, height: 30)
    #expect(MenuBarBorrowPlanner.returnDrop(anchor: neighbour, anchorIsDivider: false).x == -2896)
    let divider = CGRect(x: -2850, y: 0, width: 3856, height: 30)
    #expect(MenuBarBorrowPlanner.returnDrop(anchor: divider, anchorIsDivider: true).x == -2852)
}

@Test("AXPress is used only for an on-screen item whose AX frame matches its window")
func pressPolicyNeverPressesOffscreen() {
    let window = CGRect(x: 3284, y: -1080, width: 38, height: 30)
    #expect(MenuBarPressPolicy.shouldUseAXPress(axFrame: CGRect(x: 3291, y: -1077, width: 24, height: 24),
                                                windowFrame: window, axIsOnMenuBar: true))
    // AX reports another display's copy: click the visible glyph instead.
    #expect(!MenuBarPressPolicy.shouldUseAXPress(axFrame: CGRect(x: 958, y: 4, width: 24, height: 24),
                                                 windowFrame: window, axIsOnMenuBar: true))
    #expect(!MenuBarPressPolicy.shouldUseAXPress(axFrame: CGRect(x: -2600, y: 4, width: 24, height: 24),
                                                 windowFrame: nil, axIsOnMenuBar: false))
}

@Test("restore waits for the menu to close, a 1s grace and 250ms of idle; app switches restore at once")
func closeStateNeedsGraceAndIdle() {
    #expect(MenuBarPressPolicy.closeState(menuVisible: true, closedFor: nil, idleFor: .seconds(5), frontmostChanged: false) == .open)
    #expect(MenuBarPressPolicy.closeState(menuVisible: false, closedFor: .milliseconds(400), idleFor: .seconds(5), frontmostChanged: false) == .closedWaitingGrace)
    #expect(MenuBarPressPolicy.closeState(menuVisible: false, closedFor: .milliseconds(1200), idleFor: .milliseconds(100), frontmostChanged: false) == .closedWaitingGrace)
    #expect(MenuBarPressPolicy.closeState(menuVisible: false, closedFor: .milliseconds(1200), idleFor: .milliseconds(300), frontmostChanged: false) == .restore)
    #expect(MenuBarPressPolicy.closeState(menuVisible: false, closedFor: .milliseconds(10), idleFor: .zero, frontmostChanged: true) == .restore)
    #expect(MenuBarPressPolicy.closeState(menuVisible: true, closedFor: nil, idleFor: .zero, frontmostChanged: true) == .open)
}

@Test("a returned item counts as back even when AX glyph frames overlap by a few points")
func returnedItemToleratesAXOverlap() {
    let neighbour = CGRect(x: -680, y: -1077, width: 37, height: 24)
    #expect(MenuBarBorrowPlanner.isBack(item: CGRect(x: -714, y: -1077, width: 36, height: 24), before: neighbour))
    #expect(!MenuBarBorrowPlanner.isBack(item: CGRect(x: -640, y: -1077, width: 36, height: 24), before: neighbour))
    #expect(!MenuBarBorrowPlanner.isBack(item: CGRect(x: 3249, y: -1077, width: 36, height: 24), before: neighbour))
}
