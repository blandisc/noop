import XCTest
import StrandTraining
import StrandAnalytics
@testable import Cenit

/// FER-88 — regresión de la decisión #4 del épico («La línea de la subida») dentro de
/// `RoutineEditorScreen`: el `raise` que llega a `EditorItem` (y de ahí a `PlanSlot`) NUNCA se
/// condiciona por el veredicto. `RoutineEditorScreen.load()` ya cumplía esto antes de esta fase
/// (`raise: seed.evaluation?.raise`, sin `if allowsRaise(advice)` alrededor); FER-88 solo extrajo esa
/// línea a `RoutineEditorScreen.raiseForEditorItem(_:)`, nombrada y `static`, para que quedara
/// probable sin montar la vista completa (`EditorItem` es `private` al archivo — no se puede
/// construir desde aquí ni con `@testable import`).
///
/// Este test truena si alguien reintroduce el bug que la decisión #4 prohíbe: envolver esa línea en
/// `if TrainingRegulation.allowsRaise(advice) { seed.evaluation?.raise } else { nil }` (o el
/// equivalente con `explainsHeldRaise`) — el código de ANTES de FER-82/838, donde un día `.recover`
/// hacía que el editor sembrara la sesión sin la subida ganada y el héroe perdía la fila «↑ X te
/// espera».
@MainActor
final class RoutineEditorScreenRaiseTests: XCTestCase {

    /// Un slot que YA ganó su subida: 3×8 a 80 kg, dos veces, con progresión encendida — el mismo
    /// fixture que `SingleOracleSeedTests.earnedSlot()`/`earnedHistory()`.
    private func earnedSlot() -> RoutineExercise {
        RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0,
                        targetSets: 3, targetReps: 8, targetWeightKg: 80,
                        restMode: .fixed, restSeconds: 90,
                        progressionEnabled: true, progressionSessions: 2, progressionIncrementKg: 2.5)
    }

    private func earnedHistory() -> [(startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)] {
        [1, 2].flatMap { session in
            (0..<3).map { _ in (startTs: session * 1000, weightKg: 80.0, reps: 8, optedOut: false) }
        }
    }

    /// `.recover` NUNCA aplica una subida (`TrainingRegulation.allowsRaise(.recover) == false`), pero
    /// la retiene: `ProgressionPlanner.evaluate` devuelve un `Raise` con `waiting == true`, no `nil`.
    /// `raiseForEditorItem` debe dejarlo pasar tal cual — sigue poblado, como pide el criterio.
    func testHeldRaiseSurvivesRecoverAdvice() {
        let evaluation = ProgressionPlanner.evaluate(re: earnedSlot(), history: earnedHistory(),
                                                     inventory: [], equipment: nil, advice: .recover)
        XCTAssertFalse(TrainingRegulation.allowsRaise(.recover), "fixture del test: .recover no aplica")
        guard let raise = RoutineEditorScreen.raiseForEditorItem(evaluation) else {
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
        guard let raise = RoutineEditorScreen.raiseForEditorItem(evaluation) else {
            return XCTFail("expected an applied raise")
        }
        XCTAssertFalse(raise.waiting)
    }

    /// Sin evaluación (el slot no opta a progresión, o `sessionSeed` no la calculó) → `nil`, sin
    /// tronar. `raiseForEditorItem` no inventa una subida donde `sessionSeed` no la vio.
    func testNilEvaluationYieldsNilRaise() {
        XCTAssertNil(RoutineEditorScreen.raiseForEditorItem(nil))
    }
}
