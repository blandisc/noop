import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-280 · clase 2 / FER-295 · 2A — la cápsula outline no puede driftar de las recetas citadas.
final class OutlineCapsuleTests: XCTestCase {

    func test_sm_padding_matchesRoutineSheetLiveTarjeta() {
        XCTAssertEqual(OutlineCapsule<Text>.Size.sm.horizontalPad, LiquidSpace.s250,
                       "sm H = RoutineSheetLiveTarjeta:125/336")
        XCTAssertEqual(OutlineCapsule<Text>.Size.sm.verticalPad, LiquidSpace.s150,
                       "sm V = RoutineSheetLiveTarjeta:125/336")
    }

    func test_md_padding_matchesExerciseLibraryChip() {
        XCTAssertEqual(OutlineCapsule<Text>.Size.md.horizontalPad, LiquidSpace.s300,
                       "md H = ExerciseLibraryScreen:206")
        XCTAssertEqual(OutlineCapsule<Text>.Size.md.verticalPad, 6,
                       "md V = ExerciseLibraryScreen:206 (chip 6pt)")
    }

    func test_lg_padding_matchesSecondaryButtonRecipe() {
        XCTAssertEqual(OutlineCapsule<Text>.Size.lg.horizontalPad, LiquidSpace.s400,
                       "lg H = LiquidSpace.s400")
        XCTAssertEqual(OutlineCapsule<Text>.Size.lg.verticalPad, 0,
                       "lg V = 0 (altura vía minHeight)")
        XCTAssertEqual(OutlineCapsule<Text>.Size.lg.minHeight, EntrenarMetrics.secondaryButton,
                       "lg minHeight = EntrenarMetrics.secondaryButton (36)")
        XCTAssertEqual(OutlineCapsule<Text>.Size.lg.touchInset,
                       (EntrenarMetrics.row - EntrenarMetrics.secondaryButton) / 2,
                       "lg toque 44 vía inset negativo sin agrandar el dibujo 36")
    }

    func test_xl_padding_matchesFocusRestSkip() {
        XCTAssertEqual(OutlineCapsule<Text>.Size.xl.horizontalPad, LiquidSpace.s400,
                       "xl H = LiquidSpace.s400 (misma familia que lg)")
        XCTAssertEqual(OutlineCapsule<Text>.Size.xl.verticalPad, 0,
                       "xl V = 0 (altura vía minHeight)")
        XCTAssertEqual(OutlineCapsule<Text>.Size.xl.minHeight, EntrenarMetrics.focusRestSkip,
                       "xl minHeight = EntrenarMetrics.focusRestSkip (46)")
        XCTAssertEqual(OutlineCapsule<Text>.Size.xl.touchInset, 0,
                       "xl ya mide 46 ≥ 44; sin expandTouch")
        XCTAssertNotEqual(OutlineCapsule<Text>.Size.lg.minHeight,
                          OutlineCapsule<Text>.Size.xl.minHeight)
    }

    func test_sizes_differ() {
        XCTAssertNotEqual(OutlineCapsule<Text>.Size.sm.horizontalPad,
                          OutlineCapsule<Text>.Size.md.horizontalPad)
        XCTAssertNotEqual(OutlineCapsule<Text>.Size.md.horizontalPad,
                          OutlineCapsule<Text>.Size.lg.horizontalPad)
    }

    @MainActor
    func test_exists_asPublicAPI() {
        // Compila el atajo LocalizedStringKey y el ViewBuilder — si alguien borra la pieza,
        // este archivo deja de linkear.
        let _: any View = OutlineCapsule("Use", theme: .base, action: {})
        let _: any View = OutlineCapsule(theme: .base, filled: true, action: {}) {
            Text(verbatim: "Barbell")
        }
    }

    @MainActor
    func test_estilo_init_instantiatesEachCase() {
        let t = InstrumentoTheme.base
        let _: any View = OutlineCapsule("Outline", theme: t, estilo: .outline, action: {})
        let _: any View = OutlineCapsule("Suave", theme: t, estilo: .outlineSuave, action: {})
        let _: any View = OutlineCapsule("Papel", theme: t, size: .lg, estilo: .papel, action: {})
        let _: any View = OutlineCapsule("Vidrio", theme: t, estilo: .vidrio, action: {})
        let _: any View = OutlineCapsule("Teñida", theme: t, estilo: .tenida(.verde), action: {})
        let _: any View = OutlineCapsule(theme: t, size: .md, estilo: .tenida(.ambar), action: {}) {
            Text(verbatim: "Hoy subes")
        }
        let _: any View = Text(verbatim: "ZONA 2")
            .outlineCapsule(.papel, size: .sm, theme: t)
    }

    @MainActor
    func test_legacy_filled_fill_stillWork() {
        let t = InstrumentoTheme.base
        let _: any View = OutlineCapsule("Barbell", theme: t, size: .md, filled: true, action: {})
        let _: any View = OutlineCapsule(theme: t, filled: true, fill: t.dataStrain, action: {}) {
            Text(verbatim: "Match")
        }
        let _: any View = OutlineCapsule("Start", theme: t, filled: false, action: {})
    }
}
