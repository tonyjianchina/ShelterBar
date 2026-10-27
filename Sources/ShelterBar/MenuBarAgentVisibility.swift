import AppKit
import Foundation
import OSLog

enum MenuBarCollectionCapability {
    static let shelterBarBundleID = "com.jensen.shelterbar"
    static let alwaysAllowedBundleIDs: Set<String> = [
        "com.apple.controlcenter", "com.apple.MenuBarAgent", "com.apple.systemuiserver",
        "com.apple.TextInputMenuAgent", "com.apple.Siri", "com.apple.Spotlight",
        "com.apple.wifi.WiFiAgent", "com.apple.ScreenTimeAgent", "com.apple.AirPlayUIAgent",
        "com.apple.UserNotificationCenter", "com.apple.notificationcenterui", "com.apple.loginwindow",
    ]

    static func protectedBundleIDs(ownBundleID: String?) -> Set<String> {
        var protected = alwaysAllowedBundleIDs.union([shelterBarBundleID])
        if let ownBundleID { protected.insert(ownBundleID) }
        return protected
    }

    static func supports(bundleID: String?, ownBundleID: String?) -> Bool {
        guard let bundleID, !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !protectedBundleIDs(ownBundleID: ownBundleID).contains(bundleID)
    }
}

@objc private protocol MenuBarAssessmentAssertion: AnyObject {
    @objc(activateWithConfiguration:completionHandler:)
    func activate(with configuration: AnyObject, completionHandler: @escaping (NSError?) -> Void)
    func invalidate()
}

enum MenuBarRestrictionError: LocalizedError {
    case unavailable
    case configurationFailed
    case activation(NSError)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "MenuBarClientCore.framework 不可用或接口已经改变"
        case .configurationFailed:
            return "无法创建菜单栏显示配置"
        case let .activation(error):
            return "MenuBarAgent 拒绝了显示配置：\(error.localizedDescription)"
        case .timedOut:
            return "MenuBarAgent 显示配置超时"
        }
    }
}

/// Small seam around macOS 27's MenuBarAgent restriction. The private
/// framework is resolved at runtime, so older systems continue to use the
/// Command-drag implementation without linking against a private SDK.
@MainActor
protocol MenuBarRestrictionApplying: AnyObject {
    var isAvailable: Bool { get }
    func restrict(allowedBundleIDs: [String], completion: @MainActor @escaping (Error?) -> Void)
    func release()
}

@MainActor
final class MenuBarClientRestriction: MenuBarRestrictionApplying {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configurationInitializer =
        NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let allowedSystemItems: [NSNumber] =
        (0..<64).map { NSNumber(value: $0) }

    private let classes: (assertion: NSObject.Type, configuration: NSObject.Type)?
    private var active: MenuBarAssessmentAssertion?
    private var pending: MenuBarAssessmentAssertion?

    init() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27,
              dlopen(Self.frameworkPath, RTLD_NOW) != nil,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              assertion.instancesRespond(
                to: #selector(MenuBarAssessmentAssertion.activate(with:completionHandler:))
              ),
              assertion.instancesRespond(to: #selector(MenuBarAssessmentAssertion.invalidate)),
              configuration.instancesRespond(to: Self.configurationInitializer) else {
            classes = nil
            menuBarMoveLog.notice("macOS 27 MenuBarAgent visibility API is unavailable; using legacy movement")
            return
        }
        classes = (assertion, configuration)
        menuBarMoveLog.info("macOS 27 MenuBarAgent visibility API resolved")
    }

    var isAvailable: Bool { classes != nil }

    func restrict(allowedBundleIDs: [String], completion: @MainActor @escaping (Error?) -> Void) {
        guard let classes else {
            completion(MenuBarRestrictionError.unavailable)
            return
        }
        guard let configuration = Self.makeConfiguration(
            classes.configuration,
            bundleIDs: allowedBundleIDs
        ) else {
            completion(MenuBarRestrictionError.configurationFailed)
            return
        }

        pending?.invalidate()
        let assertion = unsafeBitCast(classes.assertion.init(), to: MenuBarAssessmentAssertion.self)
        pending = assertion
        menuBarMoveLog.info("activating MenuBarAgent restriction with \(allowedBundleIDs.count) allowed bundle identifiers")
        assertion.activate(with: configuration) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.pending === assertion else { return }
                self.pending = nil
                if let error {
                    assertion.invalidate()
                    menuBarMoveLog.error("MenuBarAgent restriction failed: \(error.localizedDescription, privacy: .public)")
                    completion(MenuBarRestrictionError.activation(error))
                } else {
                    // Replace only after the new assertion is active so the
                    // menu bar never flashes fully visible between updates.
                    self.active?.invalidate()
                    self.active = assertion
                    completion(nil)
                }
            }
        }
    }

    func release() {
        pending?.invalidate()
        pending = nil
        active?.invalidate()
        active = nil
    }

    private static func makeConfiguration(
        _ configurationClass: NSObject.Type,
        bundleIDs: [String]
    ) -> AnyObject? {
        let allocated = (configurationClass as AnyObject)
            .perform(NSSelectorFromString("alloc"))?
            .takeUnretainedValue()
        return allocated?
            .perform(
                configurationInitializer,
                with: allowedSystemItems as NSArray,
                with: bundleIDs as NSArray
            )?
            .takeRetainedValue()
    }
}

