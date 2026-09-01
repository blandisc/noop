import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-280 · clase 2 — la cápsula outline no puede driftar de las recetas citadas.
final class OutlineCapsuleTests: XCTestCase {

    func test_sm_padding_matchesRoutineSheetLiveTarjeta() {
        XCTAssertEqual(OutlineCapsule<Text>.Size.sm.horizontalPad, LiquidSpace.s250,
                       "sm H = RoutineSheetLiveTarjeta:125/336")
        XCTAssertEqual(OutlineCapsule<Text>.Size.sm.verticalPad, LiquidSpace.s150,
                       "sm V = RoutineSheetLiveTarjeta:125/336")
    }

    func test_md_padding_matchesExerciseLibraryChip() {
        XCTAssertEqual(OutlineCapsule<Text>.Size.md.horizontalPad, CenitMetrics.gap,
                       "md H = ExerciseLibraryScreen:206")
        XCTAssertEqual(OutlineCapsule<Text>.Size.md.verticalPad, 6,
                       "md V = ExerciseLibraryScreen:206 (chip 6pt)")
    }

    func test_sizes_differ() {
        XCTAssertNotEqual(OutlineCapsule<Text>.Size.sm.horizontalPad,
                          OutlineCapsule<Text>.Size.md.horizontalPad)
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
}
