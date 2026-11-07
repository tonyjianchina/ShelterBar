# PR #4 repair verification — 2026-11-07

Branch: `cursor/fix-qq-icon-and-same-version-update-e677`, based directly on
`e16b8b5a2914326f2a29aad6fb316bc486e6de0f`. No merge from main, version bump,
release publication, website change, or social post.

## Changes and causes

- QQ Music's custom status view rejects both AXPress and AXShowMenu with
  `-25206` (`actionUnsupported`). Its wide status view also replaces the title
  with playback controls on hover. A normal shelf click now temporarily
  reveals the item, reloads the AX reference, tries the bounded AX actions,
  and right-clicks the trailing QQ logo at its current visible position.
  QQ's native context menu contains 上一首 / 播放 / 下一首. Other applications
  retain a left-click fallback. A missing resulting window reports failure;
  an AX timeout that already opened a window never causes a second click.
- Composite capture edge padding was measured in physical pixels. A Retina
  overflow chevron's seven-pixel inset passed the fixed six-pixel threshold
  and overwrote valid cached artwork. Padding is now measured in logical
  points, covered at 1x, 2x and 3x plus the existing real-image/cache fixtures.
- Discovery now keeps all unsaved items resident. Empty, partial and late
  initial scans, permission grants, restarts and newly launched applications
  never opt items into collection. Only an explicit user collection does so.
- A saved selection can precede its live AX inventory. An empty host intent
  correctly remains expanded; the engine now waits for discovery rather than
  interpreting this as an unsafe ShelterBar entry and entering degraded mode.
- Real startup logs also showed the 750ms watchdog returning an empty scan
  just before the AX source returned 16 items. The source's cooperative
  deadline now leaves up to 100ms for the final bounded synchronous AX request
  and delivery; the hard watchdog still caps an uncooperative source.
- The native collection diagnostic now accepts the explicitly requested QQ
  target and reads the current combined accessibility count label.

## Verification

Environment: macOS 27.0.1 (26A434), arm64, built for macOS 14+. Native checks
used `/Applications/ShelterBar.app/Contents/MacOS/ShelterBar --preview` under
the terminal's existing Accessibility, event-listen, event-post and screen
capture authorization. No TCC permissions were reset or granted by this task.
Automatic update scheduling was disabled by an environment variable during
isolated native checks; the real manual updater still used the default feed.

Command:

```sh
swift test --force-resolved-versions --jobs 2 --no-parallel
scripts/package-release.sh
```

| Check | Result |
| --- | --- |
| Original baseline | 195 application tests: three failing tests, four issues; 32 Core tests passed |
| Final regression | 207 application tests + 32 Core tests, all passed |
| DMG / ZIP / SHA256 / signatures / DMG layout | Passed |
| Remove old installed bundle, install from final ZIP | Passed; stable self-signed requirement retained |
| Clean preferences and runtime cache, first `--preview` | Passed: empty shelf, no collected preference written |
| Manual drag of QQ into installed app | Passed: one shelf item, persists through polling |
| Ordinary shelf click opens QQ menu | Passed: actual QQ window 28222, layer 101, 71x82 at (1104, 34) |
| Close QQ menu | Passed: QQ automatically returns to the one-item shelf |
| Restore original preferences and restart | Passed: one QQ item, original selection/order/pinning preserved, no unsafe-entry error |
| Manual same-version update check | Passed: UI shows 0.5.14 (38) is current; cached, no download |
| Same-version reinstall check | Passed: application PID, binary SHA256, inode and modification time unchanged |

Local package version remains `0.5.14` build `38`. Installed binary SHA256:
`7d03facf651cf718288f24c4314f09cba815428756385f762c2f8df761f7d28f`.

Local evidence is in `dist/pr4-verification/` (intentionally ignored by Git):

- `full-tests-final.log`, `package.log`
- `final-qq-manual-collection.log`, `final-qq-menu.log`, `qq-open-menu-windows.log`
- `update-before.json`, `update-after.json`, `same-version-update.log`
- `01-final-clean-preview.png`, `03-qq-menu-open.png`
- `04-qq-returned-to-shelf.png`, `05-restored-preferences.png`
- `06-up-to-date-no-reinstall.png`

The original runtime data and preferences are backed up at
`/Users/zhengjian/Documents/备份/ShelterBar/pr4-20261107-1444/`.
