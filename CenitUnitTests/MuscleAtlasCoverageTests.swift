#if os(iOS)
import XCTest
@testable import Cenit

/// Pins the muscle taxonomy contract that the fatigue map + session checkout rely on (FER-781):
/// the anatomical silhouette must cover EXACTLY the 17 canonical muscle regions that the ExerciseDB
/// bake collapses its ~50 fine muscle names down to (`Tools/bake-exercisedb/transform.py` `MUSCLE_MAP`).
/// If the two drift, a baked muscle either paints no region (silently dropped from the map) or a path
/// references a key the load math never produces — so this test is the guard that keeps them in lockstep.
final class MuscleAtlasCoverageTests: XCTestCase {

    /// The 17 canonical keys — the value set of the bake's `MUSCLE_MAP`, single-sourced here so the
    /// Swift side of the contract is explicit and any divergence fails loudly.
    private static let canonical: Set<String> = [
        "abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms",
        "glutes", "hamstrings", "lats", "lower back", "middle back", "neck", "quadriceps",
        "shoulders", "traps", "triceps",
    ]

    func testCanonicalHasSeventeenRegions() {
        XCTAssertEqual(Self.canonical.count, 17)
    }

    /// Every silhouette muscle key is a canonical region — no path references a key the load math can't
    /// produce.
    func testAnatomyKeysAreAllCanonical() {
        let keys = Set((MuscleAnatomy.front + MuscleAnatomy.back).map(\.muscle))
        let strays = keys.subtracting(Self.canonical)
        XCTAssertTrue(strays.isEmpty, "Silhouette paints non-canonical muscles: \(strays.sorted())")
    }

    /// Every canonical region is painted on the silhouette (front or back) — no baked muscle disappears
    /// from the map.
    func testEveryCanonicalMuscleHasARegion() {
        let keys = Set((MuscleAnatomy.front + MuscleAnatomy.back).map(\.muscle))
        let missing = Self.canonical.subtracting(keys)
        XCTAssertTrue(missing.isEmpty, "Canonical muscles with no silhouette region: \(missing.sorted())")
    }
}
#endif
