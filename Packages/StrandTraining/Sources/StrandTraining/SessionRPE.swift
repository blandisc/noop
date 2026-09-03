import Foundation

// SessionRPE.swift — the SUGGESTED answer to «¿qué tan duro estuvo?» (ola 1 · E2).
//
// The receipt asks for the session's effort ALWAYS, watch or no watch (D-Q13): the rating is the only
// signal that discriminates intensity in strength work, and a session with a pulse is also the only
// way to collect calibration pairs. Asking with a blank row costs a decision the user already made
// set by set, so the row opens on the mean of the WORK sets they rated.
//
// Deliberate exclusions: warm-ups are not the session (they're the ramp), drops are a continuation of
// their mother set at a lighter load (double-counting them would drag the mean up), and a set that was
// never marked done never happened. A set without a rating is simply not in the mean — it does not
// pull it toward anything. No rating anywhere → `nil`, never a defaulted 7.
//
// Rounding to the half-step matches the row the user taps (6, 6.5, … 10); the clamp keeps a stray
// value inside the row. Lives HERE and not in StrandAnalytics because it reads `SetEntry`/`SetKind`
// (ARCHITECTURE §3: StrandAnalytics never imports StrandTraining).
public enum SessionRPE {

    /// Lowest / highest rating the session-effort row offers (RIR-anchored, Zourdos 2016:
    /// 10 = 0 reps in reserve). Mirrors `SessionRPELoad.rpeMin/rpeMax` in StrandAnalytics, which
    /// cannot be imported from here.
    public static let min: Double = 6
    public static let max: Double = 10

    /// The suggested session effort: mean of the RATED, DONE, non-warm-up, non-drop sets, rounded to
    /// the nearest half step and clamped into the row. `nil` when no such set carries a rating.
    ///
    /// It is a SUGGESTION: whoever presents it decides whether an accepted value is recorded as
    /// `sessionRpeSource == .prefill` (taken as offered) or `.answered` (tapped). It is NOT the
    /// session-RPE construct: the mean of per-set ratings sits ABOVE the global rating of the same
    /// session (Sweet et al. 2004, JSCR 18(4):796-802), which is why the receipt shows it as «sugerido»
    /// and never writes it on the user's behalf.
    public static func prefill(sets: [SetEntry]) -> Double? {
        let rated = sets.filter { $0.kind == .work && $0.done && $0.mode != .drop }.compactMap(\.rpe)
        guard !rated.isEmpty else { return nil }
        let mean = rated.reduce(0, +) / Double(rated.count)
        let half = (mean * 2).rounded() / 2
        return Swift.min(Swift.max(half, min), max)
    }
}
