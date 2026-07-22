import Foundation

// Shared vocabulary of daily metric value types consumed by both CenitStore (persistence)
// and StrandAnalytics (math). Moved out of CenitStore so analytics no longer depends on the
// store package for these shapes (plan 2026-07-20 · L3-C1a).

/// One cached sleep session. Natural key (deviceId, startTs).
/// `stagesJSON` is the verbatim JSON array of stage segments ([{start,end,stage}]) — stored as a
/// string so the cache stays schema-agnostic about the staging shape.
public struct CachedSleepSession: Equatable, Codable, Sendable {
    public let startTs: Int          // unix seconds
    public let endTs: Int            // unix seconds
    public let efficiency: Double?
    public let restingHr: Int?
    public let avgHrv: Double?
    public let stagesJSON: String?
    public init(startTs: Int, endTs: Int, efficiency: Double?, restingHr: Int?,
                avgHrv: Double?, stagesJSON: String?) {
        self.startTs = startTs; self.endTs = endTs
        self.efficiency = efficiency; self.restingHr = restingHr
        self.avgHrv = avgHrv; self.stagesJSON = stagesJSON
    }
}

/// One cached daily-metrics row. Natural key (deviceId, day).
public struct DailyMetric: Equatable, Codable, Sendable {
    public let day: String           // YYYY-MM-DD
    public let totalSleepMin: Double?
    public let efficiency: Double?
    public let deepMin: Double?
    public let remMin: Double?
    public let lightMin: Double?
    public let disturbances: Int?
    public let restingHr: Int?
    public let avgHrv: Double?
    public let recovery: Double?
    public let strain: Double?
    public let exerciseCount: Int?
    // In-sleep signal aggregates (v7 columns). All nullable; computed server-side.
    public let spo2Pct: Double?        // mean SpO2 (%) during sleep
    public let skinTempDevC: Double?   // skin-temperature deviation (°C) from baseline
    public let respRateBpm: Double?    // mean respiration rate (breaths/min) during sleep
    // On-device daily activity totals (v11 columns, APPROXIMATE estimates). Both nullable, so
    // imported/cloud rows that never carry them stay nil and old call sites are unaffected.
    public let steps: Int?             // daily step total from the cumulative @57 counter
    public let activeKcalEst: Double?  // whole-day HR-only calorie estimate (kcal)
    // Per-score confidence tiers (v32 columns, FER-676): raw ScoreConfidence strings
    // ("calibrating"/"building"/"solid") persisted next to the scores they grade. Plain TEXT here —
    // ScoreConfidence lives in StrandAnalytics, above this package; conversion happens at the app layer.
    // Nullable: imported/cloud rows never carry them.
    public let effortConfidence: String?  // strain (effort) tier, from the day's HR coverage
    public let restConfidence: String?    // sleep (rest) tier, from duration + resolved stages (+ H9)
    public init(day: String, totalSleepMin: Double?, efficiency: Double?, deepMin: Double?,
                remMin: Double?, lightMin: Double?, disturbances: Int?, restingHr: Int?,
                avgHrv: Double?, recovery: Double?, strain: Double?, exerciseCount: Int?,
                spo2Pct: Double? = nil, skinTempDevC: Double? = nil, respRateBpm: Double? = nil,
                steps: Int? = nil, activeKcalEst: Double? = nil,
                effortConfidence: String? = nil, restConfidence: String? = nil) {
        self.day = day; self.totalSleepMin = totalSleepMin; self.efficiency = efficiency
        self.deepMin = deepMin; self.remMin = remMin; self.lightMin = lightMin
        self.disturbances = disturbances; self.restingHr = restingHr; self.avgHrv = avgHrv
        self.recovery = recovery; self.strain = strain; self.exerciseCount = exerciseCount
        self.spo2Pct = spo2Pct; self.skinTempDevC = skinTempDevC; self.respRateBpm = respRateBpm
        self.steps = steps; self.activeKcalEst = activeKcalEst
        self.effortConfidence = effortConfidence; self.restConfidence = restConfidence
    }
}

