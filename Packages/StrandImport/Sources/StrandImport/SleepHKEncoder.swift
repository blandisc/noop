import Foundation
import WhoopStore

/// Descriptor for a single Apple Health sleep sample — platform-agnostic so the
/// mapping logic is testable on macOS without a HealthKit import.
public struct SleepHKSample: Equatable {
    public let hkValue: Int       // HKCategoryValueSleepAnalysis raw value
    public let start: Date
    public let end: Date
    public let dedupeKey: String  // value for HKMetadataKeyExternalUUID

    // Explicit public init — a public struct's memberwise init is internal, so `HealthKitBridge`
    // (CenitApp module) couldn't construct these from `HKCategorySample`s without it (FER-486).
    public init(hkValue: Int, start: Date, end: Date, dedupeKey: String) {
        self.hkValue = hkValue; self.start = start; self.end = end; self.dedupeKey = dedupeKey
    }
}

/// Maps `CachedSleepSession` records from WhoopStore into `SleepHKSample` descriptors
/// that `HealthKitBridge` (iOS-only) writes to `HKHealthStore`.
///
/// Keeping this encoder separate from the bridge means the stage-mapping and
/// key-generation logic can be unit-tested on macOS without `HKHealthStore`.
///
/// HKCategoryValueSleepAnalysis raw values used here are stable since iOS 16 / macOS 13
/// and documented at developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis.
public enum SleepHKEncoder {

    // Raw values for HKCategoryValueSleepAnalysis (stable since iOS 16 / macOS 13).
    public static let inBedValue: Int      = 0  // .inBed
    public static let awakeValue: Int      = 2  // .awake
    public static let asleepCoreValue: Int = 3  // .asleepCore  (NREM light)
    public static let asleepDeepValue: Int = 4  // .asleepDeep
    public static let asleepREMValue: Int  = 5  // .asleepREM

    /// Maps a WHOOP stage string to the matching `HKCategoryValueSleepAnalysis` raw value.
    public static func hkValue(forStage stage: String) -> Int {
        switch stage {
        case "deep":  return asleepDeepValue
        case "rem":   return asleepREMValue
        case "wake":  return awakeValue
        case "light": return asleepCoreValue
        default:      return asleepCoreValue
        }
    }

    /// Converts sleep sessions to HK sample descriptors.
    ///
    /// Each session contributes one `.inBed` sample (full span) plus one sample per
    /// stage segment decoded from `stagesJSON`. Sessions with `end ≤ start` and
    /// segments with `end ≤ start` are skipped silently.
    public static func samples(
        from sessions: [CachedSleepSession], deviceId: String
    ) -> [SleepHKSample] {
        var result: [SleepHKSample] = []
        for session in sessions {
            let sStart = Date(timeIntervalSince1970: TimeInterval(session.startTs))
            let sEnd   = Date(timeIntervalSince1970: TimeInterval(session.endTs))
            guard sEnd > sStart else { continue }

            let inBedKey = "noop:\(deviceId):sleep:inBed:\(session.startTs)"
            result.append(SleepHKSample(
                hkValue: inBedValue, start: sStart, end: sEnd, dedupeKey: inBedKey))

            guard let json = session.stagesJSON,
                  let data = json.data(using: .utf8),
                  let segs = try? JSONDecoder().decode([SleepSegment].self, from: data)
            else { continue }

            for seg in segs {
                let segStart = Date(timeIntervalSince1970: TimeInterval(seg.start))
                let segEnd   = Date(timeIntervalSince1970: TimeInterval(seg.end))
                guard segEnd > segStart else { continue }
                let segKey = "noop:\(deviceId):sleep:\(session.startTs):\(seg.start)"
                result.append(SleepHKSample(
                    hkValue: hkValue(forStage: seg.stage),
                    start: segStart, end: segEnd, dedupeKey: segKey))
            }
        }
        return result
    }

    // Local mirror of StrandAnalytics.StageSegment — avoids a cross-package dep.
    // Field names and types match the JSON written by AnalyticsEngine.encodeStages().
    private struct SleepSegment: Decodable {
        let start: Int
        let end: Int
        let stage: String
    }
}
