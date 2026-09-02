import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-280 · clase 4 — pastilla El Eje + chip de valencia no pueden driftar de las recetas.
final class LiquidStatePillTests: XCTestCase {

    func test_estado_padding_matchesBreathingView() {
        XCTAssertEqual(LiquidStatePillMetrics.estadoPadH, LiquidSpace.s300,
                       "BreathingView:193 / IntervalTimerView:208")
        XCTAssertEqual(LiquidStatePillMetrics.estadoPadV, LiquidSpace.s150,
                       "BreathingView:194 / IntervalTimerView:209")
        XCTAssertEqual(LiquidStatePillMetrics.dotSize, LiquidSpace.s150,
                       "BreathingView:187 — Circle 6×6")
    }

    func test_valencia_padding_matchesWorkoutHistory() {
        XCTAssertEqual(LiquidStatePillMetrics.valenciaPadH, LiquidSpace.chipHorizontal,
                       "WorkoutHistoryScreen:655")
        XCTAssertEqual(LiquidStatePillMetrics.valenciaPadV, LiquidSpace.s075,
                       "WorkoutHistoryScreen:655")
        XCTAssertEqual(LiquidStatePillMetrics.valenciaFontSize, 11,
                       "WorkoutHistoryScreen:652 — grotesk 11 bold")
    }

    func test_dotVivoDefault_isVerdePrimario() {
        // BreathingView pinta el punto con LiquidColor.verdePrimario — no un status genérico.
        let a = LiquidStatePillMetrics.dotVivoDefault.rgbaComponents
        let b = LiquidColor.verdePrimario.rgbaComponents
        XCTAssertEqual(a.r, b.r, accuracy: 0.001)
        XCTAssertEqual(a.g, b.g, accuracy: 0.001)
        XCTAssertEqual(a.b, b.b, accuracy: 0.001)
    }

    func test_valencia_tintFill_andChipRadius_areCanonical() {
        // Candado de los tokens que el chip usa (WorkoutHistoryScreen:656-657).
        XCTAssertEqual(CenitOpacity.tintFill, 0.10, accuracy: 0.0001)
        XCTAssertEqual(LiquidRadius.chip, 8)
    }

    @MainActor
    func test_exists_asPublicAPI() {
        let _: any View = LiquidStatePill("Ready")
        let _: any View = LiquidStatePill("Live", dot: LiquidStatePillMetrics.dotVivoDefault)
        let _: any View = LiquidStatePill(valencia: "+12%", tono: InstrumentoTheme.base.positiveText)
    }
}
