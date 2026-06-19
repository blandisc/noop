import Foundation

// MARK: - Sleep-schedule regularity (FER-218)
//
// How CONSISTENT the timing of sleep is, night to night — a separate axis from how MUCH or how WELL
// you sleep. The validated quantity is the standard deviation of the **mid-sleep point**
// (mid = midpoint between onset and wake) over a rolling window of nights; a lower SD means a steadier
// schedule. We also report the **weekend shift** (social jetlag): the gap between the typical weekend
// mid-sleep and the typical weekday mid-sleep.
//
// Mid-sleep is handled as a point on the 24 h **clock circle** and reduced with CIRCULAR statistics,
// so a 23:30 onset and a 00:30 onset average to ~midnight instead of ~11:30 — the midnight wrap is
// built into the math, not patched with an origin (Roenneberg 2006; Mardia & Jupp 2000). The functions
// are pure + deterministic (no `Date()` read internally); the app layer feeds in the onset/wake
// instants it already holds in `CachedSleepSession` as `NightTiming` (so this stays DB-free).
//
// The SD in minutes is the load-bearing, literature-anchored figure; the 0–100 score is presentation
// only (a bounded, monotonic remap of the SD for the UI), never a clinical claim.
//
// Methods / citations
// -------------------
//   • Mid-sleep point & social jetlag: Roenneberg et al., "Social jetlag and obesity",
//     *Chronobiology International* 23(1–2), 2006.
//   • Mid-sleep timing variability predicts cardiometabolic risk: Huang & Redline,
//     "Sleep Irregularity and the Risk of Type 2 Diabetes", *Diabetes Care* 42, 2019.
//   • Sleep-regularity (timing variability) and mortality: Windred et al., "Sleep regularity is a
//     stronger predictor of mortality risk than sleep duration", *Sleep* 47(1), 2024.
//   • Circular mean / SD of a directional quantity: Mardia & Jupp, *Directional Statistics*, 2000.

public enum SleepRegularity {

    /// One night reduced to the two instants regularity needs: when sleep began and when it ended,
    /// as unix seconds. Built from `CachedSleepSession.startTs/endTs` by the app layer.
    public struct NightTiming: Equatable, Sendable {
        public let onset: Int   // unix seconds — sleep onset (session start)
        public let wake: Int    // unix seconds — wake (session end)
        public init(onset: Int, wake: Int) {
            self.onset = onset
            self.wake = wake
        }
    }

    /// The regularity readout for the most recent window of nights.
    public struct Result: Equatable, Sendable {
        /// SD of the mid-sleep point over the window, in MINUTES (circular). The validated quantity;
        /// lower = steadier.
        public let midSleepSDMinutes: Double
        /// Number of nights that fed the SD (the effective window size).
        public let nights: Int
        /// `true` until the window reaches the stable threshold (≈14 nights): the figure is shown but
        /// flagged "still settling". `false` once it's stable.
        public let preliminary: Bool
        /// Presentation-only 0–100 score (higher = steadier), a bounded monotonic remap of the SD.
        public let score: Int
        /// Weekend shift (social jetlag) in MINUTES: shortest-arc gap between the weekend and weekday
        /// median mid-sleep, or `nil` when either side lacks enough nights to be meaningful.
        public let weekendShiftMinutes: Double?

        public init(midSleepSDMinutes: Double, nights: Int, preliminary: Bool,
                    score: Int, weekendShiftMinutes: Double?) {
            self.midSleepSDMinutes = midSleepSDMinutes
            self.nights = nights
            self.preliminary = preliminary
            self.score = score
            self.weekendShiftMinutes = weekendShiftMinutes
        }
    }

    /// Minimum nights to report anything (a "preliminary" read).
    public static let minNights = 7
    /// Nights at/above which the read is considered stable (drops the `preliminary` flag).
    public static let stableNights = 14
    /// The rolling window: the most recent `windowNights` are used for the SD.
    public static let windowNights = 14
    /// Mid-sleep swing (SD, minutes) at/above which the schedule reads fully irregular — the score's
    /// lower anchor. A product-calibration knob (same altitude as the night thresholds), not a
    /// validated quantity.
    static let worstMidSleepSwingMinutes = 120.0

    /// Compute the regularity read from a list of nights (any order). Returns `nil` when fewer than
    /// `minNights` nights are available — the caller then shows the calibration state, not a fake number.
    ///
    /// - Parameters:
    ///   - nights: the nights to consider; the most recent `windowNights` (by onset) are used.
    ///   - calendar: injected for testability (weekday classification + minute-of-day). Defaults to `.current`.
    public static func compute(_ nights: [NightTiming],
                               calendar: Calendar = .current) -> Result? {
        // Drop naps before anything else: a nap is near anti-phase to the nocturnal mid-sleep and
        // would wreck the SD, so only "main nights" feed schedule regularity (FER-298, SleepMainNight).
        let mainNights = nights.filter { SleepMainNight.qualifies(startTs: $0.onset, endTs: $0.wake) }
        // Most-recent-first, then take the rolling window.
        let ordered = mainNights.sorted { $0.onset > $1.onset }
        let window = Array(ordered.prefix(windowNights))
        guard window.count >= minNights else { return nil }

        // Mid-sleep point per night, computed once and reused (both the SD and the weekend split need it).
        let timed = window.map { (night: $0, mid: midSleepMinuteOfDay($0, calendar)) }
        let sd = circularSDMinutes(timed.map(\.mid))
        let n = window.count

        return Result(
            midSleepSDMinutes: sd,
            nights: n,
            preliminary: n < stableNights,
            score: score(forSDMinutes: sd),
            weekendShiftMinutes: weekendShift(timed, calendar: calendar))
    }

