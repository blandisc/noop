import Foundation

// ProgressionState.swift — double-progression decision for one exercise (FER-B).
//
// A TRANSPARENT, database-free classifier: given an exercise's recent history and its plan, decide
// whether the working weight should go up, stay (mid-cycle), or come down (deload). It is the single
// place the "when do I add weight?" rule lives, so the UI never re-derives it.
//
// Method — DOUBLE PROGRESSION (no rep ranges): the rep goal IS the plan's `targetReps`. You "meet" a
// session when every work set hits `targetReps` at the current working weight. Meet it for
// `sessionsToAdvance` consecutive sessions (default 2) and the next session earns `+increment` kg. This
// is standard progressive-overload programming (Baechle & Earle, "Essentials of Strength Training and
// Conditioning", NSCA, 3rd ed., 2008 — progressive overload; the double-progression variant is a common
// linear-periodization tactic). It is a training convention, NOT a prescription or a clinical claim.
//
// Deload — a stall (3 consecutive sessions at the same weight WITHOUT meeting the goal) proposes dropping
// ~7.5% and rebuilding. The 7.5% is a documented gym heuristic (the 5–10% band commonly cited for a
// deload), not a formula. Whether it's proposed or only surfaced is the user's `DeloadPolicy`.
//
// Light week — FRONTIER (ola 1 · E10, FER-329). A session served in a program's light week
// (`PastSession.deload`) is not a data point of the cycle: half the work sets, and with
// `DeloadRule.volumeAndLoad` also less weight. It can neither earn a raise nor prove a stall, so it is
// invisible to the met-run and it STOPS the fail-run. What it must never do is erase progress — met,
// met, light, met still reads as three met sessions minus the light one, not as a reset. The REACTIVE
// deload below stays fully alive inside a program (gate /biomecanico #1, 2026-09-02): a stall in week 2
// of 5 still proposes −7.5 % instead of waiting for the light week.
//
// Recovery gate — when today's recovery reads LOW (`TrainingRegulation.Reason.recoveryLow`), a ready
// upgrade is DEFERRED (not cancelled): it becomes `.deferred`, and the cycle progress is preserved so
// the raise simply waits for the next session.
//
// Pure & framework-free: primitives in, enum out. The caller (the app layer) builds `ProgressionInput`
// from CenitStore history and the routine plan, mirroring `OneRepMax`.

/// The progression verdict for one exercise. `.deferred` is a `.readyToAdvance` that today's low recovery
/// is holding back — the raise is earned, it just waits.
public enum ProgressionState: Equatable, Sendable {
    /// The goal was met `sessionsToAdvance` sessions running: train at `newKg` next.
    case readyToAdvance(newKg: Double)
    /// Mid-cycle: `done` of `of` qualifying sessions so far at the current weight.
    case inCycle(done: Int, of: Int)
    /// Stuck at the current weight for `sessions` sessions without meeting the goal (below the deload
    /// threshold, or at/above it when the policy is "only warn").
    case stalled(sessions: Int)
    /// A proposed deload: drop from `fromKg` to `toKg` and rebuild.
    case deloading(fromKg: Double, toKg: Double)
    /// Earned a raise to `newKg`, but low recovery defers it to the next session.
    case deferred(newKg: Double)
}

public enum ProgressionMath {

    /// Consecutive-session threshold that trips a deload proposal (handoff: "3 sesiones estancado").
    public static let deloadStallThreshold = 3
    /// Fractional drop a deload proposes (7.5% — within the commonly cited 5–10% deload band).
    public static let deloadFraction = 0.075

    // MARK: - Ritmo «Según reps en reserva» (ola 1 · E4)
    //
    // Method — RIR-anchored RPE (Zourdos 2016, JSCR 30(1):267-275; Helms 2016, SCJ 38(4):42-49,
    // DOI 10.1519/SSC.0000000000000218): 10 = 0 reps in reserve, 9 = 1, 8 = 2. Helms 2016 is literal
    // about the raise — «increase the intensity if able to complete sets with more than [target] RIR»
    // — which is the NSCA's «2 for 2» rule reached in ONE session instead of two.
    //
    // These are gym CONVENTIONS with a defensible method, not a prescription: calibration defaults,
    // /biomecanico owns them.

