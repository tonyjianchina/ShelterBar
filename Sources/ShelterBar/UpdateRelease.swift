import Foundation
import CryptoKit

enum UpdateValidationError: LocalizedError, Equatable {
    case malformedChecksumLine(String)
    case duplicateChecksum(String)
    case missingChecksum(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case let .malformedChecksumLine(line): "SHA256SUMS 包含无效行：\(line)"
        case let .duplicateChecksum(filename): "SHA256SUMS 重复定义了 \(filename)"
        case let .missingChecksum(filename): "SHA256SUMS 中找不到 \(filename)"
        case let .checksumMismatch(filename): "\(filename) 的 SHA256 校验失败"
        }
    }
}

struct SHA256Manifest: Sendable {
    private let hashes: [String: String]

    init(text: String) throws {
        var parsed: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { throw UpdateValidationError.malformedChecksumLine(line) }
            let hash = String(fields[0]).lowercased()
            var filename = String(fields[1]).trimmingCharacters(in: .whitespaces)
            if filename.first == "*" { filename.removeFirst() }
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }), !filename.isEmpty else {
                throw UpdateValidationError.malformedChecksumLine(line)
            }
            guard parsed[filename] == nil else { throw UpdateValidationError.duplicateChecksum(filename) }
            parsed[filename] = hash
        }
        hashes = parsed
    }

    func expectedHash(for filename: String) -> String? { hashes[filename] }

    func verify(_ data: Data, named filename: String) throws -> Bool {
        guard let expected = expectedHash(for: filename) else {
            throw UpdateValidationError.missingChecksum(filename)
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == expected
    }

    func verify(fileAt url: URL, named filename: String) throws {
        guard try verify(Data(contentsOf: url, options: .mappedIfSafe), named: filename) else {
            throw UpdateValidationError.checksumMismatch(filename)
        }
    }
}

struct ShelterBarVersion: Comparable, CustomStringConvertible, Sendable {
    private enum PrereleaseIdentifier: Equatable, Sendable {
        case number(Int)
        case text(String)
    }

    let major: Int
    let minor: Int
    let patch: Int
    private let prerelease: [PrereleaseIdentifier]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        let metadataPieces = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        if metadataPieces.count == 2 {
            let identifiers = metadataPieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ identifier in
                      !identifier.isEmpty
                          && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                  }) else { return nil }
        }
        value = String(metadataPieces[0])
        let pieces = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              core.allSatisfy({ Self.isValidNumericIdentifier($0) }),
              let major = Int(core[0]), let minor = Int(core[1]), let patch = Int(core[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        let prerelease: [PrereleaseIdentifier]
        if pieces.count == 1 {
            prerelease = []
        } else {
            let identifiers = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ identifier in
                      !identifier.isEmpty
                          && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                          && (!identifier.allSatisfy(\.isNumber) || Self.isValidNumericIdentifier(identifier))
                  }) else { return nil }
            prerelease = identifiers.map { identifier in
                if let value = Int(identifier), identifier.allSatisfy(\.isNumber) {
                    return .number(value)
                }
                return .text(String(identifier))
            }
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    private static func isValidNumericIdentifier(_ value: Substring) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber }
            && (value.count == 1 || value.first != "0")
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prerelease.isEmpty else { return core }
        let suffix = prerelease.map {
            switch $0 {
            case let .number(value): String(value)
            case let .text(value): value
            }
        }.joined(separator: ".")
        return "\(core)-\(suffix)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore { return lhsCore.lexicographicallyPrecedes(rhsCore) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (left, right) {
            case let (.number(a), .number(b)): return a < b
            case (.number, .text): return true
            case (.text, .number): return false
            case let (.text(a), .text(b)): return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct ShelterBarBuildNumber: Comparable, CustomStringConvertible, Sendable {
    private let components: [UInt64]

    init?(_ rawValue: String) {
        let pieces = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count),
              pieces.allSatisfy({ piece in
                  !piece.isEmpty && piece.allSatisfy { $0.isASCII && $0.isNumber }
                      && (piece.count == 1 || piece.first != "0")
              }) else { return nil }
        var parsed = pieces.compactMap { UInt64(String($0)) }
        guard parsed.count == pieces.count else { return nil }
        while parsed.count > 1, parsed.last == 0 { parsed.removeLast() }
        components = parsed
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum UpdateEligibility: Equatable, Sendable {
    case newer
    case reinstall
    case notNewer
    case invalidBuildRegression

    static func evaluate(
        currentVersion: ShelterBarVersion,
        currentBuild: ShelterBarBuildNumber,
        candidateVersion: ShelterBarVersion,
        candidateBuild: ShelterBarBuildNumber,
        allowsReinstall: Bool
    ) -> Self {
        guard candidateVersion >= currentVersion else { return .notNewer }
        if candidateBuild > currentBuild { return .newer }
        if candidateBuild < currentBuild { return .invalidBuildRegression }
        if candidateVersion == currentVersion, allowsReinstall { return .reinstall }
        return .notNewer
    }
}

struct ReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let digest: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case digest
    }
}

struct ReleaseCandidate: Equatable, Sendable {
    let version: ShelterBarVersion
    let archive: ReleaseAsset
    let checksums: ReleaseAsset
}

struct ReleaseCatalog: Sendable {
    private struct GitHubRelease: Decodable, Sendable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [ReleaseAsset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }
    }

    private let releases: [GitHubRelease]

    init(data: Data) throws {
        releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    /// GitHub's releases endpoint includes prereleases; only drafts are private
    /// publishing state and therefore ineligible. Each candidate must have the
    /// exact Apple Silicon ZIP plus the checksum manifest from the same release.
    func latest(for current: ShelterBarVersion) -> ReleaseCandidate? {
        releases.compactMap { release -> ReleaseCandidate? in
            guard !release.draft, let version = ShelterBarVersion(release.tagName),
                  version >= current else { return nil }
            let archiveName = "ShelterBar-\(version)-macos-arm64.zip"
            guard let archive = release.assets.first(where: { $0.name == archiveName }),
                  let checksums = release.assets.first(where: { $0.name == "SHA256SUMS" }) else { return nil }
            return ReleaseCandidate(version: version, archive: archive, checksums: checksums)
        }.max { $0.version < $1.version }
    }
}
