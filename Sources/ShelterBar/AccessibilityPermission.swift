import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermission {
    // TCC can briefly report AX trust while event-listen or event-post access is
    // still denied (notably after an ad-hoc rebuild or a permission toggle).
    // Treat the three capabilities as one gate so the app never installs a
    // consuming event tap unless it can also complete the synthetic gesture.
    static var isGranted: Bool {
        hasRequiredAccess(
            accessibility: AXIsProcessTrusted(),
            listenEvents: CGPreflightListenEventAccess(),
            postEvents: CGPreflightPostEventAccess()
        )
    }

    static func hasRequiredAccess(
        accessibility: Bool,
        listenEvents: Bool,
        postEvents: Bool
    ) -> Bool {
        accessibility && listenEvents && postEvents
    }

    // Screen recording is independent of the event-tap gate. Onboarding moves
    // on to it as soon as AX trust exists, instead of waiting for input
    // monitoring and event posting to settle as well.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func readyForScreenCaptureOnboarding(
        accessibility: Bool,
        listenEvents: Bool,
        postEvents: Bool
    ) -> Bool {
        accessibility
    }

    static func request() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
    }

    static func openSettings() {
        let section = AXIsProcessTrusted() && CGPreflightPostEventAccess()
            ? "Privacy_ListenEvent"
            : "Privacy_Accessibility"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(section)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
