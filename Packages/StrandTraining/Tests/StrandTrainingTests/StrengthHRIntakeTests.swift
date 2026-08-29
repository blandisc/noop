import XCTest
@testable import StrandTraining

final class StrengthHRIntakeTests: XCTestCase {
    func testRejectsWhenPaused() {
        let ts = Date()
        XCTAssertNil(StrengthHRIntake.accept(bpm: 120, ts: ts, lastTs: nil, paused: true))
    }

    func testRejectsBpmOutOfRange() {
        let ts = Date()
        XCTAssertNil(StrengthHRIntake.accept(bpm: 24, ts: ts, lastTs: nil, paused: false))
        XCTAssertNil(StrengthHRIntake.accept(bpm: 241, ts: ts, lastTs: nil, paused: false))
        XCTAssertNotNil(StrengthHRIntake.accept(bpm: 25, ts: ts, lastTs: nil, paused: false))
        XCTAssertNotNil(StrengthHRIntake.accept(bpm: 240, ts: ts, lastTs: nil, paused: false))
    }

    func testRejectsRepeatedTimestamp() {
        let ts = Date()
        XCTAssertNil(StrengthHRIntake.accept(bpm: 120, ts: ts, lastTs: ts, paused: false))
    }

    func testAcceptsRepeatedBpmWithDistinctTimestamp() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = t0.addingTimeInterval(1)
        let sample = StrengthHRIntake.accept(bpm: 120, ts: t1, lastTs: t0, paused: false)
        XCTAssertEqual(sample, StrengthHRSample(bpm: 120, ts: t1))
    }

    // MARK: - D4 (FER-226 round 2): second-precision truncation happens BEFORE the guard, so a
    // sub-second collision is rejected in this pure rule — never silently at the DB's `ON CONFLICT
    // DO NOTHING`, which would leave the in-memory series (kept both) and the persisted one (kept
    // only the first) disagreeing after a crash-restore.

    /// Two pulses within the same whole second: the second is rejected here, in `accept`, not merely
    /// discarded later by the `strengthHrSample` primary key.
    func testRejectsSecondPulseWithinTheSameWholeSecond() {
        let base = Date(timeIntervalSince1970: 1_000.2)
        let sameSecondLater = Date(timeIntervalSince1970: 1_000.9)   // still floor()==1000
        let first = StrengthHRIntake.accept(bpm: 118, ts: base, lastTs: nil, paused: false)
        XCTAssertNotNil(first)
        let second = StrengthHRIntake.accept(bpm: 121, ts: sameSecondLater, lastTs: first?.ts, paused: false)
        XCTAssertNil(second, "a pulse landing in the same truncated second as the last accepted one must be rejected")
    }

    /// The returned sample's `ts` is truncated DOWN to whole seconds — it is exactly what will become
    /// the `strengthHrSample` primary key, so the pure rule and the DB must agree bit-for-bit.
    func testAcceptedSampleTimestampIsTruncatedToWholeSeconds() {
        let sample = StrengthHRIntake.accept(bpm: 120, ts: Date(timeIntervalSince1970: 1_000.75),
                                             lastTs: nil, paused: false)
        XCTAssertEqual(sample?.ts, Date(timeIntervalSince1970: 1_000))
    }

    /// A `lastTs` that is itself un-truncated (e.g. a raw `Date()` from a caller that hasn't adopted
    /// the truncated contract) still compares correctly — `accept` normalizes both sides internally.
    func testRejectsRepeatedTimestampEvenWhenLastTsIsUnTruncated() {
        let untruncatedLast = Date(timeIntervalSince1970: 1_000.1)
        let sameSecond = Date(timeIntervalSince1970: 1_000.8)
        XCTAssertNil(StrengthHRIntake.accept(bpm: 120, ts: sameSecond, lastTs: untruncatedLast, paused: false))
    }

    /// Crossing into the NEXT whole second is still accepted — the truncation rejects sub-second
    /// collisions, not legitimate consecutive readings.
    func testAcceptsPulseInTheNextWholeSecond() {
        let first = StrengthHRIntake.accept(bpm: 120, ts: Date(timeIntervalSince1970: 1_000.9),
                                            lastTs: nil, paused: false)
        let second = StrengthHRIntake.accept(bpm: 121, ts: Date(timeIntervalSince1970: 1_001.1),
                                             lastTs: first?.ts, paused: false)
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.ts, Date(timeIntervalSince1970: 1_001))
    }
}