public extension DailyMetric {
    /// A per-column update for `with(...)`: `.keep` carries the current value through untouched, `.set(x)`
    /// replaces it. This exists because most columns are themselves `Optional`, so a plain `nil`-default
    /// parameter can't distinguish "leave as-is" from "clear to nil" — the enum makes the two EXPLICIT at every
    /// call site (`.set(nil)` clears; omitting keeps). A literal `nil` won't even compile, which is the point:
    /// silent nilification is exactly the bug `with(...)` prevents.
    enum FieldUpdate<Value> {
        case keep
        case set(Value)
        fileprivate func resolve(_ current: Value) -> Value {
            switch self { case .keep: return current; case .set(let v): return v }
        }
    }

    /// Return a copy of this row with only the named columns changed; every omitted column is carried through
    /// verbatim. This is the SINGLE place the 17-field initializer is fanned out for a copy-with-change, so a
    /// column added to `DailyMetric` is carried here by default instead of being silently nilled at each of the
    /// hand-rolled reconstructors that used to rebuild the whole struct (`fillingNils`, `withRecovery`,
    /// `SourceLens.hrvMasked`/`crossSourceMasked`). Pass
    /// `.set(x)` to replace a column, including `.set(nil)` to clear a nullable one.
    func with(
        day: FieldUpdate<String> = .keep,
        totalSleepMin: FieldUpdate<Double?> = .keep,
        efficiency: FieldUpdate<Double?> = .keep,
        deepMin: FieldUpdate<Double?> = .keep,
        remMin: FieldUpdate<Double?> = .keep,
        lightMin: FieldUpdate<Double?> = .keep,
        disturbances: FieldUpdate<Int?> = .keep,
        restingHr: FieldUpdate<Int?> = .keep,
        avgHrv: FieldUpdate<Double?> = .keep,
        recovery: FieldUpdate<Double?> = .keep,
        strain: FieldUpdate<Double?> = .keep,
        exerciseCount: FieldUpdate<Int?> = .keep,
        spo2Pct: FieldUpdate<Double?> = .keep,
        skinTempDevC: FieldUpdate<Double?> = .keep,
        respRateBpm: FieldUpdate<Double?> = .keep,
        steps: FieldUpdate<Int?> = .keep,
        activeKcalEst: FieldUpdate<Double?> = .keep,
        effortConfidence: FieldUpdate<String?> = .keep,
        restConfidence: FieldUpdate<String?> = .keep
    ) -> DailyMetric {
        DailyMetric(
            day: day.resolve(self.day),
            totalSleepMin: totalSleepMin.resolve(self.totalSleepMin),
            efficiency: efficiency.resolve(self.efficiency),
            deepMin: deepMin.resolve(self.deepMin),
            remMin: remMin.resolve(self.remMin),
            lightMin: lightMin.resolve(self.lightMin),
            disturbances: disturbances.resolve(self.disturbances),
            restingHr: restingHr.resolve(self.restingHr),
            avgHrv: avgHrv.resolve(self.avgHrv),
            recovery: recovery.resolve(self.recovery),
            strain: strain.resolve(self.strain),
            exerciseCount: exerciseCount.resolve(self.exerciseCount),
            spo2Pct: spo2Pct.resolve(self.spo2Pct),
            skinTempDevC: skinTempDevC.resolve(self.skinTempDevC),
            respRateBpm: respRateBpm.resolve(self.respRateBpm),
            steps: steps.resolve(self.steps),
            activeKcalEst: activeKcalEst.resolve(self.activeKcalEst),
            effortConfidence: effortConfidence.resolve(self.effortConfidence),
            restConfidence: restConfidence.resolve(self.restConfidence))
    }
}

/// Whether a planned meal was followed on a given day. Tri-state, mirroring the journal's
/// yes/no/skip. `sustitui` (an equivalent substitution) counts as adherent — the % rule lives in
/// StrandAnalytics (FER-372); this enum only records the raw status.
public enum DietMealStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case cumpli      // ate it as planned
    case sustitui    // substituted with an equivalent
    case salte       // skipped
}
