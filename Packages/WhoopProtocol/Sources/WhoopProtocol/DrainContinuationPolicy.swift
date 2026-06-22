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
/// **Signal — ground truth, not a frame-count heuristic (FER-480).** "Is there more backlog?" is judged
/// against what the strap *says it holds* (`GET_DATA_RANGE` newest banked-record unix, `strapNewestTs`)
/// versus what we've *actually persisted* (`ourFrontierTs` = max persisted HR ts) — the same idiom as
/// `StuckStrapDetector`. The strap still ahead of our frontier by more than `behindGapSeconds` ⇒ real
/// backlog remains ⇒ keep going. This replaced FER-287's original `largeSessionFrames` batch-size guess,
/// which our own notes admitted was unanchored (it needed a hardware capture to tune; FER-288).
///
/// **Stale-epoch fallback (#451).** A strap that was fully discharged (or carries a previous owner's
/// history) banks records across multiple clock epochs, and `GET_DATA_RANGE`'s "newest" can latch an OLD
/// value (e.g. 2024 when the real newest is 2026) — reading as "behind us", which would stop the drain
/// after ONE session and force the user to tap the strap. But if the just-closed session **persisted real
/// sensor rows** AND the trim cursor advanced, the strap is demonstrably still handing over backlog, so we
/// keep going regardless of a stale range. Empty / console-only ENDs persist 0 rows, so a genuinely
/// caught-up strap still stops.
///
/// **Anti-spin (`lastTrimAdvanced`).** Only continue if the just-ended session actually moved the strap's
/// `strap_trim` cursor. A frozen cursor (strap handing back console-only / refusing to trim) would spin
/// forever burning battery — stop and let the periodic floor retry slowly.
///
/// **Safety / termination.** Only a **cleanly-closed** session chains (`HISTORY_COMPLETE` / caught-up):
/// a timeout or session-cap close means the link is unhealthy, so we fall back to the rate-limited path
/// instead of hammering it. A `caughtUp` session (the `CaughtUpDetector` judged the backlog drained) stops
/// regardless — it also bounds the case where the HR-only frontier lags the true newest record on a
/// 4.0 synced night. `maxChain` is a hard backstop that guarantees the chain terminates. Chaining never
/// changes which bytes go out (it re-uses `SEND_HISTORICAL_DATA`) and never touches the durable
/// `strap_trim` cursor, so it can only change *when* the next session fires, never data integrity.
///
/// Plain value type — no CoreBluetooth / I/O — unit-tested in WhoopProtocolTests and relocatable to the
/// planned orchestration package (FER-101) without churn, exactly like `CaughtUpDetector`.
public struct DrainContinuationPolicy: Equatable, Sendable {
    /// How far ahead (seconds) the strap's newest banked record must be vs our persisted frontier before
    /// "more backlog remains" counts as real, not clock noise. Matches `StuckStrapDetector.behindGapSeconds`
    /// so the two agree on "behind".
    public let behindGapSeconds: Int
    /// Hard cap on consecutive auto-fired sessions in one chain — the termination backstop. Sized to drain
    /// a full night (~19,400 frames ÷ ~270/session ≈ 72 sessions) with margin; past it, the 900 s periodic
    /// re-sync drains any remainder. With ground-truth stopping (above) this is now only a backstop, not
    /// the primary stop — kept high deliberately so a deep multi-night backlog drains in one hands-off
    /// chain (the FER-287 intent) rather than across many 15-min-spaced batches.
    public let maxChain: Int

    private var continued: Int

    public init(behindGapSeconds: Int = 300, maxChain: Int = 120) {
        self.behindGapSeconds = behindGapSeconds
        self.maxChain = maxChain
        self.continued = 0
    }

    /// Decide whether to auto-fire another offload session immediately. Returns `true` at most `maxChain`
    /// times per chain; call `reset()` when a *non-chained* (rate-limited) sync starts a fresh drain.
    /// - Parameters:
    ///   - completedCleanly: the session ended via `HISTORY_COMPLETE` or caught-up (not timeout / cap).
    ///   - caughtUp: the `CaughtUpDetector` judged the backlog drained this session — a hard stop.
    ///   - strapNewestTs: newest banked-record unix the strap reports (`GET_DATA_RANGE`); nil if unknown.
    ///   - ourFrontierTs: newest record we've persisted (max HR ts); nil if unknown.
    ///   - rowsPersistedThisSession: biometric rows the just-closed session actually persisted (the #451
    ///     fallback signal — real progress even when the range read is stale).
    ///   - lastTrimAdvanced: the just-ended session moved the `strap_trim` cursor (anti-spin guard).
    public mutating func shouldContinue(completedCleanly: Bool,
                                        caughtUp: Bool,
                                        strapNewestTs: Int?,
                                        ourFrontierTs: Int?,
                                        rowsPersistedThisSession: Int,
                                        lastTrimAdvanced: Bool) -> Bool {
        guard completedCleanly, !caughtUp else { return false }
        guard lastTrimAdvanced else { return false }          // don't spin on a frozen cursor
        guard continued < maxChain else { return false }      // termination backstop
        // Ground truth: the strap reports newer data than we hold. Reliable when its clock epoch is sane.
        let behind: Bool = {
            guard let newest = strapNewestTs, let frontier = ourFrontierTs else { return false }
            return (newest - frontier) > behindGapSeconds
        }()
        // #451 fallback: a stale/unknown range can read "not behind" even while real backlog streams, so a
        // session that persisted real rows (and advanced the trim, guarded above) keeps draining anyway.
        guard behind || rowsPersistedThisSession > 0 else { return false }
        continued += 1
        return true
    }

    /// How many sessions the current chain has auto-fired (for logging / observability).
    public var chainLength: Int { continued }

    /// Re-arm the chain. Call when a non-`.drain` trigger (manual / periodic / connect / foreground /
    /// strap) starts a new offload, so each fresh drain gets the full `maxChain` budget.
    public mutating func reset() { continued = 0 }
}
