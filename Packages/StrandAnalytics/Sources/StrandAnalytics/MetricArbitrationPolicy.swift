import Foundation

// MARK: - MetricArbitrationPolicy (FER-670 — port of upstream v5, single-construct subset)
//
// A DATA table (not if/else branches) keyed by metric × source that yields a trust tier + a plain,
// published reason string, plus the per-metric cross-validation tolerances for `FusionResolver`.
//
// DELIBERATELY EXCLUDED (the FER-670 critical condition): HRV, resting HR, respiration, SpO₂, skin
// temp and the sleep STAGES. The upstream table conflated RMSSD and SDNN under one `hrv` kind with a
// ±8/±20 ms tolerance — but they are different constructs with NO published conversion (Task Force
// 1996; Shaffer & Ginsberg 2017), and RHR/respiration/stages carry measured band↔Apple instrument
// offsets (FER-629). Those metrics are governed by `SourceLens` (baseline purity per instrument);
// `kind(forKey:)` returns nil for them, so the resolver refuses to arbitrate them at all.
//
// What remains is the single-construct set — every source measures the SAME thing:
//   • steps           — a daily step count (phone pedometer vs strap motion count/estimate)
//   • sleep total     — minutes asleep for the night (comparable across sources; the stages are NOT —
//                       same split `SourceLens.crossSourceMasked` draws, where duration survives)
//   • active calories — a daily active-energy estimate (estimates everywhere, same construct)
//
// Trust tiers (lower = more trusted), grounded in what a device MEASURES vs ESTIMATES:
//   0 — direct dedicated count/measurement for this metric
//   1 — derived on-device from raw strap streams by NOOP
//   2 — phone aggregate (Apple Health)
//   3 — estimate / proxy
//
// "Best signal" is always backed by a NAMED, VISIBLE reason — never "accurate"/"correct"/"clinical".
// This is wellness transparency, not a diagnosis.
public enum MetricArbitrationPolicy {

    /// The single-construct metric families this engine arbitrates. Nothing else — see the header.
    public enum MetricKind: String, Equatable, Sendable, CaseIterable {
        case steps
        case sleep      // total sleep minutes ONLY, never the stages
        case calories
    }

    /// Map a resolver series key onto a `MetricKind` — or nil for every key this engine does NOT
    /// arbitrate (hrv, rhr, resp_rate, spo2, skin_temp, the sleep stages, anything unknown). nil is
    /// the exclusion contract: `FusionResolver.resolve` returns nil for those keys, and `SourceLens`
    /// keeps governing them (FER-629).
    public static func kind(forKey key: String) -> MetricKind? {
        switch key {
        case "steps":
            return .steps
        case "sleep_total_min", "asleep_min":
            return .sleep
        case "active_kcal", "energy_kcal":
            return .calories
        default:
            return nil
        }
    }

    /// The canonical resolver key `FusionResolver`/`Repository.fusionByDay` emit for a metric, folding
    /// every alias onto it (`energy_kcal`→`active_kcal`, `asleep_min`→`sleep_total_min`). A key the
    /// engine doesn't arbitrate passes through unchanged. This is the single place aliasing lives, so a
    /// caller looking up the fusion map by a descriptor key never has to know the synonyms (FER-670).
    public static func canonicalKey(forKey key: String) -> String {
        switch kind(forKey: key) {
        case .steps:    return "steps"
        case .sleep:    return "sleep_total_min"
        case .calories: return "active_kcal"
        case nil:       return key
        }
    }

