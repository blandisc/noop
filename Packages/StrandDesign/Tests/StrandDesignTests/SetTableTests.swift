import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-81 — auditoría de crecimiento: `SetTable` era más delgada que la tabla de series que debe
/// reemplazar en `LiveStrengthSheet`. Estas pruebas cubren la lógica PURA que ese crecimiento
/// agregó (estado de celda, contrato de toque, reflow, accesibilidad) — todo lo que un cambio
/// futuro podría romper sin que el ojo lo note en una captura.
final class SetTableTests: XCTestCase {

    // MARK: Punto 2 — estado de celda (fantasma / tocada / en edición), el corazón de FER-952

    /// `done` manda siempre. El código viejo no tenía este concepto — cualquier reversión que borre
    /// esta prioridad deja una serie YA registrada mostrando cursor o semilla tenue.
    func testDoneSiempreAsienta() {
        for state: EntrenarCellState in [.ghost, .touched, .editing] {
            XCTAssertEqual(SetTable.visualRole(state: state, done: true), .settled,
                            "\(state) con done=true debe asentarse, sin importar en qué quedó")
        }
    }

    func testFantasmaTocadaEdicionSinRegistrar() {
        XCTAssertEqual(SetTable.visualRole(state: .ghost, done: false), .ghost)
        XCTAssertEqual(SetTable.visualRole(state: .touched, done: false), .normal)
        XCTAssertEqual(SetTable.visualRole(state: .editing, done: false), .editing)
    }

    // MARK: Punto 9 — el ✓ debe leer `isCurrent`, no solo `done`

    /// Antes del crecimiento, el color del check solo conocía `done` — esta prueba es exactamente la
    /// que el código viejo (sin la rama `isCurrent`) hacía tronar: «la próxima serie» pendiente se
    /// quedaba en tinta apagada en vez de ámbar.
    func testElCheckDeLaProximaSerieVaEnAmbarNoApagado() {
        XCTAssertEqual(SetTable.checkRole(done: false, isCurrent: true), .active)
        XCTAssertEqual(SetTable.checkRole(done: false, isCurrent: false), .idle)
    }

    /// Registrada gana siempre, incluso si por error el llamador manda `isCurrent` también en true.
    func testElCheckRegistradoGanaAIsCurrent() {
        XCTAssertEqual(SetTable.checkRole(done: true, isCurrent: true), .done)
        XCTAssertEqual(SetTable.checkRole(done: true, isCurrent: false), .done)
    }

    // MARK: Punto 10 — reflow a partir de accessibility1

    func testReflowaDesdeAccessibility1() {
        XCTAssertFalse(SetTable.reflows(at: .xxxLarge), "xxxLarge todavía es texto normal, no reflow")
        XCTAssertTrue(SetTable.reflows(at: .accessibility1), "accessibility1 es donde arranca el reflow")
        XCTAssertTrue(SetTable.reflows(at: .accessibility5))
    }

    func testTamañosNormalesNuncaReflowan() {
        for size: DynamicTypeSize in [.xSmall, .medium, .large, .xLarge, .xxLarge, .xxxLarge] {
            XCTAssertFalse(SetTable.reflows(at: size), "\(size) no debería reflowar")
        }
    }

    // MARK: Puntos 3/4/5 — el contrato de toque distingue QUÉ celda, por tipo de ejercicio

    /// Regresión directa del Punto 5: antes de crecer, `.bodyweight` solo exponía UNA celda de dato
    /// (mal etiquetada «REPS»); un `onTapCell` que solo mandara el id no podía distinguir «+carga»
    /// de reps. Con la columna real, son dos celdas independientes.
    func testPesoCorporalExponeCargaYReps() {
        XCTAssertEqual(SetTable.interactiveCells(kind: .bodyweight, showRPE: false), [.primary, .reps])
    }

    func testPesoPorRepsExponeCargaYReps() {
        XCTAssertEqual(SetTable.interactiveCells(kind: .weightReps, showRPE: false), [.primary, .reps])
    }

    /// Punto 3: RPE es opcional y se agrega al final, solo si `showRPE` está encendido.
    func testRPEEsOpcionalYSoloDondeHayReps() {
        XCTAssertEqual(SetTable.interactiveCells(kind: .weightReps, showRPE: true), [.primary, .reps, .rpe])
        XCTAssertEqual(SetTable.interactiveCells(kind: .bodyweight, showRPE: true), [.primary, .reps, .rpe])
        // Tiempo/distancia no califican esfuerzo por repetición — showRPE=true no les agrega nada.
        XCTAssertEqual(SetTable.interactiveCells(kind: .time, showRPE: true), [.primary])
        XCTAssertEqual(SetTable.interactiveCells(kind: .distance, showRPE: true), [.primary, .pairedTime])
    }

