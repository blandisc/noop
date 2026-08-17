import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-84 — la boleta deja de ser un pictograma: la joya se coloca por la desviación REAL del día.
///
/// El mapa que se prueba aquí es el contrato entero de esa superficie: el centro es tu base, el
/// borde de la banda es tu ±1σ (el MISMO corte con el que el motor decide si un eje se salió), y
/// más allá la joya camina hasta el tope del bigote y ahí se queda. Sin números impresos: si este
/// mapa se tuerce, la hoja miente sin que nadie lo note leyendo el texto.
final class VotoRielPosicionTests: XCTestCase {

    private func pos(_ z: Double) -> CGFloat { LiquidVotoRiel.posicion(desviacion: z) }

    func testBaseQuedaEnElCentro() {
        XCTAssertEqual(pos(0), 0.5, accuracy: 0.0001)
    }

    /// ±1σ cae EXACTAMENTE en el borde de la banda: el corte que vota y el dibujo son el mismo.
    func testUnaSigmaCaeEnElBordeDeLaBanda() {
        XCTAssertEqual(pos(1), LiquidVotoRiel.posBandaHi, accuracy: 0.0001)
        XCTAssertEqual(pos(-1), 1 - LiquidVotoRiel.posBandaHi, accuracy: 0.0001)
    }

    func testDentroDeLaBandaSeQuedaDentro() {
        for z in [-0.9, -0.5, -0.1, 0.1, 0.5, 0.9] {
            let p = pos(z)
            XCTAssertGreaterThan(p, 1 - LiquidVotoRiel.posBandaHi, "z=\(z)")
            XCTAssertLessThan(p, LiquidVotoRiel.posBandaHi, "z=\(z)")
        }
    }

    func testFueraDeLaBandaSaleDeLaBanda() {
        XCTAssertGreaterThan(pos(1.5), LiquidVotoRiel.posBandaHi)
        XCTAssertLessThan(pos(-1.5), 1 - LiquidVotoRiel.posBandaHi)
    }

    /// Un extremo se ve extremo, pero nunca se sale del instrumento.
    func testLosExtremosSeDetienenEnElBigote() {
        for z in [2.5, 4.0, 12.0, 1_000.0] {
            XCTAssertEqual(pos(z), LiquidVotoRiel.bigoteHi, accuracy: 0.0001, "z=\(z)")
        }
        for z in [-2.5, -4.0, -12.0, -1_000.0] {
            XCTAssertEqual(pos(z), LiquidVotoRiel.bigoteLo, accuracy: 0.0001, "z=\(z)")
        }
    }

    /// El mapa es monótono: más lejos de tu base, más lejos del centro. Sin esto, dos días
    /// distintos podrían dibujarse en el mismo lugar.
    func testElMapaEsMonotono() {
        var previa = pos(-3)
        for step in stride(from: -2.9, through: 3.0, by: 0.1) {
            let actual = pos(step)
            XCTAssertGreaterThanOrEqual(actual, previa, "z=\(step)")
            previa = actual
        }
    }

    /// Simetría: la misma distancia a cada lado de la base se dibuja a la misma distancia del centro.
    func testElMapaEsSimetrico() {
        for z in [0.3, 0.75, 1.0, 1.8, 2.4] {
            XCTAssertEqual(pos(z) - 0.5, 0.5 - pos(-z), accuracy: 0.0001, "z=\(z)")
        }
    }
}
