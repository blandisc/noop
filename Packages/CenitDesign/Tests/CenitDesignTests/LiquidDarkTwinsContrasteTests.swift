import XCTest
import SwiftUI
@testable import CenitDesign

/// A2/FER-346 — los gemelos oscuros de `LiquidColor` (solo iPhone, D1=a) pasan AA sobre el lienzo
/// oscuro. Igual que `LiquidOLEDContrasteTests` mide el set del Watch, esto mide el set oscuro del
/// teléfono con la MISMA autoridad (`OKLab.contrastRatio`), nunca a ojo. XCTest → hilo principal
/// (resolver colores dinámicos off-main deadlockea en macOS; ver LiquidDetalleLegoTests).
final class LiquidDarkTwinsContrasteTests: XCTestCase {

    override func setUp() { super.setUp(); LiquidTheme.oscuroHabilitado = true }
    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    /// El suelo oscuro contra el que se mide (el lienzo de pantalla en oscuro).
    private var suelo: Color { LiquidColor.fondoAlto.resolved(at: .dark) }

    private func cr(_ token: Color) -> Double {
        OKLab.contrastRatio(token.resolved(at: .dark), suelo)
    }

    /// Texto/tinta: ≥ 4.5:1 (AA texto normal) sobre el lienzo oscuro.
    func testTintaPasaAATextoSobreOscuro() {
        let inks: [(String, Color)] = [
            ("tinta900", LiquidColor.tinta900), ("tinta700", LiquidColor.tinta700),
            ("tinta500", LiquidColor.tinta500),
        ]
        for (n, c) in inks {
            XCTAssertGreaterThanOrEqual(cr(c), 4.5 - 0.05, "\(n) debe pasar AA texto (≥4.5) sobre oscuro, dio \(cr(c))")
        }
    }

    /// Tonos de dato: ≥ 3:1 (AA-large / dato a tamaño de numeral) sobre el lienzo oscuro.
    func testTonosDeDatoPasanSobreOscuro() {
        let datos: [(String, Color)] = [
            ("rosa", LiquidColor.rosa), ("indigo", LiquidColor.indigo), ("cian", LiquidColor.cian),
            ("ambar", LiquidColor.ambar), ("teal", LiquidColor.teal), ("azul", LiquidColor.azul),
            ("doradoTemp", LiquidColor.doradoTemp), ("verdeCarga", LiquidColor.verdeCarga),
            ("estresMedio", LiquidColor.estresMedio), ("estresAlto", LiquidColor.estresAlto),
            ("verdePrimario", LiquidColor.verdePrimario), ("negativo", LiquidColor.negativo),
            ("atencion", LiquidColor.atencion), ("atencionTexto", LiquidColor.atencionTexto),
            ("positivo", LiquidColor.positivo),
        ]
        for (n, c) in datos {
            XCTAssertGreaterThanOrEqual(cr(c), 3.0 - 0.05, "\(n) debe pasar ≥3:1 sobre oscuro, dio \(cr(c))")
        }
    }

    /// El gemelo oscuro DIFIERE del claro (si no, no habría modo oscuro para ese rol).
    func testGemelosDifierenDelClaro() {
        for (n, c) in [("tinta900", LiquidColor.tinta900), ("indigo", LiquidColor.indigo),
                       ("fondoAlto", LiquidColor.fondoAlto)] {
            let l = c.resolved(at: .light).rgbaComponents, d = c.resolved(at: .dark).rgbaComponents
            XCTAssertFalse(abs(l.r - d.r) < 0.02 && abs(l.g - d.g) < 0.02 && abs(l.b - d.b) < 0.02,
                           "\(n): el gemelo oscuro debe diferir del claro")
        }
    }
}
