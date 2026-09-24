import Foundation
import CoreGraphics

/// Mouse gesture policy shared by the event tap and its regression tests.
/// A drag outside the shelf is cancellation, never a click on the source app.
public struct MenuBarDragGesture: Sendable {
    public enum Outcome: Equatable, Sendable {
        case click(String)
        case collect(String)
        case cancel
    }

    private var itemID: String?
    private var origin = CGPoint.zero
    public private(set) var isDragging = false
    public private(set) var isCancelled = false
    public var isTracking: Bool { itemID != nil }

    public init() {}

    public mutating func begin(itemID: String, at point: CGPoint) {
        self.itemID = itemID
        origin = point
        isDragging = false
        isCancelled = false
    }

    public mutating func move(to point: CGPoint) {
        guard isTracking, !isCancelled else { return }
        isDragging = isDragging || hypot(point.x - origin.x, point.y - origin.y) >= 5
    }

    public mutating func finish(at point: CGPoint, shelf: CGRect) -> Outcome? {
        guard let itemID else { return nil }
        move(to: point)
        let result: Outcome = isCancelled ? .cancel : isDragging
            ? (shelf.contains(point) ? .collect(itemID) : .cancel)
            : .click(itemID)
        self = Self()
        return result
    }

    public mutating func cancel() { self = Self() }
    public mutating func cancelUntilRelease() { isCancelled = true }
}
