import Testing
@testable import ShelterBarCore

@Test("screen capture is requested immediately after accessibility becomes granted")
func permissionOnboardingRequestsScreenCaptureAfterAccessibilityGrant() {
    var onboarding = PermissionOnboarding()

    #expect(onboarding.nextAction(
        accessibilityGranted: false,
        screenCaptureGranted: false
    ) == .requestAccessibility)
    #expect(onboarding.nextAction(
        accessibilityGranted: false,
        screenCaptureGranted: false
    ) == nil)

    #expect(onboarding.nextAction(
        accessibilityGranted: true,
        screenCaptureGranted: false
    ) == .requestScreenCapture)
    #expect(onboarding.nextAction(
        accessibilityGranted: true,
        screenCaptureGranted: false
    ) == nil)
}

@Test("permission onboarding is already complete when both permissions are granted")
func permissionOnboardingSkipsGrantedPermissions() {
    var onboarding = PermissionOnboarding()

    #expect(onboarding.nextAction(
        accessibilityGranted: true,
        screenCaptureGranted: true
    ) == nil)
}
