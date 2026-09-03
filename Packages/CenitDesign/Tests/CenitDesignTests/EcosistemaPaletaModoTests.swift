import XCTest
import SwiftUI
import simd
@testable import CenitDesign

/// A1/FER-345 — la paleta del héroe Metal ahora resuelve por `colorScheme` REAL (antes con un
/// `EnvironmentValues()` vacío nunca seguía el modo, y `blanco` era `SIMD4(1,1,1,1)` fijo). Con el flag
/// encendido, `blanco` (= `ecosistemaBlanco`) y un tono de identidad deben DIFERIR entre `.light` y
/// `.dark`; con el flag apagado, iguales (el orbe no cambia en producción hasta A3).
final class EcosistemaPaletaModoTests: XCTestCase {

    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    private func iguales(_ a: SIMD4<Float>, _ b: SIMD4<Float>, eps: Float = 1.0 / 255) -> Bool {
        simd_max(abs(a - b), SIMD4<Float>(repeating: 0)).max() <= eps
    }

    func testPaletaDifierePorModoConFlagEncendido() {
        LiquidTheme.oscuroHabilitado = true
        let clima = LiquidColor.verdePrimario
        let claro = EcosistemaPaleta.desde(clima: clima, colorScheme: .light)
        let oscuro = EcosistemaPaleta.desde(clima: clima, colorScheme: .dark)
        XCTAssertFalse(iguales(claro.blanco, oscuro.blanco), "blanco (ecosistemaBlanco) debe diferir por modo")
        XCTAssertFalse(iguales(claro.reposo, oscuro.reposo), "reposo (besada rosa) debe diferir por modo")
    }

    func testPaletaIgualPorModoConFlagApagado() {
        LiquidTheme.oscuroHabilitado = false
        let clima = LiquidColor.verdePrimario
        let claro = EcosistemaPaleta.desde(clima: clima, colorScheme: .light)
        let oscuro = EcosistemaPaleta.desde(clima: clima, colorScheme: .dark)
        XCTAssertTrue(iguales(claro.blanco, oscuro.blanco), "con flag apagado el orbe no cambia por modo")
        XCTAssertTrue(iguales(claro.reposo, oscuro.reposo))
    }
}
