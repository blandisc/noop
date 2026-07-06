import Foundation

// MuscleFatigueMap.swift — per-muscle training load / freshness, crossed with the strap's
// systemic recovery (FER-350). The jewel of the loop: which muscles are loaded vs fresh, and
// what's safe to train today — something a tracker without a strap (Fitbod) and a strap without
// set logging (WHOOP) each can't do alone.
//
// TRANSPARENT & cited, no black box:
//
//   • Load per muscle = Σ over your work sets that hit it of `involvement · decay(daysAgo)`,
//     where involvement is the muscle-involvement convention (primary 1.0 / secondary 0.5,
//     see `Exercise.muscleInvolvement`) and the decay is exponential by days since the set:
//        decay(d) = 2^(−d / halfLife),  halfLife = 2 days.
//     A set today counts ~1.0; two days ago ~0.5; four days ago ~0.25. The 2-day half-life is a
//     calibration knob anchored to muscle recovery, not a constant read off one experiment: muscle
//     protein synthesis (MPS) is elevated ~24 h and back near baseline by ~36 h after a bout
//     (MacDougall 1995), and its exact duration shortens with training state and "remains unknown"
//     (Damas 2015); functional recovery (strength, soreness) typically runs longer, ~48–96 h. A
//     2-day half-life sits between those — a defensible middle for perceived load, not a claim that
//     any single process has that time constant:
//        MacDougall JD et al. "The time course for elevated muscle protein synthesis following
//        heavy resistance exercise." Can J Appl Physiol 20(4):480–6, 1995.
//        Damas F, Phillips S, Vechin FC, Ugrinowitsch C. "A review of resistance training-induced
//        changes in skeletal muscle protein synthesis…" Sports Med 45(6):801–7, 2015.
//
//   • There is NO recency window anymore (FER-719): the decay itself carries time — a set 10 days
//     old weighs 2^(−5) ≈ 0.03 and vanishes on its own. The old 3/7/14-day lens double-encoded
//     recency (filter + decay) and was retired with the Entrenar v3 handoff; the caller bounds the
//     event span it fetches (the screens read ~84 days).
//
//   • The manual «mark all recovered» reset (FER-525) is PRESERVED and is orthogonal to the decay:
//     it is a data filter applied by the caller (work sets before the reset timestamp never become
//     events), so the map reads all-fresh without touching this math or deleting history.
//
//   • «Fresh vs loaded» is RELATIVE to the user's own current map — `relative = load / max(load)`
//     across their muscles — so it reads "which of YOUR muscles are most loaded right now" with
//     no fragile absolute constant.
//
//   • Weekly volume (`weeklySets`) is the RAW count of involvement-weighted work sets in the last
//     7 days (no decay), shown in the detail and judged against a ~10–20 sets/week-per-muscle band.
//     The ~10-set LOWER anchor (a near-maximal hypertrophy threshold on a graded dose-response) is
//     from Schoenfeld 2017; that meta-analysis explicitly notes the evidence is INSUFFICIENT to set
//     an upper limit (data are sparse beyond ~10–12 weekly sets), so the 20-set ceiling here is a
//     practical product convention, NOT a Schoenfeld finding — high volume is flagged for awareness,
//     not called unsafe:
//        Schoenfeld BJ, Ogborn D, Krieger JW. "Dose-response relationship between weekly resistance
//        training volume and increases in muscle mass: a systematic review and meta-analysis."
//        J Sports Sci 35(11):1073–82, 2017.
//
//   • The recommendation crosses local freshness with the strap's systemic recovery (0–100,
//     same red/yellow/green bands as `RecoveryScorer`): a low recovery day gates everything to
//     rest regardless of how fresh a muscle is.
//
// Pure & database-free, like `OneRepMax`: it operates on flat `MuscleSetEvent` primitives, so it
// needs no dependency on StrandTraining or GRDB. The caller (the Cuerpo screen) reads work sets
// from WhoopStore, expands each one across `Exercise.muscleInvolvement`, computes `daysAgo` in the
// device's local calendar, and reads systemic recovery from the dashboard.

public enum MuscleFatigueMap {

    /// Half-life of the per-set load decay, in days. A set's contribution halves every 2 days —
    /// tracking the ~24–72 h MPS time course (MacDougall 1995; Damas 2015).
    public static let halfLifeDays: Double = 2.0

