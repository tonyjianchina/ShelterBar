# Shelf UI experiment

Baseline: `ffb198c811ba7b490ebd3daeef691aa18880034c`. Native macOS SwiftUI/AppKit experiment, 2026-10-30.

## Problem and recommendation

The previous view chose **either** a permission/status message **or** the collected icons. A successful background operation or a declined optional recording permission therefore removed the controls needed to open or return items, despite the count still saying four. The baseline native fixture confirmed four mounted `ShelfIconView` controls normally, but zero with a message or without recording permission.

Keep the compact native icon strip and place notices in a secondary row. This gives operations a stable location and keeps the existing drag source alive while feedback changes. A normal shelf remains 66 pt tall. A message or drag hint adds 42 pt; permission guidance with buttons adds 64 pt. The panel grows downwards from its menu-bar anchor so the icon row does not jump. Permission grants remain explicit, including an “允许录屏” button; no capture or permission policy changes are included here.

| Option | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| Inline message replacing icons (baseline) | Fixed compact height | Hides actions; truncates guidance; disrupts native source controls | Reject |
| Stable icon strip with contextual footer | Keeps drag/click access, compact normal state, clear optional permission wording | Taller only while feedback is visible | Adopt |
| Expanded grid/list palette | More room for labels and search | Larger permanent UI; different drag target geometry and interaction model | Defer until large collections justify it |

The icon strip retains horizontal scrolling, now allows the native scrollbar indicator, and stays usable at 320 pt. Empty state text describes the next action. Pin, menu, progress, notice dismissal and icon controls have explicit accessibility labels/help. Focused icons accept Return or Space; key repeat does not reopen the menu.

## Native render evidence

These PNGs were rendered from the actual production `ShelfView` using `NSHostingView.cacheDisplay` and four synthetic items (forty for overflow). They are **view renders, not screenshots of the desktop**. No screen capture API, production application, real menu-bar layout, TCC permission change or installation was used. The baseline renders were exported before changing the view, from the baseline revision above. The same dimensions and fixture data were used for the before/after states.

| State | Before | After |
| --- | --- | --- |
| Optional recording permission declined | [Before](shelf-ui/before/optional-permission.png) — 0 mounted icons | [After](shelf-ui/after/optional-permission.png) — 4 mounted icons |
| Status message | [Before](shelf-ui/before/notice.png) — 0 mounted icons | [After](shelf-ui/after/notice.png) — 4 mounted icons |
| Normal | [Before](shelf-ui/before/normal.png) | [After](shelf-ui/after/normal.png) |

Additional renders: [320 pt width](shelf-ui/after/narrow.png), [40 icons](shelf-ui/after/overflow.png), [active drag](shelf-ui/after/dragging.png), [empty](shelf-ui/after/empty.png).

The question marks in the declined-permission fixtures are the existing placeholder policy for synthetic items without an application identity or usable capture. This change preserves that policy; hover and accessibility labels identify each item. At narrow width only part of the collection is visible, and the remainder stays scrollable.

## Verification

`Tests/ShelterBarTests/ShelfPresentationUITests.swift` hosts the real view with isolated `UserDefaults` and injected item data. Its focused coverage checks:

- Four icon controls retain their **native object identities** through status, recording-permission, dragging and dismissal transitions; accessibility press remains functional.
- A notice arriving during an active pointer drag keeps the source alive and completes the return callback. The drag hint has priority until release; the operation message then appears.
- Forty controls in a 320 pt host have a scrollable document larger than the viewport. The last item begins outside the visible region, is scrolled into view and activates through accessibility. This uses an undisplayed fixture `NSWindow` so AppKit commits the document geometry; it never orders the window onscreen.
- Focused icons activate on Space/Return exactly once, and ignore repeated activation keys.
- An opt-in exporter regenerates the synthetic PNGs from the production view.

Full regression completed successfully:

```sh
SHELTERBAR_UI_FIXTURE_DIRECTORY=/tmp/shelterbar-ui-after \
  swift test --force-resolved-versions -j 2
```

Result: **203 passing tests** (171 ShelterBar tests + 32 core tests), no failures. The existing Swift Testing dependency deprecation warnings remain. `git diff --check` passed.

To export only the current native fixtures:

```sh
SHELTERBAR_UI_FIXTURE_DIRECTORY=/tmp/shelterbar-ui-after \
  swift test --force-resolved-versions -j 2 --filter exportShelfUIFixtures
```

## Boundaries

The experiment verifies real view rendering, control continuity, local AppKit scrolling, native activation and the existing pointer-tracking seam. It does not claim live third-party menu interaction, VoiceOver navigation, TCC onboarding, multi-display panel placement or deployed-app validation. No production launch or installation was needed. The installer/release integration should retain its separate checks for those paths.
