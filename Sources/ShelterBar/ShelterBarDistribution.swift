import AppKit

/// Direct downloads keep the GitHub updater. The App Store compile
/// (`SHELTERBAR_DISTRIBUTION=app-store`, `-DSHELTERBAR_APP_STORE`) removes that
/// updater and private visibility implementation from the binary. This audit
/// flavor does not enable the App Sandbox and is not an
/// uploadable Mac App Store build. See docs/MAC-APP-STORE.md.
enum ShelterBarDistribution {
    /// Canonical policy URL. The page lives at website/dist/privacy/index.html.
    /// It is not live until that file is deployed and the host stops serving
    /// the marketing homepage for /privacy.
    static let privacyPolicyURL = URL(string: "https://shelterbar.zhengjian.me/privacy")!

    #if SHELTERBAR_APP_STORE
    static let includesGitHubUpdater = false
    #else
    static let includesGitHubUpdater = true
    #endif

    @MainActor
    static func openPrivacyPolicy() {
        NSWorkspace.shared.open(privacyPolicyURL)
    }
}
