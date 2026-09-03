import XCTest
@testable import StrandTraining

/// Ola 1 · E10 (FER-329): la regla de la semana ligera. El 7,5 % se INYECTA (vive en
/// `ProgressionMath.deloadFraction`, StrandAnalytics, que StrandTraining no puede importar), así que
/// aquí se escribe literal una sola vez, con el nombre de dónde sale.
final class ProgramDeloadTests: XCTestCase {

    /// El MISMO valor que `StrandAnalytics.ProgressionMath.deloadFraction` — una familia de «bajar».
    private let deloadFraction = 0.075

    private func work(_ n: Int, kg: Double = 100) -> [RoutineSet] {
        (0..<n).map { RoutineSet(id: "w\($0)", position: $0, kind: .work, reps: 8, weightKg: kg) }
    }

    private func workCount(_ sets: [RoutineSet]) -> Int { sets.filter { $0.kind == .work }.count }

    func testHalfTheWorkSetsRoundedDownNeverBelowOne() {
        XCTAssertEqual(ProgramDeload.lightWorkSetCount(4), 2)
        XCTAssertEqual(ProgramDeload.lightWorkSetCount(3), 1)
        XCTAssertEqual(ProgramDeload.lightWorkSetCount(1), 1)
        XCTAssertEqual(ProgramDeload.lightWorkSetCount(5), 2)
    }

    func testVolumeOnlyTrimsSetsAndLeavesTheWeightAlone() {
        for (planned, expected) in [(4, 2), (3, 1), (1, 1), (5, 2)] {
            let out = ProgramDeload.apply(rule: .volumeOnly, to: work(planned),
                                          deloadFraction: deloadFraction)
            XCTAssertEqual(workCount(out), expected, "\(planned) series de trabajo → \(expected)")
            XCTAssertTrue(out.allSatisfy { $0.weightKg == 100 }, "volumeOnly no toca el peso")
        }
    }

    func testWarmupsSurviveUntouched() {
        let sets = [RoutineSet(id: "c0", position: 0, kind: .warmup, reps: 10, weightKg: 40),
                    RoutineSet(id: "c1", position: 1, kind: .warmup, reps: 5, weightKg: 60)]
            + work(4).map { var s = $0; s.position += 2; return s }
        let out = ProgramDeload.apply(rule: .volumeAndLoad, to: sets, deloadFraction: deloadFraction)
        let warmups = out.filter { $0.kind == .warmup }
        XCTAssertEqual(warmups.count, 2)
        XCTAssertEqual(warmups.map(\.weightKg), [40, 60], "el calentamiento no baja de peso ni de número")
        XCTAssertEqual(workCount(out), 2)
    }

    func testVolumeAndLoadUsesTheSameSevenAndAHalfPercent() {
        let out = ProgramDeload.apply(rule: .volumeAndLoad, to: work(4), deloadFraction: deloadFraction)
        XCTAssertEqual(workCount(out), 2)
        for s in out where s.kind == .work {
            XCTAssertEqual(s.weightKg ?? 0, 92.5, accuracy: 0.0001, "100 × (1 − 0,075)")
        }
    }

    func testVolumeAndLoadLandsOnABuildableWeightThroughTheInjectedSnap() {
        // La app compone con `PlateMath.snap`; aquí se inyecta un rack de paso 2,5 kg (misma
        // aritmética: múltiplo inferior) para probar que el redondeo entra por el parámetro y no
        // se queda en un peso imposible de armar.
        let step = 2.5
        let out = ProgramDeload.apply(rule: .volumeAndLoad, to: work(4, kg: 100),
                                      deloadFraction: deloadFraction,
                                      snap: { ($0 / step).rounded(.down) * step })
        for s in out where s.kind == .work {
            let kg = s.weightKg ?? 0
            XCTAssertEqual(kg, 92.5, accuracy: 0.0001)
            XCTAssertEqual((kg / step).truncatingRemainder(dividingBy: 1), 0, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(kg, 100, "nunca propone MÁS peso que el de trabajo")
        }
    }

    func testNoneIsTheIdentity() {
        let sets = work(4)
        XCTAssertEqual(ProgramDeload.apply(rule: .none, to: sets, deloadFraction: deloadFraction), sets)
    }

    func testASetWithoutAPrescribedWeightIsNotInvented() {
        let sets = (0..<2).map { RoutineSet(id: "w\($0)", position: $0, kind: .work, reps: 8) }
        let out = ProgramDeload.apply(rule: .volumeAndLoad, to: sets, deloadFraction: deloadFraction)
        XCTAssertEqual(workCount(out), 1)
        XCTAssertNil(out.first?.weightKg, "sin peso planeado no se inventa uno para bajarlo")
    }

    // MARK: - Sobre el ejercicio completo (las DOS formas del plan en disco)

    func testLegacyExerciseWithoutExplicitSetsIsStillServedLight() {
        // Rutina legada: `sets` vacío, el plan vive en `targetSets`/`targetReps`. Sin normalizar por
        // `plannedSets`, la semana ligera no hacía NADA aquí — y en silencio.
        let re = RoutineExercise(routineId: "r", exerciseId: "ex", position: 0,
                                 targetSets: 4, targetReps: 8, targetWeightKg: 100)
        XCTAssertTrue(re.sets.isEmpty, "el fixture tiene que cruzar el caso legado o no prueba nada")
        let out = ProgramDeload.apply(rule: .volumeOnly, to: re, deloadFraction: deloadFraction)
        XCTAssertEqual(out.sets.filter { $0.kind == .work }.count, 2)
        XCTAssertEqual(out.targetSets, 2, "`targetSets` queda coherente con la receta servida")
        XCTAssertEqual(out.sets.map(\.weightKg), [100, 100])
    }

    func testExplicitPlanIsServedLightAndKeepsTargetSetsCoherent() {
        var re = RoutineExercise(routineId: "r", exerciseId: "ex", position: 0, targetSets: 4)
        re.sets = work(4)
        let out = ProgramDeload.apply(rule: .volumeAndLoad, to: re, deloadFraction: deloadFraction)
        XCTAssertEqual(out.sets.count, 2)
        XCTAssertEqual(out.targetSets, 2)
        XCTAssertEqual(out.sets.first?.weightKg ?? 0, 92.5, accuracy: 0.0001)
    }

    func testNoneLeavesTheExerciseByteForByte() {
        var re = RoutineExercise(routineId: "r", exerciseId: "ex", position: 0, targetSets: 4)
        re.sets = work(4)
        XCTAssertEqual(ProgramDeload.apply(rule: .none, to: re, deloadFraction: deloadFraction), re)
        // Y una rutina legada tampoco se materializa cuando no hay semana ligera que servir.
        let legacy = RoutineExercise(routineId: "r", exerciseId: "ex", position: 0, targetSets: 4)
        XCTAssertTrue(ProgramDeload.apply(rule: .none, to: legacy,
                                          deloadFraction: deloadFraction).sets.isEmpty)
    }

    func testSurvivingSetsKeepTheirOwnIdentity() {
        let out = ProgramDeload.apply(rule: .volumeOnly, to: work(5), deloadFraction: deloadFraction)
        XCTAssertEqual(out.map(\.id), ["w0", "w1"], "sobreviven las PRIMERAS, con su id y su position")
        XCTAssertEqual(out.map(\.position), [0, 1])
    }
}
