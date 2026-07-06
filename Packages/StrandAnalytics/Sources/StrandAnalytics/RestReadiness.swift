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
                                targetHR: Int? = nil,
                                marginBPM: Int = defaultMarginBPM,
                                bandBPM: Int = defaultBandBPM,
                                minRestS: Int = defaultMinRestS,
                                maxRestS: Int = defaultMaxRestS) -> RestReadiness {
        // 1. We need live HR (+worn) AND a target — either the explicit one (FER-495) or the FER-348
        //    resting+margin default. With neither, fall to the honest fixed timer (never invent HR or
        //    color). The clock still releases at the ceiling so the rest doesn't hang. FER-506 relaxed
        //    this: a peakDrop/fixedBpm target no longer requires a resting baseline.
        guard worn, let hr = currentHR,
              let target = targetHR ?? restingHR.map({ Int($0.rounded()) + marginBPM }) else {
            let released = elapsedS >= maxRestS
            return RestReadiness(bpmToReady: nil, targetReadyHR: nil,
                                 state: .noSignal,
                                 reason: .noSignal,
                                 ready: released)
        }

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

// MARK: - Configurable rest target (FER-495)

/// Resolves the «ready» HR target (bpm) for one exercise's rest, per the user's chosen reference.
/// Pure, Sendable, database-free. The verdict is fed to `RestReadinessRule.evaluate(targetHR:)`.
///
/// `Reference` is this rule's own vocabulary; the persisted domain enum (`StrandTraining.HRRestReference`)
/// is mapped onto it by the app-layer consumer, so this math package stays decoupled from the data model.
///
/// Returns `nil` when the inputs can't yield an honest target — then the caller falls back to FER-348
/// (resting+margin) or, with no resting baseline, to the fixed timer (never an invented HR).
///
/// Method — `karvonenReserve` uses the heart-rate reserve method (Karvonen MJ, Kentala E, Mustala O.
/// "The effects of training on heart rate." Ann Med Exp Biol Fenn. 1957;35(3):307–315): the same %HRR
/// the repo already uses in `StrainScorer`, here to set a rest floor instead of a workout intensity.
/// APPROXIMATE — a rest cue, no clinical claim.
public enum RestTarget {
    /// How the rest target is derived. Mirrors `StrandTraining.HRRestReference` (mapped by the consumer).
    public enum Reference: String, Equatable, Sendable {
        case restingMargin    // FER-348 default — handled by evaluate(); resolve returns nil
        case peakDrop         // target = peakHR · (1 − value)
        case karvonenReserve  // target = restingHR + value·(maxHR − restingHR)
        case fixedBpm         // target = value (bpm)
    }

    /// `value` is a fraction 0…1 for `peakDrop`/`karvonenReserve`, bpm for `fixedBpm`, unused for
    /// `restingMargin`. Returns the target bpm, or `nil` when it can't be computed honestly.
    public static func resolve(reference: Reference, value: Double,
                               peakHR: Int?, restingHR: Double?, maxHR: Double?) -> Int? {
        switch reference {
        case .restingMargin:
            // FER-348 default (value 0) → nil so evaluate() owns the resting + 20 default (single source).
            // FER-759: a custom margin (value > 0, in bpm) → target = round(restingHR) + margin, letting the
            // user pull the «recovered» target down toward their own resting HR.
            guard value > 0, let r = restingHR else { return nil }
            return Int(r.rounded()) + Int(value)
        case .peakDrop:
            guard let peak = peakHR, peak > 0 else { return nil }
            let frac = min(max(value, 0), 0.9)            // clamp the drop to a sane 0–90%
            var t = Double(peak) * (1 - frac)
            if let r = restingHR { t = max(t, r) }        // floor: a target below resting is meaningless
            return Int(t.rounded())
        case .karvonenReserve:
            guard let r = restingHR, let m = maxHR, m > r else { return nil }   // no profile → nil
            let frac = min(max(value, 0), 1)
            return Int((r + frac * (m - r)).rounded())
        case .fixedBpm:
            guard value > 0 else { return nil }
            return Int(value.rounded())
        }
    }
}
