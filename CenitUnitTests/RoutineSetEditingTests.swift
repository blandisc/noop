import XCTest
import StrandTraining
@testable import Cenit

/// FER-88 — el detector puro «series iguales» (`RoutineSetEditing.workSetsAreEqual`): decide si
/// `RoutineEditorScreen` pliega la receta de un ejercicio en una `RecetaLine` o la abre en renglones
/// automáticos. Cada caso documenta qué código viejo lo haría tronar: antes de esta fase la función
/// no existía, así que TODO este archivo truena contra `main` — la referencia útil es qué comparación
/// exacta rompería si alguien la simplifica de vuelta a «compara solo el primer y último set», ignora
/// el calentamiento a medias, o deja de filtrar `kind == .work`.
final class RoutineSetEditingTests: XCTestCase {

    private func workSet(_ w: Double?, _ r: Int?, id: String = UUID().uuidString) -> RoutineSet {
        RoutineSet(id: id, position: 0, kind: .work, reps: r, weightKg: w)
    }

    private func warmupSet(_ w: Double?, _ r: Int?) -> RoutineSet {
        RoutineSet(id: UUID().uuidString, position: 0, kind: .warmup, reps: r, weightKg: w)
    }

    /// Tres series de trabajo idénticas → colapsa. Truena si la función compara identidad de
    /// posición en vez de valor, o si deja de usar `allSatisfy` contra el PRIMER set.
    func testEqualWorkSetsCollapse() {
        let sets = [workSet(80, 8), workSet(80, 8), workSet(80, 8)]
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual(sets))
    }

    /// Una serie con peso distinto → renglones. Truena si la función solo mira `reps` y olvida
    /// `weightKg` en la comparación.
    func testOneSetWithDifferentWeightExpands() {
        let sets = [workSet(80, 8), workSet(80, 8), workSet(85, 8)]
        XCTAssertFalse(RoutineSetEditing.workSetsAreEqual(sets))
    }

    /// Una serie con reps distintas (mismo peso) → renglones. Truena si la función solo mira
    /// `weightKg` y olvida `reps`.
    func testOneSetWithDifferentRepsExpands() {
        let sets = [workSet(80, 8), workSet(80, 8), workSet(80, 6)]
        XCTAssertFalse(RoutineSetEditing.workSetsAreEqual(sets))
    }

    /// Calentamiento distinto con trabajo igual → colapsa igual: el calentamiento NUNCA cuenta.
    /// Truena si la función deja de filtrar `kind == .work` antes de comparar (p. ej. si comparara
    /// `sets` crudo, esta prueba fallaría porque el calentamiento a 40 kg / 10 reps difiere del
    /// trabajo a 80 kg / 8).
    func testDifferentWarmupWithEqualWorkStillCollapses() {
        let sets = [warmupSet(32, 10), warmupSet(48, 10), warmupSet(64, 10),
                    workSet(80, 8), workSet(80, 8), workSet(80, 8)]
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual(sets))
    }

    /// Un solo set de trabajo → colapsa (caso trivial: nada con qué diferir). Truena si la función
    /// usa `dropFirst().allSatisfy` sobre una lista de un elemento y accede fuera de rango, o si
    /// exige `work.count > 1` para considerar «igual».
    func testSingleWorkSetCollapses() {
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual([workSet(80, 8)]))
    }

    /// Sin series (caso imposible en la práctica, no en el tipo) → colapsa: nada que distinguir.
    /// Truena si la función fuerza `first!` en vez de usar `guard let`.
    func testNoSetsCollapses() {
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual([]))
    }

    /// Solo calentamiento, sin ninguna serie de trabajo → colapsa (mismo caso trivial que «sin
    /// series»: el filtro por `.work` deja la lista vacía).
    func testOnlyWarmupCollapses() {
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual([warmupSet(32, 10), warmupSet(48, 8)]))
    }

    /// Peso `nil` en todas (aún sin capturar) pero mismas reps → colapsa: `nil == nil` es igual,
    /// no una excepción. Truena si la comparación usara `??` con un valor centinela que rompiera la
    /// igualdad de dos `nil` reales.
    func testAllNilWeightsWithEqualRepsCollapses() {
        let sets = [workSet(nil, 8), workSet(nil, 8), workSet(nil, 8)]
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual(sets))
    }

    // MARK: - Bloqueado hasta E13/FER-94 (RoutineSet.repsRangeTop en Training.swift)
    //
    // Esta fase (FER-88) extiende el detector para tratar dos series con distinto TECHO de rango de
    // reps como distintas — el criterio de aceptación lo pide explícitamente («dos series con mismo
    // peso/reps pero repsRangeTop distinto → renglones»; «nil == nil → colapsa, regresión explícita»).
    // `RoutineSet.repsRangeTop` no existe todavía (verificado: `grep -rn repsRangeTop Cenit/ Packages/`
    // → 0 resultados) y `Training.swift` es de E13/FER-94, no de esta fase (ver «Fuera de alcance» del
    // issue) — así que estas dos pruebas quedan documentadas y comentadas, NO borradas, listas para
    // descomentarse en cuanto el campo aterrice:
    //
    // func testDifferentRepsRangeTopExpandsEvenWithSameWeightAndReps() {
    //     var a = workSet(80, 8); a.repsRangeTop = 10
    //     let b = workSet(80, 8)   // repsRangeTop == nil
    //     XCTAssertFalse(RoutineSetEditing.workSetsAreEqual([a, b]))
    // }
    //
    // func testEqualNilRepsRangeTopStillCollapses() {
    //     let sets = [workSet(80, 8), workSet(80, 8)]   // repsRangeTop nil en ambas
    //     XCTAssertTrue(RoutineSetEditing.workSetsAreEqual(sets))
    // }
}
