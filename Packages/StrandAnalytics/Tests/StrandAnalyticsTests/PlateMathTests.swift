import XCTest
@testable import StrandAnalytics

/// FER-720 (F5 · 3a) — the barbell plate-loading and warm-up-ramp helper. Checks the mock's headline
/// case (92.5 → 20+15+1.25 per side on a 20 kg bar), inventory limits, non-exact loads, and the ramp.
final class PlateMathTests: XCTestCase {

    // MARK: perSide

    func testHeadlineCase925() {
        // Mock 3a: "20 + 15 + 1,25 · barra 20 kg · total 92,5". Per side = (92.5 − 20)/2 = 36.25.
        let l = PlateMath.perSide(targetKg: 92.5)
        XCTAssertEqual(l.perSide, [20, 15, 1.25])
        XCTAssertEqual(l.achievedKg, 92.5, accuracy: 0.0001)
        XCTAssertEqual(l.shortfallKg, 0, accuracy: 0.0001)
    }

    func testRoundNumber100() {
        // (100 − 20)/2 = 40 per side → 20 + 20 (default set tops at 20 kg).
        let l = PlateMath.perSide(targetKg: 100)
        XCTAssertEqual(l.perSide, [20, 20])
        XCTAssertEqual(l.achievedKg, 100, accuracy: 0.0001)
    }

    func testBarOnlyWhenTargetAtOrBelowBar() {
        let atBar = PlateMath.perSide(targetKg: 20)
        XCTAssertEqual(atBar.perSide, [])
        XCTAssertEqual(atBar.achievedKg, 20, accuracy: 0.0001)
        XCTAssertEqual(atBar.shortfallKg, 0, accuracy: 0.0001)

        // Target below the bar is degenerate: the empty bar (20) already exceeds it, so no plates and
        // no shortfall (you can't load less than the bar).
        let belowBar = PlateMath.perSide(targetKg: 15)
        XCTAssertEqual(belowBar.perSide, [])
        XCTAssertEqual(belowBar.achievedKg, 20, accuracy: 0.0001)
        XCTAssertEqual(belowBar.shortfallKg, 0, accuracy: 0.0001)
    }

