import Foundation

/// What a completed strength session's "effort" hero should show (FER-226). `StrainScorer` refuses a
/// strain reading below its minimum-readings/span gate — that's correct, not a bug — so a short
/// session (or one with no watch at all) needs an honest fallback instead of "Sin frecuencia
/// cardiaca". Pure precedence rule; does not touch `StrainScorer`'s own thresholds.
public enum SessionEffortDisplay: Equatable, Sendable {
    /// A valid strain score was computed.
    case effort(Double)
    /// No strain (too short / gated), but the watch captured enough HR to average.
    case durationWithHR(Int)
    /// No strain and no HR at all (no watch, or the capturer produced nothing).
    case durationOnly

    public static func resolve(strain: Double?, avgHr: Int?) -> SessionEffortDisplay {
        if let strain { return .effort(strain) }
        if let avgHr { return .durationWithHR(avgHr) }
        return .durationOnly
    }
}
