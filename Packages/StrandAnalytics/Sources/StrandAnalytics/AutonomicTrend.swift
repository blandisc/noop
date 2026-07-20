import Foundation

/// AutonomicTrend — a categorical read of where the user's recent nocturnal HRV sits against
/// THEIR OWN settled baseline. Never a 0–100 recovery score, never a medical claim: just a
/// direction (below / in base / above), gated hard on how many dense nights we have, with the
/// honest hedge carried in `confidence`.
///
/// Input is the sequence of DENSE nights only (each already an emitted apple_rmssd_night),
/// oldest → newest. The engine is pure and deterministic: `asOf` and `recentCutoff` are
/// "YYYY-MM-DD" day keys the caller derives, and the engine only ever compares day strings
/// (lexicographic == chronological), so no date math or time zone lives here.
public enum AutonomicTrend {

    public enum Direction: String, Sendable, Equatable { case below, inBase, above }

    public struct Read: Sendable, Equatable {
        /// nil while calibrating (< minNightsTrend usable, or < recentMinDenseNights recent).
        public let direction: Direction?
        public let confidence: ScoreConfidence
        /// Total dense nights with day ≤ asOf.
        public let nightsUsable: Int
        /// Nights still needed to reach the trend gate: max(0, minNightsTrend − nightsUsable).
        public let nightsToTrend: Int
        /// Dense nights inside [recentCutoff, asOf].
        public let recentDenseNights: Int
        /// The 7-day geometric-mean z vs the past-only base — only on .solid with a read.
        public let z7d: Double?
        /// Per-night past-only z, oldest → newest; [] unless .solid.
        public let spark: [Double]
        /// True iff the asOf night is among the dense input nights. The engine only sees dense
        /// nights, so it cannot tell a THIN night (sampled but < 60 clean / < 30 pairs) from a
        /// MISSING one — both read false here. R3 owns the product 3-state (dense / thin / missing),
        /// computed from the persisted clean+pairs series; never infer "thin night" from this Bool.
        public let asOfWasDense: Bool

        public init(direction: Direction?, confidence: ScoreConfidence, nightsUsable: Int,
                    nightsToTrend: Int, recentDenseNights: Int, z7d: Double?,
                    spark: [Double], asOfWasDense: Bool) {
            self.direction = direction
            self.confidence = confidence
            self.nightsUsable = nightsUsable
            self.nightsToTrend = nightsToTrend
            self.recentDenseNights = recentDenseNights
            self.z7d = z7d
            self.spark = spark
            self.asOfWasDense = asOfWasDense
        }
    }

    /// Trend gate: dense nights needed before any direction is shown. == Baselines.minNightsTrust.
    public static let minNightsTrend: Int = 14
    /// Solid gate: dense nights before the direction/band/sparkline appear. 21 (~3 weeks) is a
    /// conservative product knob, consistent with Plews/Buchheit multi-week lnRMSSD monitoring
    /// guidance (Plews et al. 2013, Sports Med 43(9):773–781) — not a precise settling time.
    public static let minNightsSWCSolid: Int = 21
    /// Minimum dense nights inside the recent window for a read (else calibrating).
    public static let recentMinDenseNights: Int = 3
    /// Dead-zone half-width in z units (already standardized): |z| < swcK ⇒ inBase. A product knob
    /// for how big a move counts as a real direction — NOT a Plews-derived SWC.
    public static let swcK: Double = 0.5

    public static func evaluate(nights: [(day: String, rmssdMs: Double)],
                                asOf: String, recentCutoff: String) -> Read {
        // Deterministic ordering; never look past asOf. Plausibility gate (FER-1003 science gate): drop
        // nights whose RMSSD is outside the baseline's own [minVal, maxVal]. The EWMA base already
        // skip-and-holds these; gating `usable` here makes the recent geometric mean, the sparkline, AND
        // the night counts symmetric with the base — closing the asymmetry where an in-DB artifact night
        // (e.g. persisted before `NocturnalHRV.night` grew the same gate) poisoned the recent value while
        // the base correctly ignored it. Defense-in-depth; one source of truth (Baselines.hrvCfg).
        let plausible = Baselines.hrvCfg.minVal...Baselines.hrvCfg.maxVal
        let usable = nights
            .filter { $0.day <= asOf && plausible.contains($0.rmssdMs) }
            .sorted { $0.day != $1.day ? $0.day < $1.day : $0.rmssdMs < $1.rmssdMs }

        let nightsUsable = usable.count
        let recentVals = usable.filter { $0.day >= recentCutoff }.map { $0.rmssdMs }
        let recentDense = recentVals.count
        let confidence: ScoreConfidence =
            nightsUsable >= minNightsSWCSolid ? .solid
          : nightsUsable >= minNightsTrend ? .building
          : .calibrating
        let nightsToTrend = max(0, minNightsTrend - nightsUsable)
        let asOfDense = usable.contains { $0.day == asOf }

        // CALIBRATING: not enough total dense nights, or too few recent.
        if nightsUsable < minNightsTrend || recentDense < recentMinDenseNights {
            return Read(direction: nil, confidence: confidence, nightsUsable: nightsUsable,
                        nightsToTrend: nightsToTrend, recentDenseNights: recentDense,
                        z7d: nil, spark: [], asOfWasDense: asOfDense)
        }

        // BUILDING: enough to trust the count but not yet the SWC geometry → force inBase.
        if nightsUsable < minNightsSWCSolid {
            return Read(direction: .inBase, confidence: .building, nightsUsable: nightsUsable,
                        nightsToTrend: nightsToTrend, recentDenseNights: recentDense,
                        z7d: nil, spark: [], asOfWasDense: asOfDense)
        }

        // SOLID.
        let pastOnlyBase = Baselines.foldHistory(
            usable.filter { $0.day < recentCutoff }.map { Optional($0.rmssdMs) },
            cfg: Baselines.hrvCfg)
        // Geometric mean of the recent window (log domain, matching hrvCfg).
        let meanLn = recentVals.map { Foundation.log($0) }.reduce(0, +) / Double(recentVals.count)
        let value = Foundation.exp(meanLn)
        let z7d = Baselines.deviation(value, state: pastOnlyBase).z
        let dir: Direction = z7d <= -swcK ? .below : z7d >= swcK ? .above : .inBase

        // Past-only expanding z per night, oldest → newest, last 14.
        let last14 = Array(usable.suffix(14))
        let spark: [Double] = last14.map { n in
            let base = Baselines.foldHistory(
                usable.filter { $0.day < n.day }.map { Optional($0.rmssdMs) },
                cfg: Baselines.hrvCfg)
            return Baselines.deviation(n.rmssdMs, state: base).z
        }

        return Read(direction: dir, confidence: .solid, nightsUsable: nightsUsable,
                    nightsToTrend: nightsToTrend, recentDenseNights: recentDense,
                    z7d: z7d, spark: spark, asOfWasDense: asOfDense)
    }
}
