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

    // MARK: - `normalizedRepsRangeTop` (R4, FER-166 ronda 2 — invariante piso ≤ techo)
    //
    // `repsRangeLabel` ya TOLERABA un techo inválido con un fallback de lectura (arriba). R4 va más
    // lejos: la escritura nunca debe PERSISTIR un rango invertido en primer lugar — ni por un
    // instante, ni espejado a otras rondas de una superserie. Esta es la regla pura que
    // `RoutineSheetKeypad.swift` llama en cada escritura de piso/techo, y que `RoutineSheet.load()`
    // aplica una vez sobre datos legados que pudieran traer un rango roto de antes de este fix.

    /// Un techo mayor al piso es válido tal cual.
    func testNormalizeKeepsValidTop() {
        XCTAssertEqual(RoutineSet.normalizedRepsRangeTop(reps: 8, top: 12), 12)
    }

    /// Techo igual al piso → no es un rango, se normaliza a nil (piso único).
    func testNormalizeTopEqualToFloorBecomesNil() {
        XCTAssertNil(RoutineSet.normalizedRepsRangeTop(reps: 8, top: 8))
    }

    /// Techo por debajo del piso (el "10-8" invertido) → nil, nunca se persiste invertido.
    func testNormalizeTopBelowFloorBecomesNil() {
        XCTAssertNil(RoutineSet.normalizedRepsRangeTop(reps: 8, top: 5))
    }

    /// Sin techo tecleado → nil pasa derecho.
    func testNormalizeNilTopStaysNil() {
        XCTAssertNil(RoutineSet.normalizedRepsRangeTop(reps: 8, top: nil))
    }

    /// Sin piso (tipos sin reps) → un techo no tiene con qué compararse; se normaliza a nil en vez
    /// de dejar un techo huérfano que ninguna lectura puede usar.
    func testNormalizeNilFloorClearsTop() {
        XCTAssertNil(RoutineSet.normalizedRepsRangeTop(reps: nil, top: 12))
    }
}
