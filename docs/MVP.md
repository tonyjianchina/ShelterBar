# ShelterBar v0.3.0 preview acceptance

## Agreed behavior

- A persistent handle in the original top-right menu bar opens one row below it.
- The row is temporary by default and can be pinned.
- The two placement states are resident (top bar) and collected (shelf).
- With the shelf open, a mouse user drags an actual movable top-bar item down
  into it. Dragging a shelf item back into the right-hand top-bar area restores
  that real item. No shortcut or Command modifier is required.
- The shelf omits icons that are still visible on the top bar.
- Accessibility is required for discovery and native movement; Screen Recording
  permission is required to capture the original menu-bar status icons. The
  earlier permission-free running-app proxy prototype is replaced.
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
A failed refresh preserves the last successful image. If the first capture has
no usable image, recovery expands the real menu-bar items instead of leaving
them hidden without a shelf image. Cached snapshots do not guarantee immediate
updates for every animated or changing status.

Top-item drag interception is enabled only while the shelf is visible; the
event tap can remain installed while the shelf is closed.
It has a cached hit map, skips tagged synthetic events, and does no AX queries
in the event callback. An AppKit dragging source reports shelf-item releases in
the top-right menu-bar area even though other apps cannot accept our drag data.

A single movement operation reveals the divider, requests a native Command
drag, observes the actual result, verifies other residents, and only then
collapses and saves placement. Failure/cancellation reveals all items with
feedback; no unverified success is persisted. Screen changes cancel the
operation. Stable identities restore across launches; ambiguous ones do not.

Opening a collected item's menu defers re-collection until the next explicit
shelf opening. Newly discovered off-row items while collapsed trigger recovery
expansion. The More menu can always show all top icons.

## Acceptance checks

- [x] Automated: dropping into the shelf yields a single collect action.
- [x] Automated: releasing elsewhere or Escape cancels, including before the
  movement threshold; ordinary clicks remain clicks.
- [x] Automated: our synthetic movement events bypass our input tap.
- [x] Automated: an ignored OS move fails; fresh geometry must confirm success.
- [x] Automated: cross-display rows cannot be confused.
- [x] Automated: a saved collected item still visible on top is not duplicated.
- [x] Automated: revoking permission clears actionable entries.
- [x] Automated: ambiguous identities are not persisted for a later session.
- [ ] v0.3.0 UI inspection: shelf layout, original-icon rendering, and readable
  authorization controls.
- [ ] Authorized native session: grant Accessibility and Screen Recording through
  the in-app controls, restart if necessary, and confirm the original third-party
  status glyphs appear rather than application icons.
- [ ] Authorized native session: verify monochrome appearance, original colored
  and multi-shade status images, aspect ratios, visible capture, hidden refresh
  attempts while the shelf is open, no periodic capture while it is closed,
  last-successful-image retention, and initial-capture recovery.
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
