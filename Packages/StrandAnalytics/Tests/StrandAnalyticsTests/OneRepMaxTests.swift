import XCTest
@testable import StrandAnalytics

/// FER-346 — the estimated-1RM helper. Checks the cited formulas against known points, the honest
/// reps clamp, the single-rep identity, and the day-bucketed sparkline aggregation.
final class OneRepMaxTests: XCTestCase {

    func testEpleyKnownPoints() {
        // Epley: w·(1 + reps/30). 100×10 → 133.33; 100×5 → 116.67.
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 10, formula: .epley)!, 133.33, accuracy: 0.01)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 5, formula: .epley)!, 116.67, accuracy: 0.01)
    }

    func testBrzyckiKnownPoints() {
        // Brzycki: w·36/(37−reps). 100×10 → 133.33; 100×5 → 112.5.
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 10, formula: .brzycki)!, 133.33, accuracy: 0.01)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 5, formula: .brzycki)!, 112.5, accuracy: 0.01)
    }

    func testBrzyckiMoreConservativeAtModerateReps() {
        // The two agree at 10 reps but Epley reads higher at 5 reps.
        let e = OneRepMax.estimate(weightKg: 100, reps: 5, formula: .epley)!
        let b = OneRepMax.estimate(weightKg: 100, reps: 5, formula: .brzycki)!
        XCTAssertGreaterThan(e, b)
    }

    func testSingleRepIsItsOwnMax() {
        XCTAssertEqual(OneRepMax.estimate(weightKg: 140, reps: 1, formula: .epley)!, 140, accuracy: 0.0001)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 140, reps: 1, formula: .brzycki)!, 140, accuracy: 0.0001)
    }

    func testHighRepsAreClampedNotExtrapolated() {
        // A 20-rep set is estimated as a 12-rep one (the clamp), and Brzycki never explodes near reps=37.
        let clamped = OneRepMax.estimate(weightKg: 100, reps: 12, formula: .epley)!
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 20, formula: .epley)!, clamped, accuracy: 0.0001)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 40, formula: .brzycki)!,
                       OneRepMax.estimate(weightKg: 100, reps: 12, formula: .brzycki)!, accuracy: 0.0001)
    }

    func testNotEstimableReturnsNil() {
        XCTAssertNil(OneRepMax.estimate(weightKg: 0, reps: 5))
        XCTAssertNil(OneRepMax.estimate(weightKg: -10, reps: 5))
        XCTAssertNil(OneRepMax.estimate(weightKg: 100, reps: 0))
    }

    func testBestEstimatePicksHighest() {
        let sets: [(weightKg: Double, reps: Int)] = [(60, 10), (80, 5), (100, 12)]
        // Best should be the 100×12 set; 60×10 and 80×5 are lower.
        let best = OneRepMax.bestEstimate(sets, formula: .epley)!
        XCTAssertEqual(best, OneRepMax.estimate(weightKg: 100, reps: 12, formula: .epley)!, accuracy: 0.0001)
    }

    func testBestEstimateNilWhenNoneEstimable() {
        let sets: [(weightKg: Double, reps: Int)] = [(0, 5), (-1, 8)]
        XCTAssertNil(OneRepMax.bestEstimate(sets))
    }

    func testDailySparklineBucketsBestPerDayAscending() {
        let sets: [(day: String, weightKg: Double, reps: Int)] = [
            ("2026-06-18", 60, 8),
            ("2026-06-20", 80, 5),
            ("2026-06-18", 70, 5),   // beats the other 06-18 set
            ("2026-06-19", 0, 5),    // not estimable → dropped
        ]
        let spark = OneRepMax.dailySparkline(sets, formula: .epley)
        XCTAssertEqual(spark.map(\.day), ["2026-06-18", "2026-06-20"])   // 06-19 dropped, ascending
        XCTAssertEqual(spark[0].estimatedKg,
                       OneRepMax.estimate(weightKg: 70, reps: 5, formula: .epley)!, accuracy: 0.0001)
    }
}
