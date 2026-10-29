import ApplicationServices
import Foundation
import Testing
@testable import ShelterBar

private final class PressProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private(set) var maximumActive = 0
    private(set) var ranOnMainThread = false

    func action(_ reference: MenuBarItemReference) -> AXError {
        lock.withLock {
            active += 1
            maximumActive = max(maximumActive, active)
            ranOnMainThread = ranOnMainThread || Thread.isMainThread
        }
        Thread.sleep(forTimeInterval: 0.12)
        lock.withLock { active -= 1 }
        return .cannotComplete
    }
}

@Test("a slow AX press yields the main actor and preserves the result")
@MainActor
func slowAXPressDoesNotFreezeMainActor() async {
    let baselineProbe = PressProbe()
    let probe = PressProbe()
    let executor = MenuBarAXPressExecutor(action: probe.action)
    let reference = MenuBarItemReference(
        pid: getpid(), element: AXUIElementCreateApplication(getpid()), frame: .zero
    )
    // The old opener called AXPress synchronously on the main actor. Inject
    // the same bounded foreign-process delay into both call paths. This is a
    // scheduler benchmark, not a measurement of a native menu opening.
    let baselineStarted = ContinuousClock.now
    let baselineHeartbeat = Task { @MainActor in baselineStarted.duration(to: .now) }
    let baselineResult = baselineProbe.action(reference)
    let blockedHeartbeat = await baselineHeartbeat.value

    let started = ContinuousClock.now
    let heartbeat = Task { @MainActor in started.duration(to: .now) }
    let result = await executor.press(reference)
    let responsiveHeartbeat = await heartbeat.value

    #expect(baselineProbe.ranOnMainThread)
    #expect(!probe.ranOnMainThread)
    #expect(result == baselineResult)
    // Assert thread affinity, not wall-clock limits that fail on busy CI hosts.
    print("AX_PRESS_BENCH baselineHeartbeat=\(blockedHeartbeat) asyncHeartbeat=\(responsiveHeartbeat) asyncTotal=\(started.duration(to: .now))")
}

@Test("two pending AX presses execute serially")
@MainActor
func axPressesKeepSerialOrdering() async {
    let probe = PressProbe()
    let executor = MenuBarAXPressExecutor(action: probe.action)
    let reference = MenuBarItemReference(
        pid: getpid(), element: AXUIElementCreateApplication(getpid()), frame: .zero
    )
    async let first = executor.press(reference)
    async let second = executor.press(reference)
    let results = await (first, second)
    #expect(results.0 == .cannotComplete && results.1 == .cannotComplete)
    #expect(probe.maximumActive == 1)
    #expect(!probe.ranOnMainThread)
}

@Test("an already cancelled activation never sends an AX press")
@MainActor
func cancelledAXPressDoesNotRun() async {
    let probe = PressProbe()
    let executor = MenuBarAXPressExecutor(action: probe.action)
    let reference = MenuBarItemReference(
        pid: getpid(), element: AXUIElementCreateApplication(getpid()), frame: .zero
    )
    let press = Task { await executor.press(reference) }
    press.cancel()
    #expect(await press.value == .failure)
    #expect(probe.maximumActive == 0)
}
