import AppKit
import Testing
@testable import ShelterBar

private let builtInBar = CGRect(x: 0, y: 0, width: 1512, height: 32)
private let cameraHousing = CGRect(x: 665, y: 0, width: 185, height: 32)

@Test("DeepSeek trace: icons covered by the camera housing are not visible repair targets")
@MainActor
func capturedNotchItemsAreNotVisible() {
    // Captured immediately after DeepSeek was collected on the built-in display.
    let docker = CGRect(x: 775, y: 4.5, width: 47, height: 24)
    let weChat = CGRect(x: 820, y: 4.5, width: 75, height: 24)
    let deepSeek = CGRect(x: 941, y: 4.5, width: 34, height: 24)
    #expect(!MenuBarGeometry.isOnMenuBar(docker, regions: [builtInBar], excluded: [cameraHousing]))
    // The exposed 45 points must remain protected as a resident, not be
    // silently hidden just because a different icon is being collected.
    #expect(MenuBarGeometry.isOnMenuBar(weChat, regions: [builtInBar], excluded: [cameraHousing]))
    #expect(MenuBarGeometry.isOnMenuBar(deepSeek, regions: [builtInBar], excluded: [cameraHousing]))
}

@Test("an icon with a visible fragment must not count as successfully hidden")
@MainActor
func clippedMenuBarItemIsNotVisible() {
    #expect(MenuBarGeometry.isOnMenuBar(CGRect(x: -10, y: 4, width: 30, height: 24),
                                        regions: [builtInBar], excluded: []))
}

@Test("external display negative coordinates remain visible, but fullscreen off-row frames do not")
@MainActor
func externalMenuBarVisibility() {
    let external = CGRect(x: -400, y: -1080, width: 1920, height: 24)
    #expect(MenuBarGeometry.isOnMenuBar(CGRect(x: 874, y: -1077, width: 34, height: 24),
                                       regions: [builtInBar, external], excluded: [cameraHousing]))
    #expect(!MenuBarGeometry.isOnMenuBar(CGRect(x: 874, y: -1139, width: 34, height: 24),
                                        regions: [builtInBar, external], excluded: [cameraHousing]))
}

@Test("a partial icon's drag origin avoids the camera housing even when its center is covered")
@MainActor
func dragOriginUsesExposedSection() {
    let frame = CGRect(x: 640, y: 4.5, width: 90, height: 24)
    let exposed = MenuBarGeometry.visibleFrame(frame, regions: [builtInBar], excluded: [cameraHousing])
    #expect(exposed == CGRect(x: 640, y: 4.5, width: 25, height: 24))
    #expect(MenuBarGeometry.visibleFrame(CGRect(x: 775, y: 4.5, width: 47, height: 24),
                                        regions: [builtInBar], excluded: [cameraHousing]) == nil)
}
