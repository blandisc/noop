import XCTest
import SwiftUI
@testable import CenitDesign

/// A1/FER-345 — el contrato de resolución de tema. Prueba el MECANISMO (independiente de qué tokens
/// se hayan migrado aún): un `LiquidTheme.dynamic(light:dark:)` resuelve por modo SOLO cuando el
/// kill-switch `oscuroHabilitado` está encendido, y `Color.resolved(at:)` resuelve de forma explícita
/// (no depende de la apariencia del host headless). Con el flag apagado (default de A1/A2) TODO
/// resuelve claro en ambos schemes — el invariante «apagado hasta A3».
final class LiquidThemeResolveTests: XCTestCase {

    override func tearDown() {
        LiquidTheme.oscuroHabilitado = false   // deja el default global limpio para otros tests
        super.tearDown()
    }

    private func approxEqual(_ a: Color, _ b: Color, eps: Double = 1.0 / 255) -> Bool {
        let x = a.rgbaComponents, y = b.rgbaComponents
        return abs(x.r - y.r) <= eps && abs(x.g - y.g) <= eps
            && abs(x.b - y.b) <= eps && abs(x.a - y.a) <= eps
    }

    /// Flag ON: un token dinámico con gemelos distintos resuelve distinto en .light vs .dark (AC1).
    func testResuelveDistintoPorModoConFlagEncendido() {
        LiquidTheme.oscuroHabilitado = true
        let token = LiquidTheme.dynamic(light: .white, dark: .black)
        XCTAssertFalse(approxEqual(token.resolved(at: .light), token.resolved(at: .dark)),
                       "Con el flag ON, un token con gemelos distintos debe resolver distinto por modo")
    }

    /// Flag OFF (default de A1/A2): el MISMO token resuelve a `light` en AMBOS schemes
    /// («apagado hasta A3», requisito 6) — cero rama oscura viva.
    func testColapsaAClaroConFlagApagado() {
        LiquidTheme.oscuroHabilitado = false
        let token = LiquidTheme.dynamic(light: .white, dark: .black)
        XCTAssertTrue(approxEqual(token.resolved(at: .light), .white),
                      "Con el flag OFF, .light debe ser el valor claro")
        XCTAssertTrue(approxEqual(token.resolved(at: .dark), .white),
                      "Con el flag OFF, .dark también debe colapsar al valor claro (apagado hasta A3)")
    }

    /// `resolved(at:)` es determinista: mismo scheme → mismo resultado, sin depender del host.
    func testResueltoEsDeterminista() {
        LiquidTheme.oscuroHabilitado = true
        let token = LiquidTheme.dynamic(light: .white, dark: .black)
        XCTAssertTrue(approxEqual(token.resolved(at: .dark), token.resolved(at: .dark)))
    }
}
