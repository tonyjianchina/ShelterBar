import Foundation

enum UpdateInstallError: LocalizedError {
    case invalidManifest
    case invalidBundle(String)
    case commandFailed(String, String)
    case installLocationNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: "SHA256SUMS 不是 UTF-8 文本"
        case let .invalidBundle(reason): "更新包无效：\(reason)"
        case let .commandFailed(command, output): "\(command) 失败：\(output)"
        case let .installLocationNotWritable(path): "无法写入安装位置：\(path)"
        }
    }
}

struct UpdateInstallPlan: Sendable {
    let helperURL: URL
    let arguments: [String]

    func launchHelper() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helperURL.path] + arguments
        try process.run()
    }
}

enum UpdateInstaller {
    static let expectedBundleIdentifier = "com.jensen.shelterbar"
    static let expectedCertificateSHA1 = "abcd7a5b7b4ff47f6e6448fab665faf8f0c5f910"
    static let expectedDesignatedRequirement = "identifier \"\(expectedBundleIdentifier)\" and certificate leaf = H\"\(expectedCertificateSHA1)\""

    static func prepare(
        candidate: ReleaseCandidate,
        archiveData: Data,
        checksumData: Data,
        currentAppURL: URL,
        currentVersion: ShelterBarVersion,
        currentBuild: ShelterBarBuildNumber,
        allowsReinstall: Bool,
        currentPID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws -> UpdateInstallPlan? {
        guard currentAppURL.lastPathComponent == "ShelterBar.app" else {
            throw UpdateInstallError.invalidBundle("当前应用不是 ShelterBar.app")
        }
        let parent = currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.installLocationNotWritable(parent.path)
        }
        guard let checksumText = String(data: checksumData, encoding: .utf8) else {
            throw UpdateInstallError.invalidManifest
        }
        let manifest = try SHA256Manifest(text: checksumText)
        guard try manifest.verify(archiveData, named: candidate.archive.name) else {
            throw UpdateValidationError.checksumMismatch(candidate.archive.name)
        }

        let fileManager = FileManager.default
        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ShelterBarUpdate-\(UUID().uuidString)", isDirectory: true)
        let extracted = workRoot.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        let archiveURL = workRoot.appendingPathComponent(candidate.archive.name)
        try archiveData.write(to: archiveURL, options: .atomic)
        do {
            try run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, extracted.path])
            let app = extracted.appendingPathComponent("ShelterBar.app", isDirectory: true)
            let candidateBuild = try validate(app: app, version: candidate.version)
            switch UpdateEligibility.evaluate(
                currentVersion: currentVersion,
                currentBuild: currentBuild,
                candidateVersion: candidate.version,
                candidateBuild: candidateBuild,
                allowsReinstall: allowsReinstall
            ) {
            case .newer, .reinstall:
                break
            case .notNewer:
                try fileManager.removeItem(at: workRoot)
                return nil
            case .invalidBuildRegression:
                throw UpdateInstallError.invalidBundle(
                    "构建号从 \(currentBuild) 倒退为 \(candidateBuild)"
                )
            }

            let token = UUID().uuidString
            let staged = parent.appendingPathComponent(".ShelterBar.update-\(token).app", isDirectory: true)
            let backup = parent.appendingPathComponent(".ShelterBar.backup-\(token).app", isDirectory: true)
            try fileManager.copyItem(at: app, to: staged)
            try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

            let helper = workRoot.appendingPathComponent("install-update.sh")
            try helperScript.write(to: helper, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)

            let logDirectory = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/ShelterBar", isDirectory: true)
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let log = logDirectory.appendingPathComponent("update-helper.log")
            return UpdateInstallPlan(
                helperURL: helper,
                arguments: [currentAppURL.path, staged.path, backup.path, String(currentPID), log.path, workRoot.path]
            )
        } catch {
            try? fileManager.removeItem(at: workRoot)
            throw error
        }
    }

    private static func validate(app: URL, version: ShelterBarVersion) throws -> ShelterBarBuildNumber {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
              info["CFBundleIdentifier"] as? String == expectedBundleIdentifier,
              let rawVersion = info["CFBundleShortVersionString"] as? String,
              ShelterBarVersion(rawVersion) == version,
              let rawBuild = info["CFBundleVersion"] as? String,
              let build = ShelterBarBuildNumber(rawBuild) else {
            throw UpdateInstallError.invalidBundle("标识符、版本或构建号与 release 不一致")
        }
        let executable = app.appendingPathComponent("Contents/MacOS/ShelterBar")
        let architectures = try run("/usr/bin/lipo", ["-archs", executable.path])
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard architectures == ["arm64"] else {
            throw UpdateInstallError.invalidBundle("期望 arm64，实际为 \(architectures.joined(separator: ", "))")
        }
        try run("/usr/bin/codesign", [
            "--verify", "--deep", "--strict", "--verbose=2",
            "-R=\(expectedDesignatedRequirement)", app.path,
        ])
        let requirementOutput = try run("/usr/bin/codesign", ["-d", "-r-", app.path])
        guard requirementOutput.lowercased().contains("designated => \(expectedDesignatedRequirement)".lowercased()) else {
            throw UpdateInstallError.invalidBundle("designated requirement 不匹配")
        }
        return build
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError.commandFailed(URL(fileURLWithPath: executable).lastPathComponent, output)
        }
        return output
    }

    private static let helperScript = #"""
