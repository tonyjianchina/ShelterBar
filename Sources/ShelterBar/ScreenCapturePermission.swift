import AppKit

@MainActor
enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    enum RequestResult {
        case granted, manualApprovalRequired

        var guidance: String? {
            switch self {
            case .granted: nil
            case .manualApprovalRequired:
                "若系统没有弹出授权，请打开设置；列表中没有 ShelterBar 时，点“+”选择 /Applications/ShelterBar.app。"
            }
        }
    }

    // Invoked by onboarding after Accessibility succeeds, or by the explicit
    // permission button. Routine background scans never call this directly.
    @discardableResult
    static func request(
        systemRequest: () -> Bool = { CGRequestScreenCaptureAccess() },
        openSettings _: () -> Bool = { ScreenCapturePermission.openSettings() }
    ) -> RequestResult {
        if systemRequest() { return .granted }
        // Do not open System Settings in the same call. On macOS 27 the TCC
        // request can return false while the prompt is still being scheduled;
        // deep-linking immediately races and may suppress that prompt. The
        // shelf keeps an explicit Settings button as the reliable fallback.
        return .manualApprovalRequired
    }

    @discardableResult
    static func openSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
