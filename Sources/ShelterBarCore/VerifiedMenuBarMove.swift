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
        readSourceFrame: (() -> CGRect?)? = nil,
        pickupPoint: ((CGRect) -> CGPoint?)? = nil,
        isDestinationFrameAllowed: ((CGRect) -> Bool)? = nil,
        requestedDropPoint: CGPoint? = nil,
        isDropAllowed: ((CGPoint) -> Bool)? = nil,
        verificationAttempts: Int = 16,
        report: ((String) -> Void)? = nil,
        send: (CGRect, CGPoint) async -> Bool,
        wait: () async -> Void = { try? await Task.sleep(for: .milliseconds(80)) }
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard let initial = readItem(), let divider = readDivider() else {
            report?("item or divider frame unavailable")
            return false
        }
        guard let region = menuBarRegion(divider), menuBarRegion(initial) == region,
              abs(initial.midY - divider.midY) < 8 else {
            report?("item \(initial) and divider \(divider) are not on one menu bar row")
            return false
        }
        // Equal row heights do not identify a display: adjacent screens can
        // share their top edge. Keep the entire operation in this one region.
        if let requestedDropPoint, !region.contains(requestedDropPoint) {
            report?("requested drop \(requestedDropPoint) is outside region \(region)")
            return false
        }
        if reached(placement, item: initial, divider: divider) { return true }
        // AX reports the glyph, not necessarily the full native status window.
        // Place the whole dragged item beyond the native divider, accounting
        // for an off-center pickup when a notch partially covers the source.
        guard let insertion = readInsertionFrame?() ?? (readInsertionFrame == nil ? divider : nil),
              menuBarRegion(insertion) == region else {
            report?("native divider window unavailable or on another display")
            return false
        }
        guard let source = readSourceFrame?() ?? (readSourceFrame == nil ? initial : nil),
              menuBarRegion(source) == region else {
            report?("native source window unavailable or on another display")
            return false
        }
        let centeredPickup = CGPoint(x: initial.midX, y: initial.midY)
        guard let pickup = pickupPoint?(initial) ?? (pickupPoint == nil ? centeredPickup : nil),
              initial.contains(pickup), source.contains(pickup) else {
            report?("item \(initial) has no visible pickup point")
            return false
        }
        let destination = CGPoint(
            x: placement == .collected
                ? insertion.minX - (source.maxX - pickup.x) - 2
                : insertion.maxX + (pickup.x - source.minX) + 2,
            // Menu-bar reordering is horizontal. Preserve the actual pickup
            // row instead of nudging a padded native window up or down to the
            // insertion window's sometimes half-point-different center.
            y: pickup.y
        )
        guard region.contains(destination) else {
            report?("destination \(destination) is outside region \(region)")
            return false
        }
        // A release under a camera housing has no menu bar to land on.
        if let isDropAllowed, !isDropAllowed(destination) {
            report?("destination \(destination) is hidden by the camera housing")
            return false
        }
        // Use the complete native status window when one is available. AX often
        // exposes only the glyph, whose smaller bounds can clear a notch while
        // the real draggable window still intersects it.
        let destinationFrame = source.offsetBy(
            dx: destination.x - pickup.x,
            dy: destination.y - pickup.y
        )
        if let isDestinationFrameAllowed, !isDestinationFrameAllowed(destinationFrame) {
            report?("destination window \(destinationFrame) is not fully visible")
            return false
        }
        guard await send(initial, destination) else {
            report?("native drag from \(initial) to \(destination) could not be posted")
            return false
        }
        for _ in 0..<max(1, verificationAttempts) {
            guard !Task.isCancelled else { return false }
            if let item = readItem(), let liveDivider = readDivider(),
               menuBarRegion(item) == region, menuBarRegion(liveDivider) == region,
               abs(item.midY - liveDivider.midY) < 8,
               reached(placement, item: item, divider: liveDivider) { return true }
            await wait()
        }
        report?("item never observed on the \(placement) side; last item \(readItem().map { "\($0)" } ?? "nil"), divider \(readDivider().map { "\($0)" } ?? "nil")")
        return false
    }

    private static func reached(_ placement: MenuBarPlacement, item: CGRect, divider: CGRect) -> Bool {
        placement == .collected ? item.maxX <= divider.minX + 1 : item.minX >= divider.maxX - 1
    }
}
