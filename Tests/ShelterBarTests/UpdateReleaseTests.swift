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

    let automatic = try #require(catalog.latest(for: current, allowsReinstall: false))
    #expect(automatic.version.description == "0.6.0-beta.1")
    #expect(automatic.archive.name == "ShelterBar-0.6.0-beta.1-macos-arm64.zip")
    #expect(automatic.checksums.name == "SHA256SUMS")

    let atLatest = try #require(ShelterBarVersion("0.6.0-beta.1"))
    #expect(catalog.latest(for: atLatest, allowsReinstall: false) == nil)
    #expect(catalog.latest(for: atLatest, allowsReinstall: true)?.version == atLatest)
}
