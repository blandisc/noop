import Foundation
import StrandModels

// MARK: - Daily stress model (transparent autonomic-load proxy)
//
// The 0–3 daily stress proxy and its band — the pure math extracted from the app layer's
// `StressModel` (FER-756). This is the DAILY counterpart to `StressEngine` (intraday);
// presentation (band copy/colors, explanation copy, calm-time strings) stays in the app.
//
// Source of the daily 0–3 value, in priority order:
//   1. The persisted `stress` metric series ("strap") — if a day has a stored value we trust it.
//   2. Otherwise DERIVE it from how today's resting HR / HRV sit against a personal 30-day baseline:
//        zRHR = (todayRHR − meanRHR) / sdRHR        // positive when RHR is UP
//        zHRV = (meanHRV − todayHRV) / sdHRV        // positive when HRV is DOWN
//        raw  = zRHR + zHRV                          // combined autonomic load
//        stress = 3 / (1 + e^(−raw))                // 0 calm · 1.5 baseline · 3 high
//   Bands:  0–1 LOW · 1–2 MEDIUM · 2–3 HIGH.

// MARK: - Stress band

public enum StressBand: Sendable {
    case low, medium, high

    public init(score: Double) {
        switch score {
        case ..<1.0: self = .low
        case ..<2.0: self = .medium
        default:     self = .high
        }
    }
}

// MARK: - Daily stress model (transparent: stored value OR z-score derivation)

public struct DailyStressModel {
    /// One charted day of the 0–3 proxy. `date` is the day key parsed in UTC (DST-stable),
    /// matching the app's day-key contract (FER-325).
    public struct Point: Sendable, Equatable {
        public let date: Date
        public let value: Double
    }

    public let score: Double            // 0–3 (today)
    public let band: StressBand
    public let rhrToday: Int?
    public let hrvToday: Double?
    public let rhrDelta: Double?        // today − baseline mean (bpm)
    public let hrvDelta: Double?        // today − baseline mean (ms)
    public let fullTrend: [Point]       // entire daily proxy history, oldest→newest
    public let usingStored: Bool        // true when today's value came from the stored series

    // "Calm time": of the last up-to-30 charted days, how many sat in the LOW band.
    public let calmDays: Int            // days with value < 1.0 in the window
    public let calmWindow: Int          // window size (0 → needs history)

    // FER-397 — the hero is anchored to the most recent day that actually carries a reading, so a still-
    // empty "today" row at the midnight boundary doesn't blank the screen. These describe that anchor.
    public let anchorDayKey: String     // the day the hero score is from
    public let anchorIsToday: Bool      // false → the view MUST date the hero (it's yesterday's, never "today's")
    public let heroIsFresh: Bool        // anchor ∈ {today, yesterday}: show the hero. Older → hide it, but the
                                        // trend/patterns below still render from `fullTrend`.

