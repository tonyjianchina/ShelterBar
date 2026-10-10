import Testing
import ShelterBarCore
@testable import ShelterBar

@Test("input control requires AX, event listening, and event synthesis access")
@MainActor
func inputControlRequiresEveryPermission() {
    #expect(AccessibilityPermission.hasRequiredAccess(
        accessibility: true,
        listenEvents: true,
        postEvents: true
    ))
    #expect(!AccessibilityPermission.hasRequiredAccess(
        accessibility: false,
        listenEvents: true,
        postEvents: true
    ))
    #expect(!AccessibilityPermission.hasRequiredAccess(
        accessibility: true,
        listenEvents: false,
        postEvents: true
    ))
    #expect(!AccessibilityPermission.hasRequiredAccess(
        accessibility: true,
        listenEvents: true,
        postEvents: false
    ))
}

@Test("an explicit input-permission click still opens settings after a silent startup request")
@MainActor
func inputPermissionClickFallsBackAfterSilentSystemRequest() {
    var requests: [String] = []
    var settingsOpens = 0
    let operations = AccessibilityPermission.RequestOperations(
        requestAccessibility: { requests.append("accessibility") },
        canListen: { false },
        requestListening: { requests.append("listening"); return false },
        canPost: { false },
        requestPosting: { requests.append("posting"); return false },
        isGranted: { false },
        openSettings: { settingsOpens += 1; return true }
    )
    let coordinator = PermissionOnboardingCoordinator(
        accessibilityGranted: { false },
        screenCaptureGranted: { false },
        requestAccessibility: { AccessibilityPermission.request(using: operations) },
        requestScreenCapture: { Issue.record("Input access is still missing") }
    )

    // The OS declines/suppresses the automatic prompt. The shelf's button calls
    // this same coordinator method, even after onboarding recorded its attempt.
    #expect(coordinator.advance() == .requestAccessibility)
    let beforeClick = settingsOpens
    coordinator.requestAccessibility()
    #expect(requests == ["accessibility", "listening", "posting",
                         "accessibility", "listening", "posting"])
    #expect(settingsOpens == beforeClick + 1)
    // Background polling must never reopen settings repeatedly.
    #expect(coordinator.advance() == nil)
    #expect(settingsOpens == beforeClick + 1)
}

@MainActor
private func deniedInputOperations(openSettings: @escaping () -> Bool = { true })
    -> AccessibilityPermission.RequestOperations {
    .init(
        requestAccessibility: {}, canListen: { false }, requestListening: { false },
        canPost: { false }, requestPosting: { false }, isGranted: { false },
        openSettings: openSettings
    )
}

@Test("a silent denied input request returns visible settings guidance")
@MainActor
func inputPermissionDeniedRequestReportsSettings() {
    let result = AccessibilityPermission.request(using: deniedInputOperations())
    #expect(result == .settingsOpened)
    #expect(result.guidance?.contains("系统设置") == true)
    #expect(result.guidance?.contains("添加") == true)
}

@Test("failure to open input settings is reported instead of mistaken for a grant")
@MainActor
func inputPermissionSettingsFailureHasGuidance() {
    let result = AccessibilityPermission.request(using: deniedInputOperations(openSettings: { false }))
    #expect(result == .settingsUnavailable)
    #expect(result.guidance?.contains("手动") == true)
}

@Test("already granted input access neither requests again nor opens settings")
@MainActor
func inputPermissionAlreadyGrantedDoesNotPrompt() {
    var operations = deniedInputOperations(openSettings: {
        Issue.record("Do not reopen settings when already granted"); return false
    })
    operations.isGranted = { true }
    operations.requestAccessibility = { Issue.record("Do not request existing access") }
    operations.requestListening = { Issue.record("Do not request existing access"); return false }
    operations.requestPosting = { Issue.record("Do not request existing access"); return false }
    let result = AccessibilityPermission.request(using: operations)
    #expect(result == .granted)
    #expect(result.guidance == nil)
}

@Test("a grant completed during input requests does not open settings afterward")
@MainActor
func inputPermissionGrantDuringRequestAvoidsSettings() {
    var granted = false
    var operations = deniedInputOperations(openSettings: {
        Issue.record("The grant completed; settings should stay closed"); return false
    })
    operations.isGranted = { granted }
    operations.requestPosting = { granted = true; return true }
    #expect(AccessibilityPermission.request(using: operations) == .granted)
}

@Test("successful individual input requests cannot bypass the complete input gate")
@MainActor
func inputPermissionPartialGrantStillNeedsSettings() {
    var operations = deniedInputOperations()
    operations.requestListening = { true }
    operations.requestPosting = { true }
    #expect(AccessibilityPermission.request(using: operations) == .settingsOpened)
}

@Test("input settings target AX before input monitoring and preserve launch failure")
@MainActor
func inputPermissionSettingsSelectMissingAccess() {
    for (ax, post, expected) in [
        (false, false, "Privacy_Accessibility"),
        (false, true, "Privacy_Accessibility"),
        (true, false, "Privacy_Accessibility"),
        (true, true, "Privacy_ListenEvent"),
    ] {
        var destination: String?
        let opened = AccessibilityPermission.openSettings(
            accessibilityGranted: { ax }, postingGranted: { post },
            openURL: { destination = $0.absoluteString; return false }
        )
        #expect(destination == "x-apple.systempreferences:com.apple.preference.security?\(expected)")
        #expect(!opened)
    }
}
