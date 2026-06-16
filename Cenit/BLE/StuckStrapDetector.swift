import Foundation

/// Detects a "stuck strap": the strap reports records newer than ours (`strapNewestTs` from
/// GET_DATA_RANGE) AND our biometric data frontier (`ourFrontierTs` = max persisted HR ts; NOT the
/// strap_trim cursor, which climbs on empty ENDs while stuck) hasn't advanced for `stuckAfterSeconds`.
/// Comparing the two is what separates genuinely stuck from off-wrist / caught-up (strap not ahead of
/// us → no new data expected → never stuck). Pure + value-typed so it's trivially testable.
struct StuckStrapDetector {
    let stuckAfterSeconds: TimeInterval
    /// How far ahead the strap must be (seconds) before "frozen frontier" counts as behind, not noise.
    let behindGapSeconds: Int
    private var lastFrontierTs: Int?
    private var lastAdvanceWall: TimeInterval?

    init(stuckAfterSeconds: TimeInterval, behindGapSeconds: Int = 300) {
        self.stuckAfterSeconds = stuckAfterSeconds
        self.behindGapSeconds = behindGapSeconds
    }

    /// `strapNewestTs` = newest record the strap reports having (GET_DATA_RANGE). `ourFrontierTs` =
    /// newest record we've persisted. Stuck = behind (strap ahead by > behindGapSeconds) AND our
    /// frontier hasn't advanced for >= stuckAfterSeconds. Advancing → healthy; not-behind → caught up.
    mutating func observe(strapNewestTs: Int?, ourFrontierTs: Int?, now: TimeInterval) -> Bool {
        guard let strapNewest = strapNewestTs, let frontier = ourFrontierTs else { return false }
        guard let last = lastFrontierTs else {           // first observation: seed, not stuck
            lastFrontierTs = frontier; lastAdvanceWall = now; return false
        }
        if frontier > last {                              // progressing → healthy, reset the clock
            lastFrontierTs = frontier; lastAdvanceWall = now; return false
        }
        let behind = (strapNewest - frontier) > behindGapSeconds
        if !behind {                                      // caught up / off-wrist → not stuck
            lastAdvanceWall = now; return false
        }
        return (now - (lastAdvanceWall ?? now)) >= stuckAfterSeconds  // behind AND frozen → stuck
    }
}
