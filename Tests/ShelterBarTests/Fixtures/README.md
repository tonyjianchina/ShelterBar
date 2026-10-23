# Composite glyph regressions

These samples reproduce the user's 2026-10-23 build 31 report without manipulating
the live menu bar or collecting system recording/overflow controls.

- `composite-ollama.png`: original persisted opaque icon, including wallpaper.
- `composite-{mail,wechat,muse}-overflow.png`: corrupted persisted captures, whose
  old AX rectangles contain the system overflow chevron instead of their owner.
- `shelf-before-corruption.png`: user-provided shelf screenshot with the correct
  Mail and WeChat pictograms and counts. Tests crop just the inside of their
  rectangles (excluding the one-pixel shelf/background boundary).

Run `swift test --filter compositeFixture`. To export the count-free renderings,
set `SHELTERBAR_GLYPH_PREVIEW_DIR` to an existing temporary directory. Exported
previews use the production drawing path with a light background and 3× scale.