    /// At or below this the session was COMFORTABLE (≥ 2 reps in reserve) — the raise can come early.
    public static let rpeComfortableMax = 8.0
    /// At or above this the session was AT THE LIMIT (≈ 0 reps in reserve).
    public static let rpeLimitMin = 9.5
    /// How many consecutive met-at-limit sessions before they stop being invisible and count as
    /// standard. Reuses `deloadStallThreshold` on purpose — no new constant, and it is the same
    /// «three sessions and I tell you» the deload already speaks. Gate /biomecanico #2: without a cap
    /// a user who rates 9.5–10 out of habit (Steele 2017, PeerJ 5:e4105 — the less experienced
    /// under-predict how many reps they had left, so they rate HIGH) would be frozen forever: no raise, no
    /// deload, no stall signal. Never lowers the weight — Helms 2016 only reduces intensity when the
    /// reps were NOT completed.
    public static var atLimitStreakCap: Int { deloadStallThreshold }

    /// How hard a past session was, read from its per-set RPE.
    public enum Effort: Equatable, Sendable {
        /// Every work set at or under `rpeComfortableMax` — reps left in reserve.
        case comfortable
        /// Between the two thresholds: the session the plan expects.
        case standard
        /// At least one work set at or above `rpeLimitMin` — nothing left in the tank.
        case atLimit
        /// No usable rating (missing on some set, or not as many ratings as work sets). Behaves
        /// exactly like `standard`: an unrated session must never change the rule.
        case unknown
    }

    /// The session's effort. `unknown` — never a guess — whenever the ratings don't cover the work sets.
    public static func effort(_ s: PastSession) -> Effort {
        guard !s.workSetRPE.isEmpty, s.workSetRPE.count == s.workSetReps.count else { return .unknown }
        let rated = s.workSetRPE.compactMap { $0 }
        guard rated.count == s.workSetRPE.count else { return .unknown }
        if rated.contains(where: { $0 >= rpeLimitMin }) { return .atLimit }
        if rated.allSatisfy({ $0 <= rpeComfortableMax }) { return .comfortable }
        return .standard
    }

    /// The sessions the cycle can see at the CURRENT working weight, newest → older, stopping at a
    /// weight change. One copy of the rule: `classify` and the at-limit counter both read it.
    ///
    /// Ola 1 · E10: a light-week session is TRANSPARENT to both ends of this. It doesn't get to define
    /// the current weight (`current` is the newest NON-deload session — otherwise a week at −7,5 %
    /// would redefine the working load and the next raise would climb from the reduced weight), and it
    /// doesn't break the trailing run by weight either — it rides along so `classify` can decide, per
    /// branch, whether to skip it (met-run) or stop at it (fail-run).
    static func trailingAtCurrentWeight(_ sessions: [PastSession]) -> [PastSession] {
        guard let currentIdx = sessions.lastIndex(where: { !$0.deload }) else { return [] }
        let currentKg = sessions[currentIdx].workingKg
        var trailing: [PastSession] = []
        for s in sessions[...currentIdx].reversed() {
            if s.deload { trailing.append(s); continue }
            guard abs(s.workingKg - currentKg) < 0.0001 else { break }
            trailing.append(s)
        }
        return trailing
    }

    /// How many consecutive sessions at the top of the history met the goal AT THE LIMIT — the number
    /// the copy needs for «N sesiones al límite». 0 when the newest session missed or wasn't at the limit.
    public static func atLimitStreak(_ input: ProgressionInput) -> Int {
        let sessions = input.history.filter { !$0.optedOut }
        var streak = 0
        for s in trailingAtCurrentWeight(sessions) {
            if s.deload { continue }   // ola 1 · E10: la semana ligera no cuenta ni rompe la racha
            guard metGoal(s, targetReps: input.targetReps, targetSets: input.targetSets),
                  effort(s) == .atLimit else { break }
            streak += 1
        }
        return streak
    }

