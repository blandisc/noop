import Foundation

// ComparisonEngine.swift — period-over-period comparison of a daily metric.
//
// Pure, deterministic, DB-free. Given two slices of a series (e.g. this month vs
// last month) it summarises each into a `SeriesStat` (mean / median / min / max /
// sample-SD / count / least-squares slope-per-day) and reports the change between
// the two as a signed delta, a percent change, and a coarse direction (-1/0/1).
//
// The slope is the ordinary least-squares slope of value against the 0-based day
// index (0, 1, 2, … in the order supplied), i.e. the average per-step trend across
// the period. With < 2 points or zero index variance the slope is 0.
//
// `monthOverMonth` splits a "yyyy-MM-dd"-keyed series on the calendar month of a
// reference day: the reference day's own month is `current`, the immediately
// preceding calendar month is `previous`. Splitting is done on the "yyyy-MM"
// prefix so it is locale/timezone-free and matches the day strings AnalyticsEngine
// emits.

/// Summary statistics for one slice of a daily series.
public struct SeriesStat: Equatable, Sendable {
    /// Arithmetic mean of the values (0 when empty).
    public let mean: Double
    /// Median of the values (0 when empty).
    public let median: Double
    /// Minimum value (0 when empty).
    public let min: Double
    /// Maximum value (0 when empty).
    public let max: Double
    /// Sample standard deviation, ddof = 1 (0 when fewer than 2 values).
    public let stdev: Double
    /// Number of values in the slice.
    public let n: Int
    /// Least-squares slope of value vs 0-based day index (0 when n < 2).
    public let slopePerDay: Double

    public init(mean: Double, median: Double, min: Double, max: Double,
                stdev: Double, n: Int, slopePerDay: Double) {
        self.mean = mean
        self.median = median
        self.min = min
        self.max = max
        self.stdev = stdev
        self.n = n
        self.slopePerDay = slopePerDay
    }

    /// An empty stat (all zeros, n = 0).
    public static let empty = SeriesStat(mean: 0, median: 0, min: 0, max: 0,
                                         stdev: 0, n: 0, slopePerDay: 0)
}

/// The comparison of a `current` period against a `previous` one.
public struct PeriodComparison: Equatable, Sendable {
    /// Stats for the current period.
    public let current: SeriesStat
    /// Stats for the previous period.
    public let previous: SeriesStat
    /// Signed change in mean: current.mean − previous.mean.
    public let delta: Double
    /// Percent change in mean relative to previous.mean, or nil when previous.mean
    /// is 0 (or the previous period is empty) so a ratio is undefined.
    public let pctChange: Double?
    /// Direction of the change: -1 (down), 0 (flat), +1 (up).
    public let direction: Int

    public init(current: SeriesStat, previous: SeriesStat, delta: Double,
                pctChange: Double?, direction: Int) {
        self.current = current
        self.previous = previous
        self.delta = delta
        self.pctChange = pctChange
        self.direction = direction
    }
}

public enum ComparisonEngine {

    // MARK: - Single-slice statistics

    /// Summarise a slice of values into a `SeriesStat`. The slope is the OLS slope
    /// of value against the 0-based position index (the order in which values are
    /// supplied). Returns `.empty` for an empty input.
    public static func stat(_ values: [Double]) -> SeriesStat {
        let n = values.count
        guard n > 0 else { return .empty }

        let mean = values.reduce(0, +) / Double(n)
        let med = median(values)
        let mn = values.min()!
        let mx = values.max()!

        let sd: Double
        if n >= 2 {
            var ss = 0.0
            for v in values { let d = v - mean; ss += d * d }
            sd = (ss / Double(n - 1)).squareRoot()
        } else {
            sd = 0.0
        }

        let slope = leastSquaresSlope(values)

        return SeriesStat(mean: mean, median: med, min: mn, max: mx,
                          stdev: sd, n: n, slopePerDay: slope)
    }

    // MARK: - Two-period comparison

    /// Compare a current slice to a previous slice. The delta and direction are on
    /// the means; pctChange is nil when the previous mean is 0 / empty.
    public static func compare(current: [Double], previous: [Double]) -> PeriodComparison {
        let cur = stat(current)
        let prev = stat(previous)

        let delta = cur.mean - prev.mean

        let pct: Double?
        if prev.n > 0 && prev.mean != 0 {
            pct = (cur.mean - prev.mean) / abs(prev.mean) * 100.0
        } else {
            pct = nil
        }

        // Direction is meaningful only when both periods carry data.
        let direction: Int
        if cur.n == 0 || prev.n == 0 {
            direction = 0
        } else if delta > 0 {
            direction = 1
        } else if delta < 0 {
            direction = -1
        } else {
            direction = 0
        }

        return PeriodComparison(current: cur, previous: prev, delta: delta,
                                pctChange: pct, direction: direction)
    }

    // MARK: - Month over month

