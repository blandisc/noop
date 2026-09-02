import Foundation
import StrandModels

// MARK: - Sleep window as clock hours (FER-154)
//
// The DiurnalDial (CenitDesign, FER-134) draws the night's sleep band from a
// `SleepWindow { bedtime, wake }` in CLOCK HOURS (0...24). The store only keeps sleep
// sessions as epoch timestamps (`CachedSleepSession.startTs/endTs`); this converts the
// most recent night to LOCAL clock hours so TodayView (FER-135) can map it to a
// `SleepWindow` and inject it into the dial.
//
// Pure + deterministic: `now` and `calendar` are injected, so it never reads `Date()`
// for its logic and is fully testable. 100% offline — it only reads the sleep sessions
// already on-device (no new permission). The selection ("most recent night"), the
// freshness gate, and the epoch→clock conversion all live here (testable), leaving the
// view layer to do nothing but map the value into `SleepWindow`.

public enum SleepWindowClock {

    /// Bedtime / wake of the most recent sleep session as LOCAL clock hours (0...24, in the
    /// `calendar`'s time zone), or `nil` when there is no session — or the latest one ended
    /// more than `freshnessHours` before `now` (so a strap unworn for days doesn't surface a
    /// stale band). Does NOT wrap midnight: `bedtime` may be greater than `wake` (e.g. 23.25
    /// → 6.75); the dial wraps the arc itself, so the honest, unwrapped hours are returned.
    public static func recent(_ sessions: [CachedSleepSession],
                              now: Date,
                              calendar: Calendar = .current,
                              freshnessHours: Double = 36) -> (bedtime: Double, wake: Double)? {
        guard let latest = sessions.max(by: { $0.startTs < $1.startTs }) else { return nil }
        guard now.timeIntervalSince1970 - Double(latest.endTs) < freshnessHours * 3600 else { return nil }
        return (clockHour(latest.startTs, calendar), clockHour(latest.endTs, calendar))
    }

    /// Unix seconds → local clock hour (0...24) using the `calendar`'s time zone. Each instant
    /// resolves its own UTC offset, so a night spanning a DST change still converts correctly.
    static func clockHour(_ ts: Int, _ calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second],
                                        from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0 + Double(c.second ?? 0) / 3600.0
    }
}
