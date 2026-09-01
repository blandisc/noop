import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-280 · clase 3 — la barra de tinta no puede driftar de WeeklyPlanEditor:748-758.
final class UndoToastTests: XCTestCase {

    func test_spacing_matchesWeeklyPlanEditor() {
        XCTAssertEqual(UndoToastMetrics.hStackSpacing, CenitMetrics.gap,
                       "WeeklyPlanEditor:749 — HStack spacing 12")
        XCTAssertEqual(UndoToastMetrics.spacerMin, CenitMetrics.space2,
                       "WeeklyPlanEditor:751 — Spacer minLength 8")
    }

    func test_padding_matchesWeeklyPlanEditor() {
        XCTAssertEqual(UndoToastMetrics.padH, CenitMetrics.screenPadding,
                       "WeeklyPlanEditor:757 — pad H screenPadding")
        XCTAssertEqual(UndoToastMetrics.padV, CenitMetrics.cardPadding,
                       "WeeklyPlanEditor:757 — pad V cardPadding")
        XCTAssertEqual(UndoToastMetrics.outerPadH, CenitMetrics.screenPadding,
                       "WeeklyPlanEditor:759 — outer H screenPadding")
        XCTAssertEqual(UndoToastMetrics.outerPadBottom, 8,
                       "WeeklyPlanEditor:760 — outer bottom 8")
    }

    func test_radius_andCtaFont_matchRecipe() {
        XCTAssertEqual(UndoToastMetrics.radius, CenitMetrics.cardRadius,
                       "WeeklyPlanEditor:758 — cardRadius")
        XCTAssertEqual(UndoToastMetrics.ctaFontSize, 15,
                       "WeeklyPlanEditor:753 — grotesk 15 bold")
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