    /// Regresión directa del Punto 5: antes, `.distance` solo tenía la columna DIST — «400 m» sin su
    /// tiempo al lado no cuenta la serie completa.
    func testDistanciaExponeSuColumnaDeTiempoPareada() {
        XCTAssertEqual(SetTable.interactiveCells(kind: .distance, showRPE: false), [.primary, .pairedTime])
    }

    func testTiempoEsUnaSolaCelda() {
        XCTAssertEqual(SetTable.interactiveCells(kind: .time, showRPE: false), [.primary])
    }

    // MARK: Punto 11 — combinar accesibilidad SOLO cuando dato + check son los únicos controles

    /// `.time` es el único tipo con una sola celda de dato — es el único caso donde combinar los
    /// hijos en un solo elemento de VoiceOver no esconde ningún control.
    func testSoloTiempoCombinaSusHijosDeAccesibilidad() {
        XCTAssertTrue(SetTable.combinesAccessibilityChildren(kind: .time, showRPE: false))
        XCTAssertTrue(SetTable.combinesAccessibilityChildren(kind: .time, showRPE: true))
    }

    /// Regresión directa del Punto 11: peso×reps SIEMPRE tiene ≥2 celdas (peso + reps) — combinarlas
    /// dejaría el peso y las reps inalcanzables por separado para VoiceOver. Antes del crecimiento,
    /// la fila entera se combinaba sin condición.
    func testLosDemasTiposNuncaCombinanSusHijos() {
        XCTAssertFalse(SetTable.combinesAccessibilityChildren(kind: .weightReps, showRPE: false))
        XCTAssertFalse(SetTable.combinesAccessibilityChildren(kind: .weightReps, showRPE: true))
        XCTAssertFalse(SetTable.combinesAccessibilityChildren(kind: .bodyweight, showRPE: false))
        XCTAssertFalse(SetTable.combinesAccessibilityChildren(kind: .distance, showRPE: false))
    }

    // MARK: EntrenarExerciseKind — las banderas de columna por tipo (Punto 5)

    func testSoloPesoPorRepsYPesoCorporalTienenColumnaDeReps() {
        XCTAssertTrue(EntrenarExerciseKind.weightReps.hasRepsColumn)
        XCTAssertTrue(EntrenarExerciseKind.bodyweight.hasRepsColumn)
        XCTAssertFalse(EntrenarExerciseKind.time.hasRepsColumn)
        XCTAssertFalse(EntrenarExerciseKind.distance.hasRepsColumn)
    }

    func testSoloDistanciaTieneColumnaDeTiempoPareada() {
        XCTAssertTrue(EntrenarExerciseKind.distance.hasPairedTimeColumn)
        for kind: EntrenarExerciseKind in [.weightReps, .bodyweight, .time] {
            XCTAssertFalse(kind.hasPairedTimeColumn, "\(kind) no debería tener columna pareada")
        }
    }

    // MARK: Punto 13 — `showHeader`, adopción FER-86 en `LiveStrengthSheet`

    /// Un ejercicio con descanso a media tabla o el corte «WORK SETS» parte sus filas en más de una
    /// `SetTable` — por defecto CADA una dibuja su encabezado, así que sin que el llamador lo apague
    /// explícitamente en los tramos que no son el primero, un ejercicio terminaría con un «SET · KG ·
    /// REPS · RPE» repetido a media tabla.
    func testShowHeaderPorDefectoEsVerdadero() {
        let table = SetTable(kind: .weightReps, rows: [])
        let value = Mirror(reflecting: table).children.first { $0.label == "showHeader" }?.value as? Bool
        XCTAssertEqual(value, true, "sin llamador que lo apague, el encabezado debe seguir dibujándose")
    }

    func testShowHeaderSeApagaCuandoElLlamadorLoPide() {
        let table = SetTable(kind: .weightReps, rows: [], showHeader: false)
        let value = Mirror(reflecting: table).children.first { $0.label == "showHeader" }?.value as? Bool
        XCTAssertEqual(value, false, "el tramo que no es el primero debe poder apagar su encabezado")
    }
}
