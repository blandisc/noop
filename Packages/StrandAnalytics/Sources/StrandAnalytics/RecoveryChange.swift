import Foundation
import WhoopStore

/// «Qué cambió vs ayer» — the day-over-day movement of the recovery score, attributed to the 1–2
/// signals whose CONTRIBUTION to the score moved the most between yesterday and today (FER-642).
///
/// This is the companion to `RecoveryImpact`. Where `RecoveryImpact` decomposes TODAY's LEVEL (each
/// signal's share of today's composite z vs your personal base), this engine decomposes the CHANGE:
/// `deltaScore = todayScore − yesterdayScore`, and — for the same present signals — how much each one's
/// oriented contribution `orientedZ × weight` moved from yesterday to today. Ranking by the magnitude of
/// that CHANGE IN CONTRIBUTION answers "what changed since yesterday" honestly and in the SAME currency
/// the score is built from — so the top mover is genuinely the driver of the day-over-day Δscore, not the
/// signal with the largest raw-unit swing (a +40-min sleep night with near-flat efficiency can't outrank a
/// real HRV/RHR contribution shift, and different units — ms vs bpm vs % — never compete on raw magnitude).
/// The change is oriented so "+" always means "moved the way that helps recovery".
///
/// Method: additive day-over-day difference of each signal's own contribution to the recovery composite
/// (`contribution = orientedZ × weight`, from `RecoveryImpact`, itself an additive decomposition of the
/// score). This describes CO-MOVEMENT — a signal that moved alongside the score — never causation. The copy
/// says «cambió» / «subió» / «bajó», never «causó». There is no new scoring math here: the score deltas are
/// the app's own persisted scores, and the per-signal deltas are `RecoveryImpact` differences.
///
/// Baseline purity (FER-519 / FER-629): both impacts are computed band-only (the same whole-row `appleDays`
/// drop `RecoveryImpact` uses), so this never mixes an Apple-only night into a band day-over-day story.
/// `compute` returns nil when yesterday's row/score or either impact is missing — it never invents a change.
///
/// Pure and deterministic — no store, no clock, no state. Not medical advice.
public enum RecoveryChange {

    /// The unit a signal's displayed value is expressed in, so the UI can format «48 → 61» with «ms», «%»,
    /// «bpm», etc. Each is the quantity the SCORE actually reads for that signal (sleep = efficiency %, not
    /// duration), so the «ayer → hoy» read-out is consistent with what moved the score.
    public enum Unit: String, Sendable, Equatable {
        case millis      // HRV (ms)
        case bpm         // resting HR
        case percent     // sleep EFFICIENCY (%), the quantity the sleep term scores
        case breaths     // respiration (breaths/min)
        case celsius     // skin-temp deviation (°C)
    }

    /// One signal whose contribution moved between yesterday and today.
    public struct Change: Equatable, Sendable, Identifiable {
        public let key: String        // "hrv" | "rhr" | "sleep" | "skinTemp" | "respRate"
        public let unit: Unit
        /// Yesterday's displayed reading (in `unit`).
        public let yesterday: Double
        /// Today's displayed reading (in `unit`).
        public let today: Double
        /// The day-over-day move in this signal's ORIENTED contribution (`orientedZ × weight`): + = its
        /// contribution moved the helpful way (lifted recovery vs yesterday), − = the unhelpful way. Its
        /// magnitude is what the ranking uses.
        public let deltaContribution: Double
        /// True when the signal's contribution moved in the direction that HELPS recovery vs yesterday.
        /// Drives the ▲/▼ glyph and the «mejoró/empeoró» word.
        public var improved: Bool { deltaContribution >= 0 }
        public var id: String { key }
        public init(key: String, unit: Unit, yesterday: Double, today: Double, deltaContribution: Double) {
            self.key = key; self.unit = unit
            self.yesterday = yesterday; self.today = today; self.deltaContribution = deltaContribution
        }
    }

    public struct Result: Equatable, Sendable {
        /// Today's recovery score minus yesterday's (the displayed scores), rounded to whole points.
        public let deltaScore: Int
        /// The 1–2 signals whose contribution moved the most, ranked by |deltaContribution| descending.
        /// May be empty when no signal is present on both days (the headline still stands on `deltaScore`).
        public let movers: [Change]
        public init(deltaScore: Int, movers: [Change]) {
            self.deltaScore = deltaScore; self.movers = movers
        }
    }

    /// Sleep efficiency is stored as % or fraction depending on source (mirrors `RecoveryImpact.normEff`);
    /// normalize to a 0…1 fraction so the day-over-day % is consistent across sources.
    static func normEff(_ raw: Double?) -> Double? { raw.map { $0 > 1 ? $0 / 100 : $0 } }

    /// The displayed value for a signal on one day, in its `Unit` (nil when that day lacks the reading).
    static func displayValue(_ key: String, _ row: DailyMetric) -> Double? {
        switch key {
        case "hrv":      return row.avgHrv
        case "rhr":      return row.restingHr.map(Double.init)
        case "sleep":    return normEff(row.efficiency).map { $0 * 100 }   // efficiency as whole %
        case "respRate": return row.respRateBpm
        case "skinTemp": return row.skinTempDevC
        default:         return nil
        }
    }

    static func unit(for key: String) -> Unit {
        switch key {
        case "hrv":      return .millis
        case "rhr":      return .bpm
        case "sleep":    return .percent
        case "respRate": return .breaths
        default:         return .celsius   // skinTemp
        }
    }

    /// Compute the day-over-day recovery change and its top movers.
    ///
    /// - Parameters:
    ///   - today: today's band-only `DailyMetric` (the caller resolves it from the band slice).
    ///   - yesterday: YESTERDAY'S band-only `DailyMetric` — the previous CALENDAR day, or nil if there is
    ///     no band row for it (then the whole block hides — "vs ayer" must mean literally yesterday).
    ///   - todayScore / yesterdayScore: the DISPLAYED recovery scores (0–100). The engine invents no score,
    ///     so `deltaScore` always matches (today shown − yesterday shown).
    ///   - todayImpact / yesterdayImpact: `RecoveryImpact.compute(...)` for each day (band-only), the source
    ///     of the per-signal contributions the ranking uses. nil on either day → nil result (honest).
    /// - Returns: nil when yesterday's row/score or either impact is missing (nothing honest to show).
    public static func compute(today: DailyMetric?,
                               yesterday: DailyMetric?,
                               todayScore: Int?,
                               yesterdayScore: Int?,
                               todayImpact: RecoveryImpact.Result?,
                               yesterdayImpact: RecoveryImpact.Result?) -> Result? {
        guard let today, let yesterday,
              let todayScore, let yesterdayScore,
              let todayImpact, let yesterdayImpact else { return nil }

        let deltaScore = todayScore - yesterdayScore

        // For each signal present in BOTH impacts, the day-over-day move in its oriented contribution. The
        // displayed value is that signal's own score-relevant quantity on each day (both days must carry it).
        let movers: [Change] = todayImpact.signals.compactMap { t -> Change? in
            guard let y = yesterdayImpact.signal(t.key),
                  let vy = displayValue(t.key, yesterday),
                  let vt = displayValue(t.key, today) else { return nil }
            return Change(key: t.key, unit: unit(for: t.key),
                          yesterday: vy, today: vt,
                          deltaContribution: t.contribution - y.contribution)
        }
        .filter { abs($0.deltaContribution) > 1e-9 }             // drop signals that didn't move
        .sorted { abs($0.deltaContribution) > abs($1.deltaContribution) }

        return Result(deltaScore: deltaScore, movers: Array(movers.prefix(2)))
    }
}
