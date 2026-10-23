import Foundation
import Testing
@testable import ShelterBar

@MainActor
private final class FakeMenuBarRestriction: MenuBarRestrictionApplying {
    var isAvailable = true
    var requests: [[String]] = []
    var releases = 0
    var nextError: Error?

    func restrict(allowedBundleIDs: [String], completion: @escaping (Error?) -> Void) {
        requests.append(allowedBundleIDs)
        completion(nextError)
    }

    func release() { releases += 1 }
}

@Test("macOS 27 visibility collection excludes only the collected bundle")
@MainActor
func visibilityCollectionBuildsAllowList() async {
    let restriction = FakeMenuBarRestriction()
    let controller = MenuBarAgentVisibilityController(
        restriction: restriction,
        runningBundleIDs: { ["com.example.visible", "com.example.hidden"] }
    )

    #expect(await controller.setCollected(true, bundleID: "com.example.hidden"))
    #expect(controller.desiredHiddenBundleIDs == ["com.example.hidden"])
    #expect(controller.activeHiddenBundleIDs == ["com.example.hidden"])
    #expect(restriction.requests.last?.contains("com.example.visible") == true)
    #expect(restriction.requests.last?.contains("com.example.hidden") == false)
    #expect(restriction.requests.last?.contains("com.jensen.shelterbar") == true)
}

@Test("protected system and ShelterBar bundles never report successful collection")
@MainActor
func visibilityRejectsProtectedBundlesWithoutChangingCollection() async {
    var protected = Set(["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.jensen.shelterbar"])
    if let currentBundleID = Bundle.main.bundleIdentifier { protected.insert(currentBundleID) }
    for bundleID in protected {
        let restriction = FakeMenuBarRestriction()
        let controller = MenuBarAgentVisibilityController(
            restriction: restriction,
            runningBundleIDs: { ["com.example.hidden", bundleID] }
        )
        #expect(await controller.setCollected(true, bundleID: "com.example.hidden"))
        let requestsBeforeRejection = restriction.requests.count

        #expect(await controller.setCollected(true, bundleID: bundleID) == false)
        #expect(controller.desiredHiddenBundleIDs == ["com.example.hidden"])
        #expect(controller.activeHiddenBundleIDs == ["com.example.hidden"])
        #expect(!controller.isActivelyHidden(bundleID: bundleID))
        #expect(restriction.requests.count == requestsBeforeRejection)

        // Reject only hiding: recovery still accepts a request to make a
        // protected item resident, without releasing the unrelated item.
        #expect(await controller.setCollected(false, bundleID: bundleID))
        #expect(controller.desiredHiddenBundleIDs == ["com.example.hidden"])
        #expect(controller.activeHiddenBundleIDs == ["com.example.hidden"])
        #expect(await controller.setCollected(false, bundleID: "com.example.hidden"))
        #expect(controller.desiredHiddenBundleIDs.isEmpty)
        #expect(controller.activeHiddenBundleIDs.isEmpty)
        controller.clear()
        #expect(controller.desiredHiddenBundleIDs.isEmpty)
        #expect(controller.activeHiddenBundleIDs.isEmpty)
    }
}

@Test("collection capabilities protect both a custom host and the shipped ShelterBar bundle")
@MainActor
func visibilityProtectsHostAndShippedBundleTogether() async {
    let hostBundleID = "com.example.ShelterBarTests"
    let restriction = FakeMenuBarRestriction()
    let controller = MenuBarAgentVisibilityController(
        restriction: restriction,
        runningBundleIDs: { ["com.example.hidden", hostBundleID, "com.jensen.shelterbar"] },
        ownBundleID: hostBundleID
    )
    #expect(await controller.setCollected(true, bundleID: "com.example.hidden"))
    #expect(restriction.requests.last?.contains(hostBundleID) == true)
    #expect(restriction.requests.last?.contains("com.jensen.shelterbar") == true)

    for protected in [hostBundleID, "com.jensen.shelterbar", "com.apple.systemuiserver", "com.apple.TextInputMenuAgent"] {
        #expect(!MenuBarAgentVisibilityController.supportsCollection(bundleID: protected, ownBundleID: hostBundleID))
        #expect(!controller.canCollect(bundleID: protected))
        #expect(await controller.setCollected(true, bundleID: protected) == false)
        #expect(controller.activeHiddenBundleIDs == ["com.example.hidden"])
        #expect(controller.desiredHiddenBundleIDs == ["com.example.hidden"])
    }

    #expect(!controller.canCollect(bundleID: nil))
    #expect(!controller.canCollect(bundleID: "  "))
    #expect(controller.canCollect(bundleID: "com.example.other"))
    restriction.isAvailable = false
    #expect(!controller.canCollect(bundleID: "com.example.other"))
    controller.clear()
    #expect(controller.activeHiddenBundleIDs.isEmpty)
    #expect(controller.desiredHiddenBundleIDs.isEmpty)
}

