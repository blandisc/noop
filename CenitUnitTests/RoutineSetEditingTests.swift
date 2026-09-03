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

    // MARK: - E13/FER-94: el detector también cubre `repsRangeTop`

    /// Dos series con mismo peso/reps pero distinto techo de rango → renglones. Truena si la
    /// comparación olvida `repsRangeTop` al decidir igualdad.
    func testDifferentRepsRangeTopExpandsEvenWithSameWeightAndReps() {
        var a = workSet(80, 8); a.repsRangeTop = 10
        let b = workSet(80, 8)   // repsRangeTop == nil
        XCTAssertFalse(RoutineSetEditing.workSetsAreEqual([a, b]))
    }

    /// `repsRangeTop` nil en ambas (sin rango, comportamiento de hoy) → colapsa igual — regresión
    /// explícita: la extensión no debe romper el caso sin rango.
    func testEqualNilRepsRangeTopStillCollapses() {
        let sets = [workSet(80, 8), workSet(80, 8)]   // repsRangeTop nil en ambas
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual(sets))
    }
    // MARK: - Ola 1 · FER-327 (v5 N15): el MODO entra a la igualdad de receta

    /// Un AMRAP en la ÚLTIMA serie abre la receta, aunque el peso y el piso de reps coincidan: «8+»
    /// no es «8». Truena con el código de antes de FER-327 (la comparación ignoraba `mode`).
    func testAmrapInLastSetOpensTheReceta() {
        var amrap = workSet(80, 8); amrap.mode = .amrap
        let sets = [workSet(80, 8), workSet(80, 8), amrap]
        XCTAssertFalse(RoutineSetEditing.workSetsAreEqual(sets))
    }

    /// Y el CONTADOR está de acuerdo con el detector: si la receta se abre, no puede decir «1».
    /// Truena si la clave de igualdad del contador olvida `mode` mientras el detector sí lo mira —
    /// exactamente el estado incoherente («2 recetas» plegadas en una línea) que esto previene.
    func testRecetaCountIsNotOneWhenOnlyModeDiffers() {
        var amrap = workSet(80, 8); amrap.mode = .amrap
        let sets = [workSet(80, 8), workSet(80, 8), amrap]
        XCTAssertEqual(RoutineSetEditing.recetaCount(sets), 2)
        XCTAssertNotEqual(RoutineSetEditing.recetaCount(sets), 1)
        // Mismo modo en todas → una sola receta, comportamiento de siempre.
        XCTAssertEqual(RoutineSetEditing.recetaCount([workSet(80, 8), workSet(80, 8)]), 1)
    }

    /// El calentamiento no cuenta como receta (ni antes ni ahora).
    func testRecetaCountIgnoresWarmups() {
        XCTAssertEqual(RoutineSetEditing.recetaCount([warmupSet(40, 10), workSet(80, 8), workSet(80, 8)]), 1)
    }

    /// «Igualar todas» propaga TAMBIÉN el modo — si no, después de igualar la receta seguiría abierta.
    func testEqualizeAllPropagatesMode() {
        var amrap = workSet(80, 8); amrap.mode = .amrap
        var sets = [amrap, workSet(80, 8), workSet(75, 6)]
        RoutineSetEditing.equalizeWorkSets(&sets)
        XCTAssertEqual(sets.map(\.mode), [SetMode.amrap, .amrap, .amrap])
        XCTAssertTrue(RoutineSetEditing.workSetsAreEqual(sets), "igualar debe cerrar la receta")
        XCTAssertEqual(RoutineSetEditing.recetaCount(sets), 1)
    }

    /// «Igualar todas» no toca los calentamientos.
    func testEqualizeAllLeavesWarmupsAlone() {
        var amrap = workSet(80, 8); amrap.mode = .amrap
        var sets = [warmupSet(40, 10), amrap, workSet(75, 6)]
        RoutineSetEditing.equalizeWorkSets(&sets)
        XCTAssertEqual(sets[0].weightKg, 40)
        XCTAssertEqual(sets[0].reps, 10)
        XCTAssertEqual(sets[0].mode, .standard)
    }

    /// El espejo de superserie propaga el modo a todas las rondas de trabajo del miembro.
    func testMirrorAcrossRoundsPropagatesMode() {
        var amrap = workSet(80, 8); amrap.mode = .amrap
        var sets = [warmupSet(40, 10), workSet(70, 6), amrap, workSet(70, 6)]
        RoutineSetEditing.mirrorWorkSets(&sets, from: 2)
        XCTAssertEqual(sets.map(\.mode), [SetMode.standard, .amrap, .amrap, .amrap],
                       "el calentamiento no es una ronda: no se espeja")
        XCTAssertEqual(sets[1].weightKg, 80)
        XCTAssertEqual(sets[3].reps, 8)
        XCTAssertEqual(sets[0].weightKg, 40, "el calentamiento queda intacto")
    }

    // MARK: - editorRepsLabel (N16 · ola 1 · E7): la palabra de INTERFAZ del editor, distinta del
    // dato crudo `RoutineSet.repsRangeLabel` («8+») que StrandTraining deja a propósito sin la
    // palabra «máx» (ver su doc). Truena si alguien vuelve a leer `repsRangeLabel` directo en la
    // celda del editor.

    /// Un AMRAP en el editor lee «8 a máx» (clave «%lld to max») — nunca el «8+» del dato crudo.
    func testEditorRepsLabelReadsAToMaxForAmrap() {
        var amrap = workSet(80, 8); amrap.mode = .amrap
        XCTAssertEqual(RoutineSetEditing.editorRepsLabel(amrap), "8 to max")
    }

    /// Un rango normal (piso-techo) no cambia — sigue siendo «8-10».
    func testEditorRepsLabelKeepsRangeForStandard() {
        var ranged = workSet(80, 8)
        ranged.repsRangeTop = 10
        XCTAssertEqual(RoutineSetEditing.editorRepsLabel(ranged), "8-10")
    }

    /// Un piso fijo sin techo sigue siendo solo el piso.
    func testEditorRepsLabelKeepsFloorOnly() {
        XCTAssertEqual(RoutineSetEditing.editorRepsLabel(workSet(80, 8)), "8")
    }

    /// Sin piso (tipo sin reps) no hay nada que leer.
    func testEditorRepsLabelNilWithoutFloor() {
        XCTAssertNil(RoutineSetEditing.editorRepsLabel(workSet(80, nil)))
    }
}
