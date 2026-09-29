import ShelterBarCore
import Testing

@Test("a new item already on the collected side is adopted without a move")
func newCollectedItemNeedsNoMove() {
    let request = MenuBarReconciliationRequest(
        items: [
            ObservedMenuBarItem(id: "resident", placement: .resident, isMovable: true),
            ObservedMenuBarItem(id: "new-chat", placement: .collected, isMovable: true),
        ],
        knownItemIDs: ["resident"],
        desiredCollectedIDs: [],
        newItemPolicy: .collect
    )

    let plan = MenuBarReconciliation.plan(request)

    #expect(plan.adoptedCollectedIDs == ["new-chat"])
    #expect(plan.desiredCollectedIDs == ["new-chat"])
    #expect(plan.moves.isEmpty)
    #expect(plan.unresolvedItemIDs.isEmpty)
}

@Test("a new visible item is adopted and planned onto the collected side")
func newVisibleItemNeedsCollectionMove() {
    let plan = MenuBarReconciliation.plan(MenuBarReconciliationRequest(
        items: [ObservedMenuBarItem(id: "new-vpn", placement: .resident, isMovable: true)],
        knownItemIDs: [],
        desiredCollectedIDs: [],
        newItemPolicy: .collect
    ))

    #expect(plan.adoptedCollectedIDs == ["new-vpn"])
    #expect(plan.moves == [PlannedMenuBarMove(id: "new-vpn", placement: .collected)])
}

@Test("an unmovable item already collected remains managed without a move")
func collectedUnmovableItemRemainsManaged() {
    let plan = MenuBarReconciliation.plan(MenuBarReconciliationRequest(
        items: [ObservedMenuBarItem(id: "clock", placement: .collected, isMovable: false)],
        knownItemIDs: [],
        desiredCollectedIDs: ["clock"],
        newItemPolicy: .collect
    ))

    #expect(plan.adoptedCollectedIDs.isEmpty)
    #expect(plan.desiredCollectedIDs == ["clock"])
    #expect(plan.moves.isEmpty)
}

@Test("a new unmovable item already hidden is adopted without attempting a move")
func newCollectedUnmovableItemIsAdopted() {
    let plan = MenuBarReconciliation.plan(MenuBarReconciliationRequest(
        items: [ObservedMenuBarItem(id: "camera", placement: .collected, isMovable: false)],
        knownItemIDs: [],
        desiredCollectedIDs: [],
        newItemPolicy: .collect
    ))

    #expect(plan.adoptedCollectedIDs == ["camera"])
    #expect(plan.desiredCollectedIDs == ["camera"])
    #expect(plan.moves.isEmpty)
    #expect(plan.unresolvedItemIDs.isEmpty)
}

@Test("a stale collected preference is removed when an unmovable item is resident")
func residentUnmovableItemIsRemovedFromCollection() {
    let plan = MenuBarReconciliation.plan(MenuBarReconciliationRequest(
        items: [ObservedMenuBarItem(id: "clock", placement: .resident, isMovable: false)],
        knownItemIDs: ["clock"],
        desiredCollectedIDs: ["clock"],
        newItemPolicy: .collect
    ))

    #expect(plan.desiredCollectedIDs.isEmpty)
    #expect(plan.moves.isEmpty)
    #expect(plan.unresolvedItemIDs.isEmpty)
}
