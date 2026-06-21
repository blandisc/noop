import Foundation

// StressEventPatterns.swift — cross-day "stress by calendar-event-type" patterns (FER-388, family B).
//
// Given, per recurring event TYPE (the calendar title), the set of days it occurred on, and each day's
// mean stress, find event types whose days tend to run higher (or lower) in stress than the days without
// them. "Tends to coincide with", NEVER causal — structured output; the view writes the (localized,
// non-causal) sentence.
//
// REUSES the repo's vetted statistics, no new math: `BehaviorInsights.rank` runs a Welch t-test +
// Cohen's d with a ≥5-per-side floor and Benjamini-Hochberg FDR across the family of event types — so a
// title is only reported when it clears multiple-comparison correction. The ≥5 floor means only events
// that RECUR enough (≥5 days in the window) can become a pattern; a one-off never does. The app feeds
// this from a single on-device EventKit read (no calendar data is persisted). Pure + DB-free.

public enum StressEventPatterns {

    /// Minimum |Cohen's d| to surface a (significant) effect — avoids trumpeting a trivial difference.
    public static let minEffect = 0.3

    public struct Pattern: Equatable, Sendable {
        /// The recurring event title (the cluster key).
        public let title: String
        /// true = days with this event run MORE activated than days without; false = calmer.
        public let higher: Bool
        /// |Cohen's d| of the effect — for ranking.
        public let cohensD: Double

        public init(title: String, higher: Bool, cohensD: Double) {
            self.title = title
            self.higher = higher
            self.cohensD = cohensD
        }
    }

    /// Detect event types whose days run higher/lower in daily stress. `eventDaysByType[title]` is the set
    /// of day keys (`yyyy-MM-dd`) on which an event of that title occurred; `dayMeanByDay` is each day's
    /// mean stress (the outcome). Returns up to `maxPatterns`, strongest first; `[]` when nothing clears
    /// the bar (recurrence floor + FDR + effect size).
    public static func detect(eventDaysByType: [String: Set<String>],
                              dayMeanByDay: [String: Double],
                              maxPatterns: Int = 2) -> [Pattern] {
        guard !dayMeanByDay.isEmpty, !eventDaysByType.isEmpty else { return [] }
        let effects = BehaviorInsights.rank(behaviors: eventDaysByType, outcomeByDay: dayMeanByDay, outcome: "stress")
        var out: [Pattern] = []
        for e in effects where e.significant && abs(e.cohensD) >= minEffect {
            out.append(Pattern(title: e.behavior, higher: e.delta > 0, cohensD: abs(e.cohensD)))
        }
        return Array(out.prefix(maxPatterns))
    }
}
