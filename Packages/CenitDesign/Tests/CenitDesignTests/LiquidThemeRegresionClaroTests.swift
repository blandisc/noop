import XCTest
import SwiftUI
@testable import CenitDesign

/// A1/FER-345 — «cero regresión en claro». Cada token que A1 volvió dinámico debe resolver, en
/// `.light`, EXACTAMENTE su hex claro original (ε ≤ 1/255). Es la red que garantiza que volver los
/// tokens `LiquidTheme.dynamic(light:dark:)` no cambió NADA de lo visible hoy (el flag está apagado y
/// la app sigue pineada `.light`). Si un `light:` se tecleó mal, este test lo caza.
final class LiquidThemeRegresionClaroTests: XCTestCase {

    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    private func assertLight(_ token: Color, _ hex: String, _ name: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let a = token.resolved(at: .light).rgbaComponents
        let b = Color(hex: hex).rgbaComponents
        XCTAssertEqual(a.r, b.r, accuracy: 1.0 / 255, "\(name).r", file: file, line: line)
        XCTAssertEqual(a.g, b.g, accuracy: 1.0 / 255, "\(name).g", file: file, line: line)
        XCTAssertEqual(a.b, b.b, accuracy: 1.0 / 255, "\(name).b", file: file, line: line)
    }

    /// Con el flag APAGADO (default), los tokens sembrados son byte-idénticos a su hex original en claro.
    func testTokensSembradosClaroByteIdentico() {
        LiquidTheme.oscuroHabilitado = false
        assertLight(LiquidColor.tinta900, "#221D16", "tinta900")
        assertLight(LiquidColor.rosa, "#B85068", "rosa")
        assertLight(LiquidColor.fondoAlto, "#FEFEFD", "fondoAlto")
        assertLight(LiquidColor.papelTarjeta, "#FFFFFF", "papelTarjeta")
        assertLight(CenitColor.pantalla, "#FFFFFF", "pantalla")
        assertLight(LiquidColor.ecosistemaBlanco, "#FFFFFF", "ecosistemaBlanco")
    }

    /// Incluso con el flag ENCENDIDO, el ramo `.light` sigue byte-idéntico (el modo solo cambia `.dark`).
    func testClaroInvarianteAunConFlagEncendido() {
        LiquidTheme.oscuroHabilitado = true
        assertLight(LiquidColor.tinta900, "#221D16", "tinta900")
        assertLight(LiquidColor.fondoAlto, "#FEFEFD", "fondoAlto")
        assertLight(CenitColor.pantalla, "#FFFFFF", "pantalla")
    }
}
