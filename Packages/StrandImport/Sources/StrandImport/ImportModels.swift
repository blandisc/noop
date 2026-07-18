import Foundation

// MARK: - Source provenance

/// Where a normalized row originated. Mirrors the `dataSource.kind` provenance
/// described in the Strand design spec (§5).
public enum DataSourceKind: String, Sendable, Codable, Equatable, CaseIterable {
    case appleHealth
}

// MARK: - Generic health sample (Apple Health Record sink)

/// A single normalized Apple Health `<Record>` reading.
///
/// Timestamps are normalized to UTC `Date`s while the original UTC offset (in
/// minutes) is preserved in `tzOffsetMin`, matching the `hkSample` table shape
/// in the design spec (§5).
public struct HealthSample: Sendable, Equatable, Hashable {
    /// HealthKit type identifier, stripped of the `HKQuantityTypeIdentifier` /
    /// `HKCategoryTypeIdentifier` prefix (e.g. `HeartRate`, `SleepAnalysis`).
    public var type: String
    /// Numeric value, when the record is quantitative. `nil` for pure category
    /// records whose meaning lives in `valueString`.
    public var value: Double?
    /// Raw string value as it appeared in the export (category enum strings,
    /// or the textual numeric value). Always populated when present.
    public var valueString: String?
    /// Unit string from the record (e.g. `count/min`, `%`, `degC`). May be nil.
    public var unit: String?
    /// Start of the sample, normalized to UTC.
    public var start: Date
    /// End of the sample, normalized to UTC.
    public var end: Date
    /// Original UTC offset of the source timestamp, in minutes (e.g. `60` for
    /// `+0100`, `-300` for `-0500`).
    public var tzOffsetMin: Int
    /// `sourceName` attribute (the device/app that produced the record).
    public var sourceName: String?

    public init(
        type: String,
        value: Double?,
        valueString: String?,
        unit: String?,
        start: Date,
        end: Date,
        tzOffsetMin: Int,
        sourceName: String?
    ) {
        self.type = type
        self.value = value
        self.valueString = valueString
        self.unit = unit
        self.start = start
        self.end = end
        self.tzOffsetMin = tzOffsetMin
        self.sourceName = sourceName
    }

    /// Dedupe key per the spec: `type+startDate+endDate+sourceName+value`.
    /// Records nested in a `<Correlation>` also appear at top level; collapsing
    /// on this key removes the duplicates.
    public var dedupeKey: String {
        let v = valueString ?? value.map { String($0) } ?? ""
        return "\(type)|\(start.timeIntervalSince1970)|\(end.timeIntervalSince1970)|\(sourceName ?? "")|\(v)"
    }
}

// MARK: - Apple Health workout

/// A normalized Apple Health `<Workout>` element.
public struct HealthWorkout: Sendable, Equatable {
    /// `workoutActivityType`, stripped of the `HKWorkoutActivityType` prefix
    /// (e.g. `Running`, `FunctionalStrengthTraining`).
    public var activityType: String
    /// Total duration in seconds (from the `duration`/`durationUnit` attrs).
    public var durationS: Double?
    /// Total distance in metres, when present.
    public var distanceM: Double?
    /// Total active energy burned in kilocalories, when present.
    public var energyKcal: Double?
    public var start: Date
    public var end: Date
    public var tzOffsetMin: Int
    public var sourceName: String?

    public init(
        activityType: String,
        durationS: Double?,
        distanceM: Double?,
        energyKcal: Double?,
        start: Date,
        end: Date,
        tzOffsetMin: Int,
        sourceName: String?
    ) {
        self.activityType = activityType
        self.durationS = durationS
        self.distanceM = distanceM
        self.energyKcal = energyKcal
        self.start = start
        self.end = end
        self.tzOffsetMin = tzOffsetMin
        self.sourceName = sourceName
    }
}

// MARK: - Sleep stage interval

/// The canonical sleep stages Strand recognises from Apple Health
/// `HKCategoryValueSleepAnalysis*` values.
public enum SleepStage: String, Sendable, Equatable, CaseIterable {
    case inBed
    case asleepUnspecified   // legacy "Asleep"
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake
    case unknown

