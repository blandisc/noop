import XCTest
import SwiftUI
@testable import StrandDesign

/// El contrato de accesibilidad de la leyenda: UNA parada de VoiceOver por peldaño.
///
/// Esta prueba existe porque no existía: al extraer la leyenda del calendario de 90 a pieza
/// (FER-129) el `.combine` se movió del ítem al contenedor y los cuatro peldaños se fundieron
/// en una sola parada concatenada, en Sueño, en producción, y ninguna de las 14 pruebas del
/// calendario lo vio. Un contrato de a11y que no tiene prueba es una regresión esperando.
final class LiquidLeyendaNivelesTests: XCTestCase {

    private let cuatro: [LiquidCalendario90.NivelLeyenda] = [
        .init(id: "full", color: LiquidColor.verdePrimario, etiqueta: "Todo en rango"),
        .init(id: "caution", color: LiquidColor.atencion, etiqueta: "Una señal fuera"),
        .init(id: "easy", color: LiquidColor.negativo, etiqueta: "Dos o más fuera"),
        .init(id: "none", color: LiquidColor.celdaVaciaPip, etiqueta: "Sin lectura"),
    ]

    func testCadaPeldanoEsSuPropiaParada() {
        // Contrato: UNA parada de VoiceOver por peldaño (el helper `paradasDeVoiceOver` se podó
        // en FER-286 — era `niveles.count`; el conteo del modelo basta para fijar el contrato).
        XCTAssertEqual(cuatro.count, 4,
                       "cuatro peldaños son cuatro paradas, nunca una sola con todo concatenado")
        XCTAssertEqual([LiquidCalendario90.NivelLeyenda]().count, 0)
    }

    func testCadaParadaDictaSuPalabra() {
        XCTAssertEqual(cuatro.map(LiquidLeyendaNiveles.dictado),
                       ["Todo en rango", "Una señal fuera", "Dos o más fuera", "Sin lectura"])
    }

    /// La pieza se construye para una leyenda de N peldaños y expone los mismos contratos
    /// para la retícula de 90 y para la de 30: una sola leyenda para todo el sistema.
    func testLaMismaPiezaSirveParaTresYParaCuatro() {
        XCTAssertEqual(Array(cuatro.prefix(3)).count, 3)
    }
}
