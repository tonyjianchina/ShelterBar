import Testing
import Foundation
@testable import ShelterBar

@Test("semantic versions order prereleases before the matching stable release")
func semanticVersionOrderingIncludesPrereleases() throws {
    let beta2 = try #require(ShelterBarVersion("v0.5.12-beta.2"))
    let beta10 = try #require(ShelterBarVersion("0.5.12-beta.10"))
    let release = try #require(ShelterBarVersion("0.5.12"))
    let nextPrerelease = try #require(ShelterBarVersion("0.5.13-rc.1"))

    #expect(beta2 < beta10)
    #expect(beta10 < release)
    #expect(release < nextPrerelease)
    #expect(ShelterBarVersion("0.5.12-01") == nil)
    #expect(ShelterBarVersion("0.5.12-BETA") != ShelterBarVersion("0.5.12-beta"))
    #expect(ShelterBarVersion("0.5.12+build.01") == release)
    #expect(ShelterBarVersion("0.5.12+") == nil)
    #expect(ShelterBarVersion("0.5.12+build+other") == nil)
}

@Test("build numbers compare numerically and govern update eligibility")
func buildNumberComparisonAndEligibility() throws {
    let version = try #require(ShelterBarVersion("0.5.11"))
    let nextVersion = try #require(ShelterBarVersion("0.5.12"))
    let build34 = try #require(ShelterBarBuildNumber("34"))
    let build35 = try #require(ShelterBarBuildNumber("35"))
    let build35Patch1 = try #require(ShelterBarBuildNumber("35.0.1"))

    #expect(build34 < build35)
    #expect(build35 < build35Patch1)
    #expect(build35 == ShelterBarBuildNumber("35.0"))
    #expect(ShelterBarBuildNumber("035") == nil)
    #expect(UpdateEligibility.evaluate(
        currentVersion: version,
        currentBuild: build34,
        candidateVersion: version,
        candidateBuild: build35,
        allowsReinstall: false
    ) == .newer)
    #expect(UpdateEligibility.evaluate(
        currentVersion: version,
        currentBuild: build34,
        candidateVersion: version,
        candidateBuild: build34,
        allowsReinstall: false
    ) == .notNewer)
    #expect(UpdateEligibility.evaluate(
        currentVersion: version,
        currentBuild: build34,
        candidateVersion: version,
        candidateBuild: build34,
        allowsReinstall: true
    ) == .reinstall)
    #expect(UpdateEligibility.evaluate(
        currentVersion: version,
        currentBuild: build35,
        candidateVersion: nextVersion,
        candidateBuild: build34,
        allowsReinstall: false
    ) == .invalidBuildRegression)
    #expect(UpdateEligibility.evaluate(
        currentVersion: version,
        currentBuild: build35,
        candidateVersion: nextVersion,
        candidateBuild: build35,
        allowsReinstall: false
    ) == .notNewer)
}

@Test("update readiness marker is restricted to updater temporary directories")
func updateReadinessMarkerIsRestricted() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("ShelterBarUpdate-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let marker = root.appendingPathComponent("ready")
    UpdateReadiness.signalIfRequested(environment: ["SHELTERBAR_UPDATE_READY_FILE": marker.path])
    #expect(fileManager.fileExists(atPath: marker.path))

    let rejected = root.appendingPathComponent("not-ready")
    UpdateReadiness.signalIfRequested(environment: ["SHELTERBAR_UPDATE_READY_FILE": rejected.path])
    #expect(!fileManager.fileExists(atPath: rejected.path))
}

@Test("SHA256SUMS parsing verifies the selected release asset")
func sha256ManifestParsingAndVerification() throws {
    let filename = "ShelterBar-0.5.12-macos-arm64.zip"
    let manifest = try SHA256Manifest(text: """
    239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5  \(filename)
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa *ShelterBar-0.5.12-macos-arm64.dmg
    """)

    #expect(manifest.expectedHash(for: filename)
        == "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5")
    #expect(try manifest.verify(Data("payload".utf8), named: filename))
    #expect(try !manifest.verify(Data("tampered".utf8), named: filename))
}

@Test("release selection includes prereleases and requires complete non-draft assets")
func releaseSelectionIncludesPrereleases() throws {
    let data = Data("""
    [
      {"tag_name":"v0.5.11","draft":false,"prerelease":true,"assets":[
        {"name":"ShelterBar-0.5.11-macos-arm64.zip","browser_download_url":"https://example.test/0.5.11.zip"},
        {"name":"SHA256SUMS","browser_download_url":"https://example.test/0.5.11.sha"}
      ]},
      {"tag_name":"v0.6.0-beta.1","draft":false,"prerelease":true,"assets":[
        {"name":"ShelterBar-0.6.0-beta.1-macos-arm64.zip","browser_download_url":"https://example.test/0.6.0-beta.1.zip"},
        {"name":"SHA256SUMS","browser_download_url":"https://example.test/0.6.0-beta.1.sha"}
      ]},
      {"tag_name":"v9.0.0","draft":true,"prerelease":false,"assets":[
        {"name":"ShelterBar-9.0.0-macos-arm64.zip","browser_download_url":"https://example.test/9.0.0.zip"},
        {"name":"SHA256SUMS","browser_download_url":"https://example.test/9.0.0.sha"}
      ]},
      {"tag_name":"v1.0.0","draft":false,"prerelease":false,"assets":[]}
    ]
    """.utf8)
    let catalog = try ReleaseCatalog(data: data)
    let current = try #require(ShelterBarVersion("0.5.11"))

    let automatic = try #require(catalog.latest(for: current))
    #expect(automatic.version.description == "0.6.0-beta.1")
    #expect(automatic.archive.name == "ShelterBar-0.6.0-beta.1-macos-arm64.zip")
    #expect(automatic.checksums.name == "SHA256SUMS")

    let atLatest = try #require(ShelterBarVersion("0.6.0-beta.1"))
    #expect(catalog.latest(for: atLatest)?.version == atLatest)

    let beyondLatest = try #require(ShelterBarVersion("0.6.0-beta.2"))
    #expect(catalog.latest(for: beyondLatest) == nil)
}
