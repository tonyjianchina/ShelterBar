import Testing
@testable import ShelterBar

@Test("a denied or previously requested screen permission opens settings instead of silently doing nothing")
@MainActor
func deniedScreenPermissionOpensSettings() {
    var settingsOpened = false
    let result = ScreenCapturePermission.request(systemRequest: { false }, openSettings: {
        settingsOpened = true
        return true
    })
    #expect(settingsOpened)
    #expect(result == .settingsOpened)
    #expect(result.guidance?.contains("系统设置") == true)
}

@Test("granted screen permission does not open settings unnecessarily")
@MainActor
func grantedScreenPermissionDoesNotOpenSettings() {
    let result = ScreenCapturePermission.request(systemRequest: { true }, openSettings: {
        Issue.record("Already authorized: settings must not open")
        return true
    })
    #expect(result == .granted)
    #expect(result.guidance == nil)
}

@Test("a failed settings launch remains distinguishable from successful authorization")
@MainActor
func failedScreenPermissionSettingsLaunch() {
    let result = ScreenCapturePermission.request(systemRequest: { false }, openSettings: { false })
    #expect(result == .settingsUnavailable)
    #expect(result.guidance?.contains("手动") == true)
}
