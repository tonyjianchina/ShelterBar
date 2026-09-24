# ShelterBar MVP

## Agreed behavior

- A persistent handle in the original top-right menu bar opens one row below it.
- The row is temporary by default and can be pinned.
- The two placement states are resident (top bar) and collected (shelf).
- With the shelf open, a mouse user drags an actual movable top-bar item down
  into it. Dragging a shelf item back into the right-hand top-bar area restores
  that real item. No shortcut or Command modifier is required.
- The shelf omits icons that are still visible on the top bar.
- The latest request permits necessary system permissions. Accessibility is
  required; the earlier permission-free running-app proxy prototype is replaced.

## Implementation and recovery

The data source enumerates AXExtrasMenuBar items. The native status-button image
is template-rendered by AppKit. The transparent click overlay and top proxies
have been removed.

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
- [x] UI inspection: the new build opens its shelf with readable authorization
  controls.
- [ ] Authorized native session: top-to-shelf and shelf-to-top with a real
  third-party icon; verify physical positions, shelf membership, click menu,
  Escape, restart restoration, and notch/multi-display behavior.

## Known platform limits

Some apps do not publish accessible menu-bar items. Mandatory system controls
(clock, Control Center, camera/microphone indicator) are excluded from dragging.
The row uses app-icon thumbnails; exact live glyph capture would require a
separate Screen Recording feature. OS movement refusal is reported and leaves
the bar expanded. This development build requires manual authorization after
some ad-hoc rebuilds; the native acceptance check must not be reported as passed
until that step and the real drag loop have succeeded.
