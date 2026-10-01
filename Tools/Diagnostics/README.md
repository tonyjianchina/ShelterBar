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

The AppKit pixel check does not change the desktop. The legacy configuration
must fail; the production configuration must put the actual nontransparent
glyph pixels in the trailing visible square, not merely create a status item.

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
```

This read-only check requires existing diagnostic permissions. It strictly
matches ShelterBar's own status window, crops the trailing handle, saves
`/tmp/shelter-status-handle-capture.png`, and rejects an empty image. Inspect the
PNG too: nonempty pixels alone do not establish the correct glyph. Optional
`--inspect-surface` reports the complete own-window alpha bounds for diagnosis.
Run after collection and restart, not just while the boundary is square.
