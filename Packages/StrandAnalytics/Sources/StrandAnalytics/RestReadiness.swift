import Foundation

// RestReadiness.swift — between-sets rest guided by heart-rate recovery (HRR). (FER-348)
//
// The strength tracker's differentiator: instead of a blind countdown, the rest between
// sets watches the live heart rate from the strap and tells you when your pulse has
// settled back toward your own resting baseline — variant C2: the dominant number is
// "N bpm to ready" counting down to 0 → «Ready».
//
// Pure, Sendable, database-free. The guided session (FER-347, in Cenit/) feeds this rule
// PLAIN values — the live HR (`LiveState.heartRate`), wrist-wear (`LiveState.worn`), and
// the user's resting HR baseline — and calls `evaluate(...)` per tick. This package must
// never import CoreBluetooth/UIKit, so it never sees `LiveState` itself.
//
// Method — heart-rate recovery (HRR): the bpm the heart rate falls after stopping effort
// is an established marker of parasympathetic reactivation (Cole et al. 1999, NEJM
// 341:1351–1357; Daanen et al. 2012, Int J Sports Physiol Perform 7:251–260, HRR for
// monitoring training status). NOOP does NOT use absolute clinical HRR thresholds (those
// are diagnostic). It uses an honest personal target: "recovered" = HR has returned near
// the user's OWN resting HR. APPROXIMATE — a rest cue, not a medical verdict, no clinical
// claim. (Note: the repo already uses "HRR" for Heart-Rate *Reserve* (Karvonen) in
// StrainScorer; here it is Heart-Rate *Recovery* — a different quantity.)

/// Where the rest stands this tick. Drives the band ("almost ready → ready") so the UI
/// never fakes beat-level precision.
public enum RestReadinessState: String, Equatable, Sendable {
    case resting        // HR still elevated — keep resting
    case almostReady    // within the honesty band (≤ bandBPM over the target)
    case ready          // at/under target (and floor met), or the ceiling released it
    case noSignal       // no live HR (not worn / nil / no baseline) — falls back to a fixed timer
}

/// Why `ready` is (or isn't) true — so the session can distinguish an honest HR recovery
/// from a ceiling release (no infinite wait) or a clock-only fallback.
public enum RestReadyReason: String, Equatable, Sendable {
    case notReady
    case hrRecovered    // HR dropped to target AND the floor elapsed
    case ceiling        // max rest reached; released regardless of HR (no infinite wait)
    case noSignal       // no live HR; readiness comes from the clock alone
}

/// One tick's verdict for the between-sets rest. `bpmToReady` is the dominant C2 number.
public struct RestReadiness: Equatable, Sendable {
    /// The dominant C2 number: bpm still to fall before ready, clamped ≥ 0. `nil` when there
    /// is no live HR signal (the UI shows the fixed timer instead, no invented number/color).
    public let bpmToReady: Int?
    /// The target "recovered" HR = round(restingHR) + margin. `nil` when there is no signal.
    public let targetReadyHR: Int?
    public let state: RestReadinessState
    public let reason: RestReadyReason
    public let ready: Bool

    public init(bpmToReady: Int?, targetReadyHR: Int?, state: RestReadinessState,
                reason: RestReadyReason, ready: Bool) {
        self.bpmToReady = bpmToReady
        self.targetReadyHR = targetReadyHR
        self.state = state
        self.reason = reason
        self.ready = ready
    }
}

/// Pure rule for between-sets rest readiness. Stateless: each call gets `elapsedS`, so the
/// session (FER-347) owns the timer; the rule just maps (HR, baseline, time) → verdict.
public enum RestReadinessRule {
    /// Margin over the user's resting HR that counts as "recovered". A practical rest cue
    /// (not a clinical HRR threshold): a sustainable HR a notch above rest, not full rest.
    public static let defaultMarginBPM: Int = 20
    /// Honesty band: within this many bpm of the target we say «almost ready» rather than
    /// faking beat-level precision.
    public static let defaultBandBPM: Int = 5
    /// Floor — never call «ready» before this, even if HR already dropped (a too-quick set
    /// shouldn't be greenlit by a momentary dip).
    public static let defaultMinRestS: Int = 20
    /// Ceiling — release at this point no matter the HR, so there is never an infinite wait.
    public static let defaultMaxRestS: Int = 180

    /// Evaluate one tick. Pass plain values from the session: live HR (nil if none), wrist-wear,
    /// the user's resting-HR baseline (nil if not yet trustworthy → falls back to the timer),
    /// and seconds elapsed in this rest. Returns the C2 number + state + ready flag.
    public static func evaluate(currentHR: Int?,
                                worn: Bool,
                                restingHR: Double?,
                                elapsedS: Int,
                                marginBPM: Int = defaultMarginBPM,
                                bandBPM: Int = defaultBandBPM,
                                minRestS: Int = defaultMinRestS,
                                maxRestS: Int = defaultMaxRestS) -> RestReadiness {
        // 1. No usable HR signal → honest fixed timer; never invent HR or color. The clock
        //    still releases at the ceiling so the rest doesn't hang.
        guard worn, let hr = currentHR, let resting = restingHR else {
            let released = elapsedS >= maxRestS
            return RestReadiness(bpmToReady: nil, targetReadyHR: nil,
                                 state: .noSignal,
                                 reason: .noSignal,
                                 ready: released)
        }

        let target = Int(resting.rounded()) + marginBPM
        let gap = max(0, hr - target)

        // 2. Ceiling — released regardless of HR (no infinite wait), still reporting the honest gap.
        if elapsedS >= maxRestS {
            return RestReadiness(bpmToReady: gap, targetReadyHR: target,
                                 state: .ready, reason: .ceiling, ready: true)
        }

        // 3. HR recovered to target.
        if gap == 0 {
            // Floor blocks a premature «ready».
            if elapsedS >= minRestS {
                return RestReadiness(bpmToReady: 0, targetReadyHR: target,
                                     state: .ready, reason: .hrRecovered, ready: true)
            }
            return RestReadiness(bpmToReady: 0, targetReadyHR: target,
                                 state: .almostReady, reason: .notReady, ready: false)
        }

        // 4. Honesty band — close enough that beat-level precision would be fake.
        if gap <= bandBPM {
            return RestReadiness(bpmToReady: gap, targetReadyHR: target,
                                 state: .almostReady, reason: .notReady, ready: false)
        }

        // 5. Still resting.
        return RestReadiness(bpmToReady: gap, targetReadyHR: target,
                             state: .resting, reason: .notReady, ready: false)
    }
}
