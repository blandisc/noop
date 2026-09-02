import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-280 · clase 3 — la barra de tinta no puede driftar de WeeklyPlanEditor:748-758.
final class UndoToastTests: XCTestCase {

    func test_spacing_matchesWeeklyPlanEditor() {
        XCTAssertEqual(UndoToastMetrics.hStackSpacing, LiquidSpace.s300,
                       "WeeklyPlanEditor:749 — HStack spacing 12")
        XCTAssertEqual(UndoToastMetrics.spacerMin, LiquidSpace.s200,
                       "WeeklyPlanEditor:751 — Spacer minLength 8")
    }

    func test_padding_matchesWeeklyPlanEditor() {
        XCTAssertEqual(UndoToastMetrics.padH, LiquidSpace.s600,
                       "WeeklyPlanEditor:757 — pad H screenPadding")
        XCTAssertEqual(UndoToastMetrics.padV, LiquidSpace.s400,
                       "WeeklyPlanEditor:757 — pad V cardPadding")
        XCTAssertEqual(UndoToastMetrics.outerPadH, LiquidSpace.s600,
                       "WeeklyPlanEditor:759 — outer H screenPadding")
        XCTAssertEqual(UndoToastMetrics.outerPadBottom, 8,
                       "WeeklyPlanEditor:760 — outer bottom 8")
    }

    func test_radius_matchesLiquidTarjeta() {
        XCTAssertEqual(UndoToastMetrics.radius, LiquidRadius.tarjeta,
                       "FER-294 — radio tarjeta 18 (era cardRadius 16)")
    }

    @MainActor
    func test_exists_asPublicAPI() {
        let _: any View = UndoToast(message: "Routine deleted",
                                    theme: .base,
                                    action: {})
        let _: any View = UndoToast(message: "Folder deleted",
                                    cta: "Deshacer",
                                    theme: .base,
                                    action: {})
    }
}