    /// One past session of the exercise, as the classifier needs it. Warm-up sets are excluded by the
    /// caller — `workSetReps` is the reps hit on each WORK set, at `workingKg`.
    public struct PastSession: Equatable, Sendable {
        public let workingKg: Double
        public let workSetReps: [Int]
        /// The user chose "Volver a X" this session (opt-out): it counts as neither a hit nor a miss.
        public let optedOut: Bool
        /// The session was served in a program's LIGHT week (ola 1 · E10, `strengthSession.deload = 1`).
        /// It is a FRONTIER, not an opt-out: half the sets at (maybe) less weight is not a performance at
        /// the working weight, so it can neither earn a raise nor prove a stall — but it also must not
        /// erase what came before it. So: invisible to the met-run (it neither adds nor breaks), and a
        /// HARD STOP for the fail-run (a stall doesn't survive a week of deliberate backing off).
        public let deload: Bool
        /// Perceived effort per WORK set, parallel to `workSetReps` (ola 1 · E4). Empty = the caller
        /// doesn't carry RPE; a `nil` element = that set wasn't rated. Either way the session reads
        /// `.unknown` and the rule behaves exactly as it did before RPE existed.
        public let workSetRPE: [Double?]
        public init(workingKg: Double, workSetReps: [Int], optedOut: Bool = false,
                    workSetRPE: [Double?] = [], deload: Bool = false) {
            self.workingKg = workingKg; self.workSetReps = workSetReps; self.optedOut = optedOut
            self.workSetRPE = workSetRPE
            self.deload = deload
        }
    }

    public struct ProgressionInput: Equatable, Sendable {
        /// Past sessions of this exercise, OLDEST → NEWEST.
        public let history: [PastSession]
        public let targetReps: Int
        public let targetSets: Int
        /// Consecutive qualifying sessions before the weight goes up (`progressionSessions`, default 2).
        public let sessionsToAdvance: Int
        /// The resolved increment in kg (manual, or derived via `PlateMath.minimumIncrement`).
        public let incrementKg: Double
        /// `true` = only warn on a stall (never auto-propose a deload); maps from `DeloadPolicy.warn`.
        public let deloadWarnOnly: Bool
        /// Today's recovery reason, if known. `.recoveryLow` defers an earned raise.
        public let recoveryReason: TrainingRegulation.Reason?
        /// Defer an earned raise regardless of `recoveryReason` (FER-82). The single oracle sets this
        /// from Hoy's verdict: with «Hoy ve leve» or «Recupera» the raise waits for a better day. Kept
        /// as its own flag so the legacy score-driven path keeps its exact behaviour.
        public let deferRaise: Bool
        /// Ritmo «Según reps en reserva» (ola 1 · E4), from `RoutineExercise.progressionUseRPE`.
        /// `false` — the default and every pre-existing routine — is byte-identical to the rule
        /// before RPE existed.
        public let useRPE: Bool

        public init(history: [PastSession], targetReps: Int, targetSets: Int,
                    sessionsToAdvance: Int = 2, incrementKg: Double,
                    deloadWarnOnly: Bool = false,
                    recoveryReason: TrainingRegulation.Reason? = nil,
                    deferRaise: Bool = false,
                    useRPE: Bool = false) {
            self.history = history; self.targetReps = targetReps; self.targetSets = targetSets
            self.sessionsToAdvance = sessionsToAdvance; self.incrementKg = incrementKg
            self.deloadWarnOnly = deloadWarnOnly; self.recoveryReason = recoveryReason
            self.deferRaise = deferRaise
            self.useRPE = useRPE
        }
    }

    /// Whether a session met the goal: at least `targetSets` work sets, ALL at or above `targetReps`.
    static func metGoal(_ s: PastSession, targetReps: Int, targetSets: Int) -> Bool {
        guard s.workSetReps.count >= max(1, targetSets) else { return false }
        return s.workSetReps.allSatisfy { $0 >= targetReps }
    }

    /// Round a weight to the nearest multiple of `increment` (a deload must land on a buildable weight).
    static func round(_ kg: Double, toIncrement increment: Double) -> Double {
        guard increment > 0 else { return kg }
        return (kg / increment).rounded() * increment
    }

