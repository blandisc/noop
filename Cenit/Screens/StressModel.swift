import SwiftUI
import Foundation
import StrandAnalytics
import CenitDesign
import CenitStore

// MARK: - Stress model (presentation layer)
//
// The math — the 0–3 stress proxy, its band thresholds and the per-source baseline derivation —
// lives in `StrandAnalytics.DailyStressModel` / `StrandAnalytics.StressMath` (FER-756). This file
// keeps only PRESENTATION: the band's copy and colors, the explanation copy, the calm-time strings,
// and a thin `StressModel` shim so the live consumers (TodayView, CuerpoView, StressDetailScreen)
// keep their surface unchanged.

// MARK: - Stress band presentation (copy + color)
//
// The band enum (with its 0–3 → band init) lives in StrandAnalytics; every consumer screen already
// imports the package, so `StressBand` resolves directly — only its presentation lives here.

extension StressBand {
    var title: String {
        switch self {
        case .low:    return String(localized: "LOW")
        case .medium: return String(localized: "MEDIUM")
        case .high:   return String(localized: "HIGH")
        }
    }

    /// Sentence-case band word for «Instrumento» surfaces ("Low" / "Moderate" / "High"). Single source
    /// for the band→word mapping; distinct from `title` (ALL-CAPS, for the dark legacy gauge).
    var displayWord: LocalizedStringKey {
        switch self {
        case .low:    return "Low"
        case .medium: return "Moderate"
        case .high:   return "High"
        }
    }

    var tone: StrandTone {
        switch self {
        case .low:    return .positive
        case .medium: return .warning
        case .high:   return .critical
        }
    }

    /// The data color for this band (low→verdict, medium→warning, high→critical).
    /// Single source for the stress band→color mapping (FER-326).
    func dataColor() -> Color {
        switch self {
        case .low:    return LiquidColor.verdePrimario
        case .medium: return LiquidColor.atencion
        case .high:   return LiquidColor.negativo
        }
    }
}

// MARK: - Stress model shim (math in StrandAnalytics + copy here)

struct StressModel: Sendable {
    let score: Double            // 0–3 (today)
    let band: StressBand
    let explanation: String
    let rhrToday: Int?
    let hrvToday: Double?
    let rhrDelta: Double?        // today − baseline mean (bpm)
    let hrvDelta: Double?        // today − baseline mean (ms)
    let fullTrend: [TrendPoint]  // entire daily proxy history, oldest→newest
    let calmTimeValue: String    // e.g. "58%"
    let calmTimeCaption: String  // e.g. "of last 30 days"
    let usingStored: Bool        // true when today's value came from the stored series

    // FER-397 — the hero is anchored to the most recent day that actually carries a reading, so a still-
    // empty "today" row at the midnight boundary doesn't blank the screen. These describe that anchor.
    let anchorDayKey: String     // the day the hero score is from
    let anchorIsToday: Bool      // false → the view MUST date the hero (it's yesterday's, never "today's")
    let heroIsFresh: Bool        // anchor ∈ {today, yesterday}: show the hero. Older → hide it, but the
                                 // trend/patterns below still render from `fullTrend`.

    /// Last up-to-14 trend values, for the hero tile sparkline.
    var sparkValues: [Double] { Array(fullTrend.suffix(14)).map(\.value) }

    /// Build from oldest→newest daily metrics plus any stored "stress" series — delegates the math to
    /// `DailyStressModel` (StrandAnalytics) and adds the display copy on top.
    /// Returns nil only when there is no usable signal at all.
    init?(days: [DailyMetric], stored: [(day: String, value: Double)], todayKey: String,
          appleDays: Set<String> = []) {
        guard let core = DailyStressModel(days: days, stored: stored, todayKey: todayKey,
                                          appleDays: appleDays) else { return nil }
        self.score = core.score
        self.band = core.band
        self.rhrToday = core.rhrToday
        self.hrvToday = core.hrvToday
        self.rhrDelta = core.rhrDelta
        self.hrvDelta = core.hrvDelta
        self.usingStored = core.usingStored
        self.anchorDayKey = core.anchorDayKey
        self.anchorIsToday = core.anchorIsToday
        self.heroIsFresh = core.heroIsFresh
        self.fullTrend = core.fullTrend.map { TrendPoint(date: $0.date, value: $0.value) }

        self.explanation = StressModel.explanation(
            band: core.band,
            rhrDelta: core.rhrDelta,
            hrvDelta: core.hrvDelta,
            usingStored: core.usingStored
        )

        // "Calm time": share of the last 30 charted days that sat in the LOW band.
        if core.calmWindow == 0 {
            self.calmTimeValue = "—"
            self.calmTimeCaption = "needs history"
        } else {
            let pct = Int((Double(core.calmDays) / Double(core.calmWindow) * 100).rounded())
            self.calmTimeValue = "\(pct)%"
            self.calmTimeCaption = "low-stress days · \(core.calmWindow)d"
        }
    }

    static func explanation(band: StressBand, rhrDelta: Double?, hrvDelta: Double?, usingStored: Bool) -> String {
        let rhrUp = (rhrDelta ?? 0) > 1.0
        let rhrDn = (rhrDelta ?? 0) < -1.0
        let hrvUp = (hrvDelta ?? 0) > 1.0
        let hrvDn = (hrvDelta ?? 0) < -1.0

        switch band {
        case .high:
            if rhrUp && hrvDn {
                return String(localized: "Resting HR is elevated and HRV is below your baseline: both classic signs of high activation. Prioritise rest, hydration and an easy day.")
            } else if hrvDn {
                return String(localized: "HRV has dropped well below your baseline, pointing to elevated stress or fatigue. Ease off and give your body time to recover.")
            } else if rhrUp {
                return String(localized: "Resting heart rate is running high versus your norm: your body is under load today. Keep effort light.")
            }
            return String(localized: "Your autonomic markers are skewed toward stress today. Treat it as a recovery-focused day.")
        case .medium:
            if rhrUp || hrvDn {
                let driver = rhrUp ? String(localized: "resting HR is a touch high") : String(localized: "HRV is a little low")
                return String(localized: "Slightly off baseline, \(driver), so you're moderately activated. Nothing alarming; just don't overreach.")
            }
            return String(localized: "You're sitting around your typical autonomic baseline: moderate stress, a normal, balanced day.")
        case .low:
            if rhrDn && hrvUp {
                return String(localized: "Resting heart rate is low and HRV is up: your nervous system looks well-recovered and calm. A great day to push if you want to.")
            } else if hrvUp {
                return String(localized: "HRV is above baseline, a sign of a relaxed, well-recovered nervous system. Stress is low.")
            }
            return String(localized: "Resting heart rate and HRV are sitting at or below baseline: low physiological stress. You're in a calm, recovered state.")
        }
    }
}
