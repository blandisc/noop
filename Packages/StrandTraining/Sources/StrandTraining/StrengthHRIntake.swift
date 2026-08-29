import Foundation

/// One accepted watch-pulse sample admitted into a live strength session (FER-226). `StrandTraining`
/// has zero dependencies (not even `BiometricStreams`), so this is a local, minimal shape — the app
/// layer maps it to `BiometricStreams.HRSample` (unix-seconds `ts`) before persisting via
/// `CenitStore.appendStrengthHR`. `ts` is ALREADY truncated to whole seconds (see `accept` below) —
/// it is exactly what will become the `strengthHrSample` primary key, so the pure rule and the DB
/// agree on what counts as "the same instant" before either one sees it.
public struct StrengthHRSample: Equatable, Sendable {
    public let bpm: Int
    public let ts: Date
    public init(bpm: Int, ts: Date) {
        self.bpm = bpm
        self.ts = ts
    }
}

/// The single admission rule for a raw watch pulse into a live strength session's HR buffer
/// (FER-226 — revives the capturer killed by FER-1003's band amputation). Pure so the rule is
/// unit-tested without a session/store.
public enum StrengthHRIntake {
    /// Physiologically plausible human HR range — outside this, the sample is noise (dropped watch
    /// contact, a stray zero, a decode glitch), not a real beat.
    public static let plausibleRange = 25...240

    /// - Parameters:
    ///   - bpm: the raw reading.
    ///   - ts: when the reading was sealed (on the iPhone, at receipt). Truncated to whole seconds
    ///     BEFORE the repeated-timestamp guard runs (FER-226 round 2, D4) — `strengthHrSample`'s
    ///     primary key is `(sessionId, ts)` at second precision, so two sub-second pulses that would
    ///     silently collide on `ON CONFLICT DO NOTHING` at the DB must already collide HERE, in the
    ///     pure rule, rather than diverge between the in-memory series (which kept both) and the
    ///     persisted one (which kept only the first).
    ///   - lastTs: the timestamp of the last sample this session already accepted, if any. ALSO
    ///     truncated internally before the comparison — a caller may hand back either the truncated
    ///     `StrengthHRSample.ts` this function returned last time, or a raw un-truncated `Date`; both
    ///     compare correctly.
    ///   - paused: whether the session is currently paused.
    /// - Returns: the sample to admit, or `nil` if it should be dropped.
    public static func accept(bpm: Int, ts: Date, lastTs: Date?, paused: Bool) -> StrengthHRSample? {
        guard !paused else { return nil }
        guard plausibleRange.contains(bpm) else { return nil }
        let truncated = Date(timeIntervalSince1970: ts.timeIntervalSince1970.rounded(.down))
        if let lastTs {
            let lastTruncated = Date(timeIntervalSince1970: lastTs.timeIntervalSince1970.rounded(.down))
            if lastTruncated == truncated { return nil }
        }
        return StrengthHRSample(bpm: bpm, ts: truncated)
    }
}
