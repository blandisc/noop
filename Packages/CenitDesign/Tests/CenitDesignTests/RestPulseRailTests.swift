import XCTest
@testable import CenitDesign

/// FER-86 — el riel del descanso por pulso subió de la sesión al componente compartido. Su
/// geometría es lo único que puede estar mal de una forma que el ojo no cacha: un riel que se llena
/// al revés, o que se sale, se ve «plausible» en una captura y miente a media serie.
final class RestPulseRailTests: XCTestCase {

    /// Recién terminada la serie el corazón está en su pico nominal (objetivo + 40): el riel arranca
    /// vacío. En el objetivo está lleno. Es la dirección, y es la que se puede invertir sin notarlo.
    func testVaDeVacioEnElPicoALlenoEnElObjetivo() {
        XCTAssertEqual(RestPulseRail.fraccion(bpm: 140, target: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(RestPulseRail.fraccion(bpm: 100, target: 100), 1, accuracy: 1e-9)
        XCTAssertEqual(RestPulseRail.fraccion(bpm: 120, target: 100), 0.5, accuracy: 1e-9)
    }

    /// Satura en los dos extremos. Sin esto, un pulso por debajo del objetivo llenaría de más (el
    /// riel se saldría de su carril) y uno por encima del pico devolvería negativo (ancho negativo).
    func testSaturaEnLosDosExtremos() {
        XCTAssertEqual(RestPulseRail.fraccion(bpm: 60, target: 100), 1, accuracy: 1e-9)
        XCTAssertEqual(RestPulseRail.fraccion(bpm: 200, target: 100), 0, accuracy: 1e-9)
    }

    /// Sin objetivo no hay caída que medir: el riel se declara lleno en vez de dividir entre cero.
    func testSinObjetivoNoDivideEntreCero() {
        let f = RestPulseRail.fraccion(bpm: 120, target: nil)
        XCTAssertEqual(f, 0, accuracy: 1e-9, "sin objetivo, el pico y el piso son el mismo pulso")
        XCTAssertFalse(f.isNaN)
    }

    /// Monótona: bajar el pulso nunca puede vaciar el riel. Es la propiedad que un cambio de fórmula
    /// rompe primero, y la que ninguna captura delata.
    func testBajarElPulsoSiempreLlenaMas() {
        var previa = -1.0
        for bpm in stride(from: 140, through: 100, by: -5) {
            let f = RestPulseRail.fraccion(bpm: bpm, target: 100)
            XCTAssertGreaterThan(f, previa, "a \(bpm) bpm el riel no avanzó")
            previa = f
        }
    }
}
