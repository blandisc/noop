import Foundation

/// Pure, stateful policy: should NOOP re-assert `SET_CLOCK` (+ the data-stream `SET_CONFIG` burst) at the
/// start of the next offload session, given the latest offload's RTC verdict (`RtcHealthPolicy.Verdict`)?
///
/// Background (FER-93). A power-reset WHOOP 4.0 loses its volatile RTC and stops persisting biometry to
/// flash; it never answers `GET_CLOCK`, so NOOP can't read the clock back to confirm a fix. The only
/// reliable success signal is type-47 frames flowing again (`savingHealthy`). So NOOP just re-sends
/// `SET_CLOCK` and watches for saving to resume — but it must do so carefully:
///   - **Not every chunk.** Re-issuing the clock *mid-offload* stops the 4.0 from streaming type-47 (the
///     connect-handshake "storm" note in `BLEManager`). The BLE layer only re-asserts at the START of a
///     session, and this policy gates how often that's allowed.
///   - **Not forever.** A band that never latches (e.g. battery truly dead) must not loop re-asserting. The
///     budget caps it to `maxPerConnect`; after that NOOP rests on the honest "RTC lost" diagnostic until
///     the next BLE connect (`reset()`).
/// Once the band saves again (`savingHealthy`), the budget clears — a later relapse gets the full allowance.
///
/// Plain value type — no CoreBluetooth / I/O — unit-tested in WhoopProtocolTests and relocatable to the
/// planned orchestration package (FER-101), exactly like `CaughtUpDetector` / `RtcHealthPolicy`.
public struct ClockReassertPolicy: Equatable, Sendable {
    /// Max `SET_CLOCK` re-assertions per BLE connect — a backstop so a band that never latches can't loop
    /// forever. At one per offload session this is a handful of attempts, then NOOP rests until the next connect.
    public let maxPerConnect: Int

    private var assertsThisConnect: Int

    public init(maxPerConnect: Int = 3) {
        self.maxPerConnect = maxPerConnect
        self.assertsThisConnect = 0
    }

    /// Decide whether to re-assert the clock at the START of the next offload session. `savingHealthy` clears
    /// the budget (the band is fine now — nothing to fix). Otherwise re-assert only while the verdict asks for
    /// it AND the per-connect budget isn't spent. Returns `true` at most `maxPerConnect` times per connect.
    public mutating func shouldReassert(_ verdict: RtcHealthPolicy.Verdict) -> Bool {
        if verdict.savingHealthy {
            assertsThisConnect = 0
            return false
        }
        guard verdict.shouldReassertClock, assertsThisConnect < maxPerConnect else { return false }
        assertsThisConnect += 1
        return true
    }

    /// Reset the per-connect budget — call on a fresh BLE connect (didConnect).
    public mutating func reset() { assertsThisConnect = 0 }

    /// How many re-assertions have fired this connect (diagnostics / tests).
    public var assertionsThisConnect: Int { assertsThisConnect }
}
