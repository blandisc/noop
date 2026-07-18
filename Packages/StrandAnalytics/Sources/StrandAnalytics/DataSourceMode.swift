import Foundation
import CenitStore

/// Which data sources feed the dashboard and the recovery baseline — a single user preference (FER-484).
/// The capture pipeline (BLE strap + HealthKit) always writes ALL sources; the mode only filters what is
/// READ. `combined` is the historical behavior (strap wins, Apple Health is the base / gap-fill).
public enum DataSourceMode: String, Codable, CaseIterable, Sendable {
    /// WHOOP strap + Apple Health: strap wins, Apple fills the gaps (the historical default).
    case combined
    /// WHOOP strap only — Apple Health is excluded from every read (a night without the band stays empty).
    case whoopOnly
    /// Apple Health only — the strap is excluded from every read (its rows stay stored, just unused).
    case appleHealthOnly

    /// True when WHOOP strap rows (raw `my-whoop` + on-device `my-whoop-noop`) may be read.
    public var usesWhoop: Bool { self != .appleHealthOnly }
    /// True when Apple Health rows may be read.
    public var usesAppleHealth: Bool { self != .whoopOnly }
}

/// Applies a `DataSourceMode` to the per-source daily arrays BEFORE they enter the dashboard merge
/// (`Repository.mergeDaily`) and the baseline fold (`IntelligenceEngine`). It empties the arrays a mode
/// excludes; `combined` is the identity, so the merge it feeds is byte-for-byte the historical result —
/// the regression-zero guarantee. The mode never mutates a row, only decides which rows enter.
public enum DataSourcePolicy {
    public static func filter(_ mode: DataSourceMode,
                              imported: [DailyMetric],
                              computed: [DailyMetric],
                              apple: [DailyMetric])
        -> (imported: [DailyMetric], computed: [DailyMetric], apple: [DailyMetric]) {
        (mode.usesWhoop ? imported : [],
         mode.usesWhoop ? computed : [],
         mode.usesAppleHealth ? apple : [])
    }
}
