import AppKit
import ApplicationServices
import Testing
@testable import ShelterBar

@Suite(.serialized)
@MainActor
struct MenuBarMenuOpenerTests {
    @Test("QQ Music's wide status control opens from the trailing logo, away from playback buttons")
    func qqClickAvoidsPlaybackControls() {
        let wide = CGRect(x: 1028, y: 5.5, width: 150, height: 22)
        let point = MenuBarPressPolicy.clickPoint(in: wide, bundleID: "com.tencent.QQMusicMac")
        #expect(MenuBarPressPolicy.clickButton(bundleID: "com.tencent.QQMusicMac") == .right)
        #expect(MenuBarPressPolicy.clickButton(bundleID: "com.example.other") == .left)
        #expect(point.x > wide.maxX - wide.height)
        #expect(point.y == wide.midY)
        #expect(MenuBarPressPolicy.clickPoint(in: wide, bundleID: "com.example.other")
            == CGPoint(x: wide.midX, y: wide.midY))
        let compact = CGRect(x: 1028, y: 5.5, width: 22, height: 22)
        #expect(MenuBarPressPolicy.clickPoint(in: compact, bundleID: "com.tencent.QQMusicMac")
            == CGPoint(x: compact.midX, y: compact.midY))
    }

    private func item() -> ShelfItem {
        let reference = MenuBarItemReference(pid: getpid(), element: AXUIElementCreateApplication(getpid()),
            frame: CGRect(x: 1000, y: 5, width: 24, height: 24))
        reference.currentFrameReader = { [weak reference] in reference?.frame }
        return ShelfItem(id: "qq", title: "QQ音乐", icon: NSImage(), application: nil, menuBarReference: reference)
    }

    @Test("AXPress failure falls back to AXShowMenu and requires an observed menu", arguments: [AXError.actionUnsupported, .cannotComplete])
    func showMenuAfterFailedPress(error: AXError) async {
        let item = item()
        var attempts: [String] = []
        let operations = MenuBarMenuOpener.Operations(
            press: { _ in attempts.append("press"); return error },
            showMenu: { _ in attempts.append("showMenu"); return .success },
            currentWindows: { _ in [:] },
            newWindows: { _, _, _ in attempts.last == "showMenu" ? [42: 101] : nil },
            click: { _, _ in attempts.append("click") })
        #expect(await MenuBarMenuOpener.open(item, target: item.menuBarReference.frame, operations: operations))
        #expect(attempts == ["press", "showMenu"])
    }

    @Test("the real click re-reads the visible position after both AX actions fail")
    func clickUsesLivePosition() async {
        let item = item()
        let original = item.menuBarReference.frame
        var attempts: [String] = []
        var points: [CGPoint] = []
        let operations = MenuBarMenuOpener.Operations(
            press: { _ in
                attempts.append("press")
                item.menuBarReference.frame.origin.x = 1100
                return .cannotComplete
            },
            showMenu: { _ in attempts.append("showMenu"); return .actionUnsupported },
            currentWindows: { _ in [:] },
            newWindows: { _, _, _ in points.isEmpty ? nil : [42: 101] },
            click: { point, button in
                #expect(button == .left)
                points.append(point)
            })
        #expect(await MenuBarMenuOpener.open(item, target: original, operations: operations))
        #expect(attempts == ["press", "showMenu"])
        #expect(points == [CGPoint(x: 1112, y: 17)])
    }

    @Test("an AX timeout that actually opened a menu is never clicked a second time")
    func timeoutWithVisibleMenuIsSuccess() async {
        let item = item()
        let operations = MenuBarMenuOpener.Operations(
            press: { _ in .cannotComplete },
            showMenu: { _ in Issue.record("the menu is already open"); return .failure },
            currentWindows: { _ in [:] }, newWindows: { _, _, _ in [42: 101] },
            click: { _, _ in Issue.record("a second click would close the menu") })
        #expect(await MenuBarMenuOpener.open(item, target: item.menuBarReference.frame, operations: operations))
    }

    @Test("a click that opens no UI reports failure instead of silently claiming success")
    func missingMenuIsFailure() async {
        let item = item()
        let operations = MenuBarMenuOpener.Operations(
            press: { _ in .cannotComplete }, showMenu: { _ in .actionUnsupported },
            currentWindows: { _ in [:] }, newWindows: { _, _, _ in nil }, click: { _, _ in })
        #expect(!(await MenuBarMenuOpener.open(item, target: item.menuBarReference.frame, operations: operations)))
    }
}
