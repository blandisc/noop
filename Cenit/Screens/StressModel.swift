import SwiftUI
import Foundation
import StrandDesign
import WhoopStore

// MARK: - Stress model (transparent autonomic-load proxy)
//
// The 0–3 stress proxy and its band. Extracted from the retired dark `StressView`
// (FER-414) so the live consumers — TodayView, CuerpoView, StressDetailScreen and
// `StressModelTests` — keep it after the dark Stress Monitor screen was removed.
//
// Source of the daily 0–3 value, in priority order:
//   1. The persisted `stress` metric series ("my-whoop") — if a day has a stored value we trust it.
//   2. Otherwise DERIVE it from how today's resting HR / HRV sit against a personal 30-day baseline:
//        zRHR = (todayRHR − meanRHR) / sdRHR        // positive when RHR is UP
//        zHRV = (meanHRV − todayHRV) / sdHRV        // positive when HRV is DOWN
//        raw  = zRHR + zHRV                          // combined autonomic load
//        stress = 3 / (1 + e^(−raw))                // 0 calm · 1.5 baseline · 3 high
//   Bands:  0–1 LOW · 1–2 MEDIUM · 2–3 HIGH.

// MARK: - Stress band

enum StressBand {
    case low, medium, high

    init(score: Double) {
        switch score {
        case ..<1.0: self = .low
        case ..<2.0: self = .medium
        default:     self = .high
        }
    }

    var title: String {
        switch self {
        case .low:    return String(localized: "LOW")
        case .medium: return String(localized: "MEDIUM")
        case .high:   return String(localized: "HIGH")
        }
    }

    var tone: StrandTone {
        switch self {
        case .low:    return .positive
        case .medium: return .warning
        case .high:   return .critical
        }
    }
}

extension StressBand {
    /// The data color for this band on the active theme (low→verdict, medium→warning, high→critical).
    /// Single source for the stress band→color mapping (FER-326).
    func dataColor(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .low:    return theme.verdict
        case .medium: return theme.warning
        case .high:   return theme.critical
        }
    }
}

// MARK: - Stress model (transparent: stored value OR z-score derivation)

struct StressModel {
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


    /// Build from oldest→newest daily metrics plus any stored "stress" series.
    /// Returns nil only when there is no usable signal at all.
    init?(days: [DailyMetric], stored: [(day: String, value: Double)], todayKey: String) {
        // Anchor the hero to the most recent LOCAL day (≤ today) that actually carries a reading — a
        // stored value or some RHR/HRV — so a still-empty "today" row at the midnight boundary doesn't
        // blank the screen (FER-397). The DISPLAY then caps freshness at yesterday (`heroIsFresh`); an
        // older anchor still feeds the trend, but the view shows the empty hero. Future-dated UTC ghost
        // rows (FER-226) are dropped by the `<= todayKey` filter.
        let usable = days.filter { $0.day <= todayKey }
        guard !usable.isEmpty else { return nil }

        // Stored values keyed by day, clamped to 0–3.
        let storedByDay: [String: Double] = Dictionary(
            stored.map { ($0.day, min(max($0.value, 0), 3)) },
            uniquingKeysWith: { _, b in b }
        )

        // The anchor = the newest usable day with a raw signal (stored value or any RHR/HRV).
        func hasRawSignal(_ d: DailyMetric) -> Bool {
            storedByDay[d.day] != nil || d.restingHr != nil || d.avgHrv != nil
        }
        guard let anchorIdx = usable.lastIndex(where: hasRawSignal) else { return nil }
        let anchor = usable[anchorIdx]

        // Baseline window: up to 30 usable days strictly BEFORE the anchor, so it's measured against its
        // own recent past rather than itself.
        let baseline = Array(usable[..<anchorIdx].suffix(30))

        let rhrBase = baseline.compactMap { $0.restingHr }.map(Double.init)
        let hrvBase = baseline.compactMap { $0.avgHrv }

        let meanRHR = StressMath.mean(rhrBase)
        let sdRHR   = StressMath.std(rhrBase, mean: meanRHR)
        let meanHRV = StressMath.mean(hrvBase)
        let sdHRV   = StressMath.std(hrvBase, mean: meanHRV)

        let rhrT = anchor.restingHr.map(Double.init)
        let hrvT = anchor.avgHrv

        // Resolve the anchor's score: prefer a stored value, else derive. A raw-signal day with no stored
        // value AND no baseline before it to derive against (e.g. the very first day) is not usable.
        let derivedAvailable = (rhrT != nil && meanRHR != nil) || (hrvT != nil && meanHRV != nil)
        let storedAnchor = storedByDay[anchor.day]
        guard storedAnchor != nil || derivedAvailable else { return nil }

        let derivedScore: Double? = derivedAvailable
            ? StressMath.squash(StressMath.rawScore(
                rhrToday: rhrT, meanRHR: meanRHR, sdRHR: sdRHR,
                hrvToday: hrvT, meanHRV: meanHRV, sdHRV: sdHRV))
            : nil

        let s = storedAnchor ?? derivedScore ?? 1.5
        self.usingStored = storedAnchor != nil
        self.score = s
        self.band = StressBand(score: s)
        self.rhrToday = anchor.restingHr
        self.hrvToday = hrvT
        self.rhrDelta = (rhrT != nil && meanRHR != nil) ? (rhrT! - meanRHR!) : nil
        self.hrvDelta = (hrvT != nil && meanHRV != nil) ? (hrvT! - meanHRV!) : nil

        self.explanation = StressMath.explanation(
            band: self.band,
            rhrDelta: self.rhrDelta,
            hrvDelta: self.hrvDelta,
            usingStored: self.usingStored
        )

        // The anchor's date + whether it's fresh enough to surface as the hero (today or, at most,
        // yesterday). An older anchor → `heroIsFresh == false`: the view hides the hero but still draws
        // the trend/patterns below.
        self.anchorDayKey = anchor.day
        self.anchorIsToday = anchor.day == todayKey
        let yesterdayKey = Repository.previousDayKey(todayKey)
        self.heroIsFresh = anchor.day == todayKey || anchor.day == yesterdayKey

        // Full daily proxy history: stored value if present for the day, else the
        // z-score derivation against the SAME baseline so the line is comparable.
        var pts: [TrendPoint] = []
        for d in usable {
            guard let date = Repository.parseDayKey(d.day) else { continue }
            if let v = storedByDay[d.day] {
                pts.append(TrendPoint(date: date, value: v))
                continue
            }
            let dRHR = d.restingHr.map(Double.init)
            let dHRV = d.avgHrv
            guard (dRHR != nil && meanRHR != nil) || (dHRV != nil && meanHRV != nil) else { continue }
            let r = StressMath.rawScore(
                rhrToday: dRHR, meanRHR: meanRHR, sdRHR: sdRHR,
                hrvToday: dHRV, meanHRV: meanHRV, sdHRV: sdHRV
            )
            pts.append(TrendPoint(date: date, value: StressMath.squash(r)))
        }
        self.fullTrend = pts

        // "Calm time": share of the last 30 charted days that sat in the LOW band.
        let recent = Array(pts.suffix(30))
        if recent.isEmpty {
            self.calmTimeValue = "—"
            self.calmTimeCaption = "needs history"
        } else {
            let calm = recent.filter { $0.value < 1.0 }.count
            let pct = Int((Double(calm) / Double(recent.count) * 100).rounded())
            self.calmTimeValue = "\(pct)%"
            self.calmTimeCaption = "low-stress days · \(recent.count)d"
        }
    }
}

