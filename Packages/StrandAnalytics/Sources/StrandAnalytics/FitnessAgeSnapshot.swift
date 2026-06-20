import Foundation

// FitnessAgeSnapshot.swift — orchestration glue (FER-141) over the pure FitnessAgeEngine (FER-122).
//
// The engine exposes the math in pieces (compute / assessReadiness / physicalActivityIndexFromStrain).
// THIS file is the orchestration the app layer needs: from a trailing 7-day window of measured signals
// + the profile, it derives the engine's inputs (MEDIAN nocturnal RHR, active days, mean active-day
// strain → PA-index), runs readiness + compute together, and packages everything the UI surfaces — the
// result, the transparency checklist, and the two "levers" (resting HR + activity) the detail screen
// shows.
//
// It is PURE (no DB, no UIKit): the app passes already-extracted arrays out of `repo.days`, so this
// stays covered by `swift test`. The "pull from SQLite" half lives in the app layer (CuerpoView).

/// Everything the Fitness Age UI needs in one coherent snapshot: the computed result (when we have
/// enough), the readiness checklist + confidence, and the aggregates the detail screen displays.
public struct FitnessAgeSnapshot: Equatable, Sendable {
    /// The computed Fitness Age — nil exactly when `readiness.confidence == .notReady` (a required
    /// input is missing), so the UI shows the empty/checklist state instead of a made-up number.
    public let result: FitnessAgeResult?
    /// The transparency checklist + overall confidence (`ready` / `estimate` / `notReady`).
    public let readiness: FitnessAgeReadiness
    /// Median nocturnal resting HR over the window (bpm) — the headline's main lever. nil if no nights.
    public let restingHR: Double?
    /// Active days in the last 7 (a day with a strain reading > 0) — the activity lever.
    public let activeDays: Int
    /// Nights with a nocturnal resting-HR reading in the last 7 — drives the RHR coverage item.
    public let rhrNights: Int

    public init(result: FitnessAgeResult?, readiness: FitnessAgeReadiness,
                restingHR: Double?, activeDays: Int, rhrNights: Int) {
        self.result = result; self.readiness = readiness
        self.restingHR = restingHR; self.activeDays = activeDays; self.rhrNights = rhrNights
    }
}

extension FitnessAgeEngine {

    /// Build the full Fitness Age snapshot from a trailing 7-day window of measured signals + profile.
    ///
    /// - Parameters:
    ///   - rhrLast7: nocturnal resting HR per day (bpm), `nil` where there's no reading. Order is
    ///     irrelevant — only the set of available nights matters.
    ///   - strainLast7: daily strain on this repo's 0–21 scale, `nil` where there's no reading.
    ///   - age: chronological age from the profile (`nil` if unset → not ready).
    ///   - sex: `"male"` / `"female"` / other, from the profile (`nil` if unset → not ready).
    ///   - hasHeightWeight: whether the profile has body metrics. This ONLY powers the VO₂max checklist
    ///     item — it never blocks the headline, because the body term cancels out of the age.
    ///
    /// The RHR fed to the model is the MEDIAN of the available nights (the engine's documented contract:
    /// "compute on rolling 7-day medians", smoothing a single noisy night). Activity becomes a PA-index
    /// via `physicalActivityIndexFromStrain`. Readiness and `compute` run together so the UI gets one
    /// coherent snapshot; `compute` is skipped (result `nil`) whenever readiness is `.notReady`.
    public static func snapshot(rhrLast7: [Int?], strainLast7: [Double?],
                                age: Int?, sex: String?,
                                hasHeightWeight: Bool) -> FitnessAgeSnapshot {
        // Nocturnal RHR: median of the nights we actually have (the engine's smoothing contract).
        let rhrValues = rhrLast7.compactMap { $0 }.map(Double.init)
        let rhrNights = rhrValues.count
        let medianRHR = median(rhrValues)

        // Activity: a day counts as "active" when it logged a strain reading > 0; mean over those days
        // feeds the (deliberately soft) strain→PA-index bridge.
        let activeStrains = strainLast7.compactMap { $0 }.filter { $0 > 0 }
        let activeDays = activeStrains.count
        let meanActiveStrain = activeStrains.isEmpty
            ? 0 : activeStrains.reduce(0, +) / Double(activeStrains.count)
        let paIndex = physicalActivityIndexFromStrain(activeDaysPerWeek: activeDays,
                                                      meanActiveStrain: meanActiveStrain)

        let readiness = assessReadiness(
            hasAge: age != nil, hasSex: sex != nil,
            rhrDays: rhrNights, activityDays: activeDays,
            hasHeightWeight: hasHeightWeight, hasWaist: false)

        let result: FitnessAgeResult?
        if readiness.confidence != .notReady, let age, let rhr = medianRHR {
            // `compute` ORs in the non-binary low-confidence flag itself; we pass the coverage verdict.
            result = compute(age: Double(age), sex: sex ?? "male",
                             restingHR: rhr, paIndex: paIndex,
                             lowerConfidence: readiness.confidence == .estimate)
        } else {
            result = nil
        }

        return FitnessAgeSnapshot(result: result, readiness: readiness,
                                  restingHR: medianRHR, activeDays: activeDays, rhrNights: rhrNights)
    }

    /// Median of a value set (`nil` if empty). Single impl lives in `HRVAnalyzer.median` (FER-322).
    static func median(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : HRVAnalyzer.median(values)
    }
}

// MARK: - Age-delta direction (FER-141)

extension FitnessAgeResult {
    /// Which way the age reads. The ±0.5-yr "even" deadband is a domain decision, so it lives ONCE
    /// here — next to `deltaYears` — rather than as a bare threshold re-tested in each view; the
    /// Cuerpo row (tint + copy) and the detail sheet (tint + copy) both branch on this, so they
    /// can't silently disagree.
    public enum Direction: Sendable { case younger, older, even }

    /// `deltaYears = chronoAge − fitnessAge`; positive ⇒ younger. Within ±0.5 yr reads as "even".
    public var direction: Direction {
        if deltaYears > 0.5 { return .younger }
        if deltaYears < -0.5 { return .older }
        return .even
    }
}
