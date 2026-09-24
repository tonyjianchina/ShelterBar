import CoreGraphics
import Foundation

/// A posted mouse gesture is only a request. Commit placement only after a
/// fresh observation confirms it, including any divider reflow during a move.
@MainActor
public enum VerifiedMenuBarMove {
    public static func perform(
        to placement: MenuBarPlacement,
        readItem: () -> CGRect?,
        readDivider: () -> CGRect?,
        menuBarRegion: (CGRect) -> CGRect?,
        readInsertionFrame: (() -> CGRect?)? = nil,
        pickupPoint: ((CGRect) -> CGPoint?)? = nil,
        requestedDropPoint: CGPoint? = nil,
        send: (CGRect, CGPoint) async -> Bool,
        wait: () async -> Void = { try? await Task.sleep(for: .milliseconds(80)) }
    ) async -> Bool {
        guard !Task.isCancelled, let initial = readItem(), let divider = readDivider(),
              let region = menuBarRegion(divider), menuBarRegion(initial) == region,
              abs(initial.midY - divider.midY) < 8 else { return false }
        // Equal row heights do not identify a display: adjacent screens can
        // share their top edge. Keep the entire operation in this one region.
        if let requestedDropPoint, !region.contains(requestedDropPoint) { return false }
        if reached(placement, item: initial, divider: divider) { return true }
        // AX reports the glyph, not necessarily the full native status window.
        // Place the whole dragged item beyond the native divider, accounting
        // for an off-center pickup when a notch partially covers the source.
        guard let insertion = readInsertionFrame?() ?? (readInsertionFrame == nil ? divider : nil),
              menuBarRegion(insertion) == region else { return false }
        let centeredPickup = CGPoint(x: initial.midX, y: initial.midY)
        guard let pickup = pickupPoint?(initial) ?? (pickupPoint == nil ? centeredPickup : nil),
              initial.contains(pickup) else { return false }
        let destination = CGPoint(
            x: placement == .collected
                ? insertion.minX - (initial.maxX - pickup.x) - 2
                : insertion.maxX + (pickup.x - initial.minX) + 2,
            y: insertion.midY
        )
        guard region.contains(destination), await send(initial, destination) else { return false }
        for _ in 0..<8 {
            guard !Task.isCancelled else { return false }
            if let item = readItem(), let liveDivider = readDivider(),
               menuBarRegion(item) == region, menuBarRegion(liveDivider) == region,
               abs(item.midY - liveDivider.midY) < 8,
               reached(placement, item: item, divider: liveDivider) { return true }
            await wait()
        }
        return false
    }

    private static func reached(_ placement: MenuBarPlacement, item: CGRect, divider: CGRect) -> Bool {
        placement == .collected ? item.maxX <= divider.minX + 1 : item.minX >= divider.maxX - 1
    }
}
