# Native drag regression (2026-09-24)

Status: release-target-only candidate **does not resolve the user-reported failure**.
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
