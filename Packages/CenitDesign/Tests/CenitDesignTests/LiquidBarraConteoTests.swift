import XCTest
@testable import CenitDesign

/// Los contratos puros de la barra de conteo — los mismos que leen la vista y VoiceOver.
final class LiquidBarraConteoTests: XCTestCase {

    /// La escala la manda el caller y es COMPARTIDA: dos conteos sobre la misma ventana dan
    /// fracciones comparables. Es lo que la distingue de `LiquidBarraMarca`, que normaliza
    /// por fila a propósito y por eso no servía aquí.
    func testLaEscalaEsCompartida() {
        XCTAssertEqual(LiquidBarraConteo.fraccion(conteo: 15, escala: 30), 0.5)
        XCTAssertEqual(LiquidBarraConteo.fraccion(conteo: 3, escala: 30), 0.1)
        XCTAssertEqual(LiquidBarraConteo.fraccion(conteo: 30, escala: 30), 1.0,
                       "la ventana entera llena la barra, no el 84.7 % de la pieza hermana")
    }

    /// `nil` y `0` NO son lo mismo: sin conteo no hay barra; con conteo cero hay barra a cero.
    func testNilYCeroSonDistintos() {
        XCTAssertNil(LiquidBarraConteo.fraccion(conteo: nil, escala: 30), "no se pudo contar")
        XCTAssertEqual(LiquidBarraConteo.fraccion(conteo: 0, escala: 30), 0, "se contó y fue cero")
    }

    /// Un conteo nunca supera la ventana que lo contiene; si llega, se clampa en vez de romper.
    func testElConteoNoDesbordaLaVentana() {
        XCTAssertEqual(LiquidBarraConteo.fraccion(conteo: 45, escala: 30), 1.0)
        XCTAssertEqual(LiquidBarraConteo.fraccion(conteo: -2, escala: 30), 0.0)
    }

    /// Una escala inválida no divide entre cero ni fabrica una barra.
    func testEscalaCeroNoRompe() {
        XCTAssertNil(LiquidBarraConteo.fraccion(conteo: 5, escala: 0))
    }

    func testElValorDeVoiceOverSeComponeConPiezasLocalizadas() {
        XCTAssertEqual(LiquidBarraConteo.a11yValue(conteo: "7", escala: "de 30 noches fuera"),
                       "7 de 30 noches fuera")
    }
}
