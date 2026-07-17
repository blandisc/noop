import Foundation
import WhoopProtocol

// NightRhythmAssembler.swift — assemble ONE night's resting windows from raw R-R + gravity
// and feed them to the pure `RhythmScreener` engine. This is the wiring half of FER-666:
// it slices a night into fixed resting windows, decides motion-stillness per window, and
// hands each window to `screenWindow`. It adds NO new science — the statistics, the labels
// and the night roll-up all live in `RhythmScreener`; the motion gate reuses `SleepStager`'s
// published stillness primitive. Pure and database-free: the app layer reads the streams
// and the night bounds, this turns them into `RhythmScreener` results.
//
// NON-CLINICAL, like the engine it feeds: nothing here names a condition, scores risk, or
// emits a verdict. It only groups beats into windows and describes each one.

public enum NightRhythmAssembler {

    /// Length of one resting window (seconds). A night is sliced into consecutive windows of
    /// this size; each is screened on its own. Five minutes at ~60 bpm is ~300 beats — well
    /// above `RhythmScreener.windowMinBeats` — so a clean stretch reads "solid", while a
    /// restless stretch fails the motion or signal gate and reads "unreadable" on its own.
    public static let windowSeconds: Int = 5 * 60

    /// Minimum gravity samples in a window before its stillness can be judged at all. Below
    /// this, motion is unconfirmed and the window is treated as NOT still (conservative: an
    /// unverified window is discarded, not trusted — motion is the biggest false signal).
    public static let minGravitySamples: Int = 2

    /// One night's assembled rhythm read: the per-window results and their descriptive
    /// roll-up, plus the bounds they were assembled over. Purely descriptive — no verdict.
    public struct NightRhythm: Equatable, Sendable {
        /// Screened windows, oldest first. Empty windows (no beats) are omitted; windows that
        /// failed a gate are kept as `.unreadable` so the night roll-up counts them honestly.
        public let windows: [RhythmScreener.WindowResult]
        /// Descriptive night roll-up over `windows` (`RhythmScreener.summarizeNight`).
        public let summary: RhythmScreener.NightRhythmSummary
        /// Night bounds the read was assembled over (unix seconds).
        public let from: Int
        public let to: Int

        public init(windows: [RhythmScreener.WindowResult],
                    summary: RhythmScreener.NightRhythmSummary, from: Int, to: Int) {
            self.windows = windows
            self.summary = summary
            self.from = from
            self.to = to
        }
    }

    /// Assemble a night's resting-window rhythm read from raw R-R and gravity over
    /// `[from, to]` (unix seconds). Slices the span into `windowSeconds` windows; each window
    /// with any beats is screened (motion gate from its gravity, mean HR from its R-R). No new
    /// math — every statistic and label comes from `RhythmScreener`.
    public static func assemble(rr: [RRInterval], gravity: [GravitySample],
                                from: Int, to: Int) -> NightRhythm {
        guard to > from else {
            return NightRhythm(windows: [], summary: RhythmScreener.summarizeNight([]),
                               from: from, to: to)
        }

        // One pass per stream, bucketed by window index — O(n) instead of re-scanning the whole
        // night per window (FER-972 · P-02). Same windows as the old per-window filter: [w0, w1)
        // slices with the last one clipped at `to`; within-bucket order preserves input order.
        let count = (to - from + windowSeconds - 1) / windowSeconds
        var rrBuckets = [[RRInterval]](repeating: [], count: count)
        for s in rr where s.ts >= from && s.ts < to {
            rrBuckets[(s.ts - from) / windowSeconds].append(s)
        }
        var gravBuckets = [[GravitySample]](repeating: [], count: count)
        for g in gravity where g.ts >= from && g.ts < to {
            gravBuckets[(g.ts - from) / windowSeconds].append(g)
        }
        var windows: [RhythmScreener.WindowResult] = []
        for i in 0..<count where !rrBuckets[i].isEmpty {
            // An empty window is absence, not an unreadable read — skip it so it doesn't dilute
            // the night's readable/unreadable counts. Only windows with beats are screened.
            let input = RhythmScreener.WindowInput(rr: rrBuckets[i],
                                                   motionStill: isStill(gravBuckets[i]))
            windows.append(RhythmScreener.screenWindow(input))
        }

        return NightRhythm(windows: windows,
                           summary: RhythmScreener.summarizeNight(windows), from: from, to: to)
    }

    /// Motion gate for one window: reuse `SleepStager`'s per-sample stillness primitive. The
    /// window is "still" iff at least `SleepStager.stillFraction` of its consecutive gravity
    /// deltas fall below `SleepStager.gravityStillThresholdG`. Too few samples to judge →
    /// not still. No new threshold is introduced — both constants are the sleep spine's own.
    static func isStill(_ gravity: [GravitySample]) -> Bool {
        guard gravity.count >= minGravitySamples else { return false }
        // gravityDeltas[0] is 0 by construction (no predecessor); judge the real deltas only.
        let deltas = SleepStager.gravityDeltas(gravity).dropFirst()
        guard !deltas.isEmpty else { return false }
        let stillCount = deltas.filter { $0 < SleepStager.gravityStillThresholdG }.count
        return Double(stillCount) / Double(deltas.count) >= SleepStager.stillFraction
    }
}
