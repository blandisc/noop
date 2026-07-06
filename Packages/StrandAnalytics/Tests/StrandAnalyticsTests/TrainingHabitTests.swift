import XCTest
@testable import StrandAnalytics

final class TrainingHabitTests: XCTestCase {

    func testNilBelowMinSessions() {
        XCTAssertNil(TrainingHabit.window(startHours: [17.0]))
        XCTAssertNil(TrainingHabit.window(startHours: [17.0, 18.0]))
    }

    func testWindowCentersOnMedianWithSDSpread() {
        // Starts around 17:00 with a little spread.
        let w = TrainingHabit.window(startHours: [16.0, 17.0, 18.0])!
        XCTAssertEqual((w.start + w.end) / 2, 17.0, accuracy: 1e-9)   // symmetric about the median
        XCTAssertGreaterThan(w.end - w.start, 1.0)                    // 1 SD each side (SD == 1 here)
    }

    func testTightRoutineStillDrawsVisibleBand() {
        // All three at the same hour → SD 0, but the floor keeps a ±30-min band so it's drawable.
        let w = TrainingHabit.window(startHours: [18.0, 18.0, 18.0])!
        XCTAssertEqual(w.start, 17.5, accuracy: 1e-9)
        XCTAssertEqual(w.end,   18.5, accuracy: 1e-9)
    }

    func testClampedToDay() {
        let early = TrainingHabit.window(startHours: [0.2, 0.2, 0.2])!
        XCTAssertGreaterThanOrEqual(early.start, 0)
        let late = TrainingHabit.window(startHours: [23.8, 23.8, 23.8])!
        XCTAssertLessThanOrEqual(late.end, 24)
    }
}