    func testNonExactTargetRoundsDownWithShortfall() {
        // 93 kg isn't buildable to the exact kg with a standard set: (93−20)/2 = 36.5 per side →
        // 20+15+1.25 = 36.25, achieving 92.5, a 0.5 kg shortfall (never over-loads).
        let l = PlateMath.perSide(targetKg: 93)
        XCTAssertEqual(l.perSide, [20, 15, 1.25])
        XCTAssertEqual(l.achievedKg, 92.5, accuracy: 0.0001)
        XCTAssertEqual(l.shortfallKg, 0.5, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(l.achievedKg, 93 + 0.0001)
    }

    func testInventoryPairLimitIsRespected() {
        // Only one pair of 20s: 40 per side must fall back to 15+15+10 instead of 20+20.
        let inv: [PlateMath.PlateStock] = [
            .init(kg: 20, pairs: 1), .init(kg: 15, pairs: 8), .init(kg: 10, pairs: 8),
            .init(kg: 5, pairs: 8), .init(kg: 2.5, pairs: 8), .init(kg: 1.25, pairs: 8),
        ]
        let l = PlateMath.perSide(targetKg: 100, barKg: 20, inventory: inv)
        XCTAssertEqual(l.perSide.filter { $0 == 20 }.count, 1)
        XCTAssertEqual(l.achievedKg, 100, accuracy: 0.0001)
        XCTAssertEqual(l.perSide.reduce(0, +), 40, accuracy: 0.0001)
    }

    func testCustomBarWeight() {
        // 15 kg women's bar: (60 − 15)/2 = 22.5 per side → 20 + 2.5.
        let l = PlateMath.perSide(targetKg: 60, barKg: 15)
        XCTAssertEqual(l.perSide, [20, 2.5])
        XCTAssertEqual(l.achievedKg, 60, accuracy: 0.0001)
    }

    // MARK: warmup

    func testWarmupRampToWorkWeight() {
        // Work 100 kg: bar (0%×10), 55% → 55 kg snapped, 80% → 80 kg snapped. Strictly increasing,
        // all below the work weight, correct reps.
        let ramp = PlateMath.warmup(workKg: 100)
        XCTAssertEqual(ramp.count, 3)
        XCTAssertEqual(ramp[0].weightKg, 20, accuracy: 0.0001) // empty bar
        XCTAssertEqual(ramp[0].reps, 10)
        XCTAssertEqual(ramp[1].reps, 6)
        XCTAssertEqual(ramp[2].reps, 3)
        // Strictly increasing and each below the work weight.
        XCTAssertLessThan(ramp[0].weightKg, ramp[1].weightKg)
        XCTAssertLessThan(ramp[1].weightKg, ramp[2].weightKg)
        XCTAssertLessThan(ramp[2].weightKg, 100)
        // 55% of 100 = 55 → buildable exactly; 80% = 80 → buildable exactly.
        XCTAssertEqual(ramp[1].weightKg, 55, accuracy: 0.0001)
        XCTAssertEqual(ramp[2].weightKg, 80, accuracy: 0.0001)
    }

    func testWarmupSnapsToBuildableLoads() {
        // Every non-bar warm-up weight must be exactly buildable from the inventory (no shortfall).
        let ramp = PlateMath.warmup(workKg: 92.5)
        for set in ramp where set.fractionOfWork > 0 {
            let l = PlateMath.perSide(targetKg: set.weightKg)
            XCTAssertEqual(l.shortfallKg, 0, accuracy: 0.0001, "warm-up \(set.weightKg) not buildable")
        }
    }

    func testWarmupEmptyWhenWorkAtOrBelowBar() {
        XCTAssertTrue(PlateMath.warmup(workKg: 20).isEmpty)
        XCTAssertTrue(PlateMath.warmup(workKg: 10).isEmpty)
    }

    func testWarmupDropsRedundantSteps() {
        // Light work weight where 55% would snap back to the bar: that step is dropped, ramp stays
        // strictly increasing.
        let ramp = PlateMath.warmup(workKg: 30)
        let weights = ramp.map(\.weightKg)
        XCTAssertEqual(weights, weights.sorted())
        XCTAssertEqual(Set(weights).count, weights.count) // no duplicates
        for w in weights { XCTAssertLessThan(w, 30) }
    }

    // MARK: - minimumIncrement (FER-C)

    func testMinimumIncrementBarbellIsTwiceSmallestPlate() {
        // Default inventory's smallest plate is 1.25 → a pair adds 2.5 kg total.
        XCTAssertEqual(PlateMath.minimumIncrement(for: .barbell), 2.5, accuracy: 0.0001)
        // A gym whose smallest plate is 2.5 moves by 5 kg.
        let coarse = [PlateMath.PlateStock(kg: 20, pairs: 4), PlateMath.PlateStock(kg: 2.5, pairs: 4)]
        XCTAssertEqual(PlateMath.minimumIncrement(for: .barbell, inventory: coarse), 5, accuracy: 0.0001)
    }

    func testMinimumIncrementBarbellEmptyInventoryFallsBack() {
        XCTAssertEqual(PlateMath.minimumIncrement(for: .barbell, inventory: [], fixedStepKg: 1),
                       1, accuracy: 0.0001)
    }

    func testMinimumIncrementDumbbellAndMachineUseFixedStep() {
        // Non-barbell moves by its rack's fixed step, NOT derived from plates.
        XCTAssertEqual(PlateMath.minimumIncrement(for: .dumbbell, fixedStepKg: 2), 2, accuracy: 0.0001)
        XCTAssertEqual(PlateMath.minimumIncrement(for: .machine, fixedStepKg: 5), 5, accuracy: 0.0001)
    }

    func testImplementClassificationFromEquipmentLabel() {
        XCTAssertEqual(PlateMath.Implement.from(equipment: "barbell"), .barbell)
        XCTAssertEqual(PlateMath.Implement.from(equipment: "Smith machine"), .barbell) // guided bar
        XCTAssertEqual(PlateMath.Implement.from(equipment: "dumbbell"), .dumbbell)
        XCTAssertEqual(PlateMath.Implement.from(equipment: "leverage machine"), .machine)
        XCTAssertEqual(PlateMath.Implement.from(equipment: "cable"), .machine)
        XCTAssertEqual(PlateMath.Implement.from(equipment: "body weight"), .other)
        XCTAssertEqual(PlateMath.Implement.from(equipment: nil), .other)
    }
}
