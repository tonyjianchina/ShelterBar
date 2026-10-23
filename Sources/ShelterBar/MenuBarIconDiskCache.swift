import AppKit
import CryptoKit
import OSLog

private let iconCacheLog = Logger(subsystem: "com.jensen.shelterbar", category: "icon-cache")

/// Metadata for one persisted status item glyph.
struct MenuBarIconCacheRecord: Codable, Equatable {
    var key: String
    var file: String
    var width: Double
    var height: Double
    var isTemplate: Bool
    var tone: Int
    var byteCount: Int
    var digest: String
    var updatedAt: Date
    /// Neutral shaded glyph stored as one appearance-specific rendering; it is
    /// re-derived on load so it keeps adapting to light/dark. Optional so
    /// indexes written before this field still decode.
    var adaptive: Bool? = nil
    /// v1 removes composite wallpaper/overflow artefacts and numeric labels.
    var visualVersion: Int? = nil
}

/// Persists captured glyphs of stowed items so the shelf can show real icons
/// right after launch, while those items are still off-screen and cannot be
/// captured again. Only items with a stable identity are stored.
@MainActor
final class MenuBarIconDiskCache {
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShelterBar/IconCache", isDirectory: true)
    }

    static let indexName = "index.json"
    static let maxImageBytes = 256 * 1024

    let directory: URL
    let maxEntries: Int
    let maxBytes: Int
    private(set) var records: [String: MenuBarIconCacheRecord] = [:]
    private var images: [String: NSImage] = [:]

    init(directory: URL = MenuBarIconDiskCache.defaultDirectory,
         maxEntries: Int = 128, maxBytes: Int = 4 * 1024 * 1024) {
        self.directory = directory
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
        loadIndex()
    }

    /// Keys follow the shelf model's item id ("ax:<bundle id>:<AX identifier
    /// or main>"). Session-only ids embed a pid or element hash and would never
    /// match again after a restart, so they are not persisted.
    static func isCacheable(key: String) -> Bool {
        key.hasPrefix("ax:") && !key.hasPrefix("ax:pid:") && !key.contains(":session-")
    }

    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    var keys: Set<String> { Set(records.keys) }

    func image(for key: String, hasCount: Bool = false) -> NSImage? {
        if let image = images[key] { return image }
        guard let record = records[key],
              let data = try? Data(contentsOf: directory.appendingPathComponent(record.file)),
              let rep = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: record.width, height: record.height)
        if record.visualVersion == nil, hasCount || (!record.isTemplate && record.adaptive != true),
           let pixels = rep.cgImage {
            guard let repaired = MenuBarCompositeGlyph.make(from: pixels, logicalSize: size, hasCount: hasCount) else {
                // A saved system chevron is not a usable app icon. Leave it
                // missing so the normal explicit refresh can recapture it.
                remove(key)
                saveIndex()
                return nil
            }
            store(repaired, for: key)
            return repaired
        }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = record.isTemplate
        if !record.isTemplate, let tone = MenuBarGlyphTone(rawValue: record.tone) {
            MenuBarGlyphImage.setTone(tone, on: image)
        }
        // A neutral shaded glyph is stored as one appearance-specific variant.
        // Re-derive it so the light/dark adaptive rendering survives a restart.
        var restored = image
        if record.adaptive == true, !record.isTemplate, let cgImage = rep.cgImage,
           let remade = MenuBarGlyphImage.make(from: cgImage, logicalSize: size), !remade.isTemplate {
            restored = remade
        }
        images[key] = restored
        return restored
    }

    /// Stores a fresh non-empty capture. Returns true when it is on disk.
    @discardableResult
    func store(_ image: NSImage, for key: String, now: Date = Date()) -> Bool {
        guard Self.isCacheable(key: key), image.size.width > 0, image.size.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]),
              !png.isEmpty, png.count <= Self.maxImageBytes else { return false }
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let record = MenuBarIconCacheRecord(
            key: key, file: Self.fileName(for: key),
            width: Double(image.size.width), height: Double(image.size.height),
            isTemplate: image.isTemplate, tone: MenuBarGlyphImage.tone(of: image).rawValue,
            byteCount: png.count, digest: digest, updatedAt: now,
            adaptive: MenuBarGlyphImage.isAdaptiveNeutral(image) ? true : nil,
            visualVersion: 1
        )
        images[key] = image
        if let old = records[key], old.digest == digest, old.isTemplate == record.isTemplate,
           old.tone == record.tone, old.width == record.width, old.height == record.height,
           old.adaptive == record.adaptive, old.visualVersion == record.visualVersion {
            return true
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(record.file), options: .atomic)
        } catch {
            iconCacheLog.error("could not write icon cache: \(error.localizedDescription, privacy: .public)")
            return false
        }
        records[key] = record
        enforceLimits()
        saveIndex()
        return records[key] != nil
    }

    /// Drops entries for items that are no longer tracked.
    func prune(keeping keep: Set<String>) {
        let stale = records.keys.filter { !keep.contains($0) }
        guard !stale.isEmpty else { return }
        for key in stale { remove(key) }
        saveIndex()
    }

    private func remove(_ key: String) {
        guard let record = records.removeValue(forKey: key) else { return }
        images.removeValue(forKey: key)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.file))
    }

    private func enforceLimits() {
        var total = records.values.reduce(0) { $0 + $1.byteCount }
        for record in records.values.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            guard records.count > maxEntries || total > maxBytes else { break }
            total -= record.byteCount
            remove(record.key)
        }
    }

    private func loadIndex() {
        let url = directory.appendingPathComponent(Self.indexName)
        guard let data = try? Data(contentsOf: url),
              let list = try? { () -> JSONDecoder in
                  let decoder = JSONDecoder()
                  decoder.dateDecodingStrategy = .iso8601
                  return decoder
              }().decode([MenuBarIconCacheRecord].self, from: data) else { return }
        for record in list where Self.isCacheable(key: record.key) && record.file == Self.fileName(for: record.key)
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent(record.file).path) {
            records[record.key] = record
        }
        // Remove orphaned images left by an interrupted write.
        let known = Set(records.values.map(\.file))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            where name.hasSuffix(".png") && !known.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func saveIndex() {
        let list = records.values.sorted { $0.key < $1.key }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(list).write(to: directory.appendingPathComponent(Self.indexName), options: .atomic)
        } catch {
            iconCacheLog.error("could not write icon cache index: \(error.localizedDescription, privacy: .public)")
        }
    }
}
