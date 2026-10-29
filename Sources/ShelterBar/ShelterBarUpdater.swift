import AppKit
import Foundation
import OSLog

private let updateLog = Logger(subsystem: "com.jensen.shelterbar", category: "updates")

enum ShelterBarUpdateState: Equatable {
    case idle
    case checking
    case downloading(String)
    case verifying(String)
    case installing(String)
    case upToDate(String)
    case failed(String)

    var menuTitle: String {
        switch self {
        case .idle: "检查更新"
        case .failed: "更新失败，点击重试"
        case .checking: "正在检查更新…"
        case let .downloading(version): "正在下载 \(version)…"
        case let .verifying(version): "正在验证 \(version)…"
        case let .installing(version): "正在安装 \(version)…"
        case let .upToDate(version): "已是最新版 \(version)"
        }
    }

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing: true
        case .idle, .upToDate, .failed: false
        }
    }
}

struct UpdatePreparation: Sendable {
    let candidate: ReleaseCandidate
    let archiveData: Data
    let checksumData: Data
    let currentAppURL: URL
    let currentVersion: ShelterBarVersion
    let currentBuild: ShelterBarBuildNumber
    let allowsReinstall: Bool
}

/// Injectable I/O keeps regression tests on the real updater flow without
/// contacting GitHub, changing an installed app, or terminating the test host.
struct UpdateOperations: Sendable {
    var fetch: @Sendable (URL, Int) async throws -> Data = {
        try await UpdateHTTPClient.get($0, maximumBytes: $1)
    }
    var prepare: @Sendable (UpdatePreparation) async throws -> UpdateInstallPlan? = { request in
        try await Task.detached(priority: .userInitiated) {
            try UpdateInstaller.prepare(
                candidate: request.candidate, archiveData: request.archiveData,
                checksumData: request.checksumData, currentAppURL: request.currentAppURL,
                currentVersion: request.currentVersion, currentBuild: request.currentBuild,
                allowsReinstall: request.allowsReinstall
            )
        }.value
    }
}

private struct UpdateConfiguration {
    static let defaultFeedURL = URL(string: "https://api.github.com/repos/tonyjianchina/ShelterBar/releases?per_page=30")!

    let feedURL: URL
    let automaticUpdatesDisabled: Bool
    let initialDelay: Duration
    let interval: Duration

    init(defaults: UserDefaults, environment: [String: String]) {
        let override = environment["SHELTERBAR_UPDATE_FEED_URL"]
            ?? defaults.string(forKey: "updates.feedURL")
        feedURL = override.flatMap(URL.init(string:)) ?? Self.defaultFeedURL
        automaticUpdatesDisabled = environment["SHELTERBAR_DISABLE_AUTOMATIC_UPDATES"] == "1"
            || defaults.bool(forKey: "updates.disableAutomatic")
        let initialSeconds = environment["SHELTERBAR_UPDATE_INITIAL_DELAY_SECONDS"].flatMap(Double.init)
            ?? defaults.object(forKey: "updates.initialDelaySeconds").flatMap { $0 as? Double }
            ?? 5
        let intervalSeconds = environment["SHELTERBAR_UPDATE_INTERVAL_SECONDS"].flatMap(Double.init)
            ?? defaults.object(forKey: "updates.intervalSeconds").flatMap { $0 as? Double }
            ?? 21_600
        initialDelay = .seconds(max(0, initialSeconds))
        interval = .seconds(max(60, intervalSeconds))
    }
}

private enum UpdateNetworkError: LocalizedError {
    case unsupportedURL(URL)
    case invalidResponse
    case status(Int, URL)
    case responseTooLarge(URL)

    var errorDescription: String? {
        switch self {
        case let .unsupportedURL(url): "不允许的更新地址：\(url.absoluteString)"
        case .invalidResponse: "更新服务器返回了无效响应"
        case let .status(code, url): "更新服务器返回 HTTP \(code)：\(url.host ?? url.absoluteString)"
        case let .responseTooLarge(url): "更新响应超过大小限制：\(url.lastPathComponent)"
        }
    }
}

private enum UpdateHTTPClient {
    static func get(_ url: URL, maximumBytes: Int) async throws -> Data {
        guard url.scheme == "https" || (url.scheme == "http" && isLoopback(url.host)) else {
            throw UpdateNetworkError.unsupportedURL(url)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShelterBar-Updater", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateNetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw UpdateNetworkError.status(http.statusCode, url) }
        guard http.expectedContentLength <= Int64(maximumBytes) else {
            throw UpdateNetworkError.responseTooLarge(url)
        }
        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(Int(http.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw UpdateNetworkError.responseTooLarge(url) }
            data.append(byte)
        }
        return data
    }

    private static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}

@MainActor
final class ShelterBarUpdater {
    var onStateChange: ((ShelterBarUpdateState) -> Void)?
    private(set) var isUserInitiated = false
    private(set) var state: ShelterBarUpdateState = .idle {
        didSet {
            onStateChange?(state)
            record(state)
        }
    }

