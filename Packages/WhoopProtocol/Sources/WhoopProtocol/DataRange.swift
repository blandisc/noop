import Foundation

/// Validation of a GET_DATA_RANGE COMMAND_RESPONSE body — the band's retained-history window.
/// Pure wire-level scan (FER-756: moved from `BLEManager` so it's testable without CoreBluetooth).
public enum DataRange {
    /// Earliest unix a strap record could plausibly carry (≈2023-11-14, before any WHOOP 4 data this
    /// app would store). Words below this in a GET_DATA_RANGE body are not timestamps.
    public static let earliestUnix = 1_700_000_000

    /// The band's retained-history window from a GET_DATA_RANGE COMMAND_RESPONSE — but **validated**, not
    /// a raw u32 scan. The old code (`dataRangeNewestUnix`/`dataRangeOldestUnix`) kept any u32 LE word in
    /// a fixed nov-2023 → mar-2030 window and returned its min/max; with the WHOOP 4.0's unstable RTC that
    /// scooped up garbage — future dates (e.g. "2029-10-11") and single-point ranges (e.g. "mar 15, 2025 →
    /// mar 15, 2025") that don't match the real offload (FER-150). This scans the body once (data starts at
    /// frame[7], after [type,seq,cmd]) and returns a window ONLY when it's plausible:
    ///   - every word lies in [earliestUnix, now] — nothing in the future (small skew tolerance),
    ///   - at least two DISTINCT values bound it, so oldest < newest — never a collapsed single point.
    /// Returns nil otherwise, which the diagnostic renders as "—". `now` is injected for testability.
    public static func plausibleWindow(from frame: [UInt8], now: Int) -> (oldest: Int, newest: Int)? {
        guard frame.count > 7 else { return nil }
        let ceiling = now + 86_400   // 1-day tolerance absorbs benign RTC skew; still rejects year-future junk
        let body = Array(frame[7...])
        var oldest: Int? = nil, newest: Int? = nil, i = 0
        while i + 4 <= body.count {
            let w = Int(body[i]) | Int(body[i+1]) << 8 | Int(body[i+2]) << 16 | Int(body[i+3]) << 24
            if w >= earliestUnix && w <= ceiling {
                oldest = min(oldest ?? Int.max, w)
                newest = max(newest ?? 0, w)
            }
            i += 4
        }
        guard let oldest, let newest, oldest < newest else { return nil }
        return (oldest, newest)
    }
}
