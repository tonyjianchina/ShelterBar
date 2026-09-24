import AppKit

@MainActor
enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    enum RequestResult {
        case granted, settingsOpened, settingsUnavailable

        var guidance: String? {
            switch self {
            case .granted: nil
            case .settingsOpened: "请在系统设置中开启 ShelterBar；已开启但仍提示时，请退出并重新打开软件。"
            case .settingsUnavailable: "请手动打开系统设置 → 隐私与安全性 → 屏幕与系统音频录制，开启 ShelterBar。"
            }
        }
    }

    // Only invoked by the explicit permission button, never by a background scan.
    @discardableResult
    static func request(
        systemRequest: () -> Bool = { CGRequestScreenCaptureAccess() },
        openSettings: () -> Bool = { ScreenCapturePermission.openSettings() }
    ) -> RequestResult {
        if systemRequest() { return .granted }
        // macOS may return false without showing another prompt after an
        // earlier request. An explicit click must still have a visible result.
        return openSettings() ? .settingsOpened : .settingsUnavailable
    }

    @discardableResult
    static func openSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
