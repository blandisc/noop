import Foundation

/// The single home of the "level reading" phrase — the one line under a metric's hero that says where
/// today's value sits («In your usual range.», «Short of your target.»). FER-29 · contrato 4.
///
/// Before this, the same idea was re-expressed in four scattered switches with ~47 hand-written cases
/// and silent `default: nil` fall-throughs: `vitalReadingText` + `sleepReadingText` +
/// `recoveryReadingText` (`LiquidMetricSheetView`) and `TrainingLoadSheet.readingText`. This replaces
/// all of them with ONE data table, keyed uniformly by `(metricID, levelKey)`, that yields a stable
/// LOCALIZATION KEY the app resolves with `String(localized:)`. Coverage is TOTAL and explicit — a
/// pair that isn't in the contract returns `nil` on purpose (the app renders no line), never a mute
/// `default` that hides a gap.
///
/// The level NAME still comes from `MetricLevels.name(for:)` — this contract owns only the *reading
/// sentence*, not the label, so the two can't duplicate.
///
/// Pure and Foundation-only: it emits keys and grammar, never localized copy. The es-MX and English
/// strings for these keys live in the app's String Catalog (filled in F5); F0 fixes only the keys.
public enum MetricLevelPhrase {

    /// Which comparison grammar a metric's reading is phrased against. It selects the sentence family
    /// («above your base» vs «above the typical range» vs «short of your target») and is baked into the
    /// key so the catalog can localise each family distinctly.
    public enum Comparison: String, Sendable, CaseIterable {
        /// Against the user's OWN rolling baseline — HRV, skin temperature, resting HR, respiration.
        case vsBase
        /// Against a population / scale reference — blood oxygen, steps, stress, strain.
        case vsPopulation
        /// Against the user's own sleep need — sleep only.
        case vsTarget
    }

    /// One row of the contract: a `(metricID, levelKey)` pair and the comparison grammar it reads in.
    public struct Entry: Sendable, Equatable {
        public let metricID: String
        public let levelKey: String
        public let comparison: Comparison
        public init(metricID: String, levelKey: String, comparison: Comparison) {
            self.metricID = metricID
            self.levelKey = levelKey
            self.comparison = comparison
        }
        /// The localization key for this row.
        public var key: String {
            MetricLevelPhrase.key(metricID: metricID, levelKey: levelKey, comparison: comparison)
        }
    }

    /// The localization key for a level reading, composed purely from its inputs. Because it is pure
    /// interpolation there is no case to forget: every `(metric, level, comparison)` yields a key.
    /// Shape: `reading.<comparison>.<metricID>.<levelKey>` (e.g. `reading.vsTarget.sleep.optimal`).
    public static func key(metricID: String, levelKey: String, comparison: Comparison) -> String {
        "reading.\(comparison.rawValue).\(metricID).\(levelKey)"
    }

    /// The comparison grammar a metric reads against. `nil` for an unknown metric — the caller decides
    /// what "no grammar" means rather than getting a silent wrong default.
    public static func comparison(forMetricID id: String) -> Comparison? {
        comparisonByMetric[id]
    }

    /// The contract row for a `(metricID, levelKey)` pair, or `nil` when the pair isn't part of the
    /// contract. The app treats `nil` as "no reading line" explicitly.
    public static func entry(metricID: String, levelKey: String) -> Entry? {
        guard let comparison = comparisonByMetric[metricID],
              levelKeysByMetric[metricID]?.contains(levelKey) == true else { return nil }
        return Entry(metricID: metricID, levelKey: levelKey, comparison: comparison)
    }

    /// The localization key for a `(metricID, levelKey)` pair using the metric's own comparison, or
    /// `nil` when the pair isn't in the contract.
    public static func key(metricID: String, levelKey: String) -> String? {
        entry(metricID: metricID, levelKey: levelKey)?.key
    }

    /// Every row of the contract — the full replacement for the four scattered switches. One row per
    /// `(metric, level)`, so a test can assert total coverage against `MetricLevels` (plus HRV's
    /// personal levels and Carga's load bands, which aren't `FixedMetric`s).
    public static var table: [Entry] {
        var rows: [Entry] = []
        for (metricID, comparison) in comparisonByMetric {
            for levelKey in (levelKeysByMetric[metricID] ?? []) {
                rows.append(Entry(metricID: metricID, levelKey: levelKey, comparison: comparison))
            }
        }
        return rows
    }

    // MARK: - The data (one small table, not 47 switch cases)

    /// The comparison grammar per metric id (the ids the app's catalog uses). Carga («load») and HRV
    /// («hrv») are here alongside the fixed metrics; recovery has no sheet in FER-29 and is absent by
    /// design.
    private static let comparisonByMetric: [String: Comparison] = [
        "hrv":       .vsBase,
        "rhr":       .vsBase,
        "resp_rate": .vsBase,
        "skin_temp": .vsBase,
        "spo2":      .vsPopulation,
        "steps":     .vsPopulation,
        "stress":    .vsPopulation,
        "strain":    .vsPopulation,
        "sleep":     .vsTarget,
        "load":      .vsBase,
    ]

    /// The level keys per metric id. For the fixed metrics these mirror `MetricLevels.levels(for:)`;
    /// HRV uses the personal below/inBase/above levels, and Carga uses `ReadinessEngine.LoadBand`.
    private static let levelKeysByMetric: [String: [String]] = [
        "hrv":       ["below", "inBase", "above"],
        "rhr":       ["athlete", "excellent", "normal", "elevated"],
        "resp_rate": ["normal", "elevated"],
        "skin_temp": ["below", "inBase", "warm", "elevated"],
        "spo2":      ["low", "normal"],
        "steps":     ["sedentary", "active", "veryActive"],
        "stress":    ["low", "medium", "high"],
        "strain":    ["rest", "light", "moderate", "hard", "extreme"],
        "sleep":     ["short", "adequate", "optimal", "extended"],
        "load":      ["rampingDown", "sweetSpot", "buildingFast", "spiking"],
    ]
}
