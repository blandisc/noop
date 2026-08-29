import Foundation

/// One accepted watch-pulse sample admitted into a live strength session (FER-226). `StrandTraining`
/// has zero dependencies (not even `BiometricStreams`), so this is a local, minimal shape — the app
/// layer maps it to `BiometricStreams.HRSample` (unix-seconds `ts`) before persisting via
/// `CenitStore.appendStrengthHR`.
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
    ///   - ts: when the reading was sealed (on the iPhone, at receipt).
    ///   - lastTs: the timestamp of the last sample this session already accepted, if any.
    ///   - paused: whether the session is currently paused.
    /// - Returns: the sample to admit, or `nil` if it should be dropped.
    public static func accept(bpm: Int, ts: Date, lastTs: Date?, paused: Bool) -> StrengthHRSample? {
        guard !paused else { return nil }
        guard plausibleRange.contains(bpm) else { return nil }
        if let lastTs, lastTs == ts { return nil }
        return StrengthHRSample(bpm: bpm, ts: ts)
    }
}
