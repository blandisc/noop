import XCTest
import SwiftUI
@testable import CenitDesign

/// B1/FER-349 — el vidrio se re-ilumina para negro: los tokens `vidrio*` (relleno, borde, canto,
/// highlight) resuelven DISTINTO en oscuro (superficie lit casi-negra + canto de luz), no el blanco
/// translúcido que sobre negro se ve gris. Con el flag apagado siguen byte-idénticos en claro.
/// XCTest → hilo principal (resolver dinámico off-main deadlockea en macOS).
final class LiquidVidrioOscuroTests: XCTestCase {

    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    private func difiere(_ c: Color) -> Bool {
        let l = c.resolved(at: .light).rgbaComponents, d = c.resolved(at: .dark).rgbaComponents
        return abs(l.r - d.r) > 0.02 || abs(l.g - d.g) > 0.02 || abs(l.b - d.b) > 0.02 || abs(l.a - d.a) > 0.02
    }

    func testVidrioResuelveDistintoEnOscuro() {
        LiquidTheme.oscuroHabilitado = true
        for (n, c) in [("vidrioSuperficie", LiquidColor.vidrioSuperficie),
                       ("vidrioBordeSuperficie", LiquidColor.vidrioBordeSuperficie),
                       ("vidrioPastilla", LiquidColor.vidrioPastilla),
                       ("vidrioCanto", LiquidColor.vidrioCanto),
                       ("vidrioAtmosfera", LiquidColor.vidrioAtmosfera),
                       ("vidrioHighlight(0.8)", LiquidColor.vidrioHighlight(0.8))] {
            XCTAssertTrue(difiere(c), "\(n) debe re-iluminarse en oscuro (no quedar igual al claro)")
        }
    }

    func testVidrioClaroByteIdentico() {
        LiquidTheme.oscuroHabilitado = false
        // Con el flag apagado, el relleno de superficie sigue siendo blanco ~46 % (cero cambio hoy).
        let d = LiquidColor.vidrioSuperficie.resolved(at: .light).rgbaComponents
        XCTAssertEqual(d.r, 1, accuracy: 0.01); XCTAssertEqual(d.g, 1, accuracy: 0.01); XCTAssertEqual(d.b, 1, accuracy: 0.01)
        XCTAssertEqual(d.a, 0.46, accuracy: 0.02)
    }
}