#!/bin/sh
set -u
target=$1
staged=$2
backup=$3
old_pid=$4
log_file=$5
work_root=$6
exec >> "$log_file" 2>&1
date '+%Y-%m-%d %H:%M:%S update helper started'

relaunch_target() {
    if [ -x "$target/Contents/MacOS/ShelterBar" ]; then
        /usr/bin/nohup "$target/Contents/MacOS/ShelterBar" >/dev/null 2>&1 &
        echo "relaunched intact app; pid $!"
    else
        echo 'could not relaunch: target executable is missing'
    fi
}

attempt=0
while /bin/kill -0 "$old_pid" 2>/dev/null && [ "$attempt" -lt 300 ]; do
    /bin/sleep 0.1
    attempt=$((attempt + 1))
done
if /bin/kill -0 "$old_pid" 2>/dev/null; then
    echo 'old process did not exit; update cancelled'
    /bin/rm -rf "$staged" "$work_root"
    exit 1
fi
if [ ! -d "$target" ] || [ ! -d "$staged" ] || [ -e "$backup" ]; then
    echo 'install paths changed; update cancelled'
    /bin/rm -rf "$staged" "$work_root"
    relaunch_target
    exit 1
fi
if ! /bin/mv "$target" "$backup"; then
    echo 'could not create rollback copy'
    /bin/rm -rf "$staged" "$work_root"
    if [ ! -d "$target" ] && [ -d "$backup" ]; then
        /bin/mv "$backup" "$target" || true
    fi
    relaunch_target
    exit 1
fi
if ! /bin/mv "$staged" "$target"; then
    echo 'could not install staged app; rolling back'
    /bin/mv "$backup" "$target"
    /bin/rm -rf "$work_root"
    relaunch_target
    exit 1
fi
if ! /usr/bin/xattr -dr com.apple.quarantine "$target"; then
    echo 'could not remove quarantine; rolling back'
    /bin/rm -rf "$target"
    /bin/mv "$backup" "$target"
    /bin/rm -rf "$work_root"
    relaunch_target
    exit 1
fi
ready_file="$work_root/ready"
SHELTERBAR_UPDATE_READY_FILE="$ready_file" /usr/bin/nohup "$target/Contents/MacOS/ShelterBar" >/dev/null 2>&1 &
new_pid=$!
attempt=0
while /bin/kill -0 "$new_pid" 2>/dev/null && [ ! -f "$ready_file" ] && [ "$attempt" -lt 100 ]; do
    /bin/sleep 0.1
    attempt=$((attempt + 1))
done
if [ -f "$ready_file" ]; then
    /bin/sleep 1
fi
if [ -f "$ready_file" ] && /bin/kill -0 "$new_pid" 2>/dev/null; then
    echo "update installed; new pid $new_pid"
    /bin/rm -rf "$backup" "$work_root"
    exit 0
fi
echo 'updated app did not report ready and stay running; rolling back'
/bin/kill "$new_pid" 2>/dev/null || true
/bin/rm -rf "$target"
/bin/mv "$backup" "$target"
/bin/rm -rf "$work_root"
relaunch_target
exit 1
"""#
}

enum UpdateReadiness {
    static func signalIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let path = environment["SHELTERBAR_UPDATE_READY_FILE"] else { return }
        let file = URL(fileURLWithPath: path).standardizedFileURL
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path + "/ShelterBarUpdate-"
        guard file.lastPathComponent == "ready", file.path.hasPrefix(temporaryRoot) else { return }
        try? Data().write(to: file, options: .atomic)
    }
}
