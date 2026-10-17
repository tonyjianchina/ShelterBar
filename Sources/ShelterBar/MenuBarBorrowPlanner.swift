import CoreGraphics

enum MenuBarBorrowResult: Equatable {
    case borrowed
    /// No visible slot (notch or screen edge); expanding would not help.
    case noRoom(String)
    case failed(String)
}

struct MenuBarBorrowSlot: Equatable {
    /// Release point of the Command-drag.
    let drop: CGPoint
    /// True for the slot on the far side of ShelterBar's handle.
    let afterHandle: Bool
    /// Where the item will be laid out.
    let landing: CGRect
}

/// Geometry of a temporary single-item reveal. Status items are laid out
/// from the right, so inserting next to the handle shifts the divider (and
/// everything left of it) leftwards while the handle side stays put. The host
/// decides the insertion index from the release point relative to each
/// neighbour's midpoint.
enum MenuBarBorrowPlanner {
    static func candidateDrops(handle: CGRect, itemWidth: CGFloat, region: CGRect,
                               notches: [CGRect]) -> [MenuBarBorrowSlot] {
        guard handle.width > 0, itemWidth > 0 else { return [] }
        let inset = min(4, handle.width / 4)
        let y = handle.midY
        let candidates = [
            MenuBarBorrowSlot(drop: CGPoint(x: handle.minX + inset, y: y), afterHandle: false,
                              landing: CGRect(x: handle.minX - itemWidth, y: handle.minY,
                                              width: itemWidth, height: handle.height)),
            MenuBarBorrowSlot(drop: CGPoint(x: handle.maxX - inset, y: y), afterHandle: true,
                              landing: CGRect(x: handle.maxX - itemWidth, y: handle.minY,
                                              width: itemWidth, height: handle.height)),
        ]
        return candidates.filter { slot in
            slot.landing.minX >= region.minX && slot.landing.maxX <= region.maxX
                && !notches.contains { $0.insetBy(dx: -1, dy: 0).intersects(slot.landing) }
        }
    }

    /// Release point that inserts the item just before `anchor` (its former
    /// right neighbour, or the divider when it was the last stowed item).
    static func returnDrop(anchor: CGRect, anchorIsDivider: Bool) -> CGPoint {
        // Before the divider means "in the right half of the last stowed
        // item"; before any other neighbour, "in that neighbour's left edge".
        CGPoint(x: anchorIsDivider ? anchor.minX - 2 : anchor.minX + min(4, anchor.width / 4), y: anchor.midY)
    }
}

extension MenuBarBorrowPlanner {
    /// AX glyph frames can be a few points wider than their native windows,
    /// so adjacent items may overlap slightly; compare by position, not by
    /// strict edges.
    static func isBack(item: CGRect, before anchor: CGRect) -> Bool {
        abs(item.midY - anchor.midY) < 8 && item.midX < anchor.midX && item.maxX <= anchor.minX + 4
    }
}

/// A click reveal in progress, persisted before anything moves so a quit or
/// crash mid-reveal is repaired on the next launch.
struct MenuBarPendingRestore: Codable, Equatable {
    let id: String
    let leftNeighbor: String?
    let rightNeighbor: String?
}
