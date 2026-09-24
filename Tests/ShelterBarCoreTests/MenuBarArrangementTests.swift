import Testing
@testable import ShelterBarCore

@Test("resident items overflow by priority when the display becomes narrow")
func residentItemsOverflowByPriority() {
    let arrangement = MenuBarArrangement(
        resident: [item("vpn"), item("sync"), item("audio")],
        collected: [item("updates")]
    )

    let layout = arrangement.layout(residentCapacity: 2)

    #expect(layout.resident.map(\.id) == ["vpn", "sync"])
    #expect(layout.shelf.map(\.id) == ["audio", "updates"])
}

@Test("resident items that fit in the top bar are omitted from the shelf")
func visibleResidentItemsDoNotDuplicateInShelf() {
    let arrangement = MenuBarArrangement(
        resident: [item("finder"), item("vpn")],
        collected: [item("sync")]
    )

    let layout = arrangement.layout(residentCapacity: 2)

    #expect(layout.resident.map(\.id) == ["finder", "vpn"])
    #expect(layout.shelf.map(\.id) == ["sync"])
}

@Test("moving an item changes its placement and preserves the requested order")
func movingAnItemBetweenPlacements() {
    var arrangement = MenuBarArrangement(
        resident: [item("vpn"), item("sync")],
        collected: [item("audio"), item("updates")]
    )

    arrangement.move("sync", to: .collected, at: 1)
    arrangement.move("updates", to: .resident, at: 0)

    #expect(arrangement.resident.map(\.id) == ["updates", "vpn"])
    #expect(arrangement.collected.map(\.id) == ["audio", "sync"])
}

private func item(_ id: String) -> MenuBarItem {
    MenuBarItem(id: id, title: id, symbolName: "circle")
}
