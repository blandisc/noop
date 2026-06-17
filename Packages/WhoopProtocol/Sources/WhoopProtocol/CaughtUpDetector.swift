import Foundation

/// Pure, stateful detector: decides when a historical offload has *caught up* to the strap's live
/// edge — the band has handed over all its stored history and is now only dribbling the live ~1 Hz
/// tail. Lets the BLE layer complete the sync as a SUCCESS instead of waiting for a `HISTORY_COMPLETE`
/// metadata frame that some WHOOP 4.0 firmware (FW 1.542.0.0) never emits — so the session no longer
/// wedges to the 300 s absolute cap and shows "Sync ran long and was paused" on every sync (FER-201,
/// the positive-completion follow-up to the FER-174 backstop).
///
/// **Signal.** Per-`HISTORY_END` biometric (type-47) frame count, in arrival order. During a real
/// backlog every END is a full chunk (~50 records on observed 4.0 hardware, 2026-06-17 PacketLogger).
/// Once caught up, each END collapses to roughly one BLE round-trip's worth of live drip (~0–5
/// records). So a *sustained run* of small ENDs ⇒ the backlog is drained. A single small END
/// mid-backlog does NOT complete: the run resets on the next full chunk, so a momentary lull can't end
/// the session early.
///
/// **Safety.** Completing early is self-healing — the durable `strap_trim` cursor plus the 900 s
/// periodic re-sync drain any remainder on the next tick, and the safe-trim invariant guarantees
/// nothing is dropped. So `smallChunkMax`/`run` only tune *when the green receipt shows*, never data
/// integrity. Feed `observe` only AFTER a chunk's commit+ack so the triggering END is already durable.
///
/// Plain value type — no CoreBluetooth / I/O — unit-tested in WhoopProtocolTests and relocatable to
/// the planned orchestration package (FER-101) without churn, exactly like `RtcHealthPolicy`.
public struct CaughtUpDetector: Equatable, Sendable {
    /// A `HISTORY_END` with biometric (type-47) frames ≤ this is "small" (live drip, not a backlog
    /// chunk). Observed on hardware: backlog chunks ≈ 50, caught-up ≈ one round-trip's drip.
    /// TUNE against a hardware capture of the caught-up transition — FER-201 has none yet (the
    /// 2026-06-17 capture ended mid-drain, every END was ~50). Default chosen well below the ~50
    /// backlog-chunk size and above the observed ~4-record/round-trip drip.
    public let smallChunkMax: Int
    /// Consecutive small ENDs required to declare caught-up — guards against a one-off small chunk.
    /// At a ~4 s round-trip this is ~12 s of sustained drip, far under the 300 s cap.
    public let run: Int

    private var consecutiveSmall: Int
    private var done: Bool

    public init(smallChunkMax: Int = 8, run: Int = 3) {
        self.smallChunkMax = smallChunkMax
        self.run = run
        self.consecutiveSmall = 0
        self.done = false
    }

    /// Feed one `HISTORY_END`'s biometric (type-47) frame count. Returns `true` the first time the
    /// offload is judged caught-up, and stays `true` thereafter (idempotent). Call AFTER the chunk's
    /// safe-trim commit + ack so the triggering END is already durable.
    public mutating func observe(biometricFrames: Int) -> Bool {
        if done { return true }
        if biometricFrames <= smallChunkMax {
            consecutiveSmall += 1
        } else {
            consecutiveSmall = 0
        }
        if consecutiveSmall >= run { done = true }
        return done
    }

    /// True once the offload has been judged caught-up (mirrors the last `observe` result).
    public var isCaughtUp: Bool { done }

    /// Reset for a new offload session — call from `Backfiller.begin`.
    public mutating func reset() {
        consecutiveSmall = 0
        done = false
    }
}
