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

## macOS 27 composite captures — build 32

The region-capture fallback returns opaque wallpaper pixels. Build 31 fed those
pixels to the transparent-window decoder, so the shelf showed blue rectangles.
Its two-identical-frame check also accepted stable overflow chevrons at stale AX
coordinates. Real saved PNGs reproduce both failures independent of the shelf UI.

`MenuBarCompositeGlyph` now unmattes the smoothly varying backdrop, preserving
neutral anti-aliasing and coloured pixels. Mostly empty, strongly off-centre
captures are rejected before they can replace a cached app glyph. This is a
conservative pixel validity check, not proof of window ownership. The existing
logical-hidden, geometry, permission and two-frame checks remain in place.

Per the user's updated requirement, an AX numeric status title enables extraction
of the leading pictogram at its whitespace boundary. Numeric text and its empty
width are not shown. Plain wide artwork is left alone; app-name fallback digits
do not enable this crop. Ambiguous count separation rejects the update and keeps
the last good image. No OCR, network requests or additional screen capture is used.

Old opaque caches are migrated lazily; already-corrupted arrow entries become
missing rather than reappearing after restart. The existing explicit “刷新并恢复收纳”
action can recapture missing images. The collection state and movement engine are
unchanged. Tests replay actual cache PNGs and screenshot crops, test cache retention
and restart, and preserve coloured/wide icons. Native drag/reveal behaviour is still
subject to the user's follow-up test; replay previews do not replace that evidence.

Verification (2026-10-24): 144 app tests + 32 core tests pass, including one-digit
counts. The production renderings of the Mail/WeChat fixtures were visually
inspected without counters or rectangular backgrounds. Build 32 DMG/ZIP pass
signature, contained-binary, Finder layout and checksum checks. The installed
build 31 and its running session were not replaced during this work.
