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

    @MainActor
    struct RequestOperations {
        var requestAccessibility: () -> Void
        var canListen: () -> Bool
        var requestListening: () -> Bool
        var canPost: () -> Bool
        var requestPosting: () -> Bool
        var isGranted: () -> Bool
        var openSettings: () -> Bool

        static var system: Self {
            Self(
                requestAccessibility: {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                },
                canListen: { CGPreflightListenEventAccess() },
                requestListening: { CGRequestListenEventAccess() },
                canPost: { CGPreflightPostEventAccess() },
                requestPosting: { CGRequestPostEventAccess() },
                isGranted: { AccessibilityPermission.isGranted },
                openSettings: { AccessibilityPermission.openSettings() }
            )
        }
    }

    enum RequestResult: Equatable {
        case granted, settingsOpened, settingsUnavailable

        var guidance: String? {
            switch self {
            case .granted: nil
            case .settingsOpened:
                "请在系统设置中允许 ShelterBar；列表没有时，点“＋”添加应用。"
            case .settingsUnavailable:
                "无法打开系统设置，请手动开启 ShelterBar 的辅助功能和输入监控。"
            }
        }
    }

    @discardableResult
    static func request(using operations: RequestOperations = .system) -> RequestResult {
        if operations.isGranted() { return .granted }
        operations.requestAccessibility()
        if !operations.canListen() {
            _ = operations.requestListening()
        }
        if !operations.canPost() {
            _ = operations.requestPosting()
        }
        if operations.isGranted() { return .granted }
        // macOS may suppress a repeated/denied native prompt. A user action must
        // still lead somewhere visible, without treating the request as a grant.
        return operations.openSettings() ? .settingsOpened : .settingsUnavailable
    }

    @discardableResult
    static func openSettings(
        accessibilityGranted: () -> Bool = { AXIsProcessTrusted() },
        postingGranted: () -> Bool = { CGPreflightPostEventAccess() },
        openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        let section = accessibilityGranted() && postingGranted()
            ? "Privacy_ListenEvent"
            : "Privacy_Accessibility"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(section)"
        ) else { return false }
        return openURL(url)
    }
}
