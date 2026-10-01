# Native drag regression (2026-09-24)

Current status (2026-09-29): v0.5.4 native collection/return and restart checks
pass on the built-in notched display. The captured v0.5.3 failure and fix are
documented below. Earlier traces remain as historical evidence.

Historical status: release-target-only candidate **does not resolve the user-reported failure**.
The user reproduced the same Shadowrocket error after granting permissions and
restarting this exact build. Do not present the packet unit test as an end-to-end fix.

## Captured failure

On the built-in screen, Shadowrocket's AX frame was `(990, 4.5, 36, 24)`
and the divider was `(981, 4.5, 3, 24)`. A listen-only event tap observed
ShelterBar's tagged down, eight drag events, and up from `(1008, 16.5)` to
`(979, 16.5)`. All events, including release, targeted source window 12412.
The actual insertion window at the endpoint was divider window 28175.
The item returned to its initial frame and the UI reported:
`macOS 未接受“Shadowrocket”的位置调整，已保留顶部图标。`

The temporary AX assertion (`swift /tmp/shelter-frame-probe.swift 120`)
reproduced this exact message and exited 1. Local traces are in
`/tmp/shelter-shadow-{events,frames,verdict}.log`; these are diagnostic artifacts,
not a portable end-to-end test.

## Candidate under test

