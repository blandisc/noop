import Foundation

/// One row of a metric's levels table, ready for the UI: the engine's stable level `key`, its English
/// display `name` (from `MetricLevels.name(for:)`, the ONE key→label home), the reference-range text
/// rendered by the metric's `MetricFormat`, and the half-open bounds carried through so the chart can
/// still highlight the active band and count days in it.
///
/// This is the display half of contract 1 (FER-29): the levels table is DERIVED from the engine cuts,
/// never restated. When the app builds a metric's bands from `MetricLevels.displayBands`, «7–9 h» can't
/// drift from the engine's «420–510 min», because the number and its text come from the same place.
public struct MetricDisplayBand: Sendable, Equatable {
    /// The engine level key (e.g. `"optimal"`). Never user-facing text.
    public let key: String
    /// The English display name the app localises (`MetricLevels.name(for: key)`).
    public let name: String
    /// The reference-range text, e.g. «7:00 – 8:30», «< 95%», «≥ 18».
    public let range: String
    /// Inclusive lower bound; `nil` = open below.
    public let lower: Double?
    /// Exclusive upper bound; `nil` = open above.
    public let upper: Double?

    public init(key: String, name: String, range: String, lower: Double?, upper: Double?) {
        self.key = key
        self.name = name
        self.range = range
        self.lower = lower
        self.upper = upper
    }
}

public extension MetricLevels {

    /// The display bands for a fixed metric — the engine's own levels turned into UI rows via the
    /// metric's `MetricFormat`. This is the single source the app's catalog reads for the levels table,
    /// so there is exactly ONE ladder per metric and no two numbers for the same band (FER-29 · C1).
    ///
    /// - Sleep bands come out in clock text from the engine's minute cuts: «< 6:00 / 6:00–7:00 /
    ///   7:00–8:30 / ≥ 8:30» — never the catalog's old «7–9 h».
    /// - Blood oxygen is TWO bands (low / normal), matching the engine, not the catalog's stale three.
    /// - Respiration is TWO bands with half-open edges, killing the residual closed-interval «<= 18».
    /// - Strain's top band prints «≥ 18» — honest that the engine's top level is open above, even though
    ///   the declared scale runs to 21.
    static func displayBands(for metric: FixedMetric,
                             format: MetricFormat? = nil) -> [MetricDisplayBand] {
        let fmt = format ?? .forMetric(metric)
        return levels(for: metric).map { level in
            MetricDisplayBand(
                key: level.key,
                name: name(for: level.key),
                range: fmt.range(lower: level.lower, upper: level.upper),
                lower: level.lower,
                upper: level.upper)
        }
    }
}
