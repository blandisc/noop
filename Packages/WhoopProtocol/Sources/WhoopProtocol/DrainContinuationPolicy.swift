import Foundation

/// Pure, stateful decision: after a historical-offload session closes, should we **immediately** fire
/// another one — skipping the normal rate-limiter — because the strap clearly still has a backlog?
///
/// **Why this exists (FER-287).** The strap records biometrics at ~1 Hz, so a night with the phone
/// disconnected buffers ~19,400 frames. One offload session hands over only a bounded batch and then
/// closes (`HISTORY_COMPLETE`), so draining a whole night otherwise needs *dozens* of sessions — and
/// the only automatic re-trigger is the rate-limiter (`BackfillPolicy`: 90 s event / 900 s periodic).
/// The user ends up tapping "Sync" tens of times to push session after session. This policy lets the
/// BLE layer chain sessions back-to-back while a backlog remains, then stop on its own once drained.
///
/// **Signal.** The session's total `HISTORICAL_DATA` (type-47) frame count — the same tally the sync
/// receipt already accumulates. A session that delivered a **large** batch ⇒ the strap still had real
/// history ⇒ keep going. A **small** session ⇒ only the live ~1 Hz drip is left ⇒ stop. A `caughtUp`
/// session (the `CaughtUpDetector` judged the backlog drained) ⇒ stop regardless of count.
///
/// **Safety / termination.** Only a **cleanly-closed** session chains (`HISTORY_COMPLETE` / caught-up):
/// a timeout or session-cap close means the link is unhealthy, so we fall back to the rate-limited path
/// instead of hammering it. `maxChain` is a hard backstop that guarantees the chain terminates even if
/// the "large" heuristic never flips. Chaining never changes which bytes go out (it re-uses
/// `SEND_HISTORICAL_DATA`) and never touches the durable `strap_trim` cursor, so it can only change
/// *when* the next session fires, never data integrity — exactly like `CaughtUpDetector`.
///
/// Plain value type — no CoreBluetooth / I/O — unit-tested in WhoopProtocolTests and relocatable to the
/// planned orchestration package (FER-101) without churn, exactly like `CaughtUpDetector`.
public struct DrainContinuationPolicy: Equatable, Sendable {
    /// A cleanly-closed session with **more** type-47 frames than this still had backlog → keep draining.
    /// At/under it, the session is treated as the live drip → stop. Chosen above the observed live-tail
    /// (~8–50 frames/session) and at the low end of a real backlog batch (~100–270 on 4.0 hardware,
    /// 2026-06-19 log) so it errs toward chaining; mis-tuning is self-healing (the periodic re-sync drains
    /// any remainder, so it's never worse than today). TUNE against a hardware capture of a real
    /// (phone-was-disconnected) morning drain — FER-288 owns that capture.
    public let largeSessionFrames: Int
    /// Hard cap on consecutive auto-fired sessions in one chain — the termination backstop. Sized to drain
    /// a full night (~19,400 frames ÷ ~270/session ≈ 72 sessions) with margin; past it, the 900 s periodic
    /// re-sync drains any remainder.
    public let maxChain: Int

    private var continued: Int

    public init(largeSessionFrames: Int = 100, maxChain: Int = 120) {
        self.largeSessionFrames = largeSessionFrames
        self.maxChain = maxChain
        self.continued = 0
    }

    /// Decide whether to auto-fire another offload session immediately. Returns `true` at most `maxChain`
    /// times per chain; call `reset()` when a *non-chained* (rate-limited) sync starts a fresh drain.
    /// - Parameters:
    ///   - completedCleanly: the session ended via `HISTORY_COMPLETE` or caught-up (not timeout / cap).
    ///   - caughtUp: the `CaughtUpDetector` judged the backlog drained this session.
    ///   - sessionBiometricFrames: total type-47 frames the just-closed session delivered.
    public mutating func shouldContinue(completedCleanly: Bool,
                                        caughtUp: Bool,
                                        sessionBiometricFrames: Int) -> Bool {
        guard completedCleanly, !caughtUp else { return false }
        guard sessionBiometricFrames > largeSessionFrames else { return false }
        guard continued < maxChain else { return false }
        continued += 1
        return true
    }

    /// How many sessions the current chain has auto-fired (for logging / observability).
    public var chainLength: Int { continued }

    /// Re-arm the chain. Call when a non-`.drain` trigger (manual / periodic / connect / foreground /
    /// strap) starts a new offload, so each fresh drain gets the full `maxChain` budget.
    public mutating func reset() { continued = 0 }
}
