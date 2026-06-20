import Foundation

// StressTimeOfDayPatterns.swift — cross-day "stress by moment" patterns (FER-378, family A).
//
// Given a per-day `StressDaySummary` history, find recurring patterns: a part of the day that runs more
// activated than the rest, a weekday that runs higher/lower, or a clock-time the daily peak clusters at.
// "Tends to / usually", NEVER causal — this is structured output; the view writes the (localized,
// non-causal) sentence.
//
// REUSES the repo's vetted statistics, no new math: `BehaviorInsights.rank` runs a Welch t-test +
// Cohen's d per group with a ≥5-per-side floor, and Benjamini-Hochberg FDR across each family — so a
// part/weekday is only reported when it clears multiple-comparison correction, not by chance. A day or
// weekday simply won't reach the ≥5 floor until enough history accrues, which is the prudence the issue
// asks for (no fabricated pattern on thin data).
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

        // 2) Part-of-day family — each part's stress vs the rest of the day, across all (day, part) obs.
        var partOutcome: [String: Double] = [:]
        var partGroups: [String: Set<String>] = [:]
        for (day, s) in withMean {
            for (part, mean) in s.partMeans {
                let key = "\(day)#\(part.rawValue)"
                partOutcome[key] = mean
                partGroups[part.rawValue, default: []].insert(key)
            }
        }
        for e in BehaviorInsights.rank(behaviors: partGroups, outcomeByDay: partOutcome, outcome: stressOutcome)
        where e.significant && abs(e.cohensD) >= minEffect {
            if let part = PartOfDay(rawValue: e.behavior) {
                out.append(Pattern(family: .partOfDay(part), higher: e.delta > 0, cohensD: abs(e.cohensD)))
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
