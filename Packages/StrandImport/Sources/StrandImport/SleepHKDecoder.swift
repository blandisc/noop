import Foundation
import CenitStore

/// FER-486 (F3 of the FER-483 epic) — the INVERSE of `SleepHKEncoder`.
///
/// Turns raw Apple-Health `sleepAnalysis` category samples (watchOS 9+ stages:
/// deep / REM / core / awake / inBed) into `CachedSleepSession` rows under
/// `deviceId = "apple-health"`, so the Detalle de Sueño can draw the SAME
/// per-epoch hypnogram for a night that came from Apple (Combined-without-band,
/// or Apple-Health-only) as it does for a strap night.
///
/// PURE by design: it takes a platform-agnostic `SleepHKSample` array (the same
/// descriptor `SleepHKEncoder` consumes) so the session-grouping, stage-mapping
/// and `stagesJSON` serialization are unit-testable on macOS without HealthKit.
/// `HealthKitBridge` (iOS-only) is the thin shell that runs the `HKSampleQuery`
/// and adapts each `HKCategorySample` into a `SleepHKSample`.
///
/// HKCategoryValueSleepAnalysis raw values are stable since iOS 16 / macOS 13
/// (developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis):
///   0 inBed · 1 asleepUnspecified · 2 awake · 3 asleepCore · 4 asleepDeep · 5 asleepREM.
public enum SleepHKDecoder {

    // MARK: - HK value → NOOP stage

    /// Maps an `HKCategoryValueSleepAnalysis` raw value to a NOOP stage string
    /// (`"deep" | "rem" | "light" | "wake"`), or `nil` for values that carry no
    /// stage timeline — `inBed` (0) is an envelope, not a stage, so it is dropped
    /// (the session span already covers in-bed). `asleepUnspecified` (1) and
    /// `asleepCore` (3) both fold to `"light"` (NOOP has no separate "asleep,
    /// stage unknown" class), mirroring `SleepHKEncoder` and `collectSleep`.
    public static func stage(forHKValue value: Int) -> String? {
        switch value {
        case SleepHKEncoder.asleepDeepValue: return "deep"   // 4
        case SleepHKEncoder.asleepREMValue:  return "rem"    // 5
        case SleepHKEncoder.asleepCoreValue: return "light"  // 3
        case 1:                              return "light"  // asleepUnspecified
        case SleepHKEncoder.awakeValue:      return "wake"   // 2
        case SleepHKEncoder.inBedValue:      return nil      // 0 — envelope, not a stage
        default:                             return nil
        }
    }

    // MARK: - Samples → sessions

    /// Group sleep stage samples into one `CachedSleepSession` per night and
    /// serialize each night's stage timeline to the `[{start,end,stage}]`
    /// `stagesJSON` the hypnogram reads.
    ///
    /// SESSIONIZATION (gap-based): samples are sorted by start; a gap of more
    /// than `sessionGapSeconds` between the running session end and the next
    /// sample's start opens a NEW session. The default 1 h (3600 s) follows the
    /// official WHOOP/Apple convention that sleep blocks separated by a long
    /// awake span are distinct nights (a brief 3–4 a.m. awakening keeps one
    /// night; an afternoon nap 8 h later is its own session). `inBed`-only
    /// envelopes still extend the running span (so a night that is all `inBed`
    /// with one `asleepCore` block is one session) but contribute no segment.
    ///
    /// A session is emitted only if it has at least one real stage segment
    /// (`stagesJSON` non-empty) — a span with only `inBed` (no Apple stage data,
    /// e.g. a manual "in bed" entry) is dropped, matching the hypnogram's
    /// `intervals.count >= 2` gate. `restingHr` / `avgHrv` / `efficiency` are
    /// left `nil` — Apple's sleepAnalysis carries no per-session HR/HRV, and the
    /// daily HRV/RHR already land in `dailyMetric` via `collectSleep`'s siblings.
    ///
    /// - Parameter sessionGapSeconds: max awake gap kept inside one session.
    public static func sessions(
        from samples: [SleepHKSample], sessionGapSeconds: Int = 3600
    ) -> [CachedSleepSession] {
        // Normalize to integer unix seconds, keep only well-formed spans, sort by start.
        struct Span { let start: Int; let end: Int; let hkValue: Int }
        let spans: [Span] = samples.compactMap { s in
            let a = Int(s.start.timeIntervalSince1970)
            let b = Int(s.end.timeIntervalSince1970)
            return b > a ? Span(start: a, end: b, hkValue: s.hkValue) : nil
        }
        .sorted { $0.start < $1.start }
        guard !spans.isEmpty else { return [] }

        // Accumulate one bucket per night.
        struct Bucket { var start: Int; var end: Int; var segs: [(Int, Int, String)] }
        var buckets: [Bucket] = []
        for span in spans {
            if var last = buckets.last, span.start - last.end <= sessionGapSeconds {
                last.end = max(last.end, span.end)
                if let st = stage(forHKValue: span.hkValue) { last.segs.append((span.start, span.end, st)) }
                buckets[buckets.count - 1] = last
            } else {
                var b = Bucket(start: span.start, end: span.end, segs: [])
                if let st = stage(forHKValue: span.hkValue) { b.segs.append((span.start, span.end, st)) }
                buckets.append(b)
            }
        }

        return buckets.compactMap { b in
            guard !b.segs.isEmpty else { return nil }            // inBed-only → no hypnogram, drop
            let json = encodeSegments(b.segs.sorted { $0.0 < $1.0 })
            return CachedSleepSession(startTs: b.start, endTs: b.end, efficiency: nil,
                                      restingHr: nil, avgHrv: nil, stagesJSON: json)
        }
    }

    // MARK: - stagesJSON

    /// Encodable mirror of `StrandAnalytics.StageSegment` — kept local so this
    /// stays in `StrandImport` (which does NOT depend on StrandAnalytics) while
    /// emitting the byte-identical `[{start,end,stage}]` shape `encodeStages`
    /// writes and `SleepDetailScreen.decodeSegments` reads.
    private struct StageSegmentDTO: Encodable {
        let start: Int; let end: Int; let stage: String
    }

    private static func encodeSegments(_ segs: [(Int, Int, String)]) -> String? {
        let dto = segs.map { StageSegmentDTO(start: $0.0, end: $0.1, stage: $0.2) }
        guard let data = try? JSONEncoder().encode(dto) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
