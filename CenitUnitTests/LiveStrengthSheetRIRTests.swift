import XCTest
@testable import Cenit

/// FER-134 · «QUEDABAN»: el teclado propio captura RIR (reps in reserve), pero el motor solo guarda
/// RPE (`WorkingSet.rpe`) — nunca un campo nuevo. `LiveStrengthSheet.rpe(fromRIR:)` es el único punto
/// de esa conversión, así que es el único que necesita candado: RPE = 10 − RIR, saturado a 0…4 por si
/// algún caller manda un índice fuera del segmento «0 · 1 · 2 · 3 · 4+».
final class LiveStrengthSheetRIRTests: XCTestCase {

    /// Los cinco valores reales del segmento — «4+» es RIR 4 (RPE 6), no infinito: el motor no
    /// distingue «4» de «más de 4», las dos leen «con margen».
    func testRIRToRPEAcrossTheSegment() {
        XCTAssertEqual(LiveStrengthSheet.rpe(fromRIR: 0), 10)
        XCTAssertEqual(LiveStrengthSheet.rpe(fromRIR: 1), 9)
        XCTAssertEqual(LiveStrengthSheet.rpe(fromRIR: 2), 8)
        XCTAssertEqual(LiveStrengthSheet.rpe(fromRIR: 3), 7)
        XCTAssertEqual(LiveStrengthSheet.rpe(fromRIR: 4), 6)   // «4+»
    }

    /// Un índice fuera de rango (defensivo — el segmento nunca manda uno) satura en vez de devolver
    /// un RPE fuera de 0…10, que rompería la hoja de RPE existente (`RPESheet`, escala 0…10).
    func testRIROutOfRangeSaturates() {
        XCTAssertEqual(LiveStrengthSheet.rpe(fromRIR: -3), 10)
        XCTAssertEqual(LiveStrengthSheet.rpe(fromRIR: 9), 6)
    }

    // MARK: - rpeToWrite: registrar una serie NUNCA inventa un RPE (revisión ronda 1, hallazgo grave)

    /// El caso que rompía antes de la ronda 1: palomear directo desde el ✓ de la tabla, sin abrir el
    /// teclado, dejaba `selectedRIR` en su último valor residual (o el 2 por defecto) y escribía ese
    /// RPE fantasma. Con el segmento nunca tocado (`selectedRIR == nil`) no se escribe nada.
    func testNoWriteWhenSegmentNeverTouched() {
        XCTAssertNil(LiveStrengthSheet.rpeToWrite(selectedRIR: nil, existingRPE: nil))
    }

    /// Tocar el segmento SÍ escribe — la conversión RIR → RPE de siempre.
    func testWritesConvertedRPEWhenSegmentTouched() {
        XCTAssertEqual(LiveStrengthSheet.rpeToWrite(selectedRIR: 1, existingRPE: nil), 9)
    }

    /// Un RPE ya puesto a mano por la hoja de RPE (fuera de la escala RIR, p.ej. 9,5) nunca se pisa,
    /// aunque el segmento QUEDABAN tenga una selección.
    func testNeverOverwritesExistingRPE() {
        XCTAssertNil(LiveStrengthSheet.rpeToWrite(selectedRIR: 0, existingRPE: 9.5))
    }

    // MARK: - rirScoped: el RIR elegido no se filtra a otra serie (revisión ronda 2, hallazgo grave)

    /// El caso que rompía antes de la ronda 2: elegir QUEDABAN mientras el teclado editaba la serie A,
    /// luego palomear la serie B directo desde su ✓ de tabla (capacidad existente — «palomear CUALQUIER
    /// pendiente») sin volver a tocar el segmento. El RIR de A ya no se aplica a B.
    func testRIRDoesNotLeakToADifferentSet() {
        let chosenForA = LiveStrengthSheet.RIRTarget(ei: 0, si: 0)
        let registeringB = LiveStrengthSheet.RIRTarget(ei: 0, si: 1)
        XCTAssertNil(LiveStrengthSheet.rirScoped(selectedRIR: 2, selectedRIRTarget: chosenForA,
                                                  registering: registeringB))
    }