    /// Trust tier for a `(metric, source)` pair — lower is more trusted. Encodes the
    /// measure-vs-estimate intuition as data, consistent with the display precedence the app already
    /// ships: Apple's pedometer count beats the strap's motion figure for steps (FER-663), the band's
    /// sleep timeline beats phone sleep buckets (`Repository.mergeDaily`, imported > computed > Apple),
    /// and active energy is an estimate everywhere (phone aggregate slightly over a strap HR-estimate).
    public static func tier(metric: MetricKind, source: FusionSource) -> Int {
        switch metric {
        case .steps:
            // The device that ACTUALLY COUNTS steps wins; the strap figure is motion-derived.
            switch source {
            case .appleHealth:  return 0   // phone pedometer — counts directly
            case .whoopImport:  return 3   // strap step figure — motion-derived
            case .noopComputed: return 3   // on-device strap count/estimate (steps_est on a 4.0)
            }

        case .sleep:
            // The best sleep TIMELINE wins: imported WHOOP > NOOP-computed stager > phone buckets.
            switch source {
            case .whoopImport:  return 0
            case .noopComputed: return 1
            case .appleHealth:  return 2
            }

        case .calories:
            // Active energy is an estimate everywhere; the phone aggregate edges a pure HR estimate.
            switch source {
            case .appleHealth:  return 2
            case .whoopImport:  return 3
            case .noopComputed: return 3
            }
        }
    }

    /// Stable tiebreak WITHIN a tier (lower wins). Mirrors the merge precedence baked into
    /// `Repository.mergeDaily`: imported WHOOP first, then NOOP-computed, then Apple Health. Used only
    /// when two sources land on the SAME tier, so the resolver stays deterministic.
    public static func sourcePriority(_ source: FusionSource) -> Int {
        switch source {
        case .whoopImport:  return 0
        case .noopComputed: return 1
        case .appleHealth:  return 2
        }
    }

    /// The published "best signal" reason a source wins (or appears) for a metric. Plain English data
    /// (the UI localizes its own copy) — never asserts a value is true or medically valid.
    public static func reason(metric: MetricKind, source: FusionSource) -> String {
        switch (metric, source) {
        case (.steps, .appleHealth):
            return "counts directly"
        case (.steps, .whoopImport), (.steps, .noopComputed):
            return "motion estimate"
        case (.sleep, .whoopImport):
            return "band sleep timeline"
        case (.sleep, .noopComputed):
            return "computed on device"
        case (.sleep, .appleHealth):
            return "phone sleep buckets"
        case (.calories, .appleHealth):
            return "phone aggregate"
        case (.calories, .whoopImport), (.calories, .noopComputed):
            return "heart-rate estimate"
        }
    }

    // MARK: - Cross-validation tolerances
    //
    // Per-metric hand-set bands for the agreement classifier. A delta inside `agree` is agreement;
    // inside `minorDelta` is a plausible measurement spread (show both, no alarm); anything larger is
    // a `conflict` (flag, never merge). Steps/calories use a percentage band, sleep an absolute band;
    // `Tolerance` carries both and the classifier picks per `isPercent`.

    public struct Tolerance: Equatable, Sendable {
        /// Within this delta from the winning value → `agree`.
        public let agree: Double
        /// Within this delta (but beyond `agree`) → `minorDelta`; beyond it → `conflict`.
        public let minorDelta: Double
        /// When true the deltas are FRACTIONS of the winning value (e.g. 0.10 = ±10%), else absolute.
        public let isPercent: Bool

        public init(agree: Double, minorDelta: Double, isPercent: Bool) {
            self.agree = agree
            self.minorDelta = minorDelta
            self.isPercent = isPercent
        }
    }

    /// The tolerance band for a metric — the same constants the upstream table ships for these three
    /// kinds: steps ±10%/±30%, sleep total ±20/±60 min, active energy ±15%/±40%.
    public static func tolerance(metric: MetricKind) -> Tolerance {
        switch metric {
        case .steps:
            return Tolerance(agree: 0.10, minorDelta: 0.30, isPercent: true)
        case .sleep:
            return Tolerance(agree: 20, minorDelta: 60, isPercent: false)    // min
        case .calories:
            return Tolerance(agree: 0.15, minorDelta: 0.40, isPercent: true)
        }
    }
}
