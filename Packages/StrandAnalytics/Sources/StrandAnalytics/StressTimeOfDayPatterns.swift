import Foundation

// StressTimeOfDayPatterns.swift — cross-day "stress by moment" patterns (FER-378, family A).
//
// Given a per-day `StressDaySummary` history, find recurring patterns: a part of the day that runs more
// activated than the rest, a weekday that runs higher/lower, or a clock-time the daily peak clusters at.
// "Tends to / usually", NEVER causal — this is structured output; the view writes the (localized,
// non-causal) sentence.
//
// REUSES the repo's vetted statistics. The WEEKDAY family runs `BehaviorInsights.rank` (Welch t-test +
// Cohen's d, ≥5-per-side floor, Benjamini-Hochberg FDR) — each day lands in exactly one weekday group,
// so the two arms are independent. The PART-OF-DAY family instead uses a per-DAY PAIRED contrast (this
// part's mean minus the day's other-parts mean) tested with a one-sample t on the repo's exact Student-t
// tail (`CorrelationEngine.studentTTwoSided`) + BH across the parts: a calendar day is ONE independent
// observation, not one per (day, part). (The earlier design pooled `day#part` pseudo-days and put the
// same day in both arms of a between-groups t-test — within-day correlation made the p anti-conservative;
// BH controls multiplicity, not serial dependence, so it could not repair it.) A part/weekday is only
// reported once it clears FDR and the ≥5-day / effect-size floors — no fabricated pattern on thin data.
//
// Pure + DB-free.

public enum StressTimeOfDayPatterns {

    /// Minimum days with a reading before any detection runs at all.
    public static let minDays = 14
    /// Minimum |Cohen's d| to surface a (significant) effect — avoids trumpeting a trivial difference.
    public static let minEffect = 0.3

    public struct Pattern: Equatable, Sendable {
        public enum Family: Equatable, Sendable {
            case weekday(Int)            // Calendar weekday, 1 = Sunday … 7 = Saturday
            case partOfDay(PartOfDay)
            case peakHour(Int)           // hour-of-day (0–23) the daily peak clusters at
        }
        /// What the pattern is about.
        public let family: Family
        /// true = this slice runs MORE activated than the rest; false = calmer. (Always true for peakHour.)
        public let higher: Bool
        /// |Cohen's d| of the effect (0 for peakHour) — for ranking.
        public let cohensD: Double

        public init(family: Family, higher: Bool, cohensD: Double) {
            self.family = family
            self.higher = higher
            self.cohensD = cohensD
        }
    }

