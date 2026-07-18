import Foundation

// ActivityCostInputs.swift — turn raw tagged sessions into the day-keyed input
// `ActivityCostEngine` expects. Pure, deterministic, DB-free.
//
// The engine aligns a session day D with the next morning's Charge through
// `CorrelationEngine.shiftDay`, which is pure string arithmetic on "yyyy-MM-dd"
// in a fixed UTC calendar (it just adds calendar days to the key). That alignment
// is therefore correct ONLY if a session's day-key and the recovery day-keys were
// built in the SAME calendar. `recoveryByDay` is keyed by `DailyMetric.day` (the
// device's local calendar), so each session's start timestamp must be mapped to a
// day-key in that same local `timeZone` — pass the timezone the recovery keys were
// built in. Tests pin it for determinism.
//
// This stays agnostic of CenitStore and of how a workout was tagged: the app layer
// filters sources (e.g. drops auto-detected bouts) and cleans the sport name before
// handing sessions here, so the pure package never imports the persistence types.

public enum ActivityCostInputs {

    /// A workout reduced to what the cost engine needs: when it started (unix seconds)
    /// and its display sport name (already source-filtered and name-cleaned upstream).
    public struct Session: Equatable, Sendable {
        public let startTs: Int
        public let sport: String
        public init(startTs: Int, sport: String) {
            self.startTs = startTs
            self.sport = sport
        }
    }

    /// Group sessions into `[sport: Set<day-key>]`, mapping each `startTs` to a
    /// "yyyy-MM-dd" key in `timeZone`. A `Set` collapses same-day duplicates of a sport
    /// (e.g. the same run imported from both WHOOP and Apple Health, or a morning and an
    /// evening run) to a single day — exactly the de-duplication the engine assumes.
    /// The key format matches `CorrelationEngine.shiftDay`'s output so D→D+1 lines up.
    public static func activityDaysBySport(_ sessions: [Session],
                                           timeZone: TimeZone) -> [String: Set<String>] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var out: [String: Set<String>] = [:]
        for s in sessions {
            let date = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            let c = cal.dateComponents([.year, .month, .day], from: date)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let key = String(format: "%04d-%02d-%02d", y, m, d)
            out[s.sport, default: []].insert(key)
        }
        return out
    }
}
