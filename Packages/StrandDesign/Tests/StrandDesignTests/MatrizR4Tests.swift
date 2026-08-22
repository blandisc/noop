import XCTest
@testable import StrandDesign

// MARK: - Revisión adversarial ronda 4 (acotada): geometría Matriz + polvo
//
// Solo casos de borde sobre símbolos ya existentes. Sin tocar producción.

final class MatrizR4Tests: XCTestCase {

    // MARK: MatrizChartDraw

    /// Un único punto NaN no produce segmentos dibujables y no crashea.
    func test_tramos_unicoPuntoNaN_quedaVacioSinCrash() {
        let out = MatrizChartDraw.tramos(
            [Optional(Double.nan)],
            count: 1, width: 200,
            dominio: 0...1, height: 40, inset: 4
        )
        XCTAssertTrue(out.isEmpty)
    }

    /// Lienzo sin ancho (width: 0) con una sola muestra: x finita, no NaN ni infinito.
    func test_xAt_widthCero_countUno_esFinito() {
        let x = MatrizChartDraw.xAt(index: 0, count: 1, width: 0, inset: 4)
        XCTAssertTrue(x.isFinite)
    }

    // MARK: MatrizColina

    func test_colina_xDe_enElPiso_caeEnInset() {
        XCTAssertEqual(MatrizColina.xDe(0.5, width: 150, inset: 8), 8)
    }

    func test_colina_xDe_enElTecho_caeEnAnchoMenosInset() {
        XCTAssertEqual(MatrizColina.xDe(1.8, width: 150, inset: 8), 142)
    }

    func test_colina_campana_enElCentro_esUno() {
        XCTAssertEqual(MatrizColina.campana(1.05), 1, accuracy: 1e-12)
    }

    func test_colina_campana_muyLejos_casiCero() {
        XCTAssertLessThan(MatrizColina.campana(5), 0.001)
    }

    // MARK: MatrizRegla

    /// Último índice de una serie de 2: al final del usable (= width − reglaZona).
    func test_regla_xIndice_ultimoDeDos_alFiloDeLaZona() {
        XCTAssertEqual(
            MatrizRegla.xIndice(1, count: 2, width: 300),
            300 - MatrizTokens.reglaZona,
            accuracy: 0.001
        )
    }

    // MARK: MatrizHilos.Geometria

    func test_hilos_banda_alrededorDeMitadDeAltura_quedaDentroDelLienzo() {
        let H = MatrizTokens.alturaHilos
        let banda = MatrizHilos.Geometria.banda(base: H / 2)
        XCTAssertGreaterThanOrEqual(banda.lowerBound, 0)
        XCTAssertLessThan(banda.lowerBound, H)
        XCTAssertGreaterThanOrEqual(banda.upperBound, 0)
        XCTAssertLessThan(banda.upperBound, H)
    }

    func test_hilos_estilo_filoExactoEsFuera_yCasiFiloEsDentro() {
        XCTAssertEqual(
            MatrizHilos.Geometria.estilo(v: 1.0, parFuera: false, leido: false),
            .fuera
        )
        XCTAssertEqual(
            MatrizHilos.Geometria.estilo(v: 0.98, parFuera: false, leido: false),
            .dentro
        )
    }

    // MARK: MatrizCostura

    func test_costura_fraccionFilo_cruzaFiloBandaEnElHuecoDelAncla() {
        XCTAssertGreaterThan(MatrizCostura.fraccionFilo(1.02), MatrizCostura.filoBanda)
        XCTAssertLessThan(MatrizCostura.fraccionFilo(0.98), MatrizCostura.filoBanda)
    }

    // MARK: PolvoSimulacion

    func test_polvo_cuenta_lienzoVacioONegativo_esCero() {
        XCTAssertEqual(PolvoSimulacion.cuenta(lienzo: .zero), 0)
        XCTAssertEqual(PolvoSimulacion.cuenta(lienzo: CGSize(width: -10, height: 10)), 0)
    }

    func test_polvo_particula_tGrande_sigueDentroDelLienzoConAlfaFinita() {
        let lienzo = CGSize(width: 400, height: 800)
        let p = PolvoSimulacion.particula(
            indice: 0, t: 1e7, lienzo: lienzo,
            desplazamiento: 0, neutra: false, still: false
        )
        XCTAssertTrue((0...400).contains(p.centro.x))
        XCTAssertTrue((0...800).contains(p.centro.y))
        XCTAssertTrue(p.alfa.isFinite)
    }
}
