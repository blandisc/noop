import Foundation
import BiometricStreams

// AppleLoadEstimator.swift — daily load classification for Apple Health greenfield.
//
// The ACWR (acute:chronic workload ratio) is dead in Apple-only mode because
// `DailyMetric.strain` is never written: HealthKitBridge / AppleHealthImport leave it
// nil, so ReadinessEngine has no series to fold. This estimator is the pure decision
// that turns one day's already-collected Apple activity into rest(0) / load(TRIMP) /
// missing(NA) so the shell can persist the result into the existing `strain` column.
//
// Rest vs missing is the Athlytics/CRAN ACWR pattern (ropensci): a genuine quiet day
// folds as 0 and decays the acute EWMA; an active day without scoreable workout HR is
// excluded (hold) so we never fabricate a dose or a false rest. The load value itself
// is StrainScorer's Edwards TRIMP (Karvonen %HRR → 0–21 log map) — no new math.
//
// Rest thresholds (`stepsRestMax` / `kcalRestMax`) are calibration defaults, NOT
// validated — `/estadistico` owns the final numbers. This file is Foundation +
// BiometricStreams only: no GRDB, UIKit, AppKit, or CoreBluetooth.
//
// References: Karvonen 1957 (%HRR); Edwards 1993 (5-zone TRIMP); Williams et al. 2017
// (EWMA ACWR, Br J Sports Med 51:209); Impellizzeri et al. 2020 (ACWR descriptive only).

/// Pure per-day load classifier for Apple Health: rest (0), scored workout dose, or NA.
public enum AppleLoadEstimator {

    /// Below this many daily steps AND kcal the day counts as genuine rest (strain 0), not a gap.
    /// Calibration default (NOT validated — /estadistico owns the final number).
    public static let defaultStepsRestMax: Int = 6000
    /// Below this many active kcal the day counts as genuine rest. Calibration default.
    public static let defaultKcalRestMax: Double = 250.0

    public struct RestThresholds: Sendable, Equatable {
        public let stepsRestMax: Int
        public let kcalRestMax: Double
        public init(stepsRestMax: Int = AppleLoadEstimator.defaultStepsRestMax,
                    kcalRestMax: Double = AppleLoadEstimator.defaultKcalRestMax) {
            self.stepsRestMax = stepsRestMax; self.kcalRestMax = kcalRestMax
        }
        public static let standard = RestThresholds()
    }

    /// One day's classification: real rest (0, folds/decays the acute EWMA), a scored workout dose,
    /// or NA (excluded — an active day with no scoreable HR, never fabricated as either 0 or a dose).
    public enum DayLoad: Equatable, Sendable {
        case rest
        case load(Double)
        case missing
    }

    /// What the shell (HealthKitBridge sync / AppleHealthImport) already has per day, to classify it.
    public struct DayActivity: Sendable, Equatable {
        public let workoutHR: [HRSample]   // HR samples from HKWorkouts that day (may be empty)
        public let steps: Int?
        public let activeKcal: Double?
        public let hasWorkout: Bool        // an HKWorkout existed that day, HR or not
        public init(workoutHR: [HRSample], steps: Int?, activeKcal: Double?, hasWorkout: Bool) {
            self.workoutHR = workoutHR; self.steps = steps; self.activeKcal = activeKcal
            self.hasWorkout = hasWorkout
        }
    }

    /// Whether `day` (yyyy-MM-dd) is a COMPLETED day relative to `today` (yyyy-MM-dd) — i.e. never
    /// `today` itself. `DailyMetric.strain` must only be PERSISTED for completed days: writing it for
    /// today freezes the tile at a partial/stale value and blocks the live `estimatedStrain` fallback
    /// (which grows in real time from today's-so-far workout HR) from taking over. Both write paths
    /// (HealthKitBridge live sync, AppleHealthImport XML import) must gate their `strain` write on
    /// this before persisting — never on the classification itself. Day keys are `yyyy-MM-dd`, so a
    /// plain string compare is exact and allocation-free.
    public static func isCompletedDay(_ day: String, today: String) -> Bool { day < today }

    /// Classify one day. Order of resolution:
    /// 1. Enough workout HR to score (`StrainScorer.strain` — it already gates on
    ///    `hasEnoughData`/HRR validity and returns nil otherwise) → `.load(score)`.
    /// 2. A workout is KNOWN to have happened (`hasWorkout == true`) but couldn't be scored (no/too-
    ///    little HR — e.g. the XML-export import path, which never carries per-workout HR) → `.missing`.
    ///    NEVER downgrade a known-workout day to `.rest` just because steps/kcal look low (a strength
    ///    session can be low-step) — that would fabricate a false rest day.
    /// 3. No known workout and both activity signals absent (`steps` AND `activeKcal` are nil) →
    ///    `.missing` (we cannot tell quiet rest from a gap in Apple Health).
    /// 4. No known workout: low activity (`steps < cfg.stepsRestMax` AND `activeKcal < cfg.kcalRestMax`,
    ///    with a missing signal treated as 0) → `.rest` (genuine quiet day — folds as 0, decays the
    ///    acute EWMA).
    /// 5. No known workout, high activity → `.missing` (effort happened, off a Watch/HR-less source;
    ///    scoring it as 0 would lie, scoring it as a made-up dose would lie more).
    public static func classify(_ a: DayActivity, maxHR: Double?, restingHR: Double,
                                sex: String = "male", cfg: RestThresholds = .standard) -> DayLoad {
        if !a.workoutHR.isEmpty,
           let score = StrainScorer.strain(a.workoutHR, maxHR: maxHR, restingHR: restingHR, sex: sex) {
            return .load(score)
        }
        if a.hasWorkout { return .missing }
        // Both activity signals genuinely absent → NA (not rest). One present still uses ?? 0 for the other.
        if a.steps == nil && a.activeKcal == nil { return .missing }
        let steps = a.steps ?? 0
        let kcal = a.activeKcal ?? 0
        return (steps < cfg.stepsRestMax && kcal < cfg.kcalRestMax) ? .rest : .missing
    }
}
