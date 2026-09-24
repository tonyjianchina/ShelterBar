import AppKit
import Testing
@testable import ShelterBar

private let nativeStatusLayer = Int(CGWindowLevelForKey(.statusWindow))

private func nativeWindow(
    id: CGWindowID = 1,
    pid: pid_t = 42,
    layer: Int = nativeStatusLayer,
    frame: CGRect,
    ownerBundleID: String? = nil
) -> MenuBarNativeWindow {
    MenuBarNativeWindow(id: id, pid: pid, layer: layer, frame: frame,
                        ownerBundleID: ownerBundleID)
}

@Test("native status matching accepts captured Shadowrocket and thin divider geometry")
func nativeWindowMatchesCapturedGeometry() {
    let examples: [(CGRect, CGRect)] = [
        (CGRect(x: 990, y: 4.5, width: 36, height: 24),
         CGRect(x: 991, y: 0, width: 34, height: 33)),
        (CGRect(x: 981, y: 4.5, width: 3, height: 24),
         CGRect(x: 974, y: 0, width: 17, height: 33)),
    ]
    for (axFrame, windowFrame) in examples {
        let window = nativeWindow(pid: 1141, frame: windowFrame,
                                  ownerBundleID: "com.apple.controlcenter")
        #expect(MenuBarNativeWindow.match(axFrame: axFrame, clientPID: 42,
                                          windows: [window])?.id == 1)
    }
}

@Test("native status matching requires the client or verified Control Center ownership")
func nativeWindowRequiresKnownOwner() {
    let frame = CGRect(x: 900, y: 0, width: 30, height: 30)
    let direct = nativeWindow(frame: frame)
    let unknown = nativeWindow(id: 2, pid: 7, frame: frame)
    let unrelated = nativeWindow(id: 3, pid: 8, frame: frame,
                                 ownerBundleID: "com.example.overlay")
    #expect(MenuBarNativeWindow.match(axFrame: frame, clientPID: 42,
                                      windows: [direct, unknown, unrelated])?.id == 1)
    #expect(MenuBarNativeWindow.match(axFrame: frame, clientPID: 42,
                                      windows: [unknown, unrelated]) == nil)
}

@Test("native status matching rejects ambiguity and non-status layers")
func nativeWindowRejectsAmbiguityAndOtherLayers() {
    let frame = CGRect(x: 900, y: 0, width: 30, height: 30)
    let first = nativeWindow(frame: frame)
    let second = nativeWindow(id: 2, pid: 1141, frame: frame,
                              ownerBundleID: "com.apple.controlcenter")
    #expect(MenuBarNativeWindow.match(axFrame: frame, clientPID: 42,
                                      windows: [first, second]) == nil)
    for layer in [0, 24, 26] {
        #expect(MenuBarNativeWindow.match(axFrame: frame, clientPID: 42, windows: [
            nativeWindow(layer: layer, frame: frame),
        ]) == nil)
    }
}

@Test("native status matching rejects neighboring items, displays and oversized windows")
func nativeWindowRejectsUnrelatedGeometry() {
    let frame = CGRect(x: 900, y: 0, width: 30, height: 30)
    let rejected = [
        frame.offsetBy(dx: 30, dy: 0),
        frame.offsetBy(dx: 0, dy: -1080),
        CGRect(x: 0, y: 0, width: 1830, height: 30),
        CGRect(x: 900, y: -36, width: 30, height: 102),
        CGRect(x: 891.5, y: 0, width: 47, height: 30),
        CGRect(x: 915, y: 15, width: 0, height: 0),
    ]
    for candidate in rejected {
        #expect(MenuBarNativeWindow.match(axFrame: frame, clientPID: 42, windows: [
            nativeWindow(frame: candidate),
        ]) == nil)
    }
}

@Test("native status geometry tolerance includes its bounds but not values beyond them")
func nativeWindowGeometryToleranceIsBounded() {
    let frame = CGRect(x: 900, y: 5, width: 30, height: 24)
    let accepted = CGRect(x: 895, y: 10, width: 46, height: 24)
    #expect(MenuBarNativeWindow.match(axFrame: frame, clientPID: 42, windows: [
        nativeWindow(frame: accepted),
    ])?.id == 1)
    for rejected in [accepted.offsetBy(dx: 0.1, dy: 0), accepted.offsetBy(dx: 0, dy: 0.1)] {
        #expect(MenuBarNativeWindow.match(axFrame: frame, clientPID: 42, windows: [
            nativeWindow(frame: rejected),
        ]) == nil)
    }
}
