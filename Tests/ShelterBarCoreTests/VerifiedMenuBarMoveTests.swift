import CoreGraphics
import Testing
@testable import ShelterBarCore

private func menuBarRegion(for frame: CGRect) -> CGRect? {
    let regions = [
        CGRect(x: -1440, y: 0, width: 1440, height: 40),
        CGRect(x: 0, y: 0, width: 1440, height: 40),
        CGRect(x: 1440, y: 0, width: 1440, height: 40),
        CGRect(x: 0, y: -1080, width: 1440, height: 40),
    ]
    return regions.first { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
}

@Test("posting a move without a physical position change must fail")
@MainActor
func ignoredMoveDoesNotSucceed() async {
    let result = await VerifiedMenuBarMove.perform(
        to: .collected,
        readItem: { CGRect(x: 950, y: 5, width: 24, height: 24) },
        readDivider: { CGRect(x: 900, y: 5, width: 3, height: 24) },
        menuBarRegion: menuBarRegion, send: { _, _ in true }, wait: {}
    )
    #expect(!result)
}

@Test("a collected item moves back only after observed to the right of the live divider")
@MainActor
func confirmedReturnSucceeds() async {
    var frame = CGRect(x: 850, y: 5, width: 24, height: 24)
    var divider = CGRect(x: 900, y: 5, width: 3, height: 24)
    let result = await VerifiedMenuBarMove.perform(
        to: .resident, readItem: { frame }, readDivider: { divider },
        menuBarRegion: menuBarRegion, send: { _, _ in
            divider.origin.x = 850
            frame.origin.x = 880
            return true
        }, wait: {}
    )
    #expect(result)
}

@Test("a stale frame on another display cannot confirm success")
@MainActor
func differentRowDoesNotSucceed() async {
    let result = await VerifiedMenuBarMove.perform(
        to: .collected,
        readItem: { CGRect(x: 800, y: -1075, width: 24, height: 24) },
        readDivider: { CGRect(x: 900, y: 5, width: 3, height: 24) },
        menuBarRegion: menuBarRegion, send: { _, _ in
            Issue.record("A cross-display gesture must not be sent.")
            return true
        }, wait: {}
    )
    #expect(!result)
}

@Test("top-aligned neighboring displays cannot be collected or returned across")
@MainActor
func alignedDisplaysDoNotSucceed() async {
    for x in [-100.0, 1800.0] {
        for placement in [MenuBarPlacement.collected, .resident] {
            let result = await VerifiedMenuBarMove.perform(
                to: placement,
                readItem: { CGRect(x: x, y: 5, width: 24, height: 24) },
                readDivider: { CGRect(x: 900, y: 5, width: 3, height: 24) },
                menuBarRegion: menuBarRegion, send: { _, _ in
                    Issue.record("A move must not start across top-aligned displays.")
                    return true
                }, wait: {}
            )
            #expect(!result)
        }
    }
}

@Test("a return dropped on another top-aligned display must not move the item")
@MainActor
func neighboringDisplayDropDoesNotSucceed() async {
    let result = await VerifiedMenuBarMove.perform(
        to: .resident,
        readItem: { CGRect(x: 850, y: 5, width: 24, height: 24) },
        readDivider: { CGRect(x: 900, y: 5, width: 3, height: 24) },
        menuBarRegion: menuBarRegion,
        requestedDropPoint: CGPoint(x: 2000, y: 17),
        send: { _, _ in
            Issue.record("A drop onto another display must be rejected before moving.")
            return true
        }, wait: {}
    )
    #expect(!result)
}

@Test("a divider near a screen edge cannot send a drag outside its display")
@MainActor
func destinationOutsideDisplayDoesNotSucceed() async {
    let result = await VerifiedMenuBarMove.perform(
        to: .collected,
        readItem: { CGRect(x: 850, y: 5, width: 24, height: 24) },
        readDivider: { CGRect(x: 1, y: 5, width: 3, height: 24) },
        menuBarRegion: menuBarRegion, send: { _, _ in
            Issue.record("A synthetic destination must stay within the source display.")
            return true
        }, wait: {}
    )
    #expect(!result)
}

@Test("unidentified item or divider displays are rejected before moving")
@MainActor
func unknownDisplayDoesNotSucceed() async {
    for unknownItem in [true, false] {
        let result = await VerifiedMenuBarMove.perform(
            to: .resident,
            readItem: { CGRect(x: 850, y: 5, width: 24, height: 24) },
            readDivider: { CGRect(x: 900, y: 5, width: 3, height: 24) },
            menuBarRegion: { frame in
                if (frame.width == 24) == unknownItem { return nil }
                return menuBarRegion(for: frame)
            }, send: { _, _ in
                Issue.record("An unknown display must be rejected before moving.")
                return true
            }, wait: {}
        )
        #expect(!result)
    }
}

@Test("post-move confirmation keeps both item and divider on the original display")
@MainActor
func changedDisplayDoesNotConfirmSuccess() async {
    for positions in [(1900.0, 900.0), (850.0, -500.0), (1900.0, 1800.0)] {
        var frame = CGRect(x: 850, y: 5, width: 24, height: 24)
        var divider = CGRect(x: 900, y: 5, width: 3, height: 24)
        let result = await VerifiedMenuBarMove.perform(
            to: .resident, readItem: { frame }, readDivider: { divider },
            menuBarRegion: menuBarRegion, send: { _, _ in
                frame.origin.x = positions.0
                divider.origin.x = positions.1
                return true
            }, wait: {}
        )
        #expect(!result)
    }
}

@Test("collection within one display still succeeds after observed movement")
@MainActor
func confirmedCollectionOnSameDisplaySucceeds() async {
    var frame = CGRect(x: 950, y: 5, width: 24, height: 24)
    let result = await VerifiedMenuBarMove.perform(
        to: .collected, readItem: { frame },
        readDivider: { CGRect(x: 900, y: 5, width: 3, height: 24) },
        menuBarRegion: menuBarRegion, send: { _, _ in
            frame.origin.x = 850
            return true
        }, wait: {}
    )
    #expect(result)
}

@Test("captured Shadowrocket geometry clears the real padded divider, not just its AX glyph")
@MainActor
func nativeInsertionClearsWholeItem() async {
    var item = CGRect(x: 990, y: 4.5, width: 36, height: 24)
    let divider = CGRect(x: 981, y: 4.5, width: 3, height: 24)
    let nativeDivider = CGRect(x: 974, y: 0, width: 17, height: 33)
    var requested: CGPoint?
    let result = await VerifiedMenuBarMove.perform(
        to: .collected, readItem: { item }, readDivider: { divider },
        menuBarRegion: menuBarRegion, readInsertionFrame: { nativeDivider },
        send: { frame, end in
            requested = end
            // Model only the insertion boundary, not macOS event acceptance.
            // The previous x=979 ends inside the 974...991 native divider.
            guard end.x + frame.width / 2 < nativeDivider.minX else { return true }
            item.origin.x = end.x - frame.width / 2
            return true
        }, wait: {}
    )
    #expect(requested == CGPoint(x: 954, y: 16.5))
    #expect(result)
}

@Test("native insertion accounts for an off-center pickup and safely clears either side")
@MainActor
func nativeInsertionKeepsPickupOffset() async {
    for placement in [MenuBarPlacement.collected, .resident] {
        let x = placement == .collected ? 1050.0 : 850.0
        var item = CGRect(x: x, y: 4.5, width: 60, height: 24)
        let divider = CGRect(x: 981, y: 4.5, width: 3, height: 24)
        let nativeDivider = CGRect(x: 974, y: 0, width: 17, height: 33)
        let pickupOffset = 10.0
        let result = await VerifiedMenuBarMove.perform(
            to: placement, readItem: { item }, readDivider: { divider },
            menuBarRegion: menuBarRegion, readInsertionFrame: { nativeDivider },
            pickupPoint: { CGPoint(x: $0.minX + pickupOffset, y: $0.midY) },
            send: { _, end in
                item.origin.x = end.x - pickupOffset
                if placement == .collected { #expect(item.maxX < nativeDivider.minX) }
                else { #expect(item.minX > nativeDivider.maxX) }
                return true
            }, wait: {}
        )
        #expect(result)
    }
}

@Test("a missing native insertion window cannot silently fall back to an AX glyph")
@MainActor
func nativeInsertionMissingWindowFails() async {
    let result = await VerifiedMenuBarMove.perform(
        to: .collected,
        readItem: { CGRect(x: 990, y: 4.5, width: 36, height: 24) },
        readDivider: { CGRect(x: 981, y: 4.5, width: 3, height: 24) },
        menuBarRegion: menuBarRegion, readInsertionFrame: { nil },
        send: { _, _ in
            Issue.record("Do not send a native drag to an unknown target.")
            return true
        }, wait: {}
    )
    #expect(!result)
}