    private let defaults: UserDefaults
    private let configuration: UpdateConfiguration
    private let currentVersion: ShelterBarVersion?
    private let currentBuild: ShelterBarBuildNumber?
    private let currentAppURL: URL
    private let operations: UpdateOperations
    private var automaticTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        operations: UpdateOperations = UpdateOperations()
    ) {
        self.defaults = defaults
        self.operations = operations
        configuration = UpdateConfiguration(defaults: defaults, environment: environment)
        currentVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(ShelterBarVersion.init)
        currentBuild = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap(ShelterBarBuildNumber.init)
        currentAppURL = bundle.bundleURL
    }

    func startAutomaticUpdates() {
        guard automaticTask == nil, !configuration.automaticUpdatesDisabled else { return }
        automaticTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: configuration.initialDelay) } catch { return }
            while !Task.isCancelled {
                beginUpdate(allowsReinstall: false)
                do { try await Task.sleep(for: configuration.interval) } catch { return }
            }
        }
    }

    func checkForUpdatesAndInstall() {
        beginUpdate(allowsReinstall: true)
    }

    func stop() {
        automaticTask?.cancel()
        automaticTask = nil
        updateTask?.cancel()
        updateTask = nil
    }

    private func beginUpdate(allowsReinstall: Bool) {
        guard updateTask == nil else { return }
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await performUpdate(allowsReinstall: allowsReinstall)
            updateTask = nil
        }
    }

    func performUpdate(allowsReinstall: Bool) async {
        isUserInitiated = allowsReinstall
        guard let currentVersion, let currentBuild else {
            fail("无法读取当前版本或构建号")
            return
        }
        do {
            state = .checking
            updateLog.notice("checking \(self.configuration.feedURL.absoluteString, privacy: .public) from \(currentVersion.description, privacy: .public) (\(currentBuild.description, privacy: .public)); reinstall=\(allowsReinstall)")
            let feedData = try await operations.fetch(configuration.feedURL, 5 * 1_024 * 1_024)
            try Task.checkCancellation()
            let catalog = try ReleaseCatalog(data: feedData)
            guard let candidate = catalog.latest(for: currentVersion) else {
                state = .upToDate(currentVersion.description)
                updateLog.notice("up to date at \(currentVersion.description, privacy: .public)")
                return
            }
            let cache = UpdateCheckCache(defaults: defaults)
            if !allowsReinstall, cache.contains(candidate: candidate, feed: configuration.feedURL,
                                                version: currentVersion, build: currentBuild) {
                state = .upToDate("\(currentVersion) (\(currentBuild))")
                return
            }
            state = .downloading(candidate.version.description)
            updateLog.notice("downloading update \(candidate.version.description, privacy: .public)")
            async let archive = operations.fetch(candidate.archive.downloadURL, 250 * 1_024 * 1_024)
            async let checksums = operations.fetch(candidate.checksums.downloadURL, 1 * 1_024 * 1_024)
            let (archiveData, checksumData) = try await (archive, checksums)
            try Task.checkCancellation()
            state = .verifying(candidate.version.description)
            let plan = try await operations.prepare(UpdatePreparation(
                    candidate: candidate,
                    archiveData: archiveData,
                    checksumData: checksumData,
                    currentAppURL: currentAppURL,
                    currentVersion: currentVersion,
                    currentBuild: currentBuild,
                    allowsReinstall: allowsReinstall
                ))
            guard let plan else {
                try Task.checkCancellation()
                cache.record(candidate: candidate, feed: configuration.feedURL, version: currentVersion,
                             build: currentBuild, archive: archiveData, checksums: checksumData)
                state = .upToDate("\(currentVersion) (\(currentBuild))")
                updateLog.notice("up to date at \(currentVersion.description, privacy: .public) (\(currentBuild.description, privacy: .public))")
                return
            }
            state = .installing(candidate.version.description)
            try plan.launchHelper()
            updateLog.notice("verified update \(candidate.version.description, privacy: .public); terminating for replacement")
            NSApp.terminate(nil)
        } catch is CancellationError {
            state = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        updateLog.error("update rejected: \(message, privacy: .public)")
        state = .failed(message)
    }

    private func record(_ state: ShelterBarUpdateState) {
        let value: String
        switch state {
        case .idle: value = "idle"
        case .checking: value = "checking"
        case let .downloading(version): value = "downloading:\(version)"
        case let .verifying(version): value = "verifying:\(version)"
        case let .installing(version): value = "installing:\(version)"
        case let .upToDate(version): value = "up-to-date:\(version)"
        case let .failed(message): value = "failed:\(message)"
        }
        defaults.set(value, forKey: "updates.lastStatus")
        defaults.set(Date(), forKey: "updates.lastStatusDate")
    }
}
