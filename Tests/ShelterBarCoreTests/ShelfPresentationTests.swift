import Testing
@testable import ShelterBarCore

@Test("the shelf dismisses outside by default but remains visible while pinned")
func pinControlsAutomaticDismissal() {
    var presentation = ShelfPresentation()

    presentation.handle(.toggle)
    #expect(presentation.isVisible)

    presentation.handle(.setPinned(true))
    presentation.handle(.outsideInteraction)
    #expect(presentation.isVisible)

    presentation.handle(.setPinned(false))
    presentation.handle(.outsideInteraction)
    #expect(!presentation.isVisible)
}
