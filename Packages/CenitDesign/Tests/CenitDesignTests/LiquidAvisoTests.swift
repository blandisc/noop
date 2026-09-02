import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-280 · clase 3 — el aviso Liquid no puede driftar de HealthAlertBanner:46-50.
final class LiquidAvisoTests: XCTestCase {

    func test_tarjetaPadding_matchesLiquidTarjetaSeccionDefault() {
        XCTAssertEqual(LiquidAvisoMetrics.tarjetaPadding, LiquidSpace.s400,
                       "HealthAlertBanner:50 — liquidTarjetaSeccion() default pad")
    }

    func test_iconSize_matchesConnectNudge() {
        XCTAssertEqual(LiquidAvisoMetrics.iconSize, 17,
                       "CuerpoView:1172 — LiquidIcon size 17")
    }

    func test_slotSpacing_isLiquidSpaceS300() {
        XCTAssertEqual(LiquidAvisoMetrics.slotSpacing, LiquidSpace.s300)
    }

    func test_barraAncho_matchesLiquidPatternBlock() {
        XCTAssertEqual(LiquidAvisoMetrics.barraAncho, 2.5,
                       "LiquidPatternBlock barra lateral — HealthAlertBanner lo hereda")
    }

    @MainActor
    func test_exists_asPublicAPI() {
        // Receta ganadora (HealthAlertBanner bit-a-bit).
        let _: any View = LiquidAviso(
            titulo: "Heads up",
            cuerpo: "Your resting heart rate has been higher than usual.",
            tono: LiquidColor.atencion)
        // Variante con icono + CTA (dialectos connectNudge / TodayBanner).
        let _: any View = LiquidAviso(
            titulo: "Apple Salud",
            lineas: ["Connect Apple Health to fill steps and more."],
            tono: LiquidColor.azul,
            icono: .corazon,
            cta: "Conectar →",
            accion: {})
    }
}
