import XCTest
import SwiftUI
@testable import StrandDesign

// MARK: - Revision adversarial ronda 6 (acotada): tono del guardian + tokens/chart/hilos/costura/polvo
//
// Solo casos sobre simbolos ya existentes, distintos a R3/R4/R5 en los sondeos nuevos.
// Sin tocar produccion.

final class MatrizR6Tests: XCTestCase {

    // MARK: LiquidGuardianHoja.tono

    /// Fixture `unaFuera`: enPatron == false, nivel != nil. Con racha, el tono es negativo.
    func test_guardian_fueraDePatron_conRacha_tonoNegativo() {
        var hoja = LiquidGuardianFixtures.unaFuera
        XCTAssertFalse(hoja.enPatron)
        XCTAssertNotNil(hoja.nivel)
        hoja.racha = true
        XCTAssertEqual(hoja.tono, LiquidColor.negativo)
    }

    /// Misma hoja sin racha: tono de atencion (ambar).
    func test_guardian_fueraDePatron_sinRacha_tonoAtencion() {
        var hoja = LiquidGuardianFixtures.unaFuera
        hoja.racha = false
        XCTAssertEqual(hoja.tono, LiquidColor.atencion)
    }

    /// Fixture `enPatron`: enPatron manda sobre racha → verdePrimario.
    func test_guardian_enPatron_tonoVerdePrimario() {
        let hoja = LiquidGuardianFixtures.enPatron
        XCTAssertTrue(hoja.enPatron)
        XCTAssertEqual(hoja.tono, LiquidColor.verdePrimario)
    }

    /// Fixture `sinLectura`: nivel == nil → tinta500 (sin base todavia).
    func test_guardian_sinNivel_tonoTinta500() {
        let hoja = LiquidGuardianFixtures.sinLectura
        XCTAssertNil(hoja.nivel)
        XCTAssertEqual(hoja.tono, LiquidColor.tinta500)
    }

    // MARK: MatrizTokens

    func test_tokens_escaleraHoyMasPresenteYBarrasPiso() {
        XCTAssertGreaterThan(
            MatrizTokens.escaleraHoyApagadaAlfa,
            MatrizTokens.escaleraApagadaAlfa
        )
        XCTAssertEqual(MatrizTokens.barrasPiso, 2)
    }

    // MARK: MatrizChartDraw

    func test_xAt_countUno_caeAlFinalDelAnchoUtil() {
        let x = MatrizChartDraw.xAt(index: 0, count: 1, width: 100, inset: 4)
        XCTAssertEqual(x, 96 as CGFloat)
    }

    func test_tramos_nilCortaEnDosTramosDeUnPunto() {
        let out = MatrizChartDraw.tramos(
            [1, nil, 2], count: 3, width: 100,
            dominio: 0...5, height: 40
        )
        XCTAssertEqual(out.map(\.count), [1, 1])
    }

    // MARK: MatrizHilos.Geometria

    func test_hilos_estilo_parFueraMandaSobreValorAlto() {
        XCTAssertEqual(
            MatrizHilos.Geometria.estilo(v: 1.5, parFuera: true, leido: false),
            .par
        )
    }

    // MARK: MatrizCostura

    func test_costura_fraccionFilo_huecoDelAnclaAlrededorDeFiloBanda() {
        XCTAssertLessThan(MatrizCostura.fraccionFilo(0.98), MatrizCostura.filoBanda)
        XCTAssertGreaterThan(MatrizCostura.fraccionFilo(1.02), MatrizCostura.filoBanda)
    }

    // MARK: PolvoSimulacion.Fisica

    func test_polvo_radioMin_alMenosUno() {
        XCTAssertGreaterThanOrEqual(PolvoSimulacion.Fisica.radioMin, 1.0)
    }

    // MARK: Sondajes nuevos (no en R3/R4/R5)

    /// count <= 1 cae al mismo guard; blindar count: 0 explicitamente.
    func test_xAt_countCero_caeAlFinalDelAnchoUtil() {
        let x = MatrizChartDraw.xAt(index: 0, count: 0, width: 100, inset: 4)
        XCTAssertEqual(x, 96 as CGFloat)
        XCTAssertTrue(x.isFinite)
    }

    /// Serie contigua sin huecos: un solo tramo con todos los puntos.
    func test_tramos_serieContigua_unSoloTramo() {
        let out = MatrizChartDraw.tramos(
            [1, 2, 3], count: 3, width: 100,
            dominio: 0...5, height: 40
        )
        XCTAssertEqual(out.map(\.count), [3])
    }
}
