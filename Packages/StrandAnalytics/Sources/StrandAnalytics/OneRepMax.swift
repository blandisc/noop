import Foundation

// OneRepMax.swift — estimated one-rep-max from a work set's weight × reps (FER-346).
//
// A TRANSPARENT, cited estimate of the most you could lift once, inferred from a heavier-for-more-reps
// set you actually did. It powers the exercise detail's "1RM estimado" trend. It is NOT a prescription:
// never tell the user to load a barbell to this number — it's a progress signal, not a safety target.
//
// Two textbook formulas, both reps-to-fatigue regressions; default is Epley (the most widely used):
//   • Epley (1985):   1RM = w · (1 + reps/30)
//       Epley, B. "Poundage Chart." Boyd Epley Workout. Lincoln, NE: Body Enterprises, 1985.
//   • Brzycki (1993): 1RM = w · 36 / (37 − reps)
//       Brzycki, M. "Strength testing—predicting a one-rep max from reps-to-fatigue."
//       JOPERD 64(1):88–90, 1993.
//
// Both degrade above ~10–12 reps (and Brzycki's denominator blows up near reps = 37), so the input
// reps are CLAMPED to `maxReps = 12`: a 15-rep set is estimated as if it were 12 — a deliberate,
// consistent under-count, honest about the formulas' range rather than fabricating a high number.
// A true single (reps == 1) is its own 1RM and is returned as the bare weight.
//
// Validity evidence for reps-to-fatigue formulas generally (both Epley and Brzycki are instances of
// this family), cited by the trend delta below for its own noise floor:
//   • LeSuer, D. A. et al. "The accuracy of prediction equations for estimating 1-RM performance in
//       the bench press, squat, and deadlift." J. Strength Cond. Res. 11(4):211–213, 1997.
//       (r > 0.95 at ≤10 reps across formulas of this kind.)
//   • Reynolds, J. M. et al. "Prediction of one repetition maximum strength from multiple repetition
//       maximum testing and anthropometry." J. Strength Cond. Res. 20(3):584–592, 2006.
//       (SEE 2.98–16.16 kg depending on lift and formula.)
//
// Pure & database-free: operates on `(weightKg, reps)` primitives, so it needs no dependency on
// StrandTraining's `SetEntry`. The caller (the detail screen) reads work sets from CenitStore, maps
// them to tuples, and buckets by day for the sparkline.

public enum OneRepMax {

    /// Which reps-to-fatigue regression to use. Epley is the default (most common); Brzycki reads a
    /// touch more conservative at moderate reps.
    public enum Formula: Sendable { case epley, brzycki }

    /// Reps above this clamp the input (both formulas degrade past ~10–12, and Brzycki's `37 − reps`
    /// denominator misbehaves near 37). A 15-rep set is estimated as a 12-rep one — an honest
    /// under-count, not a fabricated high estimate.
    public static let maxReps = 12

    /// Estimated 1RM (kg) for one work set. `nil` when `weightKg ≤ 0` or `reps < 1` (not estimable).
    /// `reps == 1` returns `weightKg` exactly (a real single is its own 1RM); higher reps clamp to
    /// `maxReps` before the formula is applied.
    public static func estimate(weightKg: Double, reps: Int, formula: Formula = .epley) -> Double? {
        guard weightKg > 0, reps >= 1 else { return nil }
        guard reps > 1 else { return weightKg }
        let r = Double(min(reps, maxReps))
        switch formula {
        case .epley:   return weightKg * (1 + r / 30)
        case .brzycki: return weightKg * 36 / (37 - r)
        }
    }

    /// The best (highest) estimated 1RM across a group of work sets — what a session or day contributes
    /// to the trend. `nil` if none of the sets are estimable.
    public static func bestEstimate<S: Sequence>(_ sets: S, formula: Formula = .epley) -> Double?
        where S.Element == (weightKg: Double, reps: Int) {
        sets.compactMap { estimate(weightKg: $0.weightKg, reps: $0.reps, formula: formula) }.max()
    }

    /// One point of the detail's sparkline: the best estimated 1RM observed on a given day.
    public struct DailyBest: Sendable, Equatable {
        /// Day bucket key (the caller's convention, e.g. "2026-06-20"); points sort ascending by it.
        public let day: String
        public let estimatedKg: Double
        public init(day: String, estimatedKg: Double) { self.day = day; self.estimatedKg = estimatedKg }
    }

    /// Collapse dated work sets to the best estimated 1RM per day, ascending by day — mirrors the
    /// best-per-exercise logic of the stored PRs (progress is the heaviest implied single you showed,
    /// not an average). Days with no estimable set are dropped.
    public static func dailySparkline<S: Sequence>(_ sets: S, formula: Formula = .epley) -> [DailyBest]
        where S.Element == (day: String, weightKg: Double, reps: Int) {
        var bestByDay: [String: Double] = [:]
        for s in sets {
            guard let e = estimate(weightKg: s.weightKg, reps: s.reps, formula: formula) else { continue }
            if let cur = bestByDay[s.day] { bestByDay[s.day] = Swift.max(cur, e) }
            else { bestByDay[s.day] = e }
        }
        return bestByDay.map { DailyBest(day: $0.key, estimatedKg: $0.value) }
            .sorted { $0.day < $1.day }
    }

