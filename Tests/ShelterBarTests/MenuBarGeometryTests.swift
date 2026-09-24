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
