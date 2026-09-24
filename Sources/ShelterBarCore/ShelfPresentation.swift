public enum ShelfEvent: Sendable {
    case toggle
    case setPinned(Bool)
    case outsideInteraction
    case itemActivated
}

public struct ShelfPresentation: Equatable, Sendable {
    public private(set) var isVisible = false
    public private(set) var isPinned = false

    public init() {}

    public mutating func handle(_ event: ShelfEvent) {
        switch event {
        case .toggle:
            isVisible.toggle()
        case let .setPinned(value):
            isPinned = value
        case .outsideInteraction, .itemActivated:
            if !isPinned {
                isVisible = false
            }
        }
    }
}
