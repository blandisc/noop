import Foundation

/// Sleep-sufficiency bands — the single source of truth for the "short / neutral / complete"
/// night classification. Just the pure thresholds (minutes → band); the es-MX copy lives in the
/// UI / `DailyBrief`, never here. Extracted for FER-1030 so the `Preparedness` sleep axis and the
/// Daily Brief bullet (and the `TodayView` "Dormiste bien" cut) all read the same numbers.
///
/// Thresholds are product-calibration knobs (FER-626), NOT clinical cut-offs.
public enum SleepBands {
    /// Short-night threshold (minutes). Below this, the sleep axis flags a concern.
    public static let shortMinutes: Double = 360   // < 6 h
    /// Complete-night threshold (minutes). At or above this, sleep is sufficient.
    public static let goodMinutes: Double = 420    // ≥ 7 h

    public enum Band: String, Sendable, Equatable {
        case short      // < shortMinutes
        case neutral    // in between
        case complete   // ≥ goodMinutes
    }

    public static func band(_ minutes: Double) -> Band {
        if minutes < shortMinutes { return .short }
        if minutes >= goodMinutes { return .complete }
        return .neutral
    }
}
