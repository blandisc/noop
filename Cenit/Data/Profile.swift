import Foundation
import Combine

/// User profile (age/sex/body metrics/HR-max) persisted in UserDefaults.
/// Powers HR zones, calories and recovery baselines.
@MainActor
final class ProfileStore: ObservableObject {
    @Published var age: Int { didSet { d.set(age, forKey: K.age) } }
    @Published var sex: String { didSet { d.set(sex, forKey: K.sex) } }          // "male" | "female" | "nonbinary"
    @Published var weightKg: Double { didSet { d.set(weightKg, forKey: K.weight) } }
    @Published var heightCm: Double { didSet { d.set(heightCm, forKey: K.height) } }
    /// 0 = auto-estimate from age.
    @Published var hrMaxOverride: Int { didSet { d.set(hrMaxOverride, forKey: K.hrMax) } }

    /// Calibration divisor for the WHOOP 5/MG NATIVE step counter (`step_motion_counter@57`, FER-665).
    /// The counter over-counts, so the daily total is divided by this before display. 1.0 = raw
    /// pass-through (default, no change). Clamped 0.5–30.0 (observed 5/MG overcount reaches ~24×, so the
    /// ceiling is high). Distinct from the retired WHOOP 4.0 ESTIMATE fields — this scales a REAL counter.
    @Published var stepTicksPerStep: Double { didSet { d.set(min(max(stepTicksPerStep, 0.5), 30.0), forKey: K.stepScale) } }

    // ── Baseline re-anchoring («Recalibrar recuperación», FER-677) ──────────────────────────────
    // A local day-key ("YYYY-MM-DD") cut point: every nightly baseline fold ignores nights before it,
    // so recovery re-anchors from `baselineEpoch` onward. "" = no cut (default). `previousBaselineEpoch`
    // holds the one value we can restore, so "Deshacer" is exactly one step (not a stack).
    /// Baseline cut day-key; "" = use all history.
    @Published var baselineEpoch: String { didSet { d.set(baselineEpoch, forKey: K.baselineEpoch) } }
    /// The `baselineEpoch` in effect before the last recalibration, for one-level undo; "" = none.
    @Published var previousBaselineEpoch: String { didSet { d.set(previousBaselineEpoch, forKey: K.prevBaselineEpoch) } }

    private let d = UserDefaults.standard
    private enum K {
        static let age = "profile.age", sex = "profile.sex", weight = "profile.weightKg"
        static let height = "profile.heightCm", hrMax = "profile.hrMaxOverride"
        static let stepScale = "profile.stepTicksPerStep"
        static let baselineEpoch = "profile.baselineEpoch"
        static let prevBaselineEpoch = "profile.previousBaselineEpoch"
    }

    init() {
        age = d.object(forKey: K.age) as? Int ?? 30
        sex = d.string(forKey: K.sex) ?? "male"
        weightKg = d.object(forKey: K.weight) as? Double ?? 75
        heightCm = d.object(forKey: K.height) as? Double ?? 178
        hrMaxOverride = d.object(forKey: K.hrMax) as? Int ?? 0
        stepTicksPerStep = min(max(d.object(forKey: K.stepScale) as? Double ?? 1.0, 0.5), 30.0)
        baselineEpoch = d.string(forKey: K.baselineEpoch) ?? ""
        previousBaselineEpoch = d.string(forKey: K.prevBaselineEpoch) ?? ""
    }

    /// Tanaka estimate unless overridden.
    var hrMax: Int { hrMaxOverride > 0 ? hrMaxOverride : Int((208 - 0.7 * Double(age)).rounded()) }

    // MARK: - Baseline re-anchoring (FER-677)

    /// `baselineEpoch` as the analytics layer wants it: nil when there is no cut.
    var baselineEpochOrNil: String? { baselineEpoch.isEmpty ? nil : baselineEpoch }

    /// Re-anchor the baseline from `day` (a "YYYY-MM-DD" local day-key). Stashes the current epoch
    /// so `undoRecalibration()` can restore it (one level).
    func recalibrate(to day: String) {
        previousBaselineEpoch = baselineEpoch
        baselineEpoch = day
    }

    /// Restore the epoch in effect before the last recalibration (one level of undo).
    func undoRecalibration() {
        baselineEpoch = previousBaselineEpoch
        previousBaselineEpoch = ""
    }

    /// True while there is a recalibration to undo (an epoch is set).
    var canUndoRecalibration: Bool { !baselineEpoch.isEmpty }
}
