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

@Test("input permission requests leave System Settings closed for the native prompt")
@MainActor
func inputPermissionRequestKeepsSettingsClosed() {
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

    // macOS owns the permission alert and its "Open System Settings" action.
    // ShelterBar must not open Settings behind that alert, at launch or when
    // the user presses the shelf's permission button.
    #expect(coordinator.advance() == .requestAccessibility)
    #expect(settingsOpens == 0)
    coordinator.requestAccessibility()
    #expect(requests == ["accessibility", "listening", "posting",
                         "accessibility", "listening", "posting"])
    #expect(settingsOpens == 0)
    // Background polling must never reopen settings repeatedly.
    #expect(coordinator.advance() == nil)
    #expect(settingsOpens == 0)
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

@Test("a denied input request keeps Settings closed and returns manual guidance")
@MainActor
func inputPermissionDeniedRequestReportsSettings() {
    var settingsOpens = 0
    let result = AccessibilityPermission.request(using: deniedInputOperations(openSettings: {
        settingsOpens += 1
        return true
    }))
    #expect(settingsOpens == 0)
    #expect(result == .manualApprovalRequired)
    #expect(result.guidance?.contains("权限弹窗") == true)
    #expect(result.guidance?.contains("打开设置") == true)
}

@Test("an unavailable settings fallback is not attempted during the native request")
@MainActor
func inputPermissionSettingsFailureHasGuidance() {
    let result = AccessibilityPermission.request(using: deniedInputOperations(openSettings: { false }))
    #expect(result == .manualApprovalRequired)
    #expect(result.guidance?.contains("打开设置") == true)
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

@Test("partial input grants still require manual approval without opening Settings")
@MainActor
func inputPermissionPartialGrantStillNeedsSettings() {
    var settingsOpens = 0
    var operations = deniedInputOperations(openSettings: {
        settingsOpens += 1
        return true
    })
    operations.requestListening = { true }
    operations.requestPosting = { true }
    #expect(AccessibilityPermission.request(using: operations) == .manualApprovalRequired)
    #expect(settingsOpens == 0)
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
