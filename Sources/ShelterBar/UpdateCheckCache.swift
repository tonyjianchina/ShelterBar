import Foundation
import CryptoKit

/// A memo of a fully validated release that the installed app already has.
/// The feed is always fetched; changing either asset invalidates this memo,
/// including a higher build published under the same marketing version.
struct UpdateCheckCache {
    private struct Identity: Codable, Equatable {
        let feed: URL
        let installedVersion: String
        let installedBuild: String
        let releaseVersion: String
        let archiveURL: URL
        let checksumURL: URL
        let archiveDigest: String
        let checksumDigest: String
    }

    private static let key = "updates.verifiedCurrentRelease.v1"
    let defaults: UserDefaults

    func contains(candidate: ReleaseCandidate, feed: URL,
                  version: ShelterBarVersion, build: ShelterBarBuildNumber) -> Bool {
        guard let identity = identity(candidate: candidate, feed: feed, version: version, build: build),
              let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode(Identity.self, from: data) else { return false }
        return saved == identity
    }

    /// Call only after UpdateInstaller has verified the bundle and returned
    /// no installation plan. Payload hashes must also match feed metadata;
    /// missing or stale metadata disables the optimization, never validation.
    func record(candidate: ReleaseCandidate, feed: URL, version: ShelterBarVersion,
                build: ShelterBarBuildNumber, archive: Data, checksums: Data) {
        guard let identity = identity(candidate: candidate, feed: feed, version: version, build: build),
              identity.archiveDigest == Self.digest(archive),
              identity.checksumDigest == Self.digest(checksums),
              let data = try? JSONEncoder().encode(identity) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private func identity(candidate: ReleaseCandidate, feed: URL,
                          version: ShelterBarVersion, build: ShelterBarBuildNumber) -> Identity? {
        guard let archive = Self.validDigest(candidate.archive.digest),
              let checksums = Self.validDigest(candidate.checksums.digest) else { return nil }
        return Identity(feed: feed, installedVersion: version.description,
                        installedBuild: build.description, releaseVersion: candidate.version.description,
                        archiveURL: candidate.archive.downloadURL, checksumURL: candidate.checksums.downloadURL,
                        archiveDigest: archive, checksumDigest: checksums)
    }

    private static func validDigest(_ raw: String?) -> String? {
        guard let raw = raw?.lowercased(), raw.hasPrefix("sha256:") else { return nil }
        let hash = raw.dropFirst(7)
        guard hash.count == 64, hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return raw
    }

    private static func digest(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
