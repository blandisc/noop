import Foundation

// RespirationTrendWatch.swift — nightly respiratory-rate as a personal trend / deviation channel.
// Pure, deterministic, DB-free. The second passive "vital-sign channel" alongside the skin-temp
// deviation the illness surface already watches (FER-682).
//
// WHY RESPIRATION. Nightly (sleeping) respiratory rate is one of the most STABLE physiological
// signals night-to-night, which is what makes a small SUSTAINED drift against a person's own quiet
// baseline informative. Somnofy's contactless validation (Toften et al., "Noncontact Longitudinal
// Respiratory Rate Measurements in Healthy Adults Using Radar-Based Sleep Monitor (Somnofy):
// Validation Study", JMIR Biomed Eng 2022;7(2):e36618, PMC11041471) reports very consistent nightly
// respiratory means (MAE ~0.18 rpm) and sustained deviations that coincided with self-reported
// illness on warning windows of up to weeks. Their cohort (n=37 healthy adults, radar-based) also
// found a PERSONALIZED reference cut deviation variance markedly (~56%) vs a universal cut-off — we
// take that as MOTIVATION for a personal baseline, not as a figure that transfers to a WHOOP strap's
// respiration. So the informative signal is a rise that is small in absolute terms but SUSTAINED
// against the user's own baseline — not any one night, and not a population threshold.
//
// WHAT THIS DOES. Given the ordered nightly respiratory-rate series, it:
//   • builds the personal baseline with the SAME shipped machinery as every other vital
//     (`Baselines.foldHistory` + the standard `resp` `MetricCfg`), over the nights PRECEDING the
//     recent window so the deviation can't contaminate its own reference,
//   • flags a deviation only when the recent nights clear BOTH gates in a consistent direction —
//     an absolute floor (`minAbsoluteDeltaRpm`, so sub-rpm wobble never counts) AND the personal
//     robust-σ gate (`zThreshold`, reusing `IllnessWatch`'s convention) — SUSTAINED for at least
//     `minSustainedNights` consecutive nights ending at the newest,
//   • stays silent unless the baseline is trusted (`Baselines.minNightsTrust`), so a cold-start
//     reference never cries wolf.
//
// It reports the raw numbers (Δ rpm, z, run length, baseline) so a caller can render or feed the
// composite `IllnessSignalEngine` — see `asIllnessSignal`, which hands the oriented z to the
// multi-signal engine as respiration's contribution.
//
// WELLNESS ONLY — APPROXIMATE, NOT A DIAGNOSIS. The copy is always "your breathing drifted from
// your normal"; the engine never names a condition, infection or fever.
public enum RespirationTrendWatch {

    // MARK: - Tuning constants (pinned by test)

    /// Absolute deviation floor (breaths/min). A night must sit at least this far from the personal
    /// baseline mean, on top of the σ gate, to count toward the run. Guards against a statistically
    /// "significant" but physiologically trivial fraction-of-a-breath drift being called out.
    public static let minAbsoluteDeltaRpm: Double = 2.0

    /// Personal robust-σ gate: the night's deviation must reach this many σ (same 2σ ≈ own ~95th
    /// percentile convention as `IllnessWatch` / `VitalBands.sigmaK`). σ is the baseline's own spread.
    public static let zThreshold: Double = 2.0

    /// Consecutive nights (ending at the most recent) the deviation must persist, in a consistent
    /// direction, before it is flagged. One night is noise; a sustained run is the signal (Somnofy).
    public static let minSustainedNights: Int = 2

    /// How many trailing nights are treated as the "recent window" tested for a sustained run. The
    /// baseline is built from everything BEFORE this window so the deviation never anchors its own
    /// reference. Wide enough to catch a multi-night run, short enough that it stays "recent".
    public static let recentWindow: Int = 5

    // MARK: - Output

    /// Direction of a sustained deviation. `elevated` (breathing faster than normal) is the
    /// illness-/strain-ward direction; `depressed` is reported for completeness but is not
    /// illness-ward.
    public enum Direction: String, Equatable, Sendable, Codable {
        case none
        case elevated
        case depressed
    }

    public struct Result: Equatable, Sendable {
        /// True iff a sustained deviation cleared both gates for ≥ `minSustainedNights` nights AND the
        /// baseline was trusted.
        public let flagged: Bool
        public let direction: Direction
        /// Length of the consecutive-night run of gate-clearing nights ending at the newest night
        /// (0 when the newest night doesn't clear the gates).
        public let sustainedNights: Int
        /// Recent-run mean minus baseline, in breaths/min (signed; + = faster than normal).
        public let deltaRpm: Double
        /// Concern-oriented robust z of the recent-run mean vs baseline (+ = elevated/illness-ward).
        public let z: Double
        /// Personal baseline respiratory rate (breaths/min).
        public let baselineRpm: Double
        /// Whether the personal baseline was trusted enough to flag on.
        public let baselineTrusted: Bool
        /// Valid nights backing the baseline.
        public let baselineNights: Int
        /// One-line non-clinical copy.
        public let copy: String