    /// Detect the strongest stress-by-moment patterns from the day summaries. Returns up to
    /// `maxPatterns`, strongest first; `[]` when there isn't enough history. `calendar` maps day keys to
    /// weekdays (UTC by default, deterministic).
    public static func detect(summariesByDay: [String: StressDaySummary],
                              calendar: Calendar = utcCalendar,
                              maxPatterns: Int = 3) -> [Pattern] {
        let withMean = summariesByDay.filter { $0.value.dayMean != nil }
        guard withMean.count >= minDays else { return [] }
        var out: [Pattern] = []

        // 1) Weekday family — each weekday's day-mean stress vs all other days. One FDR family.
        let dayMeanByDay = withMean.mapValues { $0.dayMean! }
        var weekdayGroups: [String: Set<String>] = [:]
        for day in dayMeanByDay.keys {
            guard let wd = weekday(of: day, calendar: calendar) else { continue }
            weekdayGroups["wd-\(wd)", default: []].insert(day)
        }
        for e in BehaviorInsights.rank(behaviors: weekdayGroups, outcomeByDay: dayMeanByDay, outcome: stressOutcome)
        where e.significant && abs(e.cohensD) >= minEffect {
            if let wd = Int(e.behavior.dropFirst(3)) {     // "wd-3" → 3
                out.append(Pattern(family: .weekday(wd), higher: e.delta > 0, cohensD: abs(e.cohensD)))
            }
        }

        // 2) Part-of-day family — per-DAY paired contrast: this part's mean minus the mean of that day's
        //    OTHER parts, so each calendar day is one independent observation. One-sample t per part
        //    (H0: mean contrast = 0) on the exact Student-t tail, then BH across the tested parts.
        var contrastsByPart: [PartOfDay: [Double]] = [:]
        for (_, s) in withMean {
            let parts = s.partMeans
            guard parts.count >= 2 else { continue }   // need ≥2 parts that day to form a within-day contrast
            let total = parts.values.reduce(0, +)
            for (part, mean) in parts {
                let othersMean = (total - mean) / Double(parts.count - 1)
                contrastsByPart[part, default: []].append(mean - othersMean)
            }
        }
        let testedParts = contrastsByPart
            .filter { $0.value.count >= BehaviorInsights.minGroupForSignificance }
            .sorted { $0.key.rawValue < $1.key.rawValue }   // deterministic order for BH
        if !testedParts.isEmpty {
            let stats = testedParts.map { oneSampleT($0.value) }
            let qs = MultipleComparisons.benjaminiHochberg(
                stats.map { CorrelationEngine.studentTTwoSided(t: $0.t, df: $0.df) })
            for (i, entry) in testedParts.enumerated()
            where qs[i] < 0.05 && abs(stats[i].d) >= minEffect {
                out.append(Pattern(family: .partOfDay(entry.key),
                                   higher: stats[i].mean > 0, cohensD: abs(stats[i].d)))
            }
        }

        // 3) Peak-hour clustering — does the daily peak land around the same clock time on most days?
        let peaks = withMean.values.compactMap(\.peakHour)
        if peaks.count >= minDays, let hour = dominantPeakHour(peaks) {
            out.append(Pattern(family: .peakHour(hour), higher: true, cohensD: 0))
        }

        return Array(out.sorted { $0.cohensD > $1.cohensD }.prefix(maxPatterns))
    }

    // MARK: - Internals

    static let stressOutcome = "stress"

    /// One-sample t-test stats for a within-day contrast series (H0: mean = 0). Returns the t-statistic,
    /// df = n−1, one-sample Cohen's d (mean / SD), and the mean (its sign = direction). A degenerate
    /// series (n < 2 or zero variance) returns t = 0 so the Student-t tail reads p = 1 (no claim).
    static func oneSampleT(_ xs: [Double]) -> (t: Double, df: Double, d: Double, mean: Double) {
        let n = xs.count
        guard n >= 1 else { return (0, 0, 0, 0) }
        let mean = xs.reduce(0, +) / Double(n)
        guard n >= 2 else { return (0, 0, 0, mean) }
        var ss = 0.0
        for x in xs { let dd = x - mean; ss += dd * dd }
        let sd = (ss / Double(n - 1)).squareRoot()
        guard sd > 0 else { return (0, Double(n - 1), 0, mean) }
        let t = mean / (sd / Double(n).squareRoot())
        return (t, Double(n - 1), mean / sd, mean)
    }

    /// Fixed UTC calendar so a `yyyy-MM-dd` key maps to the same weekday regardless of device zone.
    public static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func weekday(of day: String, calendar: Calendar) -> Int? {
        guard let date = dayParser.date(from: day) else { return nil }
        return calendar.component(.weekday, from: date)
    }

    /// The dominant peak hour when the daily peaks cluster: the hour whose ±1h window holds a strict
    /// majority of the peaks. Returns nil when too scattered to call a pattern.
    static func dominantPeakHour(_ hours: [Int]) -> Int? {
        guard !hours.isEmpty else { return nil }
        var best = (hour: hours[0], count: 0)
        for h in Set(hours) {
            let count = hours.filter { abs($0 - h) <= 1 }.count
            if count > best.count { best = (hour: h, count: count) }
        }
        return best.count * 2 > hours.count ? best.hour : nil
    }
}