@Test("temporary reveal preserves desired collection and collapse reapplies it")
@MainActor
func visibilityRevealAndCollapse() async {
    let restriction = FakeMenuBarRestriction()
    let controller = MenuBarAgentVisibilityController(
        restriction: restriction,
        runningBundleIDs: { ["com.example.hidden"] }
    )
    #expect(await controller.setCollected(true, bundleID: "com.example.hidden"))

    controller.revealKeepingIntent()
    #expect(controller.activeHiddenBundleIDs.isEmpty)
    #expect(controller.desiredHiddenBundleIDs == ["com.example.hidden"])
    #expect(restriction.releases == 1)

    #expect(await controller.collapseToIntent())
    #expect(controller.activeHiddenBundleIDs == ["com.example.hidden"])
    #expect(restriction.requests.count == 2)
}

@Test("borrowing one collected app reveals only that app and restores it")
@MainActor
func visibilitySingleItemBorrow() async {
    let restriction = FakeMenuBarRestriction()
    let controller = MenuBarAgentVisibilityController(
        restriction: restriction,
        runningBundleIDs: { ["com.example.one", "com.example.two"] }
    )
    #expect(await controller.setCollected(true, bundleID: "com.example.one"))
    #expect(await controller.setCollected(true, bundleID: "com.example.two"))

    #expect(await controller.temporarilyReveal(bundleID: "com.example.one"))
    #expect(controller.activeHiddenBundleIDs == ["com.example.two"])
    #expect(controller.desiredHiddenBundleIDs == ["com.example.one", "com.example.two"])

    #expect(await controller.collapseToIntent())
    #expect(controller.activeHiddenBundleIDs == ["com.example.one", "com.example.two"])
}

@Test("a rejected restriction keeps the prior active visibility state")
@MainActor
func visibilityFailureDoesNotLieAboutPlacement() async {
    struct Failure: Error {}
    let restriction = FakeMenuBarRestriction()
    let controller = MenuBarAgentVisibilityController(
        restriction: restriction,
        runningBundleIDs: { ["com.example.one", "com.example.two"] }
    )
    #expect(await controller.setCollected(true, bundleID: "com.example.one"))
    restriction.nextError = Failure()

    #expect(await controller.setCollected(true, bundleID: "com.example.two") == false)
    #expect(controller.activeHiddenBundleIDs == ["com.example.one"])
    #expect(controller.desiredHiddenBundleIDs == ["com.example.one"])
}

@Test("an active restriction admits newly running resident applications without flashing hidden apps")
@MainActor
func visibilityRefreshesRunningAllowList() async {
    let restriction = FakeMenuBarRestriction()
    var running = ["com.example.hidden", "com.example.visible"]
    let controller = MenuBarAgentVisibilityController(
        restriction: restriction,
        runningBundleIDs: { running }
    )
    #expect(await controller.setCollected(true, bundleID: "com.example.hidden"))
    #expect(restriction.requests.count == 1)

    running.append("com.example.new-resident")
    #expect(await controller.collapseToIntent())
    #expect(restriction.requests.count == 2)
    #expect(restriction.requests.last?.contains("com.example.new-resident") == true)
    #expect(restriction.requests.last?.contains("com.example.hidden") == false)

    // An unchanged polling pass is idempotent.
    #expect(await controller.collapseToIntent())
    #expect(restriction.requests.count == 2)
}
