import AppKit
import Testing
@testable import ShelterBar

@Test("the revealed status boundary has a display region beside an aligned screen")
@MainActor
func revealedBoundaryHasDisplayRegion() {
    let left = CGRect(x: 0, y: 0, width: 1440, height: 40)
    let right = CGRect(x: 1440, y: 0, width: 1440, height: 40)
    let regions = [left, right]
    #expect(MenuBarGeometry.menuBarRegion(
        containing: CGRect(x: 900, y: 5, width: 24, height: 24), regions: regions
    ) == left)
    #expect(MenuBarGeometry.menuBarRegion(
        containing: CGRect(x: 1800, y: 5, width: 24, height: 24), regions: regions
    ) == right)
    #expect(MenuBarGeometry.menuBarRegion(
        containing: CGRect(x: 900, y: 5, width: 0, height: 24), regions: regions
    ) == nil)
}

@Test("a menu-bar frame must be fully outside the camera housing")
@MainActor
func cameraHousingRejectsCoveredDestinationFrames() {
    let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 32)
    let cameraHousing = CGRect(x: 665, y: 0, width: 185, height: 32)

    #expect(!MenuBarGeometry.isFullyVisible(
        CGRect(x: 840, y: 4, width: 24, height: 24),
        regions: [menuBar],
        excluded: [cameraHousing]
    ))
    #expect(!MenuBarGeometry.isFullyVisible(
        CGRect(x: 842, y: 4, width: 24, height: 24),
        regions: [menuBar],
        excluded: [cameraHousing]
    ))
    #expect(MenuBarGeometry.isFullyVisible(
        CGRect(x: 850, y: 4, width: 24, height: 24),
        regions: [menuBar],
        excluded: [cameraHousing]
    ))
    // Native status windows can be one point taller than the logical menu-bar
    // row. Their center and complete horizontal footprint still identify the
    // row, while the full native frame remains the notch intersection input.
    #expect(MenuBarGeometry.isFullyVisible(
        CGRect(x: 850, y: 0, width: 34, height: 33),
        regions: [menuBar],
        excluded: [cameraHousing]
    ))
    #expect(!MenuBarGeometry.isFullyVisible(
        CGRect(x: 1490, y: 0, width: 34, height: 33),
        regions: [menuBar],
        excluded: [cameraHousing]
    ))
}

@Test("an expanded boundary keeps its visible handle anchored at the trailing edge")
@MainActor
func expandedBoundaryUsesTrailingHandleFrame() {
    let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 32)
    let expanded = CGRect(x: -2105, y: 4, width: 3024, height: 24)

    #expect(MenuBarGeometry.trailingControlFrame(expanded, regions: [menuBar])
        == CGRect(x: 895, y: 4, width: 24, height: 24))
}
