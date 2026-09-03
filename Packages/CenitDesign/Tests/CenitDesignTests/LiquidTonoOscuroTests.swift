import XCTest
import SwiftUI
@testable import CenitDesign

/// B3/FER-351 — vidrio teñido de Entrenar en oscuro, con los emparejamientos CORRECTOS (espejo de
/// LiquidTonoContrasteTests): el rótulo sobre el VIDRIO COMPUESTO `mix(papelTarjeta, base, 0.10)` (≥4.5),
/// y el texto claro (blanco) sobre la TESELA (≥3). En oscuro el papel es oscuro → el rótulo se aclara.
final class LiquidTonoOscuroTests: XCTestCase {
    override func setUp() { super.setUp(); LiquidTheme.oscuroHabilitado = true }
    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    private func compuesto(_ t: LiquidTono) -> Color {
        OKLab.mix(LiquidColor.papelTarjeta.resolved(at: .dark), t.base.resolved(at: .dark),
                  LiquidTono.intensidadDefault)
    }

    func testRotuloAASobreVidrioOscuro() {
        for t in LiquidTono.allCases {
            let cr = OKLab.contrastRatio(t.rotulo.resolved(at: .dark), compuesto(t))
            XCTAssertGreaterThanOrEqual(cr, 4.5 - 0.1, "rótulo \(t) sobre vidrio oscuro: \(cr)")
        }
    }

    func testTeselaSostieneBlancoEnOscuro() {
        for t in LiquidTono.allCases where t != .neutro {
            let cr = OKLab.contrastRatio(.white, t.tesela.resolved(at: .dark))
            XCTAssertGreaterThanOrEqual(cr, 3.0 - 0.05, "tesela \(t) con texto blanco en oscuro: \(cr)")
        }
    }
}
