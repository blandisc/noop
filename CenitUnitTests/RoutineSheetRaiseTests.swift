import XCTest
import StrandTraining
import StrandAnalytics
import CenitStore
@testable import Cenit

/// FER-88 — regresión de la decisión #4 del épico («La línea de la subida»), portada de
/// `RoutineEditorScreenRaiseTests` a `RoutineSheet` (FER-166, F1 — «La Hoja» sustituye al editor
/// viejo): el `raise` que llega a `EditorItem` (y de ahí a `PlanSlot`) NUNCA se condiciona por el
/// veredicto. `RoutineSheet.load()` cumple esto igual que el editor viejo (`raise:
/// seed.evaluation?.raise`, sin `if allowsRaise(advice)` alrededor) — la línea sigue extraída y
/// nombrada, `static`, en `RoutineSheet.raiseForEditorItem(_:)` (`RoutineSheetLogic.swift`), para
/// que quedara probable sin montar la vista completa.
///
/// Este test truena si alguien reintroduce el bug que la decisión #4 prohíbe: envolver esa línea en
/// `if TrainingRegulation.allowsRaise(advice) { seed.evaluation?.raise } else { nil }` (o el
/// equivalente con `explainsHeldRaise`) — el código de ANTES de FER-82/838, donde un día `.recover`
/// hacía que el editor sembrara la sesión sin la subida ganada y el héroe perdía la fila «↑ X te
/// espera».
@MainActor
final class RoutineSheetRaiseTests: XCTestCase {

    /// Un slot que YA ganó su subida: 3×8 a 80 kg, dos veces, con progresión encendida — el mismo
    /// fixture que `SingleOracleSeedTests.earnedSlot()`/`earnedHistory()`.
    private func earnedSlot() -> RoutineExercise {
        RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0,
                        targetSets: 3, targetReps: 8, targetWeightKg: 80,
                        restMode: .fixed, restSeconds: 90,
                        progressionEnabled: true, progressionSessions: 2, progressionIncrementKg: 2.5)
    }

    private func earnedHistory() -> [WorkSetHistoryRow] {
        [1, 2].flatMap { session in
            (0..<3).map { _ in
                WorkSetHistoryRow(sessionId: "s\(session)", startTs: session * 1000, weightKg: 80.0, reps: 8)
            }
        }
    }

    /// `.recover` NUNCA aplica una subida (`TrainingRegulation.allowsRaise(.recover) == false`), pero
    /// la retiene: `ProgressionPlanner.evaluate` devuelve un `Raise` con `waiting == true`, no `nil`.
    /// `raiseForEditorItem` debe dejarlo pasar tal cual — sigue poblado, como pide el criterio.
    func testHeldRaiseSurvivesRecoverAdvice() {
        let evaluation = ProgressionPlanner.evaluate(re: earnedSlot(), history: earnedHistory(),
                                                     inventory: [], equipment: nil, advice: .recover)
        XCTAssertFalse(TrainingRegulation.allowsRaise(.recover), "fixture del test: .recover no aplica")
        guard let raise = RoutineSheet.raiseForEditorItem(evaluation) else {
            return XCTFail("la subida retenida debe seguir poblada en .recover")
        }
        XCTAssertTrue(raise.waiting, "retenida, no aplicada — pero PRESENTE")
        XCTAssertEqual(raise.toKg, 82.5, accuracy: 0.0001)
        XCTAssertEqual(raise.fromKg, 80, accuracy: 0.0001)
    }

    /// El mismo slot en `.planAsIs` (SÍ permite subir): la subida llega aplicada (`waiting == false`)
    /// — la otra mitad de la decisión #4, «nunca ausente por el veredicto, solo cuando no hay
    /// `proposedRaise`».
    func testAppliedRaiseSurvivesPlanAsIsAdvice() {
        let evaluation = ProgressionPlanner.evaluate(re: earnedSlot(), history: earnedHistory(),
                                                     inventory: [], equipment: nil, advice: .planAsIs)
        guard let raise = RoutineSheet.raiseForEditorItem(evaluation) else {
            return XCTFail("expected an applied raise")
        }
        XCTAssertFalse(raise.waiting)
    }

    /// Sin evaluación (el slot no opta a progresión, o `sessionSeed` no la calculó) → `nil`, sin
    /// tronar. `raiseForEditorItem` no inventa una subida donde `sessionSeed` no la vio.
    func testNilEvaluationYieldsNilRaise() {
        XCTAssertNil(RoutineSheet.raiseForEditorItem(nil))
    }
}
