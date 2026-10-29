# Shelf interaction responsiveness

Baseline: `ffb198c811ba7b490ebd3daeef691aa18880034c`. Measured on macOS 27.0.1
(`26A434`), arm64, on 2026-10-30. Changes are isolated on
`codex/shelterbar-smoothness`; no installed application, permissions or user layout
were changed for this experiment.

## Causes and chosen changes

`ShelfViewModel.apply` supplies `item.hasNumericTitle` to the icon cache. That
property performs synchronous Accessibility IPC on the main actor. Swift eagerly
evaluated the argument even when the cache already held a current image and did
not use it. `image(for:hasCount:)` now accepts a nonescaping autoclosure and reads
it only when migrating a legacy record. Current disk records and memory hits
perform no title IPC; legacy image repair keeps its numeric-label semantics.

`MenuBarMenuOpener.open` also called `AXUIElementPerformAction` on the main actor.
A foreign menu's tracking loop can hold that call until its existing 250 ms
messaging timeout. A serial `MenuBarAXPressExecutor` now runs the same bounded call
off the main thread. The opener still awaits its result before checking for the
menu or sending a fallback click. Cancellation checks prevent an already
cancelled press and prevent fallback clicking after cancellation during polling.

Skipping the live inventory/geometry checks would shorten another part of the
activation path, but could act on stale positions. Those checks, capture policy,
menu verification windows, drag handling and menu restoration remain intact.

## Controlled measurements

These are fault-injection measurements of actual cache and executor code, not
native end-to-end click timings. The title fixture sleeps for 10 ms per read;
the AXPress fixture sleeps for 120 ms and returns `cannotComplete`. Scheduling
and timer overhead explain why measured durations exceed the requested sleeps.

Five repeated focused runs gave:

| Measurement | Baseline | Changed |
| --- | --- | --- |
| 20 current-cache lookups, title IPC count | 20 | 0 |
| 20 current-cache lookups, elapsed range | 281.38–297.97 ms | 1.39–1.52 ms |
| Main-actor queued heartbeat during AXPress, range | 130.04–161.33 ms | 0.006–0.012 ms |
| Changed AXPress completion, range | — | 120.44–129.72 ms |

The cache baseline used the same regression test with only the parameter changed
back to `Bool` and `hasCount()` changed back to `hasCount`, recreating the old
eager evaluation. The assertion failed as expected with exactly 20 title reads
in all five runs; the final source was restored to the autoclosure before testing
and committing. The AX test compares the old synchronous call shape and the new
executor with the same delayed action in one process.

The main thread is available while AXPress waits; the foreign menu does not
necessarily open sooner. In the parallel full suite the corresponding heartbeat
was 431.83 ms versus 21.29 ms because other tests also use the main actor. Tests
assert thread affinity and results rather than fragile timing thresholds.

## Reproduction and regression

From the worktree root:

```sh
swift test --force-resolved-versions -j 2 --filter 'slowAXPressDoesNotFreezeMainActor|axPressesKeepSerialOrdering|cancelledAXPressDoesNotRun|cachedGlyphDoesNotReadNumericTitle|legacyGlyphStillReadsNumericTitleForMigration'
swift test --skip-build --filter 'slowAXPressDoesNotFreezeMainActor|cachedGlyphDoesNotReadNumericTitle'
swift test --force-resolved-versions -j 2
git diff --check
```

The five focused tests passed. The complete regression passed **203 tests**
(171 application + 32 core). Tests cover current disk/memory cache hits, legacy
migration, AX result preservation, serial execution and cancellation before
dispatch. Existing tests cover menu policies, activation recovery and verified
drag safety. `git diff --check` passed. The existing Swift Testing package
deprecation warnings remain.

Full test log: `/tmp/shelterbar-smoothness-full.log`; repeated focused logs:
`/tmp/shelterbar-smoothness-repeat-{1...5}.log`; cache baseline logs:
`/tmp/shelterbar-smoothness-cache-before-{1...5}.log` (local, temporary).

## Limits and recommendation

Recommend these two focused changes: they remove avoidable foreign-process work
from the UI thread without weakening activation verification. An AX call already
in progress cannot be interrupted; it retains the 250 ms timeout. Legacy cache
migration still reads the title once, and other AX geometry reads are unchanged.
No real third-party menu was opened or moved during these tests, so native menu
compatibility and complete click latency require release smoke testing. This
experiment establishes neither a whole-app speedup nor an idle CPU reduction.
