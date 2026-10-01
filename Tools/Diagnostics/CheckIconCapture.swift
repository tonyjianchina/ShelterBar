import AppKit
import ApplicationServices

// Read-only native capture check. Supply the bundle IDs of the affected apps.
// Does not request permissions, reveal hidden icons, or change preferences.
@main
struct CheckIconCapture {
    @MainActor
    static func main() async {
        guard AXIsProcessTrusted(), ScreenCapturePermission.isGranted else {
            print("BLOCKED: diagnostic host needs existing Accessibility and ScreenCapture access")
            exit(2)
        }
        let bundles = Set(CommandLine.arguments.dropFirst())
        guard !bundles.isEmpty else { print("Supply affected app bundle IDs"); exit(2) }
        let items = AccessibilityMenuBarItemSource().items().filter {
            $0.application?.bundleIdentifier.map(bundles.contains) == true
        }
        guard !items.isEmpty else { print("FAIL: no affected AX items found"); exit(1) }
        let snapshots = await MenuBarIconCapture().capture(items)
        for item in items {
            let captured = snapshots.contains { $0.id == item.id && $0.pid == item.menuBarReference.pid }
            print("\(captured ? "PASS" : "FAIL"): \(item.id) frame=\(String(describing: item.menuBarReference.currentFrame())) captured=\(captured)")
        }
        exit(snapshots.count == items.count ? 0 : 1)
    }
}
