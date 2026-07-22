import Foundation

// AnalyticsEngine.swift — day-key + stage-JSON helpers.
//
// The per-day orchestration path (`analyzeDay`) was retired with the WHOOP band
// (épico «la banda nunca existió»): the shipping app is Apple-only and never
// called it. What remains here are the small PURE helpers that outlived that
// path and are still used across the app + packages:
//   • civil-day keying (`dayString`, `localMidnight`, `futureLocalDaysToPrune`)
//   • the sleep-stage JSON codec (`encodeStages` / `decodeStages`).

public enum AnalyticsEngine {

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Format a unix-seconds timestamp as a `YYYY-MM-DD` day string in a wall-clock zone
    /// `tzOffsetSeconds` east of UTC. Default 0 = UTC, which keeps pure-function callers and tests on
    /// UTC. The device's LOCAL civil day is obtained by shifting the instant by the offset and
    /// formatting in UTC — the same trick the WHOOP CSV import used with `tzOffsetMin`, so day-keys stay
    /// deterministic and dedup-stable across sources. (FER-226: `dailyMetric.day` is the local civil day.)
    public static func dayString(_ ts: Int, tzOffsetSeconds: Int = 0) -> String {
        isoDay.string(from: Date(timeIntervalSince1970: TimeInterval(ts + tzOffsetSeconds)))
    }

    /// Unix-seconds instant of LOCAL midnight for the civil day `ts` falls on, in a wall-clock zone
    /// `tzOffsetSeconds` east of UTC. Used as the inclusive lower bound of the additive-totals window
    /// (steps + calories), replacing the old UTC-midnight floor. Pure; default 0 = UTC midnight. (FER-226)
    public static func localMidnight(_ ts: Int, tzOffsetSeconds: Int = 0) -> Int {
        let local = ts + tzOffsetSeconds
        let flooredLocal = local - ((local % 86_400) + 86_400) % 86_400
        return flooredLocal - tzOffsetSeconds
    }

    /// Which `stored` day-keys fall strictly AFTER `today` (the device's local civil day) and were NOT
    /// (re)written this run — the spurious "future-in-local" rows the one-time UTC→local re-bucket
    /// prunes (FER-226). Pure so the prune's selection is testable without the app/store. Past and
    /// today rows are never returned, so a day that couldn't be recomputed keeps its row (no data loss);
    /// `written` excludes a freshly-written future row defensively (the re-group never writes future).
    public static func futureLocalDaysToPrune(stored: [String], today: String,
                                              written: Set<String>) -> [String] {
        stored.filter { $0 > today && !written.contains($0) }
    }

    /// JSON-encode stage segments to the verbatim array shape CachedSleepSession stores.
    static func encodeStages(_ stages: [StageSegment]) -> String? {
        guard let data = try? JSONEncoder().encode(stages) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode a COMPUTED `stagesJSON` (the `[{start,end,stage}]` segment array `encodeStages` writes)
    /// back to `[StageSegment]`. Returns nil for the IMPORTED dict-of-totals form (no per-segment
    /// timeline) or empty/malformed input, so callers fall back to a coarse `[start,end]` interval.
    /// The counterpart of `encodeStages`; reused by SleepView and the SRI orchestration (FER-214).
    public static func decodeStages(_ json: String?) -> [StageSegment]? {
        guard let json, let data = json.data(using: .utf8),
              let segs = try? JSONDecoder().decode([StageSegment].self, from: data),
              !segs.isEmpty else { return nil }
        return segs
    }
}
