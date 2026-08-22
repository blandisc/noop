import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-128 · ronda 9 · la frontera del DS que tocó la r8 (el carril Grok no pudo escribir
/// esta ronda; los asserts son los de su spec, tecleados por el director).
final class MatrizR9Tests: XCTestCase {

    private static let ancla = Date(timeIntervalSinceReferenceDate: 774_500_000)

    private static func grafica(
        _ puntos: [(fecha: Date, valor: Double)],
        formatoScrub: @escaping (Double, Date) -> String = { v, _ in "\(Int(v)) ms" }
    ) -> LiquidGraficaNiveles {
        LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [.init(lo: 49, hi: 71, color: LiquidColor.cian, activa: true)],
            dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")],
            tono: LiquidColor.cian,
            formatoScrub: formatoScrub,
            estado: .datos,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
    }

    // MARK: hayEspacioParaPuntos · bordes (r8: n=1 → true)

    func test_espacio_unCentro_siempreCabe_yCero_no() {
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: [0]))
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: [296]))
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: []))
    }

    func test_espacio_umbralExacto_yUnoMas() {
        let paso = LiquidChart.puntoDatoSeparacion + 1
        let justo = (0..<LiquidChart.puntoDatoUmbral).map { CGFloat($0) * paso }
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: justo), "el umbral es inclusivo")
        let unoMas = (0...LiquidChart.puntoDatoUmbral).map { CGFloat($0) * paso }
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: unoMas), "por encima del umbral, no")
    }

    func test_espacio_dosCentrosPegados_no_yConNaN_no() {
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: [100, 100 + LiquidChart.puntoDatoSeparacion - 0.5]))
        // Un centro NaN no puede afirmar separación: `abs(nan - x) >= s` es false → no se dibuja.
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: [100, .nan]))
    }

    // MARK: valorA11y · no finito (r8)

    func test_valorA11y_infinito_noLlegaAlFormateador() {
        let pts: [(fecha: Date, valor: Double)] = [(fecha: Self.ancla, valor: .infinity)]
        XCTAssertEqual(Self.grafica(pts).valorA11y, "Sin lecturas en este rango.")
        let neg: [(fecha: Date, valor: Double)] = [(fecha: Self.ancla, valor: -.infinity)]
        XCTAssertEqual(Self.grafica(neg).valorA11y, "Sin lecturas en este rango.")
    }

    func test_valorA11y_unPuntoFinito_diceElValor() {
        let pts: [(fecha: Date, valor: Double)] = [(fecha: Self.ancla, valor: 56)]
        XCTAssertEqual(Self.grafica(pts).valorA11y, "56 ms")
    }

    func test_valorA11y_nanSoloEnElPuntoLeido() {
        // Sin scrub se lee el ÚLTIMO punto: si es hueco, el pozo; si el hueco está antes, el valor.
        let ayer = Self.ancla.addingTimeInterval(-86_400)
        let huecoAlFinal: [(fecha: Date, valor: Double)] = [(fecha: ayer, valor: 60), (fecha: Self.ancla, valor: .nan)]
        XCTAssertEqual(Self.grafica(huecoAlFinal).valorA11y, "Sin lecturas en este rango.")
        let huecoAntes: [(fecha: Date, valor: Double)] = [(fecha: ayer, valor: .nan), (fecha: Self.ancla, valor: 60)]
        XCTAssertEqual(Self.grafica(huecoAntes).valorA11y, "60 ms")
    }

    // MARK: tonoTexto · el ámbar se demota, los demás no (r8: también en LiquidFraseNivel)

    func test_tonoTexto_ambarYAtencion_aAtencionTexto_otrosIntactos() {
        XCTAssertEqual(LiquidSheetHeader.tonoTexto(LiquidColor.atencion), LiquidColor.atencionTexto)
        XCTAssertEqual(LiquidSheetHeader.tonoTexto(LiquidColor.ambar), LiquidColor.atencionTexto)
        XCTAssertEqual(LiquidSheetHeader.tonoTexto(LiquidColor.cian), LiquidColor.cian)
        XCTAssertEqual(LiquidSheetHeader.tonoTexto(LiquidColor.verdeProfundo), LiquidColor.verdeProfundo)
        XCTAssertEqual(LiquidSheetHeader.tonoTexto(LiquidColor.tinta500), LiquidColor.tinta500)
    }

    // MARK: a11yLabel · «—» con sello (r7/r8)

    func test_a11yLabel_guion_conSello_diceSoloTituloYSello() {
        XCTAssertEqual(LiquidSheetHeader.a11yLabel(titulo: "VFC", numeral: "—", unidad: "ms",
                                                  sufijo: "/ 100", sello: "ANOCHE · 3 AGO", origen: nil),
                       "VFC, —, ANOCHE · 3 AGO")
    }
}
