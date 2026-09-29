import Testing
import ShelterBarCore
@testable import ShelterBar

@Test("the coordinator asks for screen capture as soon as accessibility is granted")
@MainActor
func permissionCoordinatorAdvancesToScreenCapture() {
    var accessibilityGranted = false
    var screenCaptureGranted = false
    var requests: [PermissionOnboardingAction] = []
    let coordinator = PermissionOnboardingCoordinator(
        accessibilityGranted: { accessibilityGranted },
        screenCaptureGranted: { screenCaptureGranted },
        requestAccessibility: { requests.append(.requestAccessibility) },
        requestScreenCapture: { requests.append(.requestScreenCapture) }
    )

    #expect(coordinator.advance() == .requestAccessibility)
    #expect(requests == [.requestAccessibility])

    accessibilityGranted = true
    #expect(coordinator.advance() == .requestScreenCapture)
    #expect(requests == [.requestAccessibility, .requestScreenCapture])

    #expect(coordinator.advance() == nil)
    #expect(requests == [.requestAccessibility, .requestScreenCapture])

    screenCaptureGranted = true
    #expect(coordinator.advance() == nil)
}
