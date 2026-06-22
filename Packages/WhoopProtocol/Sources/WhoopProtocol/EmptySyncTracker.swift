import Foundation

/// Counts CONSECUTIVE completed historical-offload sessions that banked **no sensor rows** — the signal
/// `BackfillPolicy`'s empty-streak backoff reads to stop re-offloading an off-wrist / not-banking strap
/// every 90 s (FER-481). A strap off the wrist still emits EVENT packets ~every 90 s, each of which would
/// otherwise kick a console-only offload that persists nothing and drains both batteries; once the streak
/// passes `BackfillPolicy.emptyBackoffThreshold` the automatic floors stretch.
///
/// **What counts.** Only a COMPLETED session (`HISTORY_COMPLETE` / caught-up) is recorded — a timeout /
/// session-cap close is an unhealthy link, not a confirmed-empty strap, so the caller never feeds it here.
/// `rowsPersisted == 0` extends the streak; the first session that banks a real biometric row resets it to
/// 0, so baseline cadence resumes instantly the moment the strap starts handing over data again.
///
/// Pure + value-typed (no CoreBluetooth / I/O), sibling of `CaughtUpDetector` / `DrainContinuationPolicy`,
/// so it's unit-tested without a strap and relocatable to the planned orchestration package (FER-101).
public struct EmptySyncTracker: Equatable, Sendable {
    public private(set) var streak: Int

    public init() { self.streak = 0 }

    /// Record a COMPLETED offload session. `rowsPersisted` = biometric rows it banked. Zero extends the
    /// empty streak; any real row resets it to 0. Returns the updated streak (for convenient logging).
    @discardableResult
    public mutating func record(rowsPersisted: Int) -> Int {
        streak = rowsPersisted > 0 ? 0 : streak + 1
        return streak
    }
}
