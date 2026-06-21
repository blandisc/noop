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
//     A set today counts ~1.0; two days ago ~0.5; four days ago ~0.25. The 2-day half-life
//     tracks the time course of muscle protein synthesis (MPS), which is elevated ~24–48 h
//     after a resistance bout and returns toward baseline by ~48–72 h:
//        MacDougall JD et al. "The time course for elevated muscle protein synthesis following
//        heavy resistance exercise." Can J Appl Physiol 20(4):480–6, 1995.
//        Damas F, Phillips S, Vechin FC, Ugrinowitsch C. "A review of resistance training-induced
//        changes in skeletal muscle protein synthesis…" Sports Med 45(6):801–7, 2015.
//
//   • The 3/7/14-day window FILTERS which sets enter (sets older than the window are dropped);
//     a wider window shows more accumulated history. Decay is the same across windows.
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

    /// The recency lens for the map. Filters which sets count; wider = more accumulated history.
    public enum Window: Int, Sendable, CaseIterable {
        case d3 = 3, d7 = 7, d14 = 14
        public var days: Int { rawValue }
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
        /// Decayed, involvement-weighted load within the window (the map's color magnitude).
        public let load: Double
        /// `load` as a fraction of the most-loaded muscle (0…1).
        public let relative: Double
        /// Whole days since the most recent set that hit this muscle (within the window).
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

    /// Per-muscle load map for the given window, sorted by load descending (most-loaded first).
    /// Returns an empty array when there are no events in the window — the honest empty state.
    public static func loads(events: [MuscleSetEvent], window: Window) -> [MuscleLoad] {
        let inWindow = events.filter { $0.daysAgo >= 0 && $0.daysAgo <= window.days }
        guard !inWindow.isEmpty else { return [] }

        // Weekly volume is a fixed 7-day count, INDEPENDENT of the display window: compute it over the
        // FULL event set, not `inWindow`. (Bug fix: accumulating over `inWindow` meant the .d3 lens
        // dropped sets at daysAgo 4…7 before the ≤7 guard ran — identical data read 1.0 set/wk on .d3 vs
        // 3.0 on .d7/.d14, which could flip a muscle's Schoenfeld band purely from the chosen lens.)
        var weekly: [String: Double] = [:]
        for e in events where e.daysAgo >= 0 && e.daysAgo <= 7 {
            weekly[e.muscle, default: 0] += e.involvement
        }

        var decayed: [String: Double] = [:]
        var lastSeen: [String: Int] = [:]
        for e in inWindow {
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
    /// recovery. `loads` is expected already sorted by load (as `loads(events:window:)` returns it);
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
