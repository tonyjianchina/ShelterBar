import Foundation

public struct MenuBarItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var symbolName: String

    public init(id: String, title: String, symbolName: String) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
    }
}

public struct MenuBarLayout: Equatable, Sendable {
    public let resident: [MenuBarItem]
    public let shelf: [MenuBarItem]
}

public enum MenuBarPlacement: Sendable {
    case resident
    case collected
}

public struct MenuBarArrangement: Equatable, Sendable {
    public private(set) var resident: [MenuBarItem]
    public private(set) var collected: [MenuBarItem]

    public init(resident: [MenuBarItem], collected: [MenuBarItem]) {
        self.resident = resident
        self.collected = collected
    }

    public func layout(residentCapacity: Int) -> MenuBarLayout {
        let capacity = max(0, residentCapacity)
        return MenuBarLayout(
            resident: Array(resident.prefix(capacity)),
            shelf: Array(resident.dropFirst(capacity)) + collected
        )
    }

    public mutating func move(
        _ itemID: MenuBarItem.ID,
        to placement: MenuBarPlacement,
        at requestedIndex: Int
    ) {
        guard let item = remove(itemID) else { return }

        switch placement {
        case .resident:
            resident.insert(item, at: resident.safeInsertionIndex(requestedIndex))
        case .collected:
            collected.insert(item, at: collected.safeInsertionIndex(requestedIndex))
        }
    }

    private mutating func remove(_ itemID: MenuBarItem.ID) -> MenuBarItem? {
        if let index = resident.firstIndex(where: { $0.id == itemID }) {
            return resident.remove(at: index)
        }
        if let index = collected.firstIndex(where: { $0.id == itemID }) {
            return collected.remove(at: index)
        }
        return nil
    }
}

private extension Collection {
    func safeInsertionIndex(_ requestedIndex: Int) -> Index {
        index(startIndex, offsetBy: Swift.min(Swift.max(0, requestedIndex), count))
    }
}
