import XCTest
@testable import StrandDesign

// MARK: - Revision adversarial ronda 5 (acotada): geometria Matriz + polvo
//
// Solo casos de borde sobre simbolos ya existentes, distintos a R3/R4. Sin tocar produccion.

final class MatrizR5Tests: XCTestCase {

    // MARK: MatrizChartDraw

    func test_yNorm_dominioDegenerado_enElValorExacto_esMedio() {
        let result = MatrizChartDraw.yNorm(7, domain: 7...7)
        XCTAssertEqual(result, 0.5, accuracy: 0.01)
    }

    func test_tramos_countMayorQueLaSerieReal_xCaeEnPrimeraMitad() {
        let serie: [Double?] = (1...20).map { Double($0) }
        let width: CGFloat = 100
        let out = MatrizChartDraw.tramos(
            serie, count: 40, width: width,
            dominio: 0...20, height: 40
        )
        let todosLosPuntos = out.flatMap { $0 }
        XCTAssertEqual(todosLosPuntos.count, 20)
        for pt in todosLosPuntos {
            XCTAssertTrue(pt.x.isFinite)
            XCTAssertLessThanOrEqual(pt.x, width / 2 + 1)
        }
    }

    func test_xAt_lienzoMenorQueElInset_esFinito() {
        let x = MatrizChartDraw.xAt(index: 0, count: 1, width: 1, inset: 8)
        XCTAssertTrue(x.isFinite)
    }

    // MARK: MatrizColina

    func test_colina_campana_muyNegativo_esCero() {
        XCTAssertEqual(MatrizColina.campana(-1e9), 0, accuracy: 1e-9)
    }

    func test_colina_campana_muyPositivo_esCero() {
        XCTAssertEqual(MatrizColina.campana(1e9), 0, accuracy: 1e-9)
    }

    // MARK: MatrizHilos.Geometria

    func test_hilos_y_valoresExtremos_quedanDentroDelLienzo() {
        let alto = MatrizTokens.alturaHilos
        let yPos = MatrizHilos.Geometria.y(1e9, base: 28)
        let yNeg = MatrizHilos.Geometria.y(-1e9, base: 28)
        XCTAssertTrue(yPos.isFinite)
        XCTAssertTrue(yNeg.isFinite)
        XCTAssertGreaterThanOrEqual(yPos, 0)
        XCTAssertLessThanOrEqual(yPos, alto)
        XCTAssertGreaterThanOrEqual(yNeg, 0)
        XCTAssertLessThanOrEqual(yNeg, alto)
    }

    func test_hilos_estilo_sinLectura_parManda() {
        // Orden real del codigo: if leido { .leido }; if parFuera { .par }; else v>=1 ? .fuera : .dentro
        XCTAssertEqual(
            MatrizHilos.Geometria.estilo(v: .nan, parFuera: true, leido: false),
            .par
        )
    }

    func test_hilos_estilo_conLectura_leidoManda() {
        XCTAssertEqual(
            MatrizHilos.Geometria.estilo(v: .nan, parFuera: false, leido: true),
            .leido
        )
    }

    // MARK: PolvoSimulacion

    func test_polvo_particula_indiceExtremoYDesplazamientoGigante_centroDentroDelLienzo() {
        let lienzo = CGSize(width: 400, height: 800)
        let p = PolvoSimulacion.particula(
            indice: Int.max / 2, t: 0, lienzo: lienzo,
            desplazamiento: 1e9, neutra: true, still: true
        )
        XCTAssertTrue((0...400).contains(p.centro.x))
        XCTAssertTrue((0...800).contains(p.centro.y))
        XCTAssertEqual(p.tono, .neutra)
    }

    func test_polvo_cuenta_lienzoGigante_seTopaEnElMaximo() {
        let n = PolvoSimulacion.cuenta(lienzo: CGSize(width: 1e6, height: 1e6))
        XCTAssertEqual(n, PolvoSimulacion.Fisica.nMax)
    }

    // MARK: MatrizCostura

    func test_costura_fraccionFilo_extremosQuedanAcotados() {
        XCTAssertLessThan(MatrizCostura.fraccionFilo(1e9), 1)
        XCTAssertGreaterThan(MatrizCostura.fraccionFilo(-1e9), -1)
    }
}
