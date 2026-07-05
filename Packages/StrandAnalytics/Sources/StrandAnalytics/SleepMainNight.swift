import Foundation

// MARK: - "Main night" gate for schedule-regularity (FER-298)
//
// Both schedule-regularity engines — `SleepRegularity` (SD of the mid-sleep point) and
// `SleepRegularityIndex` (SRI, asleep/awake concordance 24 h apart) — measure how CONSISTENT the
// timing of the *main* sleep period is, night to night. A nap is a short daytime sleep that
// `SleepStager.detectSleep` keeps on purpose (#90); its mid-point sits ~11 h from the nocturnal
// mid-sleep, which is near anti-phase on the 24 h circle and would blow up the SD / tank the SRI
// (13 perfectly steady nights + one 2 h nap → SD 126.9 min, score 0). So a nap must NOT count as a
// "night" when scoring schedule regularity.
//
// Criterion (documented contract): a sleep period counts as a MAIN NIGHT only if it lasts at least
// `minDurationMinutes`; shorter sleeps are naps and are excluded. This is the issue's sanctioned
// "minimum duration" filter — the simplest rule that resolves the bug: naps are the only same-day
// extra sleep, and a duration floor removes them whether they share a day with a night or not. The
// threshold is a product-calibration boundary (same altitude as `worstMidSleepSwingMinutes`), not a
// clinical claim: 3 h cleanly separates a typical nap (≤ ~2 h) from a main sleep period. A genuinely
// ultra-short main sleep (< 3 h) is rare and isn't a stable schedule anchor anyway, so dropping it
// from the regularity read is acceptable.

public enum SleepMainNight {
    /// Minimum sleep duration (minutes) for a session to count as a "main night" rather than a nap.
    /// Public so the app layer can label a nap it excluded ("we ignored your 2 h nap") against the
    /// same threshold the engines use, instead of hardcoding 180 (FER-310).
    public static let minDurationMinutes = 180.0   // 3 h

    /// Does the `[startTs, endTs]` span (unix seconds) qualify as a main night (vs a nap)?
    /// Public so the app layer can share this exact predicate (e.g. `NightRhythmProvider`
    /// picking last night) instead of re-deriving the duration formula from the constant.
    public static func qualifies(startTs: Int, endTs: Int) -> Bool {
        Double(endTs - startTs) / 60.0 >= minDurationMinutes
    }
}
