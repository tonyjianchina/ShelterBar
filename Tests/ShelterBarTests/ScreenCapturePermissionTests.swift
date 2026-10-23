import Testing
@testable import ShelterBar

@Test("a denied or suppressed screen prompt does not race the prompt by opening settings immediately")
@MainActor
func deniedScreenPermissionShowsManualFallback() {
    var settingsOpened = false
    let result = ScreenCapturePermission.request(systemRequest: { false }, openSettings: {
        settingsOpened = true
        return true
    })
    #expect(!settingsOpened)
    #expect(result == .manualApprovalRequired)
    #expect(result.guidance?.contains("+") == true)
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

@Test("a suppressed prompt gives the same actionable fallback even if settings are unavailable")
@MainActor
func failedScreenPermissionSettingsLaunch() {
    let result = ScreenCapturePermission.request(systemRequest: { false }, openSettings: { false })
    #expect(result == .manualApprovalRequired)
    #expect(result.guidance?.contains("ShelterBar") == true)
}
