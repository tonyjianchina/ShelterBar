import Testing
@testable import ShelterBar

@Test("the menu identifies both the installed release and its build")
func appVersionMenuTitle() {
    #expect(AppVersion.menuTitle(info: [
        "CFBundleShortVersionString": "0.5.11", "CFBundleVersion": "33"
    ]) == "版本 0.5.11（Build 33）")
}

@Test("builds sharing a release number have distinct menu labels")
func appVersionDistinguishesBuilds() {
    let old = AppVersion.menuTitle(info: ["CFBundleShortVersionString": "0.5.11", "CFBundleVersion": "32"])
    let new = AppVersion.menuTitle(info: ["CFBundleShortVersionString": "0.5.11", "CFBundleVersion": "33"])
    #expect(old != new)
    #expect(old.contains("Build 32"))
    #expect(new.contains("Build 33"))
}

@Test("missing bundle metadata never invents a version or crashes")
func appVersionMissingMetadata() {
    #expect(AppVersion.menuTitle(info: [:]) == "版本 未知（Build 未知）")
    #expect(AppVersion.menuTitle(info: ["CFBundleShortVersionString": " ", "CFBundleVersion": 33])
        == "版本 未知（Build 未知）")
}
