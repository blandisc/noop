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

    /// One past session of the exercise, as the classifier needs it. Warm-up sets are excluded by the
    /// caller — `workSetReps` is the reps hit on each WORK set, at `workingKg`.
    public struct PastSession: Equatable, Sendable {
        public let workingKg: Double
        public let workSetReps: [Int]
        /// The user chose "Volver a X" this session (opt-out): it counts as neither a hit nor a miss.
        public let optedOut: Bool
        public init(workingKg: Double, workSetReps: [Int], optedOut: Bool = false) {
            self.workingKg = workingKg; self.workSetReps = workSetReps; self.optedOut = optedOut
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

        public init(history: [PastSession], targetReps: Int, targetSets: Int,
                    sessionsToAdvance: Int = 2, incrementKg: Double,
                    deloadWarnOnly: Bool = false,
                    recoveryReason: TrainingRegulation.Reason? = nil) {
            self.history = history; self.targetReps = targetReps; self.targetSets = targetSets
            self.sessionsToAdvance = sessionsToAdvance; self.incrementKg = incrementKg
            self.deloadWarnOnly = deloadWarnOnly; self.recoveryReason = recoveryReason
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
        guard let current = sessions.last else { return .inCycle(done: 0, of: n) }
        let currentKg = current.workingKg

        // Trailing run of sessions AT the current weight (newest → older), stopping at a weight change.
        var trailing: [PastSession] = []
        for s in sessions.reversed() {
            guard abs(s.workingKg - currentKg) < 0.0001 else { break }
            trailing.append(s)
        }
        let newestMet = metGoal(current, targetReps: input.targetReps, targetSets: input.targetSets)

        if newestMet {
            // Count consecutive met sessions from newest.
            var metRun = 0
            for s in trailing {
                guard metGoal(s, targetReps: input.targetReps, targetSets: input.targetSets) else { break }
                metRun += 1
            }
            if metRun >= n {
                // A non-positive increment can't propose a raise (QA D2): stay honestly in-cycle.
                guard input.incrementKg > 0 else { return .inCycle(done: metRun, of: n) }
                let newKg = currentKg + input.incrementKg
                // Recovery gate: a low-recovery day defers the earned raise, preserving progress.
                if input.recoveryReason == .recoveryLow { return .deferred(newKg: newKg) }
                return .readyToAdvance(newKg: newKg)
            }
            return .inCycle(done: metRun, of: n)
        } else {
            // Count consecutive missed sessions from newest.
            var failRun = 0
            for s in trailing {
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
}
