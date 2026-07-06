import Foundation

// TrainingHabit.swift — WHEN you usually train, derived from your own past sessions. The weekly
// split stores only weekday → routine (no time of day), so the only honest source for a planned
// training WINDOW is your habit: the clock hour your sessions have actually started at.
//
// This is a DESCRIPTION of your routine, not a forecast: median start hour ± 1 SD, as decimal
// clock hours in [0, 24]. nil until `minSessions` sessions exist — a caller then omits the window
// rather than inventing one.
//
// Assumption: sessions cluster within a contiguous daytime block (they do not wrap past midnight).
// A person's training routine does in practice; if it didn't, a naive mean/SD on clock hours would
// be wrong (time of day is circular). We keep the simple estimator and document the assumption
// rather than pull in circular statistics for a case that does not occur.
public enum TrainingHabit {

    /// The habitual training window, as decimal clock hours in [0, 24] (e.g. 17.5 = 17:30).
    public struct Window: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public init(start: Double, end: Double) {
            self.start = start; self.end = end
        }
    }

    /// Need at least this many past sessions before a window means anything.
    public static let minSessions = 3
    /// Floor on the half-width so a tight, always-same-hour routine still draws a visible band (±30 min).
    static let minHalfWidth = 0.5

    /// The habitual window from past session START hours (decimal clock hours, each in [0, 24)).
    /// Median ± max(1 SD, `minHalfWidth`), clamped to [0, 24]. nil below `minSessions`.
    public static func window(startHours: [Double]) -> Window? {
        guard startHours.count >= minSessions else { return nil }
        let center = median(startHours)
        let spread = max(sampleSD(startHours) ?? 0, minHalfWidth)
        return Window(start: max(0, center - spread), end: min(24, center + spread))
    }

    // MARK: - Stats (local, so this file needs no dependency)

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        let n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    static func sampleSD(_ xs: [Double]) -> Double? {
        guard xs.count >= 2 else { return nil }
        let m = xs.reduce(0, +) / Double(xs.count)
        let ss = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (ss / Double(xs.count - 1)).squareRoot()
    }
}
