import XCTest
@testable import StrandAnalytics

/// FER-327 · E6 — un AMPRAP («las que puedas») entra al ciclo de doble progresión SIN cambiar la
/// fórmula: `ProgressionMath.metGoal` ya dice «cumpliste si cada serie de trabajo llegó al objetivo»,
/// y un AMRAP que hizo 11 con objetivo 8 cumple por la misma regla que una serie fija de 11.
///
/// Estas pruebas viven en su propio archivo (no dentro de `ProgressionStateTests`) a propósito: E4
/// es el dueño de `ProgressionState.swift` en esta ola y no queremos colisionar en el mismo archivo.
/// Aquí no se toca el motor — se FIJA su comportamiento actual frente al caso nuevo, para que si
/// alguien «arregla» `metGoal` pensando en el AMRAP, la prueba lo cache.
final class SetModeProgressionTests: XCTestCase {

    /// AMRAP 11 contra objetivo 8: cumple. (El drop no llega hasta aquí: `workSetHistory` lo excluye
    /// en SQL, así que `workSetReps` nunca lo contiene — ver `StrengthStoreTests`.)
    func testAmrapAboveTargetIsAHit() {
        let session = ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 11])
        XCTAssertTrue(ProgressionMath.metGoal(session, targetReps: 8, targetSets: 3))
    }

    /// AMRAP 6 contra objetivo 8: falla, como cualquier serie corta. «Las que puedas» no es un pase
    /// libre — si no llegaste al piso, no cumpliste.
    func testAmrapBelowTargetIsAMiss() {
        let session = ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 6])
        XCTAssertFalse(ProgressionMath.metGoal(session, targetReps: 8, targetSets: 3))
    }

    /// La fórmula NO cambia: para `metGoal`, un 11 es un 11 venga de una serie fija o de un AMRAP —
    /// el modo no entra en el cálculo, solo decide (antes, en el SQL) si la serie llega o no.
    func testMetGoalFormulaIsUnchangedByHowTheRepsWereEarned() {
        let amrap = ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 11])
        let fixed = ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 11])
        XCTAssertEqual(ProgressionMath.metGoal(amrap, targetReps: 8, targetSets: 3),
                       ProgressionMath.metGoal(fixed, targetReps: 8, targetSets: 3))
    }

    /// Y el ciclo completo lo lee igual: dos sesiones seguidas con el AMRAP por encima del objetivo
    /// ganan la subida, sin nada especial para el modo.
    func testTwoAmrapSessionsAboveTargetEarnTheRaise() {
        let input = ProgressionMath.ProgressionInput(
            history: [ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 10]),
                      ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 11])],
            targetReps: 8, targetSets: 3, sessionsToAdvance: 2, incrementKg: 2.5)
        XCTAssertEqual(ProgressionMath.classify(input), .readyToAdvance(newKg: 82.5))
    }
}
