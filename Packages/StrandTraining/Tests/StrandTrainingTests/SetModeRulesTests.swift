import XCTest
@testable import StrandTraining

/// FER-327 · E6 — la tabla 3×4 de `SetMode.counts(for:)` es EL oráculo de qué cuenta una serie. Si
/// alguien la cambia sin querer (o la re-deriva en otro lado), estas pruebas caen: la tabla completa
/// está escrita aquí a mano, celda por celda, no generada desde la misma fuente que prueba.
final class SetModeRulesTests: XCTestCase {

    /// Las 12 celdas: standard sí/sí/sí/sí · amrap sí/sí/sí/sí · drop sí/no/no/no.
    func testTheFullThreeByFourTable() {
        let expected: [SetMode: [SetRule: Bool]] = [
            .standard: [.volume: true, .progression: true, .records: true, .oneRepMax: true],
            .amrap:    [.volume: true, .progression: true, .records: true, .oneRepMax: true],
            .drop:     [.volume: true, .progression: false, .records: false, .oneRepMax: false],
        ]
        XCTAssertEqual(Set(SetMode.allCases), Set(expected.keys), "un modo nuevo sin fila en la tabla")
        for mode in SetMode.allCases {
            for rule in SetRule.allCases {
                XCTAssertEqual(mode.counts(for: rule), expected[mode]![rule]!,
                               "\(mode.rawValue) × \(rule.rawValue)")
            }
        }
    }

    /// Un drop suma volumen (movió kilos de verdad) y nada más.
    func testDropOnlyCountsTowardVolume() {
        XCTAssertTrue(SetMode.drop.counts(for: .volume))
        for rule in SetRule.allCases where rule != .volume {
            XCTAssertFalse(SetMode.drop.counts(for: rule), "el drop no debe alimentar \(rule.rawValue)")
        }
    }

    /// El calentamiento sigue decidiéndose por `SetKind`, no por `SetMode`: false en las CUATRO reglas
    /// aunque su modo sea `.standard`.
    func testWarmupCountsForNothingRegardlessOfMode() {
        for mode in SetMode.allCases {
            let warmup = SetEntry(sessionId: "s", exerciseId: "e", position: 0, kind: .warmup,
                                  weightKg: 60, reps: 8, done: true, ts: 0, mode: mode)
            for rule in SetRule.allCases {
                XCTAssertFalse(warmup.counts(for: rule),
                               "un calentamiento (\(mode.rawValue)) no cuenta para \(rule.rawValue)")
            }
        }
    }

    /// Una serie NO hecha no cuenta para nada, aunque sea de trabajo y estándar.
    func testUndoneSetCountsForNothing() {
        let pending = SetEntry(sessionId: "s", exerciseId: "e", position: 0, kind: .work,
                               weightKg: 80, reps: 8, done: false, ts: 0)
        for rule in SetRule.allCases { XCTAssertFalse(pending.counts(for: rule)) }
    }

    /// La composición completa en `SetEntry`: trabajo + hecha + el modo.
    func testSetEntryCountsComposesKindDoneAndMode() {
        let drop = SetEntry(sessionId: "s", exerciseId: "e", position: 1, kind: .work,
                            weightKg: 64, reps: 9, done: true, ts: 0, mode: .drop)
        XCTAssertTrue(drop.counts(for: .volume))
        XCTAssertFalse(drop.counts(for: .progression))
        XCTAssertFalse(drop.counts(for: .records))
        XCTAssertFalse(drop.counts(for: .oneRepMax))

        let amrap = SetEntry(sessionId: "s", exerciseId: "e", position: 2, kind: .work,
                             weightKg: 80, reps: 11, done: true, ts: 0, mode: .amrap)
        for rule in SetRule.allCases { XCTAssertTrue(amrap.counts(for: rule)) }
    }

    /// El gemelo del plan (`RoutineSet.counts`) no exige `done` — un plan no se ha hecho todavía.
    func testRoutineSetCountsIgnoresDone() {
        let planned = RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 80, mode: .drop)
        XCTAssertTrue(planned.counts(for: .volume))
        XCTAssertFalse(planned.counts(for: .records))
        let warmup = RoutineSet(position: 0, kind: .warmup, reps: 10, weightKg: 40)
        XCTAssertFalse(warmup.counts(for: .volume))
    }

    // MARK: - AMRAP en el plan

    /// «8+», no «8-12»: un AMRAP no tiene techo.
    func testAmrapRepsRangeLabelIsFloorPlus() {
        let amrap = RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 80, mode: .amrap)
        XCTAssertEqual(amrap.repsRangeLabel, "8+")
        let ranged = RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 80, repsRangeTop: 12)
        XCTAssertEqual(ranged.repsRangeLabel, "8-12")
        let fixed = RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 80)
        XCTAssertEqual(fixed.repsRangeLabel, "8")
    }

    /// Un techo escrito antes de marcar AMRAP se normaliza a nil (nunca un «8-12» sobre un «8+»).
    func testNormalizedRepsRangeTopIsNilForAmrap() {
        XCTAssertNil(RoutineSet.normalizedRepsRangeTop(reps: 8, top: 12, mode: .amrap))
        XCTAssertEqual(RoutineSet.normalizedRepsRangeTop(reps: 8, top: 12), 12)
        XCTAssertEqual(RoutineSet.normalizedRepsRangeTop(reps: 8, top: 12, mode: .drop), 12)
        XCTAssertNil(RoutineSet.normalizedRepsRangeTop(reps: 8, top: 8), "un techo que no supera al piso")
    }

    // MARK: - Drop: la fracción

    func testDropFractionAndChainCap() {
        XCTAssertEqual(SetVariants.dropFraction, 0.8, accuracy: 0.0001)
        XCTAssertEqual(SetVariants.maxDropSteps, 3)
        XCTAssertEqual(SetVariants.dropTargetKg(fromKg: 80), 64, accuracy: 0.0001)
        XCTAssertEqual(SetVariants.dropTargetKg(fromKg: 64), 51.2, accuracy: 0.0001)
        XCTAssertEqual(SetVariants.dropTargetKg(fromKg: 0), 0, accuracy: 0.0001)
    }
}
