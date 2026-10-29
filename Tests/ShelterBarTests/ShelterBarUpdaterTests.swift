import AppKit
import CryptoKit
import Foundation
import Testing
@testable import ShelterBar

private actor UpdateFixtureServer {
    var archive = Data(repeating: 0x41, count: 611_877)
    var checksums = Data("verified checksums fixture".utf8)
    var includeDigests = true
    var digestOverride: String?
    var preparationError: Bool = false
    var cancellation: Bool = false
    private(set) var requested: [URL] = []
    private(set) var bytes = 0
    private(set) var preparations = 0
    private(set) var reinstallFlags: [Bool] = []

    func setFailure(_ value: Bool) { preparationError = value }
    func setCancellation(_ value: Bool) { cancellation = value }
    func omitDigests() { includeDigests = false }
    func overrideDigest(_ digest: String) { digestOverride = digest }
    func replaceArchive() { archive.append(0x42) }
    func replaceChecksums() { checksums.append(0x42) }

    func fetch(_ url: URL) throws -> Data {
        requested.append(url)
        let data: Data
        switch url.lastPathComponent {
        case "ShelterBar-0.5.12-macos-arm64.zip": data = archive
        case "SHA256SUMS": data = checksums
        default:
            func asset(_ name: String, _ contents: Data) -> [String: Any] {
                var fields: [String: Any] = [
                    "name": name, "browser_download_url": "https://updates.example.test/\(name)"
                ]
                if includeDigests {
                    fields["digest"] = digestOverride ?? "sha256:" + SHA256.hash(data: contents)
                        .map { String(format: "%02x", $0) }.joined()
                }
                return fields
            }
            data = try JSONSerialization.data(withJSONObject: [[
                "tag_name": "v0.5.12", "draft": false, "prerelease": true,
                "assets": [asset("ShelterBar-0.5.12-macos-arm64.zip", archive), asset("SHA256SUMS", checksums)]
            ]])
        }
        bytes += data.count
        return data
    }

    func prepare(_ request: UpdatePreparation) throws -> UpdateInstallPlan? {
        preparations += 1
        reinstallFlags.append(request.allowsReinstall)
        if cancellation { throw CancellationError() }
        if preparationError { throw UpdateValidationError.checksumMismatch(request.candidate.archive.name) }
        return nil
    }

    func totals() -> (requests: Int, bytes: Int, preparations: Int) {
        (requested.count, bytes, preparations)
    }
}

@MainActor
private final class UpdaterFixture {
    let server = UpdateFixtureServer()
    let defaults: UserDefaults
    let root: URL
    let suite = "ShelterBarUpdaterTests.\(UUID().uuidString)"
    let bundle: Bundle

    init(build: String = "36") throws {
        defaults = UserDefaults(suiteName: suite)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ShelterBarUpdaterTests-\(UUID().uuidString)")
        let app = root.appendingPathComponent("ShelterBar.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.jensen.shelterbar",
            "CFBundleShortVersionString": "0.5.12", "CFBundleVersion": build,
            "CFBundlePackageType": "APPL"
        ], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        bundle = try #require(Bundle(url: app))
    }

