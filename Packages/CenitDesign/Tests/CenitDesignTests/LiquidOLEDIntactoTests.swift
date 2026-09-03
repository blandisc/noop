import XCTest
import SwiftUI
@testable import CenitDesign

/// A1/FER-345 · D1=(a) — el Apple Watch conserva su vocabulario `LiquidOLED` y NO recibe los gemelos
/// oscuros del iPhone. Sus `static let` son colores FIJOS, no `LiquidTheme.dynamic`, así que resuelven
/// igual en ambos schemes incluso con el flag encendido. Este test es la red que impide que una
/// migración futura los vuelva dinámicos por accidente y le cambie la cara al reloj.
final class LiquidOLEDIntactoTests: XCTestCase {

    override func tearDown() { LiquidTheme.oscuroHabilitado = false; super.tearDown() }

    private func fijo(_ token: Color, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let l = token.resolved(at: .light).rgbaComponents
        let d = token.resolved(at: .dark).rgbaComponents
        XCTAssertEqual(l.r, d.r, accuracy: 1.0 / 255, "\(name): NO debe cambiar por modo", file: file, line: line)
        XCTAssertEqual(l.g, d.g, accuracy: 1.0 / 255, "\(name)", file: file, line: line)
        XCTAssertEqual(l.b, d.b, accuracy: 1.0 / 255, "\(name)", file: file, line: line)
    }

    /// Con el flag ENCENDIDO, cada token OLED sigue fijo (no es dinámico) — el Watch no hereda el modo.
    func testLiquidOLEDNoEsDinamico() {
        LiquidTheme.oscuroHabilitado = true
        fijo(LiquidOLED.fondo, "fondo")
        fijo(LiquidOLED.tinta, "tinta")
        fijo(LiquidOLED.tintaSecundaria, "tintaSecundaria")
        fijo(LiquidOLED.verde, "verde")
        fijo(LiquidOLED.ambar, "ambar")
        fijo(LiquidOLED.negativo, "negativo")
        fijo(LiquidOLED.rosa, "rosa")
    }
}
