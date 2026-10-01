# Shelf contrast adjustment — 2026-10-01

The user's light-shelf screenshot showed white Shadowrocket, Muse and ChatGPT
glyphs. The old capture classifier adapted only flat transparent monochrome
glyphs. Gray shading/shadows, or even one colored badge pixel, kept an otherwise
white glyph in its original color on a light panel.

Regression `capturedShadedGlyphContrast` failed before the change on both
white-on-light and black-on-dark cases. Neutral shaded captures now keep their
gray details and alpha while choosing precomputed normal/inverted variants
according to the shelf's label color. The shelf and drag rendering paths share
this resolution. Dynamic image caching is disabled to support appearance changes.

The first native candidate (build 18) made Shadowrocket and Muse dark, but a tiny
colored mark kept ChatGPT white. Build 19 permits a small chromatic minority
(at most one eighth of visible pixels), inverting **only neutral pixels**.
Chromatic pixels are unchanged; color-led icons stay entirely original. Badge
tests compare the solid colored center and hue, allowing normal edge blending
against the changed neighboring shade.

Verification: all **96 tests pass**, including the production shelf drawing path
with its default label tint under Aqua and Dark Aqua, grayscale detail/alpha
preservation and colored badge preservation. Installed build 19 is locally signed.
Its own shelf-window capture shows all three real glyphs dark on the light panel,
including ChatGPT with its colored mark retained. This is native panel-rendering
evidence, not a new claim about status-entry screen composition or interaction.

No collection preferences, privacy permissions, layout or icon sizes were changed
by this adjustment. Local app installation was updated; no remote release uploaded.