    /// Registrar la MISMA serie para la que se eligió el RIR sí lo aplica.
    func testRIRAppliesToTheSameSet() {
        let target = LiveStrengthSheet.RIRTarget(ei: 1, si: 2)
        XCTAssertEqual(LiveStrengthSheet.rirScoped(selectedRIR: 2, selectedRIRTarget: target,
                                                    registering: target), 2)
    }

    /// Sin elección (el segmento nunca se tocó), nunca hay nada que aplicar sin importar la serie.
    func testRIRScopedNilWhenNeverChosen() {
        let target = LiveStrengthSheet.RIRTarget(ei: 0, si: 0)
        XCTAssertNil(LiveStrengthSheet.rirScoped(selectedRIR: nil, selectedRIRTarget: nil, registering: target))
    }

    // MARK: - qLabel(fromRPE:): la lectura «Q n» de la tabla en filas hechas (ronda 3, hallazgo grave/menor)

    /// La vuelta exacta del RIR guardado: `rpe(fromRIR:)` seguida de `qLabel(fromRPE:)` debe
    /// devolver el mismo número que eligió el segmento — el redondeo no debe perder el valor exacto
    /// para los cinco puntos que el teclado en verdad produce.
    func testQLabelRoundTripsExactRIRValues() {
        for rir in 0...4 {
            let rpe = LiveStrengthSheet.rpe(fromRIR: rir)
            let expected = rir >= 4 ? "Q 4+" : "Q \(rir)"
            XCTAssertEqual(LiveStrengthSheet.qLabel(fromRPE: rpe), expected)
        }
    }

    /// Un RPE puesto a mano por la hoja de RPE (fuera de la escala RIR, p.ej. 9,5 o 5) también
    /// convierte y satura — la columna nunca imprime «Q» fuera de 0…4+.
    func testQLabelSaturatesForRPEOutsideTheRIRSegment() {
        XCTAssertEqual(LiveStrengthSheet.qLabel(fromRPE: 9.5), "Q 0")
        XCTAssertEqual(LiveStrengthSheet.qLabel(fromRPE: 5), "Q 4+")
        XCTAssertEqual(LiveStrengthSheet.qLabel(fromRPE: 0), "Q 4+")
    }

    // MARK: - focusDoneTiming: HECHO nunca se cuela delante de un descanso que sigue corriendo
    // (FER-135, V6, revisión ronda 1, hallazgo grave — la regresión que este archivo no atrapó antes
    // de merge: `registerActiveSet` mostraba HECHO al instante de palomear la última serie, mientras
    // el descanso real (FC/temporizador) seguía corriendo en silencio detrás).

    /// El caso que rompía: última serie de un ejercicio NO final, con un descanso real (`rest.seconds
    /// > 0`) arrancando detrás — HECHO debe ESPERAR (`.pending`, promovido cuando el descanso termine
    /// o se salte), nunca aparecer ya.
    func testFocusDoneWaitsForARealRestToEndFirst() {
        XCTAssertEqual(LiveStrengthSheet.focusDoneTiming(exerciseFullyDone: true, restStarting: true), .pending)
    }

    /// Sin descanso real que esperar (descanso fijo de 0 s, o la última serie de la última sesión) —
    /// HECHO puede mostrarse de inmediato, como antes.
    func testFocusDoneShowsImmediatelyWithNoRealRest() {
        XCTAssertEqual(LiveStrengthSheet.focusDoneTiming(exerciseFullyDone: true, restStarting: false), .immediate)
    }

    /// El ejercicio TODAVÍA tiene series de trabajo pendientes (p. ej. un salto de superserie a un
    /// compañero a mitad de ronda) — nunca hay nada que mostrar, sin importar si arrancó un descanso.
    func testFocusDoneNoneWhileExerciseStillHasWorkLeft() {
        XCTAssertEqual(LiveStrengthSheet.focusDoneTiming(exerciseFullyDone: false, restStarting: true), .none)
        XCTAssertEqual(LiveStrengthSheet.focusDoneTiming(exerciseFullyDone: false, restStarting: false), .none)
    }
}
