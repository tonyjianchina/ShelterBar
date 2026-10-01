# ShelterBar v0.5.5 preview acceptance

## Agreed behavior

- A persistent handle in the original top-right menu bar opens one row below it.
- The row is temporary by default and can be pinned.
- The two placement states are resident (top bar) and collected (shelf).
- With the shelf open, a mouse user drags an actual movable top-bar item down
  into it. Dragging a shelf item back into the right-hand top-bar area restores
  that real item. No shortcut or Command modifier is required.
- The shelf omits icons that are still visible on the top bar.
- Accessibility and Input Monitoring are required for discovery, physical drag
  interception, and native movement; Screen Recording
  permission is optional and enables capture of the original menu-bar status icons. The
  earlier permission-free running-app proxy prototype is replaced.
- On first launch, permission onboarding requests Accessibility and Input
  Monitoring first. As soon as all input capabilities are observed, it requests
  Screen Recording once and skips any permission that is already granted.
- The shelf shows captured status icons with their aspect ratio preserved.
  Monochrome glyphs follow the shelf appearance; colored and multi-shade status
  images retain their original colors.

## Implementation and recovery

The data source enumerates AXExtrasMenuBar items. The native status-button image
is template-rendered by AppKit. The transparent click overlay and top proxies
have been removed.

ScreenCaptureKit captures a single status icon only after strictly matching its
process PID, status window, and AX bounds. Images are cached in memory, without
audio capture, video recording, screenshot files, or network uploads. The app
offers **允许读取图标** (Allow icon access) and **打开设置** (Open Settings) controls;
permission changes may require quitting and reopening ShelterBar.

Visible icons are captured, and hidden icons receive refresh attempts while the
shelf is open. The periodic task does not capture while the shelf is closed.
A failed refresh preserves the last successful image. If no capture is available,
the shelf uses a placeholder and collection continues. Cached snapshots do not guarantee immediate
updates for every animated or changing status.

Top-item drag interception is enabled only while the shelf is visible; the
event tap can remain installed while the shelf is closed.
It is installed and re-enabled only while Accessibility, event listening, and
event synthesis are all authorized. Permission loss cancels the active gesture
and releases physical input. It has a cached hit map, skips tagged synthetic events, and does no AX queries
in the event callback. An AppKit dragging source reports shelf-item releases in
the top-right menu-bar area even though other apps cannot accept our drag data.

A single movement operation reveals the archive handle at its normal width, requests a native Command
drag, observes the actual result, verifies other residents, and only then
expands the same handle leftward and saves placement. The handle is both the visible
entry point and the collection boundary, so a separate invisible divider cannot be
stranded under the camera housing. The proposed destination frame must be fully
outside any camera housing before native input is sent. Failure/cancellation reveals all items with
feedback; no unverified success is persisted. Screen changes cancel the
operation. Stable identities restore across launches; ambiguous ones do not.

Opening a collected item's menu defers re-collection until the next explicit
shelf opening. Newly discovered movable items are automatically adopted into the
collected set; an item already off-row remains in place without an expand/collapse
cycle. The More menu can always show all top icons.

## Acceptance checks

- [x] Native session (2026-09-29): actual collect/return cycles for Shadowrocket,
  Chrome and NetEase Mail, stable membership through polling, restart restoration
  and repeated refresh on a built-in notched display. Commands and evidence are
  recorded in `Tools/Diagnostics/README.md` and `docs/DRAG-DEBUGGING.md`.
- [x] Automated: composited status-window discovery, asynchronous native/AX
  geometry, unmanaged stale AX entries and preservation of real participants.
- [x] Automated: dropping into the shelf yields a single collect action.
- [x] Automated: releasing elsewhere or Escape cancels, including before the
  movement threshold; ordinary clicks remain clicks.
- [x] Automated: our synthetic movement events bypass our input tap.
- [x] Automated: missing or revoked input access releases physical events and
  cancels an in-flight gesture.
- [x] Automated: an ignored OS move fails; fresh geometry must confirm success.
- [x] Automated: cross-display rows cannot be confused.
- [x] Automated: a destination intersecting the camera housing is rejected before input is posted.
- [x] Runtime: ShelterBar publishes one visible status item that serves as both handle and boundary.
- [x] Automated: a saved collected item still visible on top is not duplicated.
- [x] Automated: newly discovered visible and already-hidden items are collected
  without enumerating app or icon identities.
- [x] Automated: Screen Recording is requested exactly once after Accessibility
  changes from denied to granted.
- [x] Automated: onboarding skips both prompts when both permissions are granted.
- [x] Automated: revoking permission clears actionable entries.
- [x] Automated: ambiguous identities are not persisted for a later session.
- [x] Automated: the menu-bar transition shield remains visible through success
  or failure and falls back safely when no snapshot is available.
- [x] Packaging: the DMG stores a Finder icon-view layout with a branded
  background, ShelterBar on the left, and the Applications alias on the right.
- [ ] v0.5.5 UI inspection: shelf layout, original-icon rendering, transition
  masking, and readable
  authorization controls.
- [ ] Authorized native session: grant Accessibility, Input Monitoring, and Screen Recording through
  the in-app controls, restart if necessary, and confirm the original third-party
  status glyphs appear rather than application icons.
- [ ] Authorized native session: verify monochrome appearance, original colored
  and multi-shade status images, aspect ratios, visible capture, hidden refresh
  attempts while the shelf is open, no periodic capture while it is closed,
  last-successful-image retention, and placeholder fallback without capture.
- [ ] Authorized native session: top-to-shelf and shelf-to-top with a real
  third-party icon; verify physical positions, shelf membership, click menu,
  Escape, restart restoration, and notch/multi-display behavior.

## Known platform limits

Some apps do not publish accessible menu-bar items. Mandatory system controls
(clock, Control Center, camera/microphone indicator) are excluded from dragging.
Original status-icon capture requires Screen Recording permission and a strict
window/AX match. Some third-party status windows or hidden items may be
unavailable to ScreenCaptureKit; cached images can become stale until a later
successful capture. OS movement refusal is reported and leaves the bar expanded.
This ad-hoc signed preview has no Developer ID signature or Apple notarization,
and permissions may need to be granted again after rebuilding. Complete native
third-party compatibility remains unverified until the authorized capture and
real drag acceptance checks above have succeeded.