    /// Classify the exercise's progression state from its history and plan. Pure.
    public static func classify(_ input: ProgressionInput) -> ProgressionState {
        let n = max(1, input.sessionsToAdvance)
        // Opt-out sessions are invisible to the cycle: they count as neither hit nor miss.
        let sessions = input.history.filter { !$0.optedOut }
        // Ola 1 · E10: the cycle's «current» session is the newest one that was NOT served light. A
        // light week is a frontier, not a data point — letting it be `current` would read the reduced
        // sets (and, with `volumeAndLoad`, the reduced weight) as this exercise's real performance.
        guard let current = sessions.last(where: { !$0.deload }) else { return .inCycle(done: 0, of: n) }
        let currentKg = current.workingKg

        // Trailing run of sessions AT the current weight (newest → older), stopping at a weight change.
        let trailing = trailingAtCurrentWeight(sessions)
        let newestMet = metGoal(current, targetReps: input.targetReps, targetSets: input.targetSets)

        if newestMet {
            // Count consecutive met sessions from newest.
            let metPrefix = trailing.prefix {
                $0.deload || metGoal($0, targetReps: input.targetReps, targetSets: input.targetSets)
            }
            let metRun = metRunCount(Array(metPrefix), useRPE: input.useRPE)
            // Ola 1 · E4 (a): the newest session met the goal with reps to spare, so the raise comes
            // NOW instead of at the end of the cycle — Helms 2016's «able to complete sets with more
            // than [target] RIR». It passes through the SAME gates below (a non-positive increment
            // can't raise; today's verdict can still defer it), so FER-85 is untouched.
            let comfortableRaise = input.useRPE && effort(current) == .comfortable
            if metRun >= n || comfortableRaise {
                // A non-positive increment can't propose a raise (QA D2): stay honestly in-cycle.
                guard input.incrementKg > 0 else { return .inCycle(done: metRun, of: n) }
                let newKg = currentKg + input.incrementKg
                // Recovery gate: a day the body didn't clear defers the earned raise, preserving
                // progress. `deferRaise` is the single-oracle path (Hoy's verdict); `recoveryReason`
                // is the legacy score path. Either one defers.
                if input.deferRaise || input.recoveryReason == .recoveryLow {
                    return .deferred(newKg: newKg)
                }
                return .readyToAdvance(newKg: newKg)
            }
            return .inCycle(done: metRun, of: n)
        } else {
            // Count consecutive missed sessions from newest.
            var failRun = 0
            for s in trailing {
                // Ola 1 · E10: a light week ENDS the stall count — the sessions before it were at a
                // different dose, so calling them «three in a row at this weight» would be a lie.
                if s.deload { break }
                guard !metGoal(s, targetReps: input.targetReps, targetSets: input.targetSets) else { break }
                failRun += 1
            }
            if failRun >= deloadStallThreshold && !input.deloadWarnOnly {
                let toKg = round(currentKg * (1 - deloadFraction), toIncrement: input.incrementKg)
                return .deloading(fromKg: currentKg, toKg: toKg)
            }
            return .stalled(sessions: failRun)
        }
    }

    /// How many of the trailing MET sessions (newest → older, all of them met) count toward the cycle.
    ///
    /// Without the RPE rhythm: all of them, exactly as before. With it (ola 1 · E4, rule b): a session
    /// met AT THE LIMIT is invisible — it neither adds to the run nor breaks it — because reaching the
    /// reps with nothing in reserve is not the same evidence as reaching them with two left. The one
    /// exception is the cap: once `atLimitStreakCap` of them run consecutively, the whole streak counts
    /// as standard, so «al límite» can freeze the raise for a while but never forever.
    static func metRunCount(_ metPrefix: [PastSession], useRPE: Bool) -> Int {
        // Ola 1 · E10: a light-week session travels inside the prefix (so it doesn't break the run),
        // but it never COUNTS toward the cycle — it wasn't the session the plan asked for.
        let metPrefix = metPrefix.filter { !$0.deload }
        guard useRPE else { return metPrefix.count }
        var run = 0
        var atLimitRun = 0
        for s in metPrefix {
            if effort(s) == .atLimit {
                atLimitRun += 1
                continue
            }
            if atLimitRun >= atLimitStreakCap { run += atLimitRun }
            atLimitRun = 0
            run += 1
        }
        if atLimitRun >= atLimitStreakCap { run += atLimitRun }
        return run
    }
}
