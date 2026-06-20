import XCTest
@testable import StrandAnalytics
import WhoopStore

final class DietAdherenceTests: XCTestCase {

    func testCumpliAndSustituiCountSalteAndPendingDoNot() {
        // 5 planned; 2 cumplí + 1 sustituí + 1 salté marked (1 still pending) → adherent 3 → 3/5 = 60.
        let s: [DietMealStatus] = [.cumpli, .cumpli, .sustitui, .salte]
        XCTAssertEqual(DietAdherence.dayPercent(statuses: s, plannedMeals: 5), 60)
        XCTAssertEqual(DietAdherence.adherentCount(s), 3)
    }

    func testSustituiCountsAsAdherent() {
        XCTAssertEqual(DietAdherence.dayPercent(statuses: [.sustitui, .sustitui], plannedMeals: 2), 100)
    }

    func testAllSkippedIsZero() {
        XCTAssertEqual(DietAdherence.dayPercent(statuses: [.salte, .salte], plannedMeals: 4), 0)
    }

    func testFull() {
        XCTAssertEqual(DietAdherence.dayPercent(statuses: [.cumpli, .cumpli, .cumpli], plannedMeals: 3), 100)
    }

    func testRoundsToNearest() {
        XCTAssertEqual(DietAdherence.dayPercent(statuses: [.cumpli], plannedMeals: 3), 33)            // 33.33 → 33
        XCTAssertEqual(DietAdherence.dayPercent(statuses: [.cumpli, .cumpli], plannedMeals: 3), 67)   // 66.67 → 67
    }

    func testNoMarksWithPlanIsZeroNotNil() {
        // The plan exists but nothing is marked → 0/5 = 0 (the UI shows «—»; the math still defines it).
        XCTAssertEqual(DietAdherence.dayPercent(statuses: [], plannedMeals: 5), 0)
    }

    func testEmptyPlanReturnsNil() {
        XCTAssertNil(DietAdherence.dayPercent(statuses: [.cumpli], plannedMeals: 0))
    }
}
