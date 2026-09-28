import AppKit
import Testing
@testable import ShelterBar

@Test("temporary menu-bar rearrangement stays covered from capture through completion")
@MainActor
func menuBarRearrangementStaysCovered() async throws {
    var events: [String] = []
    let region = CGRect(x: 0, y: 0, width: 1440, height: 37)
    let shield = MenuBarTransitionShield(
        capture: { capturedRegion in
            #expect(capturedRegion == region)
            events.append("capture")
            return NSImage(size: capturedRegion.size)
        },
        present: { _, presentedRegion in
            #expect(presentedRegion == region)
            events.append("present")
        },
        dismiss: { events.append("dismiss") }
    )

    let value = try await shield.perform(over: region) {
        events.append("rearrange")
        #expect(events == ["capture", "present", "rearrange"])
        return 42
    }

    #expect(value == 42)
    #expect(events == ["capture", "present", "rearrange", "dismiss"])
}

@Test("failed capture never blocks the real menu-bar operation")
@MainActor
func unavailableShieldFallsBackToUncoveredOperation() async throws {
    var events: [String] = []
    let shield = MenuBarTransitionShield(
        capture: { _ in events.append("capture"); return nil },
        present: { _, _ in Issue.record("A missing snapshot must not be presented.") },
        dismiss: { Issue.record("An unpresented shield must not be dismissed.") }
    )

    let value = try await shield.perform(over: CGRect(x: 0, y: 0, width: 100, height: 30)) {
        events.append("rearrange")
        return 7
    }

    #expect(value == 7)
    #expect(events == ["capture", "rearrange"])
}

@Test("throwing rearrangement still removes the visual shield")
@MainActor
func failedRearrangementDismissesShield() async {
    enum ExpectedFailure: Error { case failed }
    var events: [String] = []
    let shield = MenuBarTransitionShield(
        capture: { region in events.append("capture"); return NSImage(size: region.size) },
        present: { _, _ in events.append("present") },
        dismiss: { events.append("dismiss") }
    )

    await #expect(throws: ExpectedFailure.self) {
        try await shield.perform(over: CGRect(x: 0, y: 0, width: 100, height: 30)) {
            events.append("rearrange")
            throw ExpectedFailure.failed
        }
    }
    #expect(events == ["capture", "present", "rearrange", "dismiss"])
}
