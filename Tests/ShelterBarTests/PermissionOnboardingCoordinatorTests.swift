import Testing
import ShelterBarCore
@testable import ShelterBar

@Test("granting accessibility in System Settings triggers screen capture without reopening the shelf")
@MainActor
func permissionCoordinatorObservesSystemSettingsGrant() async throws {
    var accessibilityGranted = false
    var requests: [PermissionOnboardingAction] = []
    let coordinator = PermissionOnboardingCoordinator(
        accessibilityGranted: { accessibilityGranted },
        screenCaptureGranted: { false },
        requestAccessibility: { requests.append(.requestAccessibility) },
        requestScreenCapture: { requests.append(.requestScreenCapture) }
    )

    #expect(coordinator.advance() == .requestAccessibility)
    #expect(requests == [.requestAccessibility])
    accessibilityGranted = true

    // System Settings changes trust while the app receives no new UI calls.
    let deadline = ContinuousClock.now + .seconds(5)
    while requests.count < 2 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(requests == [.requestAccessibility, .requestScreenCapture])
    #expect(coordinator.advance() == nil)
}

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

@Test("screen capture is requested right after AX trust, before input monitoring and event posting")
@MainActor
func permissionCoordinatorDoesNotWaitForInputPermissions() {
    var accessibility = false
    var listenEvents = false
    var postEvents = false
    let screenCaptureGranted = false
    var requests: [PermissionOnboardingAction] = []
    let coordinator = PermissionOnboardingCoordinator(
        accessibilityGranted: { accessibility },
        screenCaptureGranted: { screenCaptureGranted },
        requestAccessibility: { requests.append(.requestAccessibility) },
        requestScreenCapture: { requests.append(.requestScreenCapture) }
    )

    #expect(coordinator.advance() == .requestAccessibility)

    // AX granted, input monitoring and event posting still pending.
    accessibility = true
    #expect(!AccessibilityPermission.hasRequiredAccess(
        accessibility: accessibility,
        listenEvents: listenEvents,
        postEvents: postEvents
    ))
    #expect(coordinator.advance() == .requestScreenCapture)
    #expect(requests == [.requestAccessibility, .requestScreenCapture])

    // Granting the remaining input permissions later does not re-prompt.
    listenEvents = true
    postEvents = true
    #expect(coordinator.advance() == nil)
    #expect(requests == [.requestAccessibility, .requestScreenCapture])
}