    /// Split a "yyyy-MM-dd"-keyed series into the calendar month of `referenceDay`
    /// (current) vs the immediately preceding calendar month (previous), then
    /// compare. Days outside those two months are ignored. Within each month the
    /// values are ordered by day string (chronological) before computing slope.
    ///
    /// `referenceDay` must start with a "yyyy-MM" prefix; if it cannot be parsed
    /// both periods come back empty.
    public static func monthOverMonth(byDay: [(day: String, value: Double)],
                                      referenceDay: String) -> PeriodComparison {
        guard let (curYear, curMonth) = yearMonth(of: referenceDay) else {
            return compare(current: [], previous: [])
        }
        let (prevYear, prevMonth) = previousMonth(year: curYear, month: curMonth)
        let curPrefix = monthPrefix(year: curYear, month: curMonth)
        let prevPrefix = monthPrefix(year: prevYear, month: prevMonth)

        // Sort by day string so the slope is chronological regardless of input order.
        let sorted = byDay.sorted { $0.day < $1.day }
        var curVals: [Double] = []
        var prevVals: [Double] = []
        for row in sorted {
            if row.day.hasPrefix(curPrefix + "-") {
                curVals.append(row.value)
            } else if row.day.hasPrefix(prevPrefix + "-") {
                prevVals.append(row.value)
            }
        }
        return compare(current: curVals, previous: prevVals)
    }

    // MARK: - Period over period (trailing window)

    /// Compare the trailing `windowDays` ending at `referenceDay` (current) against the equally-long
    /// window immediately before it (previous), then `compare`. Unlike `monthOverMonth` this tracks the
    /// SELECTED window: a 7-day window compares last week vs the week before, a 90-day window last quarter
    /// vs the quarter before. Days are matched by their calendar distance from `referenceDay` (a pure
    /// proleptic-Gregorian day number, timezone-free), so it lines up with the "yyyy-MM-dd" day strings
    /// AnalyticsEngine emits. Within each window the values stay chronological for the slope.
    ///
    /// `referenceDay` must be "yyyy-MM-dd"; if it cannot be parsed both periods come back empty.
    /// `windowDays` must be ≥ 1.
    public static func periodOverPeriod(byDay: [(day: String, value: Double)],
                                        windowDays: Int,
                                        referenceDay: String) -> PeriodComparison {
        guard windowDays >= 1, let refOrd = epochDay(of: referenceDay) else {
            return compare(current: [], previous: [])
        }
        let sorted = byDay.sorted { $0.day < $1.day }
        var curVals: [Double] = []
        var prevVals: [Double] = []
        for row in sorted {
            guard let ord = epochDay(of: row.day) else { continue }
            let delta = refOrd - ord   // 0 = referenceDay, positive = further in the past
            if delta >= 0 && delta < windowDays {
                curVals.append(row.value)
            } else if delta >= windowDays && delta < 2 * windowDays {
                prevVals.append(row.value)
            }
        }
        return compare(current: curVals, previous: prevVals)
    }

    // MARK: - Helpers

    /// Days since 1970-01-01 for a "yyyy-MM-dd" string (Hinnant `days_from_civil`); nil if unparseable.
    public static func epochDay(of day: String) -> Int? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let y0 = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let y = y0 - (m <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                   // [0, 399]
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1  // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy           // [0, 146096]
        return era * 146097 + doe - 719468
    }

    /// Median of an array (0 when empty). Single impl lives in `HRVAnalyzer.median` (FER-322).
    static func median(_ values: [Double]) -> Double { HRVAnalyzer.median(values) }

    /// OLS slope of values against their 0-based index. 0 when n < 2 or the index
    /// has zero variance (impossible for distinct indices, but guarded anyway).
    static func leastSquaresSlope(_ values: [Double]) -> Double {
        let n = values.count
        guard n >= 2 else { return 0 }
        let nD = Double(n)
        // x = 0…n-1. meanX = (n-1)/2.
        let meanX = Double(n - 1) / 2.0
        let meanY = values.reduce(0, +) / nD
        var sxy = 0.0
        var sxx = 0.0
        for i in 0..<n {
            let dx = Double(i) - meanX
            sxy += dx * (values[i] - meanY)
            sxx += dx * dx
        }
        guard sxx > 0 else { return 0 }
        return sxy / sxx
    }

    /// Parse the "yyyy-MM" prefix of a "yyyy-MM-…" day string.
    static func yearMonth(of day: String) -> (year: Int, month: Int)? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              (1...12).contains(m) else { return nil }
        return (y, m)
    }

    /// The calendar month immediately before (year, month).
    static func previousMonth(year: Int, month: Int) -> (year: Int, month: Int) {
        if month == 1 { return (year - 1, 12) }
        return (year, month - 1)
    }

    /// Zero-padded "yyyy-MM" prefix.
    static func monthPrefix(year: Int, month: Int) -> String {
        let mm = month < 10 ? "0\(month)" : "\(month)"
        // Years are assumed 4-digit (matches AnalyticsEngine output) but we don't
        // force-pad beyond the natural string to stay robust.
        return "\(year)-\(mm)"
    }
}
