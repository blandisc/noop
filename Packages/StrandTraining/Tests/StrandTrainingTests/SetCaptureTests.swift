import XCTest
@testable import StrandTraining

final class SetCaptureTests: XCTestCase {

    func testWeightRepsKeepsWeightAndReps() {
        let f = SetCapture.fields(type: .weightReps, weightKg: 80, reps: 8, timeS: nil, distanceM: nil)
        XCTAssertEqual(f.weightKg, 80)
        XCTAssertEqual(f.reps, 8)
        XCTAssertNil(f.timeS)
        XCTAssertNil(f.distanceM)
    }

    func testWeightRepsDropsZeroes() {
        let f = SetCapture.fields(type: .weightReps, weightKg: 0, reps: 0, timeS: nil, distanceM: nil)
        XCTAssertNil(f.weightKg, "zero weight is «unset», not a real 0 kg")
        XCTAssertNil(f.reps)
    }

    func testBodyweightKeepsRepsAndOptionalLastre() {
        let loaded = SetCapture.fields(type: .bodyweight, weightKg: 10, reps: 8, timeS: nil, distanceM: nil)
        XCTAssertEqual(loaded.reps, 8)
        XCTAssertEqual(loaded.weightKg, 10, "the optional lastre persists")

        let bw = SetCapture.fields(type: .bodyweight, weightKg: 0, reps: 12, timeS: nil, distanceM: nil)
        XCTAssertEqual(bw.reps, 12)
        XCTAssertNil(bw.weightKg, "bodyweight only → no weight")
        XCTAssertNil(bw.timeS)
    }

    func testTimeKeepsOnlySeconds() {
        // A time set carries placeholder reps in the model — they must NOT persist.
        let f = SetCapture.fields(type: .time, weightKg: 0, reps: 8, timeS: 42, distanceM: nil)
        XCTAssertEqual(f.timeS, 42)
        XCTAssertNil(f.reps, "a time set persists no reps")
        XCTAssertNil(f.weightKg)
        XCTAssertNil(f.distanceM)
    }

    func testDistanceKeepsDistanceAndTime() {
        let f = SetCapture.fields(type: .distance, weightKg: 0, reps: 8, timeS: 750, distanceM: 2400)
        XCTAssertEqual(f.distanceM, 2400)
        XCTAssertEqual(f.timeS, 750)
        XCTAssertNil(f.reps, "a distance set persists no reps")
        XCTAssertNil(f.weightKg)
    }

    func testDistanceDropsZeroDistance() {
        let f = SetCapture.fields(type: .distance, weightKg: 0, reps: 0, timeS: 300, distanceM: 0)
        XCTAssertNil(f.distanceM, "zero distance is «unset»")
        XCTAssertEqual(f.timeS, 300)
    }
}