    // MARK: - Trend delta (FER-149 · «≈ +N %» chip, arbitrated by the CSO + CDO)
    //
    // Fortnight-vs-fortnight change over a FIXED 90-day window anchored at HOY calendario local —
    // never the last logged day: a lapsed streak empties the window and the chip goes silent, which
    // is the honest read (a stale number pretending to be current is worse than no number).
    //
    // Window  [today−89, today] inclusive. A = best estimated 1RM in the FIRST fortnight
    // [today−89, today−76]; B = best in the LAST fortnight [today−14, today]. Δ% = (B−A)/A·100,
    // rounded to an INTEGER (never a decimal — the formulas' own uncertainty, see this file's header
    // for Epley 1985 / Brzycki 1993, and the LeSuer 1997 / Reynolds 2006 validity evidence just below
    // it, dwarfs a fractional percentage point).
    //
    // Guards, in order: (1) at least one estimable day in EACH fortnight, (2) at least 4 estimable
    // days across the whole 90-day window (too few points, even if split across the two fortnights,
    // isn't a trend), (3) the noise floor below.

    /// Below this |Δ%|, the chip stays silent — the house's voice on a change too small to trust.
    /// A PRODUCT-CALIBRATION KNOB, not a derived statistic: informed by Epley's own ±1-rep
    /// sensitivity (roughly 2.5–2.9% per rep at typical loads) and Reynolds 2006's reported
    /// standard error of estimate (3–16 kg) — both say a single-digit swing this small is inside the
    /// formula's own noise, not a real trend.
    public static let windowDeltaNoiseFloorPercent = 2.0

    /// The minimum count of estimable days across the WHOLE 90-day window (not per fortnight) before
    /// the trend is trusted at all — a couple of scattered points either side isn't a trend.
    public static let windowDeltaMinimumDays = 4

    /// The signed, rounded percent change in estimated 1RM between the window's first and last
    /// fortnight, or `nil` when the data doesn't clear the guards above. `sets` are the exercise's
    /// raw work sets — any day-bucketing granularity finer than a day collapses to `dailySparkline`'s
    /// best-per-day, same as the sparkline itself. `todayKey` anchors the window and MUST be in the
    /// same "yyyy-MM-dd" convention the caller used to bucket `sets`' own `day` keys — for this
    /// screen that's the device's LOCAL calendar day (`Repository.localDayKey`), never UTC: the
    /// caller passes an already-local day-key rather than a bare `Date` so this function can't
    /// silently re-derive "today" in a different zone than the data (FER-149 QA: a `Date` reconverted
    /// with an internal UTC formatter disagreed with the local-zone day keys of `sets` for most of
    /// the day, for any user west of Greenwich — this is a pure, timezone-testable function precisely
    /// because the zone decision now lives entirely with the caller). Day keys are compared
    /// lexicographically (valid because "yyyy-MM-dd" sorts the same as chronological order).
    public static func windowDeltaPercent<S: Sequence>(
        _ sets: S, todayKey: String, formula: Formula = .epley
    ) -> Int? where S.Element == (day: String, weightKg: Double, reps: Int) {
        let daily = dailySparkline(sets, formula: formula)
        guard let todayMidnight = Self.dayKeyFormatter.date(from: todayKey) else { return nil }
        func shifted(_ days: Int) -> String {
            let d = Self.utcCalendar.date(byAdding: .day, value: days, to: todayMidnight) ?? todayMidnight
            return Self.dayKeyFormatter.string(from: d)
        }
        let windowStart = shifted(-89)
        let firstFortnightEnd = shifted(-76)
        let lastFortnightStart = shifted(-14)

        let inWindow = daily.filter { $0.day >= windowStart && $0.day <= todayKey }
        guard inWindow.count >= windowDeltaMinimumDays else { return nil }

        let firstFortnight = inWindow.filter { $0.day <= firstFortnightEnd }
        let lastFortnight = inWindow.filter { $0.day >= lastFortnightStart }
        guard let a = firstFortnight.map(\.estimatedKg).max(),
              let b = lastFortnight.map(\.estimatedKg).max(),
              a > 0 else { return nil }

        let deltaPercent = (b - a) / a * 100
        guard abs(deltaPercent) >= windowDeltaNoiseFloorPercent else { return nil }
        return Int(deltaPercent.rounded())
    }

    /// UTC day-key formatter ("yyyy-MM-dd"), fixed timezone so date arithmetic on a day-key string is
    /// stable regardless of the caller's locale/timezone (mirrors the pattern in `AnalyticsEngine`).
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }
}