    // MARK: - Mid-sleep point (as time-of-day, midnight-safe via circular handling)

    /// Mid-sleep point of a night as a MINUTE-OF-DAY (0..<1440) — a point on the 24 h clock circle.
    /// Because it's reduced circularly (see `circularSDMinutes` / `circularMedian`), a 23:30 onset and
    /// a 00:30 onset land at the SAME arc and never split by ~24 h. Using clock time-of-day (not an
    /// absolute epoch origin) is the chronobiology convention (Roenneberg 2006).
    static func midSleepMinuteOfDay(_ night: NightTiming, _ calendar: Calendar) -> Double {
        // Absolute mid-sleep instant = halfway between onset and wake; then reduce to minute-of-day.
        let midTs = Double(night.onset + night.wake) / 2.0
        let midDate = Date(timeIntervalSince1970: midTs)
        let c = calendar.dateComponents([.hour, .minute, .second], from: midDate)
        return Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0) + Double(c.second ?? 0) / 60.0
    }

    // MARK: - Weekend shift (social jetlag)

    /// Shortest-arc gap between the weekend and weekday median mid-sleep, in MINUTES (so a 23:50 vs
    /// 00:10 gap reads as 20 min, not 1420). A night is "weekend" when its onset falls on Friday or
    /// Saturday night. `nil` when either side has < 2 nights. Takes the mid-sleep already computed by
    /// `compute`, so the calendar isn't reduced a second time.
    static func weekendShift(_ nights: [(night: NightTiming, mid: Double)], calendar: Calendar) -> Double? {
        var weekend: [Double] = []
        var weekday: [Double] = []
        for (night, mid) in nights {
            let wd = calendar.component(.weekday,
                                        from: Date(timeIntervalSince1970: TimeInterval(night.onset)))
            // Gregorian weekday: 1 = Sun … 6 = Fri, 7 = Sat. Friday & Saturday onsets are "weekend".
            if wd == 6 || wd == 7 { weekend.append(mid) } else { weekday.append(mid) }
        }
        guard weekend.count >= 2, weekday.count >= 2,
              let we = circularMedian(weekend), let wk = circularMedian(weekday) else { return nil }
        return shortestArcMinutes(we, wk)
    }

    // MARK: - SD → score (presentation only)

    /// Map the mid-sleep SD (minutes) to a 0–100 steadiness score. Anchored so a very steady schedule
    /// (SD ≈ 0) scores ~100 and a highly irregular one (SD ≥ `worstMidSleepSwingMinutes`) scores ~0,
    /// linear between. This is UI sugar over the validated SD, NOT a clinical metric.
    static func score(forSDMinutes sd: Double) -> Int {
        // The circular SD is already in [0, 720]; only the high end needs clamping to the score anchor.
        let worst = worstMidSleepSwingMinutes
        let s = 100.0 * (1.0 - min(sd, worst) / worst)
        return Int(s.rounded())
    }

    // MARK: - Circular statistics (minutes on a 1440-min clock)

    private static let dayMinutes = 1440.0

    /// Circular standard deviation of clock minutes, returned in MINUTES. Each value becomes an angle
    /// θ = 2π·m/1440; with mean resultant length R = |mean(e^{iθ})|, the circular SD is √(−2 ln R)
    /// (Mardia & Jupp 2000), scaled back to minutes by 1440/2π. `0` for < 2 values, and clamped so a
    /// degenerate R≈0 maps to the half-day cap instead of +∞.
    static func circularSDMinutes(_ minutes: [Double]) -> Double {
        let n = minutes.count
        guard n >= 2 else { return 0 }
        var sumSin = 0.0, sumCos = 0.0
        for m in minutes {
            let a = 2 * Double.pi * m / dayMinutes
            sumSin += sin(a); sumCos += cos(a)
        }
        let r = (sumSin * sumSin + sumCos * sumCos).squareRoot() / Double(n)
        guard r > 1e-9 else { return dayMinutes / 2 }      // fully dispersed → cap at 12 h
        let sdRadians = (-2 * Foundation.log(min(r, 1))).squareRoot()
        return sdRadians * dayMinutes / (2 * Double.pi)
    }

    /// Circular median of clock minutes: the candidate value minimizing the summed shortest-arc
    /// distance to all points (robust + wrap-aware). `nil` if empty. O(n²) — fine for ≤14 nights.
    static func circularMedian(_ minutes: [Double]) -> Double? {
        guard !minutes.isEmpty else { return nil }
        var best = minutes[0]; var bestCost = Double.infinity
        for cand in minutes {
            let cost = minutes.reduce(0.0) { $0 + shortestArcMinutes(cand, $1) }
            if cost < bestCost { bestCost = cost; best = cand }
        }
        return best
    }

    /// Shortest distance between two clock minutes around the 1440-min circle (0…720).
    static func shortestArcMinutes(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: dayMinutes)
        return min(d, dayMinutes - d)
    }
}