        public init(flagged: Bool, direction: Direction, sustainedNights: Int, deltaRpm: Double,
                    z: Double, baselineRpm: Double, baselineTrusted: Bool, baselineNights: Int,
                    copy: String) {
            self.flagged = flagged; self.direction = direction
            self.sustainedNights = sustainedNights; self.deltaRpm = deltaRpm; self.z = z
            self.baselineRpm = baselineRpm; self.baselineTrusted = baselineTrusted
            self.baselineNights = baselineNights; self.copy = copy
        }
    }

    /// Standing not-a-diagnosis tail, reused verbatim from `IllnessSignalEngine`.
    public static let disclaimerTail = IllnessSignalEngine.disclaimerTail

    // MARK: - Evaluate

    /// Evaluate the nightly respiratory-rate series (oldest → newest) for a sustained personal
    /// deviation. `nil` entries are missing nights (skipped, and they break a run — a gap is not a
    /// continuation).
    public static func evaluate(nightly: [Double?]) -> Result {
        let cfg = Baselines.respCfg

        // Baseline from the nights BEFORE the recent window, so the tested deviation can't anchor its
        // own reference. If there aren't enough nights for a window + baseline, everything is the base.
        let recentCount = Swift.min(recentWindow, nightly.count)
        let baselineSlice = Array(nightly.dropLast(recentCount))
        let base = Baselines.foldHistory(baselineSlice, cfg: cfg)
        let baselineRpm = base.baseline
        let trusted = base.trusted

        // Walk the recent nights newest → oldest, counting the consecutive run that clears BOTH gates
        // in a single consistent direction. A missing night, an in-range night, or a direction flip
        // ends the run.
        let recent = Array(nightly.suffix(recentCount))
        var runDir: Direction = .none
        var run = 0
        var runValues: [Double] = []
        for v in recent.reversed() {
            guard let v = v else { break }
            let dev = Baselines.deviation(v, state: base)
            let absOK = abs(dev.delta) >= minAbsoluteDeltaRpm
            let dir: Direction = dev.z >= zThreshold ? .elevated
                               : dev.z <= -zThreshold ? .depressed
                               : .none
            guard absOK, dir != .none else { break }
            if runDir == .none { runDir = dir }
            guard dir == runDir else { break }
            run += 1
            runValues.append(v)
        }

        let runMean = runValues.isEmpty ? baselineRpm : runValues.reduce(0, +) / Double(runValues.count)
        let deltaRpm = runMean - baselineRpm
        // Concern-oriented z: elevated is positive. Reuse the baseline's robust σ via deviation.
        let z = runValues.isEmpty ? 0.0 : Baselines.deviation(runMean, state: base).z

        let sustained = run >= minSustainedNights
        let flagged = sustained && trusted && runDir != .none

        let copy: String
        if !trusted {
            copy = "Still learning your normal breathing rate - keeping an eye on it."
        } else if flagged {
            let word = runDir == .elevated ? "faster" : "slower"
            let rpm = String(format: "%.1f", abs(deltaRpm))
            copy = "Your breathing has run \(word) than your normal (about \(rpm)/min) for "
                + "\(run) nights. \(disclaimerTail)"
        } else {
            copy = "Your breathing looks like your normal range."
        }

        return Result(flagged: flagged, direction: flagged ? runDir : .none, sustainedNights: run,
                      deltaRpm: deltaRpm, z: z, baselineRpm: baselineRpm, baselineTrusted: trusted,
                      baselineNights: base.nValid, copy: copy)
    }

    // MARK: - Composite integration (second channel)

    /// Hand this channel's reading to the multi-signal `IllnessSignalEngine` as respiration's
    /// contribution. Returns `nil` (absent) when there is no sustained run or the baseline is
    /// untrusted, so a quiet channel neither corroborates nor is counted. `zIllnessward` is the
    /// concern-oriented z (elevated = positive), exactly what the composite engine expects.
    public static func asIllnessSignal(_ result: Result) -> IllnessSignalEngine.SignalReading? {
        guard result.flagged, result.direction == .elevated else { return nil }
        return IllnessSignalEngine.SignalReading(zIllnessward: result.z, present: true)
    }
}