    /// Map a raw HealthKit `SleepAnalysis` category value string to a stage.
    /// Accepts both the modern `HKCategoryValueSleepAnalysis…` form and the
    /// legacy numeric/short forms.
    public static func from(rawValue raw: String) -> SleepStage {
        switch raw {
        case "HKCategoryValueSleepAnalysisInBed", "InBed", "0":
            return .inBed
        case "HKCategoryValueSleepAnalysisAsleep", "HKCategoryValueSleepAnalysisAsleepUnspecified", "Asleep", "1":
            return .asleepUnspecified
        case "HKCategoryValueSleepAnalysisAsleepCore", "AsleepCore", "3":
            return .asleepCore
        case "HKCategoryValueSleepAnalysisAsleepDeep", "AsleepDeep", "4":
            return .asleepDeep
        case "HKCategoryValueSleepAnalysisAsleepREM", "AsleepREM", "5":
            return .asleepREM
        case "HKCategoryValueSleepAnalysisAwake", "Awake", "2":
            return .awake
        default:
            return .unknown
        }
    }
}

/// A single contiguous sleep-stage interval from Apple Health.
public struct SleepStageInterval: Sendable, Equatable {
    public var stage: SleepStage
    public var start: Date
    public var end: Date
    public var tzOffsetMin: Int
    public var sourceName: String?

    public init(
        stage: SleepStage,
        start: Date,
        end: Date,
        tzOffsetMin: Int,
        sourceName: String?
    ) {
        self.stage = stage
        self.start = start
        self.end = end
        self.tzOffsetMin = tzOffsetMin
        self.sourceName = sourceName
    }
}

// MARK: - Import results & summary

/// Lightweight summary of an import: how many normalized rows were produced and
/// the overall date span they cover.
public struct ImportSummary: Sendable, Equatable {
    public var sourceKind: DataSourceKind
    public var recordCount: Int
    public var earliest: Date?
    public var latest: Date?
    /// Per-category counts (e.g. `["HeartRate": 1200, "SleepAnalysis": 88]`).
    public var countsByCategory: [String: Int]
    /// Number of XML spans dropped during a tolerant import: either a single
    /// hard parse error after which we kept the partial result (counts as 1), or
    /// the number of illegal-byte runs the pre-parse sanitizer scrubbed. Surfaced
    /// honestly in the UI so a partial import never silently looks complete.
    /// `0` for a fully clean import. Defaulted so older call sites stay source-compatible.
    public var skippedSpans: Int

    public init(
        sourceKind: DataSourceKind,
        recordCount: Int,
        earliest: Date?,
        latest: Date?,
        countsByCategory: [String: Int],
        skippedSpans: Int = 0
    ) {
        self.sourceKind = sourceKind
        self.recordCount = recordCount
        self.earliest = earliest
        self.latest = latest
        self.countsByCategory = countsByCategory
        self.skippedSpans = skippedSpans
    }
}

/// Normalized output of parsing an Apple Health export.
///
/// The export is aggregated to per-day rows **while parsing** (streaming), so
/// the result holds only O(days) `daily` aggregates — never the tens of millions
/// of raw `<Record>` samples a multi-year export contains (the old OOM path).
public struct AppleHealthImportResult: Sendable, Equatable {
    /// Per-day aggregates, merged across quantity samples and sleep, sorted by day.
    public var daily: [AppleDailyAggregate]
    public var workouts: [HealthWorkout]
    public var summary: ImportSummary

    public init(
        daily: [AppleDailyAggregate],
        workouts: [HealthWorkout],
        summary: ImportSummary
    ) {
        self.daily = daily
        self.workouts = workouts
        self.summary = summary
    }
}


// MARK: - Errors

public enum ImportError: Error, Equatable, Sendable, CustomStringConvertible {
    case fileNotFound(String)
    case notAZipOrFolder(String)
    case missingEntry(String)
    case xmlParseFailed(String)
    case emptyExport(String)

    public var description: String {
        switch self {
        case .fileNotFound(let p):    return "File not found: \(p)"
        case .notAZipOrFolder(let p): return "Expected a folder or .zip: \(p)"
        case .missingEntry(let e):    return "Required entry not found: \(e)"
        case .xmlParseFailed(let m):  return "XML parse failed: \(m)"
        case .emptyExport(let m):     return "Export contained no usable data: \(m)"
        }
    }
}
