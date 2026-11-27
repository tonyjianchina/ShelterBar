import Foundation
import Testing
@testable import ShelterBar

@Test("the default build keeps the GitHub updater")
func directDistributionKeepsTheGitHubUpdater() {
    #expect(ShelterBarDistribution.includesGitHubUpdater)
}

@Test("the in-app privacy link is the canonical HTTPS policy page")
func privacyPolicyLinkIsTheCanonicalHTTPSPage() {
    let url = ShelterBarDistribution.privacyPolicyURL
    #expect(url.scheme == "https")
    #expect(url.host == "shelterbar.tonyjianchina.chatgpt.site")
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
