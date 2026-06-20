import Foundation
import WhoopStore

// SleepMath.swift — the single source of truth for sleep "need" and accumulated "debt" (FER-339).
//
// Before this, the Sleep Detail screen and the InsightEngine (what the coach reports) each computed
// sleep debt their OWN way — the detail vs a personal need (mean asleep, 7.5 h floor), the engine vs a
// fixed 8 h target — so the user saw two different debts for the same nights. Both now consume this.
//
// The "need" definition (personal mean floored at 7.5 h) is carried over from the detail screen as the
// shipped behavior; whether need should instead be a fixed/population target is a science decision for
// /cso — and now it lives in exactly ONE place to change.
public enum SleepMath {

    /// Floor for personal need: 7.5 h. Need never drops below this, even for a chronic under-sleeper.
    public static let needFloorMinutes = 450.0
    /// Trailing window (nights) for accumulated debt.
    public static let debtWindow = 7

    /// Personal nightly sleep need (minutes): the mean of nights actually slept, never below the floor.
    public static func needMinutes(_ days: [DailyMetric]) -> Double {
        let totals = days.compactMap { $0.totalSleepMin }.filter { $0 > 0 }
        guard !totals.isEmpty else { return needFloorMinutes }
        return max(needFloorMinutes, totals.reduce(0, +) / Double(totals.count))
    }

    /// Accumulated sleep debt (minutes) over the trailing `debtWindow`: per-night shortfall vs
    /// `needMinutes`, floored at 0 per night (one long night doesn't pay off a short one).
    public static func debtMinutes(_ days: [DailyMetric]) -> Double {
        let need = needMinutes(days)
        return days.suffix(debtWindow)
            .compactMap { $0.totalSleepMin }
            .reduce(0.0) { $0 + max(0.0, need - $1) }
    }
}