Only release targeting changed: down/drag target the source window; release
targets the unique on-screen status-level window containing the endpoint.
Distance, timing, modifier flags, and real-frame success verification are unchanged.
`swift test --filter nativeDragReleaseTarget` failed against the previous packet
builder and passes with this correction. This checks packet construction, not
macOS acceptance. The native implementation was cross-checked against the
[Ice event implementation](https://github.com/jordanbaird/Ice/blob/main/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift).

The user restored permissions and reproduced the failure. A subsequent automated
restore attempt returned offscreen external-display AX coordinates (y = -1139),
and emitted no tagged drag events; that attempt is a different failure and cannot
validate a synthetic-event correction. Clicking a regular built-in-screen window
through computer use did not switch the AX menu-bar coordinates to the built-in
screen. Keep the current signed build while collecting a real drag trace; avoid
another speculative rebuild/reauthorization cycle. Do not reset TCC or grant
privacy switches automatically.

Other falsifiable hypotheses to test if release targeting is insufficient:

1. Remaining event fields or delivery sequence cause the system to cancel.
2. The endpoint is too close to the divider to trigger insertion.
3. Display transitions invalidate source/destination frames during the gesture.

A separate observed macOS 26 detail: CGWindowList reports status windows owned
by Control Center, not the client application. Icon capture's strict client-PID
matching may therefore need investigation after native movement succeeds.

## Camera-housing regression (2026-09-29)

The v0.5.2 two-item layout allowed the visible archive handle to sit at
`x=895...919` while the independent divider remained at `x=840...843`, inside
the built-in display's camera housing at `x=665...850`. Native movement then
targeted an unavailable insertion position and macOS correctly rejected it.

The fix uses the archive handle itself as the collection boundary and expands
that same item leftward when the section collapses. Native moves now calculate
the complete destination frame and reject it before posting input when any part
intersects the camera housing. A blocked destination returns actionable guidance
instead of the generic macOS refusal message.

## Follow-up trace and second candidate

The user-triggered read-only loop reproduced the exact error again in
`/tmp/shelter-release-target-{events,frames}.log`. Release now has the correct
divider ID, proving the first candidate was insufficient. Source AX positions
were `(990,4.5,36,24)` → `(996,20.5,36,24)` → `(978,20.5,36,24)` → original.
Neighbors and divider did not reorder: pickup occurred, insertion did not commit.

The native windows differ from AX glyphs: source `(991,0,34,33)` and divider
`(974,0,17,33)`. Thus the previous endpoint x979 remained inside the actual
divider window. Session-head trace also showed inherited foreground PID 97940
and window-number field 0; this is a packet-construction finding, not proof that
WindowServer ultimately routed to the wrong process.

Second candidate changes:

- Resolve unique native status windows, accepting either the client process or
  the verified `com.apple.controlcenter` host; reject unknown/ambiguous windows.
- Calculate a whole-item-clear endpoint from native divider bounds and actual
  pickup offset (x954 for this captured AX frame), with same-display validation.
- Populate source native PID, window-number field 0x33 and public window fields;
  clear Command on release. Preserve tagged-event bypass and real AX verification.
- Use the same host-aware matcher for icon capture, which runs after movement.

Regression red/green: replayed legacy endpoint and packet fields cause 10
expectation failures in 3 focused tests; corrected candidate passes all 4 focused
tests. Full suite: **54 tests pass**. These tests verify geometry and construction,
**not actual macOS acceptance**; native end-to-end verification remains required.
No Ice source code was copied. Its implementation was used only to identify event
field conventions to investigate.

Built/restarted second candidate with cdhash
`5b250f966364c00f0621bd2d8ceb8447dd232da7`. Native validation is currently
blocked: fresh tccd entries at 20:44:18 report `Failed to match existing code
requirement` for both Accessibility and ScreenCapture. Do not rebuild again just
to retry this candidate; it needs user-mediated authorization for this unchanged
binary first. No TCC database or privacy toggle was modified by the agent.

## v0.5.3 recurrence and verified v0.5.4 fix (2026-09-29)

`osascript Tools/Diagnostics/CheckReconciliation.applescript` reproduced the
installed v0.5.3 failure repeatedly, exit 1:
`FAIL: 无法安全整理当前菜单栏，已展开全部图标。`

The source discovery query used `.optionOnScreenOnly`. On this machine it
returned zero status-layer windows, while `.optionAll` returned Control Center's
hosted native windows at the live AX coordinates. Chrome AX `(857,4.5,24,24)`
matched native window 4816 `(850,0,38,33)`; ShelterBar AX `(1062,4.5,24,24)`
matched window 6039 `(1055,0,38,33)`. Neither native record had an on-screen flag.
The captured regression test failed both matches before the fix and passed after.

Full native testing then exposed two secondary failures. Reordered AX geometry
updated before native-window animation; a failed pair matched again after 150 ms.
Pair discovery now waits up to 450 ms without relaxing the strict matcher.
Lark Helper also retained AX `(-1,981,56,24)` with no native status window.
It must neither participate in resident verification nor be adopted as collected
when the boundary expands. Real collapsed Shadowrocket geometry retained its
menu-bar row, `(-2127,4.5,36,24)`.

A boundary at the leftmost safe position also needs an inverse move: move our
boundary after the selected item, then restore other residents before collapse.
The engine still verifies every actual participant before persisting success.

Observed native input checks (ordinary mouse input, actual production app):

- Shadowrocket: `(913,4.5,36,24)` → `(-2127,4.5,36,24)` → `(913,4.5,36,24)`.
- Chrome: `(955,4.5,24,24)` → `(-2119,4.5,24,24)` → `(955,4.5,24,24)`.
- NetEase Mail: `(1181,4.5,67,24)` → `(-2127,4.5,67,24)` → `(947,4.5,67,24)`.
- Shelf count follows 0 → 1 → 0 in each cycle, remaining at 1 through multiple
  background polls. Lark's stale entry is not adopted.
- Quitting and restarting restores the saved Shadowrocket collection. Explicit
  refresh passes with both an empty and a populated shelf.

These are native local checks, not a blanket multi-display compatibility claim.
No TCC database, code-requirement record or privacy toggle was modified.

Final-package acceptance: the native cycles above ran the release executable
from the development host with existing permissions. The v0.5.4 DMG and ZIP
passed signature, binary equality and checksum checks. Installing that DMG at
`/Applications/ShelterBar.app` and launching normally reported Accessibility
permission missing, so the final normal-launch drag check is **blocked**, not
passed. The user must reauthorize the new ad-hoc build before that acceptance
check can continue. No privacy control was changed or bypassed. The native
scripts now reject missing permission explicitly instead of counting a
permission-only panel as successful reconciliation.

## Missing ShelterBar handle after collection (2026-10-01)

v0.5.4 build 10 retained a live status item, but its archive glyph disappeared
after collection. The AX item expanded to 3026 points. AppKit's image-only
button cell still centered the icon despite `.imageRight`, placing the glyph
near x1505 in local coordinates instead of the visible x3002...3026 edge.
`CheckStatusHandle --legacy` reproduces the offscreen pixels and exits 1.

A trailing NSImageView passed detached button layout tests but failed actual
hosted-window capture after collapse (local builds 11/12). Explicit redraw did
not reliably repair it. Do not count a subview's frame as a visible icon.

Build 14 uses a native template image with transparent leading space and the
archive pixels at its trailing edge. It preserves the standard status button,
target/action, and accessibility label. Frame notifications refresh the image
when the system finishes resizing; explicit boundary transitions refresh it too.

Verification: 92 tests pass, including rendered alpha bounds, asynchronous
button-size changes, and native template/accessibility properties. The installed
locally signed build 14 restored saved collection on normal launch, retaining
the original collected entries. Actual hosted capture while collapsed showed native width 3040 points,
6080×66 pixels, glyph alpha bounds `(6027,21,26,26)`, and a nonempty trailing
handle at `(1096,4.5,24,24)` on the built-in screen. Repeated captures pass.
The earlier subview candidate produced a completely transparent captured surface.

No TCC database or privacy switches were changed. Local builds use the existing
`ShelterBar Local Code Signing` identity. The September 29 DMG in dist/releases
is still build 10 and must be rebuilt before any publication; this change has
not been published as a download. This is a handle-visibility fix, not proof
that every collected third-party icon can be captured without ScreenCapture access.
