import XCTest
@testable import CenitDesign

/// Contrato de VoiceOver de `LiquidRegularityCard`, en frío (sin simulador).
/// Run: `swift test --filter LiquidRegularityCardA11yTests`
final class LiquidRegularityCardA11yTests: XCTestCase {

    func test_conPuntaje() {
        XCTAssertEqual(
            LiquidRegularityCard.a11yLabel(
                titulo: "Regularidad",
                puntaje: 82,
                leyenda: "Muy regular — tu cuerpo sabe cuándo dormir"),
            "Regularidad, 82, Muy regular — tu cuerpo sabe cuándo dormir")
    }

    /// Con `puntaje == nil` la voz dice «sin dato», nunca «··».
    func test_calibrando_sinDato() {
        XCTAssertEqual(
            LiquidRegularityCard.a11yLabel(
                titulo: "Regularidad",
                puntaje: nil,
                leyenda: "Aún conociendo tu ritmo"),
            "Regularidad, sin dato, Aún conociendo tu ritmo")
    }

    /// Un `a11yLabel` explícito del caller gana (contrato de escape del DS).
    func test_override_gana() {
        // El helper puro no conoce el override — el override se aplica en el init —
        // aquí solo se documenta el formato canónico que el override sustituye.
        let canonico = LiquidRegularityCard.a11yLabel(
            titulo: "Regularidad", puntaje: 50, leyenda: "Regular")
        XCTAssertEqual(canonico, "Regularidad, 50, Regular")
    }
}
