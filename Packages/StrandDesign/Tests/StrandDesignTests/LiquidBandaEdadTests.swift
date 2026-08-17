import XCTest
import SwiftUI
@testable import StrandDesign

/// Contrato de mapeo de `LiquidBandaEdad`, en frío (sin simulador).
/// Run: `swift test --filter LiquidBandaEdadTests`
final class LiquidBandaEdadTests: XCTestCase {

    // MARK: Posición dentro del dominio

    func test_posicion_interpolaDentroDelDominio() {
        XCTAssertEqual(LiquidBandaEdad.posicion(26, en: 26...42), 0, accuracy: 0.0001)
        XCTAssertEqual(LiquidBandaEdad.posicion(34, en: 26...42), 0.5, accuracy: 0.0001)
        XCTAssertEqual(LiquidBandaEdad.posicion(42, en: 26...42), 1, accuracy: 0.0001)
    }

    /// El invariante que sustituye a la escala auto-ensanchable del papel: una edad FUERA
    /// del dominio se pega al extremo en vez de dibujarse fuera de la regla.
    func test_posicion_seClampeaFueraDelDominio() {
        XCTAssertEqual(LiquidBandaEdad.posicion(12, en: 26...42), 0, accuracy: 0.0001)
        XCTAssertEqual(LiquidBandaEdad.posicion(99, en: 26...42), 1, accuracy: 0.0001)
        // Y sigue clampeado con valores absurdos (no hay NaN ni infinitos que propagar).
        XCTAssertEqual(LiquidBandaEdad.posicion(-1_000, en: 26...42), 0, accuracy: 0.0001)
    }

    /// Dominio degenerado (`lower == upper`): no hay escala que interpolar, todo va al centro.
    func test_posicion_dominioDegenerado_vaAlCentro() {
        XCTAssertEqual(LiquidBandaEdad.posicion(34, en: 34...34), 0.5, accuracy: 0.0001)
        XCTAssertEqual(LiquidBandaEdad.posicion(10, en: 34...34), 0.5, accuracy: 0.0001)
    }

    // MARK: No crashea en los casos límite

    #if os(macOS)
    /// Los tres casos que podrían reventar el mapeo —edad muy por debajo, muy por encima y
    /// dominio degenerado— se dibujan de verdad, no solo se calculan.
    @MainActor
    func test_render_casosLimite_noCrashea() throws {
        let casos: [(String, LiquidBandaEdad)] = [
            ("muy abajo", .init(edadCorporal: 12, edadReal: 34, dominio: 26...42,
                                etiquetaCorporal: "12 años", etiquetaReal: "34 años",
                                tono: LiquidColor.positivo,
                                a11yLabel: "Edad corporal", a11yValue: "12 años")),
            ("muy arriba", .init(edadCorporal: 99, edadReal: 34, dominio: 26...42,
                                 etiquetaCorporal: "99 años", etiquetaReal: "34 años",
                                 tono: LiquidColor.atencion,
                                 a11yLabel: "Edad corporal", a11yValue: "99 años")),
            ("dominio degenerado", .init(edadCorporal: 34, edadReal: 34, dominio: 34...34,
                                         etiquetaCorporal: "34 años", etiquetaReal: "34 años",
                                         tono: LiquidColor.tinta900,
                                         a11yLabel: "Edad corporal", a11yValue: "34 años")),
        ]
        for (nombre, banda) in casos {
            let vista = banda
                .environment(\.liquidMotionDisabled, true)
                .frame(width: 320, height: 80)
            let renderer = ImageRenderer(content: vista)
            XCTAssertNotNil(renderer.nsImage, "\(nombre): no rasterizó")
        }
    }
    #endif
}
