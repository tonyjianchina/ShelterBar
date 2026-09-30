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
