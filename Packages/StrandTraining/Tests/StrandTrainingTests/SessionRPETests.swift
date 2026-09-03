import XCTest
@testable import StrandTraining

/// Ola 1 · E2 — the suggested answer to «¿qué tan duro estuvo?».
final class SessionRPETests: XCTestCase {

    private func set(_ rpe: Double?, kind: SetKind = .work, done: Bool = true,
                     mode: SetMode = .standard) -> SetEntry {
        SetEntry(sessionId: "s", exerciseId: "e", position: 0, kind: kind, weightKg: 60, reps: 8,
                 done: done, ts: 0, rpe: rpe, mode: mode)
    }

    func testPrefillMeanOfDoneWorkSetsRoundedHalf() {
        // 8, 9, 9 → 8.666… → 8.5 (nearest half step of the row the user taps).
        XCTAssertEqual(SessionRPE.prefill(sets: [set(8), set(9), set(9)])!, 8.5, accuracy: 1e-9)
        // 8, 9 → 8.5 exactly.
        XCTAssertEqual(SessionRPE.prefill(sets: [set(8), set(9)])!, 8.5, accuracy: 1e-9)
        // 9, 9, 10 → 9.333… → 9.5
        XCTAssertEqual(SessionRPE.prefill(sets: [set(9), set(9), set(10)])!, 9.5, accuracy: 1e-9)
    }

    func testPrefillIgnoresWarmupDropAndUndone() {
        let sets = [set(6, kind: .warmup),           // the ramp is not the session
                    set(10, mode: .drop),            // a drop continues its mother set, lighter
                    set(10, done: false),            // never happened
                    set(8), set(8)]
        XCTAssertEqual(SessionRPE.prefill(sets: sets)!, 8, accuracy: 1e-9)
    }

    func testPrefillNilWithoutRPE() {
        XCTAssertNil(SessionRPE.prefill(sets: [set(nil), set(nil)]))
        XCTAssertNil(SessionRPE.prefill(sets: []))
        XCTAssertNil(SessionRPE.prefill(sets: [set(9, kind: .warmup)]))
        // A set with no rating is simply not in the mean — it never pulls it toward a default.
        XCTAssertEqual(SessionRPE.prefill(sets: [set(nil), set(9)])!, 9, accuracy: 1e-9)
    }

    func testPrefillStaysInsideTheRow() {
        XCTAssertEqual(SessionRPE.prefill(sets: [set(1), set(1)])!, SessionRPE.min, accuracy: 1e-9)
        XCTAssertEqual(SessionRPE.prefill(sets: [set(20), set(20)])!, SessionRPE.max, accuracy: 1e-9)
    }
}
