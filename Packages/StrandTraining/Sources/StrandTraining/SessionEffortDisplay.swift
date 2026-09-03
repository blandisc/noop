import Foundation

/// What a completed strength session's "effort" hero should show (FER-226). `StrainScorer` refuses a
/// strain reading below its minimum-readings/span gate — that's correct, not a bug — so a short
/// session (or one with no watch at all) needs an honest fallback instead of "Sin frecuencia
/// cardiaca". Pure precedence rule; does not touch `StrainScorer`'s own thresholds.
///
/// Ola 1 · E3 (FER-330): surfaces that show a load with `strainSource == .rpe` must say «estimado»
/// exactly once. `isEstimated` is the single check those surfaces share — the receipt, the detail
/// hero, the history row and WorkoutEditSheet — so a measured session never picks up the word by
/// accident and an estimated one never forgets it.
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

    /// Whether this session's load was estimated from minutes × effort (ola 1).
    /// `nil` alongside a non-nil strain = pre-v42 row = measured (`hr`), same rule as `StrengthSession`.
    public static func isEstimated(strainSource: StrainSource?) -> Bool {
        strainSource == .rpe
    }

    /// The numeral a surface prints for an estimated effort — always with the `~` honesty glyph
    /// (LENGUAJE §5.6). The caller supplies the already-formatted number (`MetricFormat` /
    /// `StrengthHistoryFormat.strain`); this only adds the tilde so every surface agrees.
    public static func estimatedNumeral(_ formatted: String) -> String {
        formatted.hasPrefix("~") ? formatted : "~\(formatted)"
    }
}