    /// Parse a stored `yyyy-MM-dd` day key back to a Date in UTC (en_US_POSIX) — same contract as the
    /// app's `Repository.parseDayKey` (charts parse keys in UTC for DST-stable positions, FER-325).
    private static let dayKeyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The `yyyy-MM-dd` key for the day BEFORE `s`, computed in UTC (one fixed 24 h step — UTC has no
    /// DST). Used to cap the "fall back to the most recent reading" at yesterday (FER-397).
    private static func previousDayKey(_ s: String) -> String? {
        guard let d = dayKeyParser.date(from: s) else { return nil }
        return dayKeyParser.string(from: d.addingTimeInterval(-86_400))
    }

    /// Build from oldest→newest daily metrics plus any stored "stress" series.
    /// Returns nil only when there is no usable signal at all.
    ///
    /// `appleDays` are the day-keys surfaced from Apple Health (`repo.appleHealthDays`). BOTH baselines are
    /// split by source so each reading is z-scored against the baseline of ITS OWN source. HRV: band nights
    /// are RMSSD, Apple nights are SDNN — two constructs with no published conversion (Task Force 1996;
    /// Shaffer & Ginsberg 2017, Front Public Health 5:258). RHR: the band reads it from the sleep nadir
    /// (deep-sleep-weighted night average), Apple from awake sedentary samples that EXCLUDE sleep, so Apple
    /// RHR runs systematically ~10–13 bpm higher (Fenland Study, Gonzales et al. 2023, PLoS One 18(5):
    /// e0285272: sleep 56.9 vs seated 67.6 bpm) — not the same number, no fixed offset (it varies per
    /// person). The z-score is the common currency; raw bpm/ms are never compared across sources (FER-633,
    /// supersedes the old merged-RHR FER-519 policy). `appleDays == []` is the identity — strap-only unchanged.
    public init?(days: [DailyMetric], stored: [(day: String, value: Double)], todayKey: String,
                 appleDays: Set<String> = []) {
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

        // RHR baseline split by source (FER-633): band nights → sleep-nadir RHR, Apple nights → awake
        // sedentary RHR. Each reading is z-scored against the baseline of its own source; the two are never
        // mixed (systematic ~10–13 bpm gap, no fixed offset — see the init doc). `appleDays == []` →
        // rhrAppleBase empty and every day routes to rhrBandBase == the old single base, so a strap-only
        // user's scores are bit-for-bit identical.
        let rhrBandBase  = baseline.filter { !appleDays.contains($0.day) }.compactMap { $0.restingHr }.map(Double.init)
        let rhrAppleBase = baseline.filter {  appleDays.contains($0.day) }.compactMap { $0.restingHr }.map(Double.init)
        // HRV baseline split by source (FER-623): band nights → RMSSD, Apple nights → SDNN. Each reading is
        // z-scored against the baseline of its own source; the two are never mixed (no published conversion).
        // `appleDays == []` → sdnnBase empty and every day routes to rmssdBase == the old single base, so a
        // strap-only user's scores are bit-for-bit identical.
        let rmssdBase = baseline.filter { !appleDays.contains($0.day) }.compactMap { $0.avgHrv }
        let sdnnBase  = baseline.filter {  appleDays.contains($0.day) }.compactMap { $0.avgHrv }

        let meanBandRHR  = StressMath.mean(rhrBandBase)
        let sdBandRHR    = StressMath.std(rhrBandBase, mean: meanBandRHR)
        let meanAppleRHR = StressMath.mean(rhrAppleBase)
        let sdAppleRHR   = StressMath.std(rhrAppleBase, mean: meanAppleRHR)
        let meanRMSSD = StressMath.mean(rmssdBase)
        let sdRMSSD   = StressMath.std(rmssdBase, mean: meanRMSSD)
        let meanSDNN  = StressMath.mean(sdnnBase)
        let sdSDNN    = StressMath.std(sdnnBase, mean: meanSDNN)

        // Pick the RHR baseline for a day by its source. An Apple-only day with no Apple-RHR base yet →
        // (nil, 0): the RHR term drops in `rawScore` and stress derives from HRV alone (honest cold-start).
        func rhrBaseFor(_ day: String) -> (mean: Double?, sd: Double) {
            appleDays.contains(day) ? (meanAppleRHR, sdAppleRHR) : (meanBandRHR, sdBandRHR)
        }
        // Pick the HRV baseline for a day by its source. An Apple-only day with no SDNN base yet → (nil, 0):
        // the HRV term drops in `rawScore` and stress derives from RHR alone (honest cold-start).
        func hrvBaseFor(_ day: String) -> (mean: Double?, sd: Double) {
            appleDays.contains(day) ? (meanSDNN, sdSDNN) : (meanRMSSD, sdRMSSD)
        }

        let rhrT = anchor.restingHr.map(Double.init)
        let hrvT = anchor.avgHrv
        let (meanRHRa, sdRHRa) = rhrBaseFor(anchor.day)
        let (meanHRVa, sdHRVa) = hrvBaseFor(anchor.day)

        // Resolve the anchor's score: prefer a stored value, else derive. A raw-signal day with no stored
        // value AND no baseline before it to derive against (e.g. the very first day) is not usable.
        let derivedAvailable = (rhrT != nil && meanRHRa != nil) || (hrvT != nil && meanHRVa != nil)
        let storedAnchor = storedByDay[anchor.day]
        guard storedAnchor != nil || derivedAvailable else { return nil }

        let derivedScore: Double? = derivedAvailable
            ? StressMath.squash(StressMath.rawScore(
                rhrToday: rhrT, meanRHR: meanRHRa, sdRHR: sdRHRa,
                hrvToday: hrvT, meanHRV: meanHRVa, sdHRV: sdHRVa))
            : nil

        let s = storedAnchor ?? derivedScore ?? 1.5
        self.usingStored = storedAnchor != nil
        self.score = s
        self.band = StressBand(score: s)
        self.rhrToday = anchor.restingHr
        self.hrvToday = hrvT
        self.rhrDelta = (rhrT != nil && meanRHRa != nil) ? (rhrT! - meanRHRa!) : nil
        self.hrvDelta = (hrvT != nil && meanHRVa != nil) ? (hrvT! - meanHRVa!) : nil

        // The anchor's date + whether it's fresh enough to surface as the hero (today or, at most,
        // yesterday). An older anchor → `heroIsFresh == false`: the view hides the hero but still draws
        // the trend/patterns below.
        self.anchorDayKey = anchor.day
        self.anchorIsToday = anchor.day == todayKey
        let yesterdayKey = Self.previousDayKey(todayKey)
        self.heroIsFresh = anchor.day == todayKey || anchor.day == yesterdayKey

        // Full daily proxy history: stored value if present for the day, else the
        // z-score derivation against the SAME baseline so the line is comparable.
        var pts: [Point] = []
        for d in usable {
            // Pure civil→epoch arithmetic (same as ComparisonEngine.epochDay / Repository.parseDayKey);
            // avoids DateFormatter once per row on series up to ~4k days (FER-972 · M-04).
            guard let epoch = ComparisonEngine.epochDay(of: d.day) else { continue }
            let date = Date(timeIntervalSince1970: Double(epoch) * 86_400)
            if let v = storedByDay[d.day] {
                pts.append(Point(date: date, value: v))
                continue
            }
            let dRHR = d.restingHr.map(Double.init)
            let dHRV = d.avgHrv
            let (mRHR, sdR) = rhrBaseFor(d.day)
            let (mHRV, sdH) = hrvBaseFor(d.day)
            guard (dRHR != nil && mRHR != nil) || (dHRV != nil && mHRV != nil) else { continue }
            let r = StressMath.rawScore(
                rhrToday: dRHR, meanRHR: mRHR, sdRHR: sdR,
                hrvToday: dHRV, meanHRV: mHRV, sdHRV: sdH
            )
            pts.append(Point(date: date, value: StressMath.squash(r)))
        }
        self.fullTrend = pts

        // "Calm time": share of the last 30 charted days that sat in the LOW band.
        let recent = Array(pts.suffix(30))
        self.calmWindow = recent.count
        self.calmDays = recent.filter { $0.value < 1.0 }.count
    }
}

// MARK: - Stress math (pure, testable helpers)

public enum StressMath {
    public static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Population standard deviation; 0 when there's no spread.
    public static func std(_ xs: [Double], mean m: Double?) -> Double {
        guard let m, xs.count > 1 else { return 0 }
        let v = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
        return v.squareRoot()
    }

    /// Combined autonomic z-score. RHR-up and HRV-down both push it positive.
    public static func rawScore(
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
    public static func squash(_ raw: Double) -> Double {
        let s = 3.0 / (1.0 + exp(-raw))
        return min(max(s, 0), 3)
    }
}