    /// Hypertrophy weekly-volume guideline (involvement-weighted sets per muscle), Schoenfeld 2017.
    public static let weeklyBandLow: Double = 10
    public static let weeklyBandHigh: Double = 20

    /// The top of the 0…N sets/week rail the band (10–20) is drawn on, shared by the muscle detail and
    /// the «Volume per muscle» screen so the two rails can't diverge.
    public static let weeklyVolumeRailTop: Double = 30

    /// Format an involvement-weighted set count for display: whole when integral, one decimal otherwise
    /// (secondary muscles contribute 0.5). Shared so the map, the detail and the volume screen agree.
    public static func formattedSets(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(v == v.rounded() ? 0 : 1)))
    }

    /// Relative-load thresholds for the fresh / moderate / loaded buckets (fraction of the user's
    /// most-loaded muscle).
    public static let freshBelow: Double = 0.33
    public static let loadedAbove: Double = 0.66

    /// Recovery band cutoffs (0–100), mirroring `RecoveryScorer` (red < 34 ≤ yellow < 67 ≤ green).
    public static let recoveryRedMax: Double = 34
    public static let recoveryYellowMax: Double = 67

    // MARK: - Inputs

    /// One muscle touched by one work set: the involvement weight (primary 1.0 / secondary 0.5)
    /// and how many whole days ago the set was performed (0 = today), in the caller's local calendar.
    public struct MuscleSetEvent: Sendable, Equatable {
        public let muscle: String
        public let involvement: Double
        public let daysAgo: Int
        public init(muscle: String, involvement: Double, daysAgo: Int) {
            self.muscle = muscle; self.involvement = involvement; self.daysAgo = daysAgo
        }
    }

    // MARK: - Outputs

    /// How loaded a muscle is relative to the user's own map.
    public enum LoadState: Sendable, Equatable { case fresh, moderate, loaded }

    /// Weekly volume vs the Schoenfeld 10–20 sets/week band.
    public enum VolumeBand: Sendable, Equatable { case below, within, above }

    /// Per-muscle readiness once systemic recovery is crossed in.
    public enum Readiness: Sendable, Equatable { case ready, caution, rest }

    /// One muscle's row in the map.
    public struct MuscleLoad: Sendable, Equatable {
        public let muscle: String
        /// Decayed, involvement-weighted load (the map's color magnitude).
        public let load: Double
        /// `load` as a fraction of the most-loaded muscle (0…1).
        public let relative: Double
        /// Whole days since the most recent set that hit this muscle.
        public let daysSinceLast: Int
        public let state: LoadState
        /// Raw involvement-weighted work sets in the last 7 days (no decay).
        public let weeklySets: Double
        public let band: VolumeBand
        public init(muscle: String, load: Double, relative: Double, daysSinceLast: Int,
                    state: LoadState, weeklySets: Double, band: VolumeBand) {
            self.muscle = muscle; self.load = load; self.relative = relative
            self.daysSinceLast = daysSinceLast; self.state = state
            self.weeklySets = weeklySets; self.band = band
        }
    }

    /// The crossed recommendation for the whole map.
    public struct Recommendation: Sendable, Equatable {
        /// Fresh muscles cleared to train today (most-fresh first). Empty when gated.
        public let readyMuscles: [String]
        /// True when systemic recovery is in the red and overrides local freshness.
        public let gatedBySystemic: Bool
        public init(readyMuscles: [String], gatedBySystemic: Bool) {
            self.readyMuscles = readyMuscles; self.gatedBySystemic = gatedBySystemic
        }
    }

    // MARK: - Load

    /// The exponential decay weight for a set performed `daysAgo` whole days ago.
    public static func decay(daysAgo: Int) -> Double {
        pow(2.0, -Double(max(0, daysAgo)) / halfLifeDays)
    }

    /// Per-muscle load map, sorted by load descending (most-loaded first). Every non-negative event
    /// enters; the decay alone decides how much of it is still felt (no recency window, FER-719).
    /// Returns an empty array when there are no events — the honest empty state.
    public static func loads(events: [MuscleSetEvent]) -> [MuscleLoad] {
        let valid = events.filter { $0.daysAgo >= 0 }
        guard !valid.isEmpty else { return [] }

        // Weekly volume stays a fixed 7-day raw count — the Schoenfeld band judges sets/week, not
        // decayed load.
        var weekly: [String: Double] = [:]
        for e in valid where e.daysAgo <= 7 {
            weekly[e.muscle, default: 0] += e.involvement
        }

        var decayed: [String: Double] = [:]
        var lastSeen: [String: Int] = [:]
        for e in valid {
            decayed[e.muscle, default: 0] += e.involvement * decay(daysAgo: e.daysAgo)
            lastSeen[e.muscle] = min(lastSeen[e.muscle] ?? Int.max, e.daysAgo)
        }

        let maxLoad = decayed.values.max() ?? 0
        return decayed.map { muscle, load in
            let relative = maxLoad > 0 ? load / maxLoad : 0
            let weeklySets = weekly[muscle] ?? 0
            return MuscleLoad(
                muscle: muscle,
                load: load,
                relative: relative,
                daysSinceLast: lastSeen[muscle] ?? 0,
                state: state(relative: relative),
                weeklySets: weeklySets,
                band: band(weeklySets: weeklySets)
            )
        }
        .sorted { ($0.load, $1.muscle) > ($1.load, $0.muscle) }
    }

    /// Fresh / moderate / loaded from a relative load (0…1).
    public static func state(relative: Double) -> LoadState {
        if relative < freshBelow { return .fresh }
        if relative > loadedAbove { return .loaded }
        return .moderate
    }

    /// Weekly volume vs the Schoenfeld band.
    public static func band(weeklySets: Double) -> VolumeBand {
        if weeklySets < weeklyBandLow { return .below }
        if weeklySets > weeklyBandHigh { return .above }
        return .within
    }

    // MARK: - Weekly volume per muscle (the «Volumen por músculo» screen, FER-719)

    /// One muscle's average weekly volume over a chosen span, judged against the Schoenfeld band.
    public struct MuscleWeeklyVolume: Sendable, Equatable {
        public let muscle: String
        /// Involvement-weighted work sets per week, averaged over the whole span (total / weeks).
        public let setsPerWeek: Double
        public let band: VolumeBand
        public init(muscle: String, setsPerWeek: Double, band: VolumeBand) {
            self.muscle = muscle; self.setsPerWeek = setsPerWeek; self.band = band
        }
    }

    /// Average effective (involvement-weighted) sets per week per muscle over the trailing `days`,
    /// sorted by volume descending. The average divides by the FULL span (`days / 7` weeks), so an
    /// untrained stretch honestly dilutes the number — «what you actually averaged», not «your best
    /// week». Judged against the same 10–20 sets/week band (Schoenfeld 2017; the 20 ceiling is a
    /// product convention — see the header). `days` is clamped to ≥ 7 so a week is the smallest unit.
    public static func weeklyVolumes(events: [MuscleSetEvent], days: Int) -> [MuscleWeeklyVolume] {
        let span = max(7, days)
        let weeks = Double(span) / 7.0
        var totals: [String: Double] = [:]
        for e in events where e.daysAgo >= 0 && e.daysAgo < span {
            totals[e.muscle, default: 0] += e.involvement
        }
        return totals.map { muscle, total in
            let perWeek = total / weeks
            return MuscleWeeklyVolume(muscle: muscle, setsPerWeek: perWeek, band: band(weeklySets: perWeek))
        }
        .sorted { ($0.setsPerWeek, $1.muscle) > ($1.setsPerWeek, $0.muscle) }
    }

    // MARK: - Cross with systemic recovery

    /// Per-muscle readiness, crossing local freshness with the strap's systemic recovery (0–100,
    /// nil when there's no recovery score yet). Red-band recovery gates everything to `rest`.
    public static func readiness(state: LoadState, recovery: Double?) -> Readiness {
        if let r = recovery, r < recoveryRedMax { return .rest }
        switch state {
        case .loaded:   return .caution
        case .moderate: return .caution
        case .fresh:    return .ready
        }
    }

    /// The whole-map recommendation: the fresh muscles cleared to train today, gated by systemic
    /// recovery. `loads` is expected already sorted by load (as `loads(events:)` returns it);
    /// ready muscles come back most-fresh first.
    public static func recommendation(loads: [MuscleLoad], recovery: Double?) -> Recommendation {
        if let r = recovery, r < recoveryRedMax {
            return Recommendation(readyMuscles: [], gatedBySystemic: true)
        }
        let ready = loads
            .filter { $0.state == .fresh }
            .sorted { $0.relative < $1.relative }
            .map(\.muscle)
        return Recommendation(readyMuscles: ready, gatedBySystemic: false)
    }
}
