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
        let t0 = Date()
        let t1 = t0.addingTimeInterval(1)
        let sample = StrengthHRIntake.accept(bpm: 120, ts: t1, lastTs: t0, paused: false)
        XCTAssertEqual(sample, StrengthHRSample(bpm: 120, ts: t1))
    }
}
