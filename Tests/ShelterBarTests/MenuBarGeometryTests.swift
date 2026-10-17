import AppKit
import Testing
@testable import ShelterBar

@Test("the one-point revealed divider has a display region beside an aligned screen")
@MainActor
func onePointDividerHasDisplayRegion() {
    let left = CGRect(x: 0, y: 0, width: 1440, height: 40)
    let right = CGRect(x: 1440, y: 0, width: 1440, height: 40)
    let regions = [left, right]
    #expect(MenuBarGeometry.menuBarRegion(
        containing: CGRect(x: 900, y: 5, width: 1, height: 24), regions: regions
    ) == left)
    #expect(MenuBarGeometry.menuBarRegion(
        containing: CGRect(x: 1800, y: 5, width: 24, height: 24), regions: regions
    ) == right)
    #expect(MenuBarGeometry.menuBarRegion(
        containing: CGRect(x: 900, y: 5, width: 0, height: 24), regions: regions
    ) == nil)
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
