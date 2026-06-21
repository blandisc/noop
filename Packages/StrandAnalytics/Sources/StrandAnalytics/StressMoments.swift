import Foundation

// StressMoments.swift — pick the day's most-activated moments (and its calmest), each crossed with the
// calendar event it fell within. Pure, DB-free. (FER-433, «Momentos primero»)
//
// The screen's goal is "when was I most activated, and what was I doing?" — that's a few MOMENTS, not the
// whole 0–3 curve. This reduces `StressEngine.intradayStress` to a short, ranked list the view leads with.
//
// Heuristic (a PRESENTATION rule, not a clinical claim — documented, no paper to cite):
//  • A "moment" is a reading at/above `activatedFloor` (1.0 = the low→medium band boundary, matching
//    `StressBand`), so only genuinely activated readings qualify; a calm day yields none.
//  • Activated moments are picked GREEDILY by height, enforcing `minSeparationSeconds` (45 min) between
//    picks so two buckets of the SAME episode (one tense meeting) never both appear — only distinct
//    episodes do. The 45-min gap is wider than a single stress episode is granular (3-min buckets) yet
//    short enough to keep two real, separate spikes.
//  • `calmest` is the single lowest waking reading of the day — an honest contrast (it may still be
//    "medio" on a day that never calmed down).
//  • Each moment is crossed with the timed event whose window contains it; all-day events never cross
//    (reuses `StressDayMap.DayEvent.contains`).
// No-reading buckets (`stress == nil`) are skipped, so gaps never fabricate or hide a moment.

public enum StressMoments {

    /// One notable reading of the day, with the timed event it fell within (if any).
    public struct Moment: Equatable, Sendable {
        /// When the reading occurred (bucket end, wall-clock).
        public let date: Date
        /// The 0–3 value at the moment.
        public let stress: Double
        /// The timed event whose window contains it, or `nil` if it fell in open time.
        public let event: StressDayMap.DayEvent?

        public init(date: Date, stress: Double, event: StressDayMap.DayEvent?) {
            self.date = date
            self.stress = stress
            self.event = event
        }
    }

    /// The day's ranked activated moments (strongest first) and its single calmest reading.
    public struct DayMoments: Equatable, Sendable {
        public let activated: [Moment]
        public let calmest: Moment?

        public init(activated: [Moment], calmest: Moment?) {
            self.activated = activated
            self.calmest = calmest
        }
    }

    /// Readings at/above this 0–3 value qualify as "activated" (1.0 = the low→medium band boundary).
    public static let activatedFloor = 1.0
    /// Minimum gap (s) between two listed activated moments, so one episode isn't listed twice. 45 min.
    public static let minSeparationSeconds = 45 * 60
    /// How many activated moments to surface at most.
    public static let defaultMaxActivated = 3

    /// Reduce a day's intraday curve to its ranked activated moments + calmest reading, each crossed with
    /// the timed event it fell within. Pure; `[]`/`nil` when the curve has no reading at all.
    public static func detect(_ curve: [StressEngine.StressPoint],
                              events: [StressDayMap.DayEvent] = [],
                              maxActivated: Int = defaultMaxActivated,
                              activatedFloor: Double = activatedFloor,
                              minSeparationSeconds: Int = minSeparationSeconds) -> DayMoments {
        // Waking readings only (skip no-reading gaps).
        let readings: [(date: Date, stress: Double)] = curve.compactMap { p in
            p.stress.map { (p.date, $0) }
        }
        guard !readings.isEmpty else { return DayMoments(activated: [], calmest: nil) }

        func event(at date: Date) -> StressDayMap.DayEvent? { events.first { $0.contains(date) } }

        // Calmest = the single lowest reading (earliest on a tie).
        let low = readings.min { a, b in
            a.stress != b.stress ? a.stress < b.stress : a.date < b.date
        }!
        let calmest = Moment(date: low.date, stress: low.stress, event: event(at: low.date))

        // Activated = greedily pick the highest readings ≥ floor, each ≥ minSeparation from every pick
        // already taken, so two buckets of one episode don't both appear. Highest first; earliest on tie.
        let candidates = readings
            .filter { $0.stress >= activatedFloor }
            .sorted { a, b in a.stress != b.stress ? a.stress > b.stress : a.date < b.date }
        let minSep = TimeInterval(minSeparationSeconds)
        var picked: [Moment] = []
        for c in candidates {
            guard picked.allSatisfy({ abs($0.date.timeIntervalSince(c.date)) >= minSep }) else { continue }
            picked.append(Moment(date: c.date, stress: c.stress, event: event(at: c.date)))
            if picked.count >= maxActivated { break }
        }

        return DayMoments(activated: picked, calmest: calmest)
    }
}