/// Owns ShelterBar's intended and currently-applied hidden app sets on macOS
/// 27. AX keeps reporting stale frames after MenuBarAgent hides an item, so
/// this is also the source of truth used by placement verification and UI.
@MainActor
final class MenuBarAgentVisibilityController {
    private let restriction: any MenuBarRestrictionApplying
    private let runningBundleIDs: @MainActor () -> [String]
    private let ownBundleID: String?
    private let activationTimeout: Duration
    private(set) var desiredHiddenBundleIDs = Set<String>()
    private(set) var activeHiddenBundleIDs = Set<String>()
    private var appliedAllowList: [String]?
    private var runtimeAvailable = true
    private var nextRequestID = 0
    private var pendingApply: (
        id: Int,
        allowed: [String],
        continuation: CheckedContinuation<Bool, Never>
    )?

    init(
        restriction: any MenuBarRestrictionApplying = MenuBarClientRestriction(),
        runningBundleIDs: @escaping @MainActor () -> [String] = {
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        },
        ownBundleID: String? = Bundle.main.bundleIdentifier,
        activationTimeout: Duration = .milliseconds(750)
    ) {
        self.restriction = restriction
        self.runningBundleIDs = runningBundleIDs
        self.ownBundleID = ownBundleID
        self.activationTimeout = activationTimeout
    }

    var isAvailable: Bool { restriction.isAvailable && runtimeAvailable }

    /// A bundle allow-list cannot hide an app that must remain allowed.
    /// Keep both the shipped identifier and the current host protected,
    /// including when this code runs in a test or development app bundle.
    static func supportsCollection(
        bundleID: String?,
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        MenuBarCollectionCapability.supports(bundleID: bundleID, ownBundleID: ownBundleID)
    }

    func canCollect(bundleID: String?) -> Bool {
        isAvailable && Self.supportsCollection(bundleID: bundleID, ownBundleID: ownBundleID)
    }

    func isDesiredHidden(bundleID: String?) -> Bool {
        bundleID.map(desiredHiddenBundleIDs.contains) ?? false
    }

    func isActivelyHidden(bundleID: String?) -> Bool {
        bundleID.map(activeHiddenBundleIDs.contains) ?? false
    }

    @discardableResult
    func setCollected(_ collected: Bool, bundleID: String) async -> Bool {
        guard !collected || canCollect(bundleID: bundleID) else { return false }
        var candidate = desiredHiddenBundleIDs
        if collected { candidate.insert(bundleID) } else { candidate.remove(bundleID) }
        guard await apply(hidden: candidate) else { return false }
        desiredHiddenBundleIDs = candidate
        activeHiddenBundleIDs = candidate
        return true
    }

    /// Show every collected app while retaining the saved collection intent.
    func revealKeepingIntent() {
        reveal(restoringIntent: desiredHiddenBundleIDs)
    }

    /// Failed transactions must not leave an uncommitted app in the next
    /// collapse. Replace intent from persisted model state, then reveal all.
    func reveal(restoringIntent hiddenBundleIDs: Set<String>) {
        restriction.release()
        appliedAllowList = nil
        desiredHiddenBundleIDs = Set(hiddenBundleIDs.filter {
            Self.supportsCollection(bundleID: $0, ownBundleID: ownBundleID)
        })
        activeHiddenBundleIDs.removeAll()
    }

    @discardableResult
    func collapseToIntent() async -> Bool {
        guard await apply(hidden: desiredHiddenBundleIDs) else { return false }
        activeHiddenBundleIDs = desiredHiddenBundleIDs
        return true
    }

    /// Reveal only one collected app so its menu can be clicked.
    @discardableResult
    func temporarilyReveal(bundleID: String) async -> Bool {
        let candidate = desiredHiddenBundleIDs.subtracting([bundleID])
        guard await apply(hidden: candidate) else { return false }
        activeHiddenBundleIDs = candidate
        return true
    }

    func clear() {
        if let pendingApply {
            self.pendingApply = nil
            pendingApply.continuation.resume(returning: false)
        }
        restriction.release()
        appliedAllowList = nil
        desiredHiddenBundleIDs.removeAll()
        activeHiddenBundleIDs.removeAll()
    }

    private func apply(hidden: Set<String>) async -> Bool {
        guard isAvailable else { return false }
        if hidden.isEmpty {
            restriction.release()
            appliedAllowList = nil
            return true
        }
        let allowed = Set(runningBundleIDs())
            .subtracting(hidden)
            .union(MenuBarCollectionCapability.protectedBundleIDs(ownBundleID: ownBundleID))
            .sorted()
        if allowed == appliedAllowList, activeHiddenBundleIDs == hidden { return true }
        guard pendingApply == nil else { return false }
        nextRequestID += 1
        let requestID = nextRequestID
        return await withCheckedContinuation { continuation in
            pendingApply = (requestID, allowed, continuation)
            restriction.restrict(allowedBundleIDs: allowed) { [weak self] error in
                self?.finishApply(requestID: requestID, error: error)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: activationTimeout)
                finishApply(requestID: requestID, error: MenuBarRestrictionError.timedOut)
            }
        }
    }

    private func finishApply(requestID: Int, error: Error?) {
        guard let pending = pendingApply, pending.id == requestID else { return }
        pendingApply = nil
        if let error {
            runtimeAvailable = false
            restriction.release()
            appliedAllowList = nil
            activeHiddenBundleIDs.removeAll()
            menuBarMoveLog.error("MenuBarAgent restriction disabled after runtime failure: \(error.localizedDescription, privacy: .public); using legacy movement")
        } else {
            appliedAllowList = pending.allowed
        }
        pending.continuation.resume(returning: error == nil)
    }

}
