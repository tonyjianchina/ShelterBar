import Foundation
import Testing
@testable import ShelterBar

@Test("the distribution selects the correct updater policy")
func directDistributionKeepsTheGitHubUpdater() {
    #if SHELTERBAR_APP_STORE
    #expect(!ShelterBarDistribution.includesGitHubUpdater)
    #else
    #expect(ShelterBarDistribution.includesGitHubUpdater)
    #endif
}

@Test("the in-app privacy link is the canonical HTTPS policy page")
func privacyPolicyLinkIsTheCanonicalHTTPSPage() {
    let url = ShelterBarDistribution.privacyPolicyURL
    #expect(url.scheme == "https")
    #expect(url.host == "shelterbar.zhengjian.me")
    #expect(url.path == "/privacy")
}

@Test("Info.plist and the privacy manifest declare the store metadata")
func infoPlistDeclaresStoreMetadataAndUsageStrings() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let plistURL = root.appendingPathComponent("Resources/Info.plist")
    let plistData = try Data(contentsOf: plistURL)
    let plist = try #require(
        PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    )
    #expect(plist["LSApplicationCategoryType"] as? String == "public.app-category.utilities")
    #expect(plist["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    #expect((plist["NSAccessibilityUsageDescription"] as? String)?.isEmpty == false)
    #expect((plist["NSScreenCaptureUsageDescription"] as? String)?.isEmpty == false)
    #expect((plist["NSScreenCaptureUsageDescription"] as? String)?.contains("optional") == true)

    let privacyURL = root.appendingPathComponent("Resources/PrivacyInfo.xcprivacy")
    let privacyData = try Data(contentsOf: privacyURL)
    let privacy = try #require(
        PropertyListSerialization.propertyList(from: privacyData, format: nil) as? [String: Any]
    )
    #expect(privacy["NSPrivacyTracking"] as? Bool == false)
    let collected = try #require(privacy["NSPrivacyCollectedDataTypes"] as? [Any])
    #expect(collected.isEmpty)
}

#if SHELTERBAR_APP_STORE
@Test("the updater-free audit never loads a private visibility backend")
@MainActor
func storeAuditHasNoPrivateBackend() {
    #expect(!MenuBarClientRestriction().isAvailable)
}
#endif
