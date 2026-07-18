import Foundation

/// The canonical `yyyy-MM-dd` day-key contract for the `day` column this package stores (FER-754).
///
/// Two zones, on purpose — the same split `Repository` documented (FER-325 / FER-630):
/// - **Write side (`local`)**: keys are minted in the device's local zone, so "today" means the
///   user's civil day. This is how every `DailyMetric.day` row is stored.
/// - **Read side (`parseUTC` / `utc`)**: charts parse keys back in UTC for DST-stable positions,
///   and format chart dates back with the exact inverse. Mixing the two directions is the
///   phantom-row / day-behind class of bug (FER-224/226, FER-630).
///
/// Screens that need a `DateFormatter` object outright reuse `localFormatter` / `utcFormatter`
/// instead of re-creating private copies (several copies had drifted: missing `en_US_POSIX`,
/// or parsing in local zone what the canon parses in UTC). `DateFormatter` is thread-safe.
public enum DayKey {
    /// Device-local `yyyy-MM-dd` formatter — the WRITE side of the day-key contract.
    public static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// UTC `yyyy-MM-dd` formatter — the READ side (DST-stable chart positions) and its inverse.
    public static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// A Gregorian calendar pinned to UTC — for whole-day arithmetic over UTC-parsed keys
    /// (one fixed 24 h step; UTC has no DST).
    public static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// `yyyy-MM-dd` in the device's local zone — how `day` keys are minted and stored.
    public static func local(_ date: Date) -> String { localFormatter.string(from: date) }

    /// Parse a stored key to a Date at UTC midnight — how charts anchor day positions.
    public static func parseUTC(_ s: String) -> Date? { utcFormatter.date(from: s) }

    /// Format a UTC-anchored chart date back to its key — the exact inverse of `parseUTC`.
    public static func utc(_ date: Date) -> String { utcFormatter.string(from: date) }
}
