import XCTest
import SwiftUI
@testable import CenitDesign

/// Retro FER-309: el QA independiente cazó TRES veces (Watch, Widgets, N1) tintas por debajo de 4.5:1
/// sobre el negro OLED porque el implementador mapea por rol sin calcular. `LiquidOLED` es el set
/// que pinta texto y dato sobre `fondo` (Watch, Dynamic Island): cada miembro se mide con la misma
/// autoridad que `EntrenarHiloContrasteTests` (`OKLab.contrastRatio`), nunca a ojo. Un hex mal
/// elegido aquí = muñeca ilegible.
final class LiquidOLEDContrasteTests: XCTestCase {
    private var rolesDeTexto: [(String, Color)] {
        [("tinta", LiquidOLED.tinta), ("tintaSecundaria", LiquidOLED.tintaSecundaria),
         ("tintaTerciaria", LiquidOLED.tintaTerciaria)]
    }

    private var rolesDeDato: [(String, Color)] {
        [("verde", LiquidOLED.verde), ("ambar", LiquidOLED.ambar),
         ("negativo", LiquidOLED.negativo), ("rosa", LiquidOLED.rosa)]
    }

    func testTintasCumplenAASobreNegro() {
        for (nombre, color) in rolesDeTexto {
            let ratio = OKLab.contrastRatio(color, LiquidOLED.fondo)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(nombre) da \(ratio):1 sobre LiquidOLED.fondo")
        }
    }

    func testTonosDeDatoCumplenAASobreNegro() {
        for (nombre, color) in rolesDeDato {
            let ratio = OKLab.contrastRatio(color, LiquidOLED.fondo)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(nombre) da \(ratio):1 sobre LiquidOLED.fondo")
        }
    }

    /// La superficie elevada (pill/tarjeta sobre negro) también hospeda texto.
    func testTintasCumplenAASobreSuperficie() {
        for (nombre, color) in rolesDeTexto {
            let ratio = OKLab.contrastRatio(color, LiquidOLED.superficie)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(nombre) da \(ratio):1 sobre LiquidOLED.superficie")
        }
    }

    /// El bug que este set corrige: los tonos de dato del iPhone NO valen como texto chico sobre negro.
    /// Si alguien «unifica» `LiquidOLED.rosa`/`negativo` con los del iPhone, esto falla.
    func testLosTonosDelIphoneNoBastanSobreNegro() {
        XCTAssertLessThan(OKLab.contrastRatio(LiquidColor.negativo, LiquidOLED.fondo), 4.5)
        XCTAssertLessThan(OKLab.contrastRatio(LiquidColor.rosa, LiquidOLED.fondo), 4.5)
    }
}