// MARK: - Stress math (pure, testable helpers)

enum StressMath {
    static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Population standard deviation; 0 when there's no spread.
    static func std(_ xs: [Double], mean m: Double?) -> Double {
        guard let m, xs.count > 1 else { return 0 }
        let v = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
        return v.squareRoot()
    }

    /// Combined autonomic z-score. RHR-up and HRV-down both push it positive.
    static func rawScore(
        rhrToday: Double?, meanRHR: Double?, sdRHR: Double,
        hrvToday: Double?, meanHRV: Double?, sdHRV: Double
    ) -> Double {
        var sum = 0.0
        if let r = rhrToday, let m = meanRHR, sdRHR > 0.0001 {
            sum += (r - m) / sdRHR            // up = stress
        }
        if let h = hrvToday, let m = meanHRV, sdHRV > 0.0001 {
            sum += (m - h) / sdHRV            // down = stress
        }
        return sum
    }

    /// Logistic squash of the raw z-sum onto 0–3 (baseline 0 → 1.5).
    static func squash(_ raw: Double) -> Double {
        let s = 3.0 / (1.0 + exp(-raw))
        return min(max(s, 0), 3)
    }

    static func explanation(band: StressBand, rhrDelta: Double?, hrvDelta: Double?, usingStored: Bool) -> String {
        let rhrUp = (rhrDelta ?? 0) > 1.0
        let rhrDn = (rhrDelta ?? 0) < -1.0
        let hrvUp = (hrvDelta ?? 0) > 1.0
        let hrvDn = (hrvDelta ?? 0) < -1.0

        switch band {
        case .high:
            if rhrUp && hrvDn {
                return String(localized: "Resting HR is elevated and HRV is below your baseline — both classic signs of high activation. Prioritise rest, hydration and an easy day.")
            } else if hrvDn {
                return String(localized: "HRV has dropped well below your baseline, pointing to elevated stress or fatigue. Ease off and give your body time to recover.")
            } else if rhrUp {
                return String(localized: "Resting heart rate is running high versus your norm — your body is under load today. Keep effort light.")
            }
            return String(localized: "Your autonomic markers are skewed toward stress today. Treat it as a recovery-focused day.")
        case .medium:
            if rhrUp || hrvDn {
                let driver = rhrUp ? String(localized: "resting HR is a touch high") : String(localized: "HRV is a little low")
                return String(localized: "Slightly off baseline — \(driver) — so you're moderately activated. Nothing alarming; just don't overreach.")
            }
            return String(localized: "You're sitting around your typical autonomic baseline — moderate stress, a normal, balanced day.")
        case .low:
            if rhrDn && hrvUp {
                return String(localized: "Resting heart rate is low and HRV is up — your nervous system looks well-recovered and calm. A great day to push if you want to.")
            } else if hrvUp {
                return String(localized: "HRV is above baseline, a sign of a relaxed, well-recovered nervous system. Stress is low.")
            }
            return String(localized: "Resting heart rate and HRV are sitting at or below baseline — low physiological stress. You're in a calm, recovered state.")
        }
    }
}
