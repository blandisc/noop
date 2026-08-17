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

    // La vara del SUEÑO: piso de 7 h (420 min) con 45 min de holgura, los números del motor.
    private let corte = (420.0 - 45.0) / 420.0
    private let holgura = 45.0 / 420.0
    /// Coloca una noche de N minutos.
    private func sueno(_ minutos: Double) -> CGFloat {
        LiquidVotoRiel.posicion(ratio: minutos / 420.0, corte: corte, holgura: holgura)
    }

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

    /// La saturación ocurre DONDE dice que ocurre: a 1.7σ y a 12σ la joya no puede estar en el
    /// mismo pixel, o la caja no mide nada fuera de la banda.
    func testEntreLaBandaYElTopeSigueHabiendoRecorrido() {
        XCTAssertLessThan(pos(1.2), pos(1.7))
        XCTAssertLessThan(pos(1.7), pos(2.2))
        XCTAssertLessThan(pos(2.2), pos(LiquidVotoRiel.zTope))
    }

    /// Un z no finito no puede llegar a `.position(x:)`: se planta en el centro.
    func testUnZNoFinitoSePlantaEnElCentro() {
        XCTAssertEqual(pos(.nan), 0.5, accuracy: 0.0001)
        XCTAssertEqual(pos(.infinity), LiquidVotoRiel.bigoteHi, accuracy: 0.0001)
        XCTAssertEqual(pos(-.infinity), LiquidVotoRiel.bigoteLo, accuracy: 0.0001)
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

    // MARK: - La vara del sueño (FER-84)

    /// El corte que VOTA cae exactamente en el tick del riel: el dibujo y el voto son el mismo sitio.
    /// El motor vota fuera bajo 375 min (7 h menos la holgura de 45).
    func testElCorteDelSuenoCaeEnSuTick() {
        XCTAssertEqual(sueno(375), 0.36, accuracy: 0.0001)
    }

    /// El defecto que esta vara viene a resolver: dos noches distintas no se dibujan en el mismo
    /// pixel. Se comprueba en TODO el rango humano, no solo en un par cómodo — la primera versión
    /// de la escala pasaba con 3 h contra 6 h y apilaba 3 h contra 5 h.
    func testNingunParDeNochesDistintasSeApila() {
        let noches: [Double] = [180, 240, 300, 360, 420, 480, 540]
        for (i, a) in noches.enumerated() {
            for b in noches.dropFirst(i + 1) {
                XCTAssertGreaterThan(abs(sueno(b) - sueno(a)), 0.04,
                                     "\(Int(a)) min y \(Int(b)) min se dibujan casi igual")
            }
        }
    }

    /// Los extremos del rango humano tocan sus bigotes, y nada se sale.
    func testLosExtremosDelRangoHumanoTocanSusBigotes() {
        XCTAssertEqual(sueno(180), LiquidVotoRiel.bigoteLo, accuracy: 0.0001, "3 h")
        XCTAssertEqual(sueno(540), LiquidVotoRiel.bigoteHi, accuracy: 0.0001, "9 h")
        XCTAssertEqual(sueno(60), LiquidVotoRiel.bigoteLo, accuracy: 0.0001, "una hora se planta")
        XCTAssertEqual(sueno(720), LiquidVotoRiel.bigoteHi, accuracy: 0.0001, "doce horas también")
    }

    /// Más sueño, más a la derecha, siempre.
    func testLaEscalaDelSuenoEsMonotona() {
        var previa = sueno(120)
        for minutos in stride(from: 150.0, through: 600.0, by: 15) {
            let actual = sueno(minutos)
            XCTAssertGreaterThanOrEqual(actual, previa, "\(minutos) min")
            previa = actual
        }
    }

    /// El rango que un humano puede dormir cabe entero en el instrumento, sin salirse.
    func testElRangoHumanoCabeEnElInstrumento() {
        for minutos in [60.0, 180, 300, 420, 480, 540, 660] {
            let p = sueno(minutos)
            XCTAssertGreaterThanOrEqual(p, LiquidVotoRiel.bigoteLo, "\(minutos) min")
            XCTAssertLessThanOrEqual(p, LiquidVotoRiel.bigoteHi, "\(minutos) min")
        }
    }

    /// Una noche en el piso recomendado cae DENTRO de la banda, a la derecha del corte.
    func testElPisoRecomendadoCaeDentroDeLaBanda() {
        XCTAssertGreaterThan(sueno(420), 0.36)
        XCTAssertLessThan(sueno(420), LiquidVotoRiel.bigoteHi)
    }

    /// Las dos varas no se mezclan: el mismo número significa cosas distintas en cada una, y el
    /// tipo obliga a decir cuál es cuál.
    func testLasDosVarasSonDistintas() {
        let porSigmas = LiquidVotoRiel.posicion(.sigmas(0))
        let porNecesidad = LiquidVotoRiel.posicion(
            .fraccionDeNecesidad(ratio: corte, corte: corte, holgura: holgura))
        XCTAssertEqual(porSigmas, 0.5, accuracy: 0.0001, "la base del autonómico va al centro")
        XCTAssertEqual(porNecesidad, 0.36, accuracy: 0.0001, "el corte del sueño va a su tick")
    }

    /// Datos imposibles no llegan al dibujo.
    func testLaVaraDelSuenoAguantaDatosRotos() {
        XCTAssertEqual(LiquidVotoRiel.posicion(ratio: .nan, corte: corte, holgura: holgura), 0.36, accuracy: 0.0001)
        XCTAssertEqual(LiquidVotoRiel.posicion(ratio: 1, corte: corte, holgura: 0), 0.36, accuracy: 0.0001)
    }

    /// Simetría: la misma distancia a cada lado de la base se dibuja a la misma distancia del centro.
    func testElMapaEsSimetrico() {
        for z in [0.3, 0.75, 1.0, 1.8, 2.4] {
            XCTAssertEqual(pos(z) - 0.5, 0.5 - pos(-z), accuracy: 0.0001, "z=\(z)")
        }
    }
}
