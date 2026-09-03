import XCTest
import SwiftUI
@testable import CenitDesign

/// A1/FER-345 — `contrastTuned` es el único camino sancionado para «tono de dato → tono de lectura AA»,
/// y su promesa es que PASA AA en AMBOS modos: en claro oscurece contra papel claro; en oscuro deja o
/// ACLARA contra el suelo oscuro (nunca oscurece sobre negro, que rompería el contraste). Con el flag
/// encendido, se prueban los dos suelos con su ancla dinámica.
final class LiquidContrastModoTests: XCTestCase {

    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    /// Para cada hue de dato, el tono afinado pasa ≥4.5:1 contra el suelo del scheme, en claro Y oscuro.
    func testContrastTunedPasaAAEnAmbosModos() {
        LiquidTheme.oscuroHabilitado = true
        let hues: [(String, Color)] = [
            ("rosa", LiquidColor.rosa), ("azul", LiquidColor.azul),
            ("cian", LiquidColor.cian), ("verdePrimario", LiquidColor.verdePrimario),
        ]
        let floor = LiquidColor.fondoAlto   // ancla dinámica (claro #FEFEFD / oscuro sembrado)
        for (nombre, hue) in hues {
            for scheme in [ColorScheme.light, .dark] {
                let tuned = LiquidColor.contrastTuned(hue, against: floor).resolved(at: scheme)
                let bg = floor.resolved(at: scheme)
                let cr = OKLab.contrastRatio(tuned, bg)
                XCTAssertGreaterThanOrEqual(cr, 4.5 - 0.05,
                    "contrastTuned(\(nombre)) en \(scheme) debe pasar ≥4.5, dio \(cr)")
            }
        }
    }

    /// El ramo claro de `contrastTuned` es el mismo `darkened` de hoy: byte-idéntico al comportamiento
    /// anterior (regresión). Se compara contra `OKLab.darkened` directo con las anclas resueltas en claro.
    func testRamoClaroByteIdenticoADarkened() {
        LiquidTheme.oscuroHabilitado = false
        let hue = LiquidColor.rosa, floor = LiquidColor.papelTarjeta
        let nuevo = LiquidColor.contrastTuned(hue, against: floor).resolved(at: .light).rgbaComponents
        let viejo = OKLab.darkened(hue.resolved(at: .light), toContrast: 4.5,
                                   against: floor.resolved(at: .light)).rgbaComponents
        XCTAssertEqual(nuevo.r, viejo.r, accuracy: 1.0 / 255)
        XCTAssertEqual(nuevo.g, viejo.g, accuracy: 1.0 / 255)
        XCTAssertEqual(nuevo.b, viejo.b, accuracy: 1.0 / 255)
    }
}
