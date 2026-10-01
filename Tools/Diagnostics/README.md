# Native regression checks

These tools drive or inspect the running app on a macOS desktop with existing
Accessibility access. They do not grant permissions or edit the app's preferences.
The native cycle physically reorders the chosen menu-bar item, returning it to
the resident section afterwards. Use a running third-party app and an empty shelf.

```sh
osascript Tools/Diagnostics/CheckReconciliation.applescript
swiftc -parse-as-library Tools/Diagnostics/CheckNativeCycle.swift -o /tmp/shelter-native-cycle
/tmp/shelter-native-cycle com.liguangming.Shadowrocket
/tmp/shelter-native-cycle com.google.Chrome
/tmp/shelter-native-cycle com.netease.macmail
```

The cycle asserts actual AX visibility and shelf count 0 → 1 → 0, with multiple
background polls while collected. A skipped or failed movement exits nonzero.
The reconciliation check caught the exact v0.5.3 error before the fix.
It also fails when the installed app has no Accessibility permission; a
permission-blocked run must not count as successful native reconciliation.

Inspect production native-window matching without changing layout:

```sh
swiftc -swift-version 6 Sources/ShelterBar/MenuBarNativeWindow.swift Tools/Diagnostics/InspectMenuBar.swift -o /tmp/shelter-inspect-menu-bar
/tmp/shelter-inspect-menu-bar
```

`Drag.swift` is a low-level ordinary mouse drag helper for diagnosis. Its four
coordinates must come from a fresh AX snapshot or screenshot, not stale values.

## Visible status handle

The AppKit pixel check does not change the desktop. The legacy oversized button
must fail; the production independent square entry must contain its glyph.
This is a drawing check, not proof of visibility in the composited menu bar.

```sh
swiftc -swift-version 6 Sources/ShelterBar/MenuBarStatusHandle.swift Tools/Diagnostics/CheckStatusHandle.swift -o /tmp/shelter-status-handle
/tmp/shelter-status-handle --legacy
/tmp/shelter-status-handle
```

Inspect the running installed app's real hosted status-window pixels:

```sh
swiftc -swift-version 6 -parse-as-library \
  Sources/ShelterBar/MenuBarIconCapture.swift \
  Sources/ShelterBar/MenuBarNativeWindow.swift \
  Sources/ShelterBar/ScreenCapturePermission.swift \
  Sources/ShelterBar/MenuBarIconPresentation.swift \
  Sources/ShelterBar/ShelfItemSource.swift \
  Tools/Diagnostics/CaptureStatusHandle.swift -o /tmp/shelter-capture-handle
/tmp/shelter-capture-handle
/tmp/shelter-capture-handle --composite
```

This read-only check requires existing diagnostic permissions. It strictly
matches ShelterBar's own status window, crops the trailing handle, saves
`/tmp/shelter-status-handle-capture.png`, and rejects an empty image. Inspect the
PNG too: nonempty pixels alone do not establish the correct glyph **or actual
screen visibility**. Build 14 passed this private-window test while its entry
remained absent from the user's screen. Optional
`--inspect-surface` reports the complete own-window alpha bounds for diagnosis.
`--composite` also captures only the menu-bar strip and compares the visible
entry with the glyph mask. A system Wi-Fi positive control must have contrast;
if the whole menu-bar capture is unavailable/blank, exit 2 means **blocked**,
not pass or app-specific failure. Exit 1 indicates a failed glyph check.
Run after collection and restart, not just with all collected items revealed.

`CaptureMenuStrip.swift` is a secondary read-only diagnostic using an explicit
display filter with `includeMenuBar = true`. It saves only the rightmost 540×33
menu-bar points to `/tmp/shelter-menubar-display.png`; it makes no pass claim.
