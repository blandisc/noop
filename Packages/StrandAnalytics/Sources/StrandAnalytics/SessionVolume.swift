import Foundation

// SessionVolume.swift — the all-time best training volume in a single SESSION (FER-149).
//
// Volume (Σ weight × reps) is standard training-load bookkeeping (Baechle & Earle, NSCA, 3rd ed.,
// 2008), not a novel formula — this file just states the ONE rule that determines what counts as
// "a session": grouped by `sessionId`, never by calendar day. Two sessions logged the same day (a
// morning and an evening one) are two separate records, not a merged one — merging them would let a
// day's leftover top-set inflate a number nobody actually moved in one sitting.
//
// Pure & database-free, same shape as `OneRepMax`: primitives in, a plain result out. The caller
// (the exercise detail screen) reads work sets from CenitStore and maps them to tuples.

public enum SessionVolume {

    /// The winning session's identity + total tonnage.
    public struct Best: Sendable, Equatable {
        public let sessionId: String
        /// The most recent timestamp among the session's sets (its tie-break identity).
        public let startTs: Int
        public let volumeKg: Double
        public init(sessionId: String, startTs: Int, volumeKg: Double) {
            self.sessionId = sessionId; self.startTs = startTs; self.volumeKg = volumeKg
        }
    }

    /// The heaviest total volume any ONE session moved — grouped by `sessionId`, never by day. A tie
    /// is broken by recency (the more recent session wins); if that ALSO ties (same volume, same
    /// last `startTs` — two distinct sessions logged in the same instant), the higher `sessionId`
    /// wins as a final, arbitrary-but-fixed tiebreak, so the result is fully deterministic regardless
    /// of the caller's (or `Dictionary`'s) iteration order. `nil` when no session's volume is
    /// positive (e.g. an all-zero or empty history) — the caller hides the record row rather than
    /// showing "0 kg".
    public static func best<S: Sequence>(_ sets: S) -> Best?
        where S.Element == (sessionId: String, startTs: Int, weightKg: Double, reps: Int) {
        var bySession: [String: (startTs: Int, volumeKg: Double)] = [:]
        for s in sets {
            var entry = bySession[s.sessionId] ?? (s.startTs, 0)
            entry.volumeKg += s.weightKg * Double(s.reps)
            entry.startTs = Swift.max(entry.startTs, s.startTs)
            bySession[s.sessionId] = entry
        }
        var winner: Best?
        for (id, entry) in bySession {
            guard entry.volumeKg > 0 else { continue }
            if let w = winner {
                if entry.volumeKg < w.volumeKg { continue }
                if entry.volumeKg == w.volumeKg {
                    if entry.startTs < w.startTs { continue }
                    if entry.startTs == w.startTs && id <= w.sessionId { continue }
                }
            }
            winner = Best(sessionId: id, startTs: entry.startTs, volumeKg: entry.volumeKg)
        }
        return winner
    }
}
