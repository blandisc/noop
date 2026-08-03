import XCTest
import SwiftUI
@testable import StrandDesign

/// Carril C · el contrato de VoiceOver de la cabecera de la hoja de resumen, en frío
/// (sin simulador). Run: swift test --filter LiquidSheetHeaderA11yTests
///
/// Cubre los dos defectos que el inventario de la hoja vieja marca como «a NO reproducir»:
/// el sufijo de la escala («/ 21», «/ 100») que la fusión de la fila del dato se había
/// comido (C1) y la unidad que la voz seguía diciendo sobre un «—» (C2).
final class LiquidSheetHeaderA11yTests: XCTestCase {

    // MARK: C1 · el sufijo de la escala vuelve al label

    /// El caso que motivó el carril: esfuerzo muestra «10.0 / 21» y VoiceOver decía
    /// «Esfuerzo del día, 10.0, Calculado» — el denominador de la escala se perdía.
    func test_sufijo_entraAlLabel() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "Esfuerzo del día", numeral: "10.0",
                                        unidad: nil, sufijo: "/ 21", origen: "Calculado"),
            "Esfuerzo del día, 10.0 / 21, Calculado")
    }

    /// Recuperación: numeral + sufijo + procedencia, sin unidad.
    func test_sufijo_recuperacion() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "RECUPERACIÓN", numeral: "78",
                                        unidad: nil, sufijo: "/ 100", origen: "Calculado"),
            "RECUPERACIÓN, 78 / 100, Calculado")
    }

    /// Unidad Y sufijo a la vez: el orden es el mismo que el de la pantalla.
    func test_sufijo_conUnidad() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "VFC", numeral: "56", unidad: "ms",
                                        sufijo: "/ 100", origen: "Apple Salud"),
            "VFC, 56 ms / 100, Apple Salud")
    }

    /// Sin sufijo (7 de las 9 métricas): el label no cambia respecto del contrato viejo —
    /// el parámetro por omisión existe justo para eso.
    func test_sinSufijo_labelIntacto() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "VFC", numeral: "56",
                                        unidad: "ms", origen: "Apple Salud"),
            "VFC, 56 ms, Apple Salud")
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "ESFUERZO", numeral: "10.0",
                                        unidad: nil, origen: nil),
            "ESFUERZO, 10.0")
    }

    // MARK: C2 · la voz no contradice a la pantalla con «—»

    /// El cuerpo oculta unidad y sufijo cuando el dato es «—»; la voz decía «VFC, — ms»
    /// sobre una pantalla que solo muestra «—».
    func test_sinDato_niUnidadNiSufijo() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "VFC", numeral: "—",
                                        unidad: "ms", origen: nil),
            "VFC, —")
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "Esfuerzo del día", numeral: "—",
                                        unidad: nil, sufijo: "/ 21", origen: "Calculado"),
            "Esfuerzo del día, —, Calculado")
    }

    // MARK: Variante rica de sueño · sin numeral

    /// `numeral == nil` (el doble dato manda): el label es el título y, si la hay, la
    /// procedencia. Ni unidad ni sufijo cuelgan de la nada.
    func test_sinNumeral_soloTituloYProcedencia() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "SUEÑO", numeral: nil, unidad: nil,
                                        origen: "Apple Salud"),
            "SUEÑO, Apple Salud")
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "SUEÑO", numeral: nil, unidad: "h",
                                        sufijo: "/ 100", origen: nil),
            "SUEÑO")
    }

    // MARK: F0.2 · el sello de la ventana entra al label (entre dato y origen)

    /// Con sello: el orden es título, dato, sello, origen.
    func test_sello_entraAlLabelEntreDatoYOrigen() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "VFC", numeral: "56", unidad: "ms",
                                        sello: "HOY · 3 AGO", origen: "Apple Salud"),
            "VFC, 56 ms, HOY · 3 AGO, Apple Salud")
    }

    /// Con «—» y sello: la unidad no se dice, el sello sí (la ventana sigue siendo info).
    func test_sello_conSinDato_sinUnidad() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "VFC", numeral: "—", unidad: "ms",
                                        sello: "HOY · 3 AGO", origen: "Apple Salud"),
            "VFC, —, HOY · 3 AGO, Apple Salud")
    }

    // MARK: El init compone el mismo label que la función estática

    /// El `init` es quien pasa el sufijo: si dejara de hacerlo, C1 volvería en silencio
    /// (el arreglo no se ve en ningún test que llame solo a la estática).
    @MainActor
    func test_init_pasaElSufijo() {
        let header = LiquidSheetHeader(icono: .llama, titulo: "Esfuerzo del día",
                                       tono: LiquidColor.ambar, numeral: "10.0",
                                       sufijo: "/ 21", origen: .calculado,
                                       origenEtiqueta: "Calculado")
        XCTAssertEqual(header.a11y, "Esfuerzo del día, 10.0 / 21, Calculado")
    }

    /// Un `a11yLabel` explícito del caller sigue ganando (contrato de escape del DS).
    @MainActor
    func test_init_respetaElLabelExplicito() {
        let header = LiquidSheetHeader(icono: nil, titulo: "RECUPERACIÓN",
                                       tono: LiquidColor.verdePrimario, numeral: "78",
                                       sufijo: "/ 100", a11yLabel: "Amaneciste al 78")
        XCTAssertEqual(header.a11y, "Amaneciste al 78")
    }
}
