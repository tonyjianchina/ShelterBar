import Foundation

enum AppVersion {
    /// Read the running app's bundle, not a hard-coded release label: multiple
    /// local builds can share the same public version number.
    static func menuTitle(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        func value(_ key: String) -> String {
            guard let text = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return "未知" }
            return text
        }
        return "版本 \(value("CFBundleShortVersionString"))（Build \(value("CFBundleVersion"))）"
    }
}
