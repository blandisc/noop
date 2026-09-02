import XCTest
@testable import CenitDesign

/// FER-51 — el motor de medios tonos es el CONTRATO entre el Canvas de F1 y el shader
/// Metal de F2: mismo Bayer, misma semilla, misma partícula. Estos tests lo clavan.
final class MatrizDitherTests: XCTestCase {

    func testBayerEsLaMatrizCanonica() {
        XCTAssertEqual(MatrizDither.bayer4x4,
                       [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5])
    }

    func testDensidadCeroNoPintaYUnoPintaTodo() {
        for x in 0..<8 {
            for y in 0..<8 {
                XCTAssertFalse(MatrizDither.encendido(x: x, y: y, densidad: 0))
                XCTAssertTrue(MatrizDither.encendido(x: x, y: y, densidad: 1))
            }
        }
    }

    func testDensidadMediaPintaExactamenteLaMitadDelBloque() {
        var encendidos = 0
        for x in 0..<4 {
            for y in 0..<4 where MatrizDither.encendido(x: x, y: y, densidad: 0.5) {
                encendidos += 1
            }
        }
        XCTAssertEqual(encendidos, 8)
    }

    func testDensidadEsMonotona() {
        for x in 0..<4 {
            for y in 0..<4 where MatrizDither.encendido(x: x, y: y, densidad: 0.3) {
                XCTAssertTrue(MatrizDither.encendido(x: x, y: y, densidad: 0.9),
                              "una celda encendida a densidad baja debe seguir encendida a densidad alta")
            }
        }
    }

    func testSemillaEsDeterministaYSeparaGraficas() {
        XCTAssertEqual(MatrizDither.semilla(chartID: "sueno", index: 3),
                       MatrizDither.semilla(chartID: "sueno", index: 3))
        XCTAssertNotEqual(MatrizDither.semilla(chartID: "sueno", index: 3),
                          MatrizDither.semilla(chartID: "fc", index: 3))
        XCTAssertNotEqual(MatrizDither.semilla(chartID: "sueno", index: 3),
                          MatrizDither.semilla(chartID: "sueno", index: 4))
    }

    func testParticulaEsDeterministaYAcotada() {
        let s = MatrizDither.semilla(chartID: "carga", index: 7)
        let a = MatrizDither.particula(s)
        let b = MatrizDither.particula(s)
        XCTAssertEqual(a.dScale, b.dScale)
        XCTAssertEqual(a.dAlpha, b.dAlpha)
        XCTAssertEqual(a.dx, b.dx)
        XCTAssertEqual(a.dy, b.dy)
        for i in 0..<200 {
            let p = MatrizDither.particula(MatrizDither.semilla(chartID: "rango", index: i))
            XCTAssertTrue((0.8...1.25).contains(p.dScale))
            XCTAssertTrue((0.75...1.0).contains(p.dAlpha))
            XCTAssertTrue((-0.5...0.5).contains(p.dx))
            XCTAssertTrue((-0.5...0.5).contains(p.dy))
        }
    }
}