    func updater(feed: String = "https://updates.example.test/releases", installedBundle: Bundle? = nil) -> ShelterBarUpdater {
        let server = server
        return ShelterBarUpdater(bundle: installedBundle ?? bundle, defaults: defaults,
            environment: ["SHELTERBAR_UPDATE_FEED_URL": feed],
            operations: UpdateOperations(
                fetch: { url, _ in try await server.fetch(url) },
                prepare: { try await server.prepare($0) }
            ))
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@Test("unchanged automatic updates fetch only the feed after one full verification, across restarts")
@MainActor
func updaterSkipsPreviouslyVerifiedPayload() async throws {
    let fixture = try UpdaterFixture()
    defer { fixture.cleanUp() }
    let first = fixture.updater()
    await first.performUpdate(allowsReinstall: false)
    let firstTotals = await fixture.server.totals()
    #expect(firstTotals.requests == 3)
    #expect(firstTotals.preparations == 1)
    #expect(first.state == .upToDate("0.5.12 (36)"))

    let restarted = fixture.updater()
    await restarted.performUpdate(allowsReinstall: false)
    let secondTotals = await fixture.server.totals()
    #expect(secondTotals.requests - firstTotals.requests == 1)
    #expect(secondTotals.preparations == 1)
    #expect(secondTotals.bytes - firstTotals.bytes < 1_000)
    #expect(!restarted.isUserInitiated)
    print("Update fixture: cold \(firstTotals.requests) requests / \(firstTotals.bytes) bytes; warm \(secondTotals.requests - firstTotals.requests) request / \(secondTotals.bytes - firstTotals.bytes) bytes; preparations \(secondTotals.preparations)")
}

@Test("replacing either same-version release asset invalidates the verified result", arguments: [false, true])
@MainActor
func updaterNoticesReplacedSameVersionAssets(checksumsOnly: Bool) async throws {
    let fixture = try UpdaterFixture()
    defer { fixture.cleanUp() }
    let updater = fixture.updater()
    await updater.performUpdate(allowsReinstall: false)
    if checksumsOnly { await fixture.server.replaceChecksums() } else { await fixture.server.replaceArchive() }
    await updater.performUpdate(allowsReinstall: false)
    let totals = await fixture.server.totals()
    #expect(totals.requests == 6)
    #expect(totals.preparations == 2)
}

@Test("manual reinstall and changed feeds bypass a previously verified result", arguments: [false, true])
@MainActor
func updaterManualAndFeedChangesCheckFully(manual: Bool) async throws {
    let fixture = try UpdaterFixture()
    defer { fixture.cleanUp() }
    await fixture.updater().performUpdate(allowsReinstall: false)
    let updater = fixture.updater(feed: manual ? "https://updates.example.test/releases" : "https://other.example.test/releases")
    await updater.performUpdate(allowsReinstall: manual)
    let totals = await fixture.server.totals()
    #expect(totals.requests == 6)
    #expect(totals.preparations == 2)
    #expect(await fixture.server.reinstallFlags == [false, manual])
    #expect(updater.isUserInitiated == manual)
}

@Test("missing asset digests never skip a fresh validation")
@MainActor
func updaterWithoutDigestsChecksFully() async throws {
    let fixture = try UpdaterFixture()
    defer { fixture.cleanUp() }
    await fixture.server.omitDigests()
    let updater = fixture.updater()
    await updater.performUpdate(allowsReinstall: false)
    await updater.performUpdate(allowsReinstall: false)
    #expect(await fixture.server.totals().preparations == 2)
}

@Test("invalid or mismatched feed digests never become a verified cache", arguments: ["md5:abcd", "sha256:" + String(repeating: "0", count: 64)])
@MainActor
func updaterDoesNotTrustUnverifiedFeedDigests(digest: String) async throws {
    let fixture = try UpdaterFixture()
    defer { fixture.cleanUp() }
    await fixture.server.overrideDigest(digest)
    let updater = fixture.updater()
    await updater.performUpdate(allowsReinstall: false)
    await updater.performUpdate(allowsReinstall: false)
    #expect(await fixture.server.totals().preparations == 2)
}

@Test("changing the installed build invalidates a result verified for the previous installation")
@MainActor
func updaterInstalledBuildChangesCheckFully() async throws {
    let fixture = try UpdaterFixture()
    let changed = try UpdaterFixture(build: "37")
    defer { fixture.cleanUp(); changed.cleanUp() }
    await fixture.updater().performUpdate(allowsReinstall: false)
    await fixture.updater(installedBundle: changed.bundle).performUpdate(allowsReinstall: false)
    #expect(await fixture.server.totals().preparations == 2)
}

@Test("failed and cancelled verifications remain retryable and never create a verified cache", arguments: [false, true])
@MainActor
func updaterFailureDoesNotCache(cancelled: Bool) async throws {
    let fixture = try UpdaterFixture()
    defer { fixture.cleanUp() }
    await fixture.server.setFailure(!cancelled)
    await fixture.server.setCancellation(cancelled)
    let updater = fixture.updater()
    await updater.performUpdate(allowsReinstall: false)
    if cancelled { #expect(updater.state == .idle) }
    else { #expect(updater.state.menuTitle == "更新失败，点击重试") }
    await fixture.server.setFailure(false)
    await fixture.server.setCancellation(false)
    await updater.performUpdate(allowsReinstall: false)
    #expect(await fixture.server.totals().preparations == 2)
    #expect(updater.state == .upToDate("0.5.12 (36)"))
}

private struct EmptyUpdateShelfSource: ShelfItemSource {
    func items(deadline: ContinuousClock.Instant) -> ShelfItemScanResult {
        ShelfItemScanResult(items: [], isComplete: true)
    }
}

@Test("background update results keep shelf messages intact, while explicit checks explain their result")
@MainActor
func backgroundUpdateResultsDoNotInterruptShelf() {
    let model = ShelfViewModel(source: EmptyUpdateShelfSource(), isTrusted: { true })
    model.message = "existing layout guidance"
    model.applyUpdateState(.upToDate("0.5.12 (36)"), isUserInitiated: false)
    #expect(model.message == "existing layout guidance")
    model.applyUpdateState(.failed("网络不可用"), isUserInitiated: false)
    #expect(model.message == "existing layout guidance")
    #expect(model.updateMenuTitle == "更新失败，点击重试")
    model.applyUpdateState(.failed("网络不可用"), isUserInitiated: true)
    #expect(model.message == "更新失败：网络不可用")
    model.applyUpdateState(.upToDate("0.5.12 (36)"), isUserInitiated: true)
    #expect(model.message == "ShelterBar 0.5.12 (36) 已是最新版本。")
}
