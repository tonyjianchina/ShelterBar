import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(source: AccessibilityMenuBarItemSource())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.statusBarController?.requestAccessibilityPermissionIfNeeded()
        }
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.statusBarController?.showShelf()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.shutdown()
    }
}
