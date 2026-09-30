import ShelterBarCore
import Testing

@Test("unobserved AX entries are not adopted or required unless already collected")
func unavailableItemsStayOutsideManagedInventory() {
    let plan = MenuBarReconciliation.plan(MenuBarReconciliationRequest(
        items: [
            ObservedMenuBarItem(id: "stale-helper", placement: nil, isMovable: true),
            ObservedMenuBarItem(id: "saved", placement: nil, isMovable: true),
        ],
        knownItemIDs: ["saved"], desiredCollectedIDs: ["saved"], newItemPolicy: .collect
    ))
    #expect(plan.adoptedCollectedIDs.isEmpty)
    #expect(plan.desiredCollectedIDs == ["saved"])
    #expect(plan.unresolvedItemIDs == ["saved"])
}
