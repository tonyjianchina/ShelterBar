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

@Test("collapsed status items keep their row while stale helper AX entries do not")
@MainActor
func hiddenItemsExcludeOffRowAXRemnants() {
    let row = CGRect(x: 0, y: 0, width: 1512, height: 32)
    #expect(MenuBarGeometry.isInMenuBarRow(
        CGRect(x: -2127, y: 4.5, width: 36, height: 24), regions: [row]))
    #expect(!MenuBarGeometry.isInMenuBarRow(
        CGRect(x: -1, y: 981, width: 56, height: 24), regions: [row]))
}

@Test("notch-hidden points are recognised so no release targets the camera housing")
@MainActor
func cameraHousingPointsAreRecognised() {
    let notch = [CGRect(x: 665, y: 0, width: 185, height: 32)]
    #expect(MenuBarGeometry.isUnderCameraHousing(CGPoint(x: 700, y: 16), excluded: notch))
    #expect(MenuBarGeometry.isUnderCameraHousing(CGPoint(x: 851, y: 16), excluded: notch))
    #expect(!MenuBarGeometry.isUnderCameraHousing(CGPoint(x: 880, y: 16), excluded: notch))
    #expect(!MenuBarGeometry.isUnderCameraHousing(CGPoint(x: 700, y: 16), excluded: []))
}

@Test("an auto-hidden menu bar row above a display still identifies that display")
@MainActor
func autoHiddenMenuBarRowIsRecognised() {
    // Measured on the user's Mac: the full-screen H27P6S row sits at y=-1139.
    let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 32)
    let external = CGRect(x: 0, y: -1080, width: 1920, height: 22)
    let regions = [builtIn, external]
    let hiddenItem = CGRect(x: 1207, y: -1139, width: 37, height: 24)
    #expect(MenuBarGeometry.menuBarRegion(containing: hiddenItem, regions: regions) == nil)
    #expect(MenuBarGeometry.hiddenMenuBarRegion(containing: hiddenItem, regions: regions) == external)
    #expect(MenuBarGeometry.menuBarRow(containing: hiddenItem, regions: regions) == external)
    let shown = CGRect(x: 1207, y: -1077, width: 37, height: 24)
    #expect(MenuBarGeometry.menuBarRow(containing: shown, regions: regions) == external)
    #expect(MenuBarGeometry.hiddenMenuBarRegion(containing: shown, regions: regions) == nil)
    // Items pushed off by a collapsed divider belong to no row.
    #expect(MenuBarGeometry.menuBarRow(containing: CGRect(x: -2500, y: -1139, width: 37, height: 24),
                                       regions: regions) == nil)
}

@Test("the boundary and handle stay addressable while a full-screen space hides the menu bar")
@MainActor
func statusControlsResolveOnAutoHiddenRow() {
    let external = CGRect(x: 0, y: -1080, width: 1920, height: 22)
    let hiddenRows = MenuBarGeometry.hiddenMenuBarRows(regions: [external])
    let hiddenHandle = CGRect(x: 1207, y: -1139, width: 24, height: 24)
    #expect(MenuBarGeometry.trailingControlFrame(hiddenHandle, regions: [external]) == nil)
    #expect(MenuBarGeometry.trailingControlFrame(hiddenHandle, regions: hiddenRows) == hiddenHandle)
    // A collapsed boundary on the hidden row still yields its trailing square.
    let collapsed = CGRect(x: -1800, y: -1139, width: 3000, height: 24)
    #expect(MenuBarGeometry.trailingControlFrame(collapsed, regions: hiddenRows)
        == CGRect(x: 1176, y: -1139, width: 24, height: 24))
    #expect(MenuBarGeometry.isInMenuBarRow(CGRect(x: -2500, y: -1139, width: 37, height: 24), regions: hiddenRows))
}

@Test("status controls on a 24 pt external menu bar resolve despite the 3 pt item offset")
@MainActor
func statusControlsResolveOnExternalMenuBar() {
    let external = CGRect(x: 1920, y: -1080, width: 1920, height: 24)
    let boundary = CGRect(x: 3304, y: -1077, width: 5, height: 24)
    let handle = CGRect(x: 3323, y: -1077, width: 24, height: 24)
    #expect(MenuBarGeometry.trailingControlFrame(boundary, regions: [external]) == boundary)
    #expect(MenuBarGeometry.trailingControlFrame(handle, regions: [external]) == handle)
    let collapsed = CGRect(x: -533, y: -1077, width: 3842, height: 24)
    #expect(MenuBarGeometry.trailingControlFrame(collapsed, regions: [external])
        == CGRect(x: 3285, y: -1077, width: 24, height: 24))
    // Still rejected when the square straddles the display edge or another row.
    #expect(MenuBarGeometry.trailingControlFrame(CGRect(x: 1910, y: -1077, width: 24, height: 24),
                                                 regions: [external]) == nil)
    #expect(MenuBarGeometry.trailingControlFrame(CGRect(x: 3304, y: -1040, width: 24, height: 24),
                                                 regions: [external]) == nil)
}
