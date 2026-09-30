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

@Test("composited macOS 26 status windows remain discoverable for live AX items")
@MainActor
func nativeWindowFindsCompositedStatusItems() {
    // Captured on 2026-09-29: visible Chrome and ShelterBar AX items,
    // hosted by Control Center, are absent from optionOnScreenOnly but
    // present in optionAll. Neither record has kCGWindowIsOnscreen.
    let records: [[String: Any]] = [
        [kCGWindowNumber as String: CGWindowID(4816),
         kCGWindowOwnerPID as String: pid_t(542),
         kCGWindowLayer as String: nativeStatusLayer,
         kCGWindowBounds as String: CGRect(x: 850, y: 0, width: 38, height: 33).dictionaryRepresentation],
        [kCGWindowNumber as String: CGWindowID(6039),
         kCGWindowOwnerPID as String: pid_t(542),
         kCGWindowLayer as String: nativeStatusLayer,
         kCGWindowBounds as String: CGRect(x: 1055, y: 0, width: 38, height: 33).dictionaryRepresentation],
    ]
    let windows = MenuBarNativeWindow.currentWindows(
        readWindowInfo: { options in options == .optionAll ? records : [] },
        ownerBundleID: { $0 == 542 ? "com.apple.controlcenter" : nil }
    )
    #expect(MenuBarNativeWindow.match(
        axFrame: CGRect(x: 857, y: 4.5, width: 24, height: 24),
        clientPID: 16237, windows: windows
    )?.id == 4816)
    #expect(MenuBarNativeWindow.match(
        axFrame: CGRect(x: 1062, y: 4.5, width: 24, height: 24),
        clientPID: 71597, windows: windows
    )?.id == 6039)
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

@Test("sequential moves wait for native animation to catch up with live AX geometry")
@MainActor
func nativeWindowAwaitsCoherentPair() async {
    var attempt = 0
    let sourceAX = CGRect(x: 883, y: 4.5, width: 24, height: 24)
    let destinationAX = CGRect(x: 1075, y: 4.5, width: 24, height: 24)
    let pair = await MenuBarNativeWindow.resolvePair(
        sourceFrame: { sourceAX }, sourcePID: 42,
        destinationFrame: { destinationAX }, destinationPID: 43,
        readWindows: {
            [nativeWindow(id: 1, pid: 42,
                          frame: CGRect(x: attempt < 3 ? 941 : 876, y: 0, width: 38, height: 33)),
             nativeWindow(id: 2, pid: 43,
                          frame: CGRect(x: 1068, y: 0, width: 38, height: 33))]
        }, wait: { attempt += 1 }
    )
    #expect(attempt == 3)
    #expect(pair?.source.id == 1)
    #expect(pair?.destination.id == 2)
}

@Test("unmatched native windows time out without relaxing ownership or geometry")
@MainActor
func nativeWindowPairTimesOut() async {
    var waits = 0
    let frame = CGRect(x: 900, y: 0, width: 38, height: 33)
    let pair = await MenuBarNativeWindow.resolvePair(
        sourceFrame: { frame }, sourcePID: 42,
        destinationFrame: { frame }, destinationPID: 43,
        readWindows: { [nativeWindow(id: 1, pid: 99, frame: frame)] },
        wait: { waits += 1 }
    )
    #expect(pair == nil)
    #expect(waits == 9)
}
