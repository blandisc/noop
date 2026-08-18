import XCTest
@testable import StrandTraining

/// `RoutineSet.repsRangeTop` + `RoutineSet.repsRangeLabel` (E13/FER-94): the field is `nil` by
/// default on every existing call site (today's behavior, byte-for-byte), and the label composes
/// "piso-techo" only when the range is genuinely wider than the floor.
final class RoutineSetRepsRangeTests: XCTestCase {

    private func set(_ reps: Int?, top: Int? = nil) -> RoutineSet {
        RoutineSet(position: 0, kind: .work, reps: reps, weightKg: 60, repsRangeTop: top)
    }

    /// No floor (time/distance types never carry `reps`) → no label at all, regardless of `repsRangeTop`.
    func testNoFloorYieldsNoLabel() {
        XCTAssertNil(set(nil).repsRangeLabel)
        XCTAssertNil(set(nil, top: 12).repsRangeLabel)
    }

    /// `nil` `repsRangeTop` (today's behavior, and the default on every existing call site) → just the
    /// floor, exactly as it read before this field existed.
    func testNoTopYieldsFloorOnly() {
        XCTAssertEqual(set(8).repsRangeLabel, "8")
    }

    /// A top strictly greater than the floor → "piso-techo".
    func testTopAboveFloorYieldsRange() {
        XCTAssertEqual(set(8, top: 12).repsRangeLabel, "8-12")
    }

    /// Defensive: a top equal to or below the floor is invalid data (nothing writes this yet — the
    /// capture UI is E7/FER-88's) and must not crash or invert the range; it falls back to the floor.
    func testTopEqualToFloorFallsBackToFloor() {
        XCTAssertEqual(set(8, top: 8).repsRangeLabel, "8")
    }

    func testTopBelowFloorFallsBackToFloor() {
        XCTAssertEqual(set(8, top: 5).repsRangeLabel, "8")
    }

    /// `repsRangeTop` defaults to `nil` when omitted — every pre-E13 call site keeps compiling and
    /// keeps behaving exactly as before.
    func testDefaultsToNilWhenOmitted() {
        let s = RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60)
        XCTAssertNil(s.repsRangeTop)
        XCTAssertEqual(s.repsRangeLabel, "8")
    }
}
