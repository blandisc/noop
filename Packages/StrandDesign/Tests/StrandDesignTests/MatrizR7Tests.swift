import XCTest
import SwiftUI
@testable import StrandDesign

// MARK: - Revision adversarial ronda 7: frontera Matriz hojas (FER-128 r6)
//
// Sondeos sobre simbolos publicos / @testable ya existentes. Sin tocar produccion.

final class MatrizR7Tests: XCTestCase {

    // MARK: Helpers (replica de LiquidCarrilEA11yTests)

    private static let ancla = Date(timeIntervalSinceReferenceDate: 774_500_000)

    private static func serie(_ n: Int) -> [(fecha: Date, valor: Double)] {
        (0..<n).map { i in
            (fecha: ancla.addingTimeInterval(Double(i - (n - 1)) * 86_400),
             valor: 56.0 + Double(i))
        }
    }

    private static func grafica(_ puntos: [(fecha: Date, valor: Double)],
                                estado: LiquidChartEstado = .datos) -> LiquidGraficaNiveles {
        LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [.init(lo: 49, hi: 71, color: LiquidColor.cian, activa: true)],
            dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")],
            tono: LiquidColor.cian,
            formatoScrub: { v, _ in "\(Int(v)) ms" },
            estado: estado,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
    }

    private static let mensajeVacio = "Sin lecturas en este rango."

    // MARK: a / b · LiquidGraficaNiveles · valorA11y vs pozo vacio

    /// Con 1 punto la voz dice la lectura, no el mensaje de vacio.
    func test_grafica_unPunto_valorA11y_noEsMensajeVacio() {
        XCTAssertNotEqual(Self.grafica(Self.serie(1)).valorA11y, Self.mensajeVacio)
    }

    /// Sin puntos la voz cae al estadoVacio.
    func test_grafica_ceroPuntos_valorA11y_esMensajeVacio() {
        XCTAssertEqual(Self.grafica([]).valorA11y, Self.mensajeVacio)
    }

    // MARK: c · MatrizChartDraw.xAt · count 1

    func test_xAt_countUno_width200_inset4_da196() {
        let x = MatrizChartDraw.xAt(index: 0, count: 1, width: 200, inset: 4)
        XCTAssertEqual(x, 196 as CGFloat)
    }

    // MARK: d · MatrizRegla.xIndice · count 1

    func test_regla_xIndice_countUno_width200_alFiloDeReglaZona() {
        let x = MatrizRegla.xIndice(0, count: 1, width: 200)
        XCTAssertEqual(x, 200 - MatrizTokens.reglaZona)
    }

    // MARK: e · MatrizChartDraw.tramos · nan + nil cortan

    func test_tramos_nanYNil_dejanUnSoloTramoDeUnPunto() {
        let out = MatrizChartDraw.tramos(
            [Double.nan, nil, 3], count: 3, width: 100,
            dominio: 0...5, height: 40
        )
        XCTAssertEqual(out.map(\.count), [1])
    }

    // MARK: f · LiquidGuardianHoja · sello nil no rompe tono

    /// El init acepta sello nil (default); clonando `unaFuera` con sello nil el tono
    /// con racha sigue siendo negativo.
    func test_guardian_selloNil_conRacha_tonoNegativo() {
        let base = LiquidGuardianFixtures.unaFuera
        var hoja = LiquidGuardianHoja(
            titulo: base.titulo,
            explicacion: base.explicacion,
            infoMostrar: base.infoMostrar,
            infoOcultar: base.infoOcultar,
            nivel: base.nivel,
            sinLectura: base.sinLectura,
            conteo: base.conteo,
            sello: nil,
            enPatron: base.enPatron,
            temp: base.temp,
            resp: base.resp,
            pieTarjeta: base.pieTarjeta,
            nota: base.nota,
            notaAvisa: base.notaAvisa,
            reglaKicker: base.reglaKicker,
            reglaTexto: base.reglaTexto,
            reglaClave: base.reglaClave,
            domino: base.domino,
            metodo: base.metodo,
            calibracion: base.calibracion
        )
        XCTAssertNil(hoja.sello)
        hoja.racha = true
        XCTAssertEqual(hoja.tono, LiquidColor.negativo)
    }

    // MARK: g / h · MatrizTokens

    func test_tokens_barrasPiso_esDos() {
        XCTAssertEqual(MatrizTokens.barrasPiso, 2 as CGFloat)
    }

    func test_tokens_escaleraHoyApagadaAlfa_es016() {
        XCTAssertEqual(MatrizTokens.escaleraHoyApagadaAlfa, 0.16)
    }

    // MARK: i · Sondeos nuevos (no en R1–R6)

    /// Con exactamente 1 punto, valorA11y trae el numero formateado (no vacio ni pozo).
    func test_grafica_unPunto_valorA11y_traeNumeroReal() {
        let voz = Self.grafica(Self.serie(1)).valorA11y
        XCTAssertFalse(voz.isEmpty)
        XCTAssertNotEqual(voz, Self.mensajeVacio)
        XCTAssertEqual(voz, "56 ms")
    }

    /// xAt con count 2: index 0 y 1 caen en [inset, width − inset] y son finitos.
    func test_xAt_countDos_indicesDentroDelAnchoUtil() {
        let inset: CGFloat = 4
        let width: CGFloat = 200
        let lo = inset
        let hi = width - inset
        let x0 = MatrizChartDraw.xAt(index: 0, count: 2, width: width, inset: inset)
        let x1 = MatrizChartDraw.xAt(index: 1, count: 2, width: width, inset: inset)
        XCTAssertTrue(x0.isFinite)
        XCTAssertTrue(x1.isFinite)
        XCTAssertGreaterThanOrEqual(x0, lo)
        XCTAssertLessThanOrEqual(x0, hi)
        XCTAssertGreaterThanOrEqual(x1, lo)
        XCTAssertLessThanOrEqual(x1, hi)
    }

    /// xIndice con count 2 tambien cae dentro del rango util del ancho.
    func test_regla_xIndice_countDos_dentroDelAnchoUtil() {
        let width: CGFloat = 200
        let lo = MatrizTokens.chartInset
        let hi = width - MatrizTokens.chartInset
        let x0 = MatrizRegla.xIndice(0, count: 2, width: width)
        let x1 = MatrizRegla.xIndice(1, count: 2, width: width)
        XCTAssertTrue(x0.isFinite)
        XCTAssertTrue(x1.isFinite)
        XCTAssertGreaterThanOrEqual(x0, lo)
        XCTAssertLessThanOrEqual(x0, hi)
        XCTAssertGreaterThanOrEqual(x1, lo)
        XCTAssertLessThanOrEqual(x1, hi)
    }
}
