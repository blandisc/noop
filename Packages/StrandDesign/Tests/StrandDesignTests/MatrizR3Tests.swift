import XCTest
@testable import StrandDesign

final class MatrizR3Tests: XCTestCase {

    func testYNormNaN() {
        let result = MatrizChartDraw.yNorm(.nan, domain: 0...10)
        XCTAssertEqual(result, 0.5, accuracy: 0.01)
    }

    func testTramosConHueco() {
        let result = MatrizChartDraw.tramos(
            [1, .nan, 2, 3],
            count: 4,
            width: 100,
            dominio: 0...5,
            height: 40
        )
        XCTAssertEqual(result.map { $0.count }, [1, 2])
    }

    func testXAtCountUno() {
        let result = MatrizChartDraw.xAt(index: 0, count: 1, width: 100, inset: 4)
        XCTAssertEqual(result, 96, accuracy: 0.01)
    }

    func testXAtIndexFueraDeRango() {
        let result = MatrizChartDraw.xAt(index: 9, count: 4, width: 100, inset: 4)
        XCTAssertEqual(result, 96, accuracy: 0.01)
    }

    func testXIndiceCountUno() {
        let result = MatrizRegla.xIndice(0, count: 1, width: 300)
        XCTAssertEqual(result, 300 - MatrizTokens.reglaZona, accuracy: 0.01)
    }

    func testFraccionFiloNaN() {
        let result = MatrizCostura.fraccionFilo(.nan)
        XCTAssertEqual(result, 0, accuracy: 0.01)
    }

    func testBaseTempSinResp() {
        let result = MatrizHilos.Geometria.baseTemp(hayResp: false)
        XCTAssertEqual(result, MatrizTokens.alturaHilos / 2, accuracy: 0.01)
    }

    func testTramosCountCero() {
        let resultado = MatrizChartDraw.tramos(
            [],
            count: 0,
            width: 100,
            dominio: 0...5,
            height: 40
        )
        XCTAssertTrue(resultado.isEmpty)
    }

    func testXAtWidthNegativo() {
        let resultado = MatrizChartDraw.xAt(index: 0, count: 3, width: -10, inset: 4)
        XCTAssertTrue(resultado.isFinite)
    }

    func testYNormDominioDegenerado() {
        let result = MatrizChartDraw.yNorm(5, domain: 7...7)
        XCTAssertEqual(result, 0.5, accuracy: 0.01)
    }

    func testColinaXDeInfinito() {
        let resultado = MatrizColina.xDe(.infinity, width: 150, inset: 8)
        XCTAssertTrue(resultado.isFinite)
    }
}
