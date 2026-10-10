# Input permission button fallback — 2026-10-10

The installed v0.5.5 (build 20) shelf displayed “授予输入权限”, but clicking it
could leave the UI unchanged. Its Accessibility request invoked the native AX,
event-listening and event-posting APIs and discarded their outcomes. There was
no fallback if macOS declined or suppressed a prompt. The manual click was not
blocked by the onboarding coordinator's one-attempt marker.

## Reproduction and regression

The OS calls are now injected at the production request boundary. No test grants
or resets the user's permissions. This regression runs the initial automatic
request followed by the same coordinator method used by the shelf button:

```sh
swift test --force-resolved-versions --filter inputPermissionClickFallsBackAfterSilentSystemRequest
```

Before the fix, both repeated runs failed with `settingsOpens = 0`, expected `1`
after the manual click; the request counters proved that both attempts reached
the native-call boundary. After the fix it passes. Polling still does not reopen
settings on every tick.

## Change

v0.5.6 (build 21) returns a distinct granted/settings-opened/settings-failed
result, opens the existing appropriate privacy pane if input access remains
unavailable, and displays guidance directly in the shelf. A failed settings
launch gives manual instructions; a missing list entry has “＋” guidance.
Already-granted access does not prompt again. The AX + event-listening +
event-posting safety gate remains unchanged, as does advancement to optional
Screen Recording after the full input gate succeeds.

Additional tests cover the shelf button callback through the coordinator and
request implementation, visible failure guidance, settings destination,
already-granted access, a grant during the request, and partial grants. These
are deterministic request/feedback tests, not a claim that macOS displayed or
the user accepted every native permission dialog. Native authorization requires
the user; do not clear TCC or enable privacy switches to make a test pass.

## Verification

- `swift test --force-resolved-versions`: all 107 tests passed.
- Release build and strict code-signature verification passed. The installed
  executable matches the built executable: local v0.5.6, build 21.
- With System Settings initially on General, launching the installed build
  opened Privacy & Security → Accessibility and displayed the new shelf guidance.
- Clicking the actual “授予输入权限” button retained the guidance and opened
  the Accessibility settings pane. No privacy switch was changed by the test.
- The native checks verify navigation and feedback, not the completion of both
  permission grants. Sequential authorization remains covered by coordinator
  tests; completing native authorization requires the user.

The v0.5.6 release ships this fix under a new tag and new asset filenames;
the public v0.5.5 download is not silently replaced.
