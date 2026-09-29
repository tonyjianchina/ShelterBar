import Foundation

public enum NewMenuBarItemPolicy: Equatable, Sendable {
    case collect
    case keepVisible
}

public struct ObservedMenuBarItem: Equatable, Sendable {
    public let id: String
    public let placement: MenuBarPlacement?
    public let isMovable: Bool

    public init(id: String, placement: MenuBarPlacement?, isMovable: Bool) {
        self.id = id
        self.placement = placement
        self.isMovable = isMovable
    }
}

public struct PlannedMenuBarMove: Equatable, Sendable {
    public let id: String
    public let placement: MenuBarPlacement

    public init(id: String, placement: MenuBarPlacement) {
        self.id = id
        self.placement = placement
    }
}

public struct MenuBarReconciliationRequest: Equatable, Sendable {
    public let items: [ObservedMenuBarItem]
    public let knownItemIDs: Set<String>
    public let desiredCollectedIDs: Set<String>
    public let newItemPolicy: NewMenuBarItemPolicy

    public init(
        items: [ObservedMenuBarItem],
        knownItemIDs: Set<String>,
        desiredCollectedIDs: Set<String>,
        newItemPolicy: NewMenuBarItemPolicy
    ) {
        self.items = items
        self.knownItemIDs = knownItemIDs
        self.desiredCollectedIDs = desiredCollectedIDs
        self.newItemPolicy = newItemPolicy
    }
}

public struct MenuBarReconciliationPlan: Equatable, Sendable {
    public let adoptedCollectedIDs: Set<String>
    public let desiredCollectedIDs: Set<String>
    public let moves: [PlannedMenuBarMove]
    public let unresolvedItemIDs: Set<String>

    public init(
        adoptedCollectedIDs: Set<String>,
        desiredCollectedIDs: Set<String>,
        moves: [PlannedMenuBarMove],
        unresolvedItemIDs: Set<String>
    ) {
        self.adoptedCollectedIDs = adoptedCollectedIDs
        self.desiredCollectedIDs = desiredCollectedIDs
        self.moves = moves
        self.unresolvedItemIDs = unresolvedItemIDs
    }
}

public enum MenuBarReconciliation {
    public static func plan(_ request: MenuBarReconciliationRequest) -> MenuBarReconciliationPlan {
        let newItemIDs = Set(request.items.map(\.id)).subtracting(request.knownItemIDs)
        var desiredCollectedIDs = request.desiredCollectedIDs
        var adoptedCollectedIDs = Set<String>()

        for item in request.items where !item.isMovable && item.placement == .resident {
            desiredCollectedIDs.remove(item.id)
        }

        if request.newItemPolicy == .collect {
            for item in request.items where newItemIDs.contains(item.id) {
                guard item.isMovable || item.placement == .collected else { continue }
                if !desiredCollectedIDs.contains(item.id) {
                    adoptedCollectedIDs.insert(item.id)
                }
                desiredCollectedIDs.insert(item.id)
            }
        }

        var moves: [PlannedMenuBarMove] = []
        var unresolvedItemIDs = Set<String>()
        for item in request.items {
            let desired: MenuBarPlacement = desiredCollectedIDs.contains(item.id) ? .collected : .resident
            guard let observed = item.placement else {
                unresolvedItemIDs.insert(item.id)
                continue
            }
            guard observed != desired else { continue }
            guard item.isMovable else {
                unresolvedItemIDs.insert(item.id)
                continue
            }
            moves.append(PlannedMenuBarMove(id: item.id, placement: desired))
        }

        return MenuBarReconciliationPlan(
            adoptedCollectedIDs: adoptedCollectedIDs,
            desiredCollectedIDs: desiredCollectedIDs,
            moves: moves,
            unresolvedItemIDs: unresolvedItemIDs
        )
    }
}
