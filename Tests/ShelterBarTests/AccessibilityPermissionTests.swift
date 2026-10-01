import Testing
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
