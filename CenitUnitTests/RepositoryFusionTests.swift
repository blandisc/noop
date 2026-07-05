import XCTest
import WhoopStore
import StrandAnalytics
@testable import Cenit

/// Pins the FER-670 fusion builder: `Repository.fusionByDay` produces a per-day compare point for the
/// three single-construct metrics ONLY (steps / sleep total / active kcal), only on days where ≥2
/// sources reported, and never for the cross-source vitals (SourceLens territory, FER-629). Display
/// transparency only — the merge/baseline paths never read it.
@MainActor
final class RepositoryFusionTests: XCTestCase {

    private func dm(_ day: String, sleep: Double? = nil, hrv: Double? = nil,
                    steps: Int? = nil, kcal: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, steps: steps, activeKcalEst: kcal)
    }

    private func agg(_ day: String, steps: Int? = nil, kcal: Double? = nil) -> AppleDaily {
        AppleDaily(day: day, steps: steps, activeKcal: kcal, basalKcal: nil, vo2max: nil,
                   avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
    }

    func testSleepConflictBandVsApple() {
        let f = Repository.fusionByDay(imported: [dm("2026-07-04", sleep: 432)],
                                       computed: [],
                                       apple: [dm("2026-07-04", sleep: 120)],
                                       appleAgg: [], stepsEst: [:])
        let p = f["2026-07-04"]?["sleep_total_min"]
        XCTAssertEqual(p?.agreement, .conflict)
        XCTAssertEqual(p?.value, 432)                       // band wins verbatim, never an average
        XCTAssertEqual(p?.winningSource, .whoopImport)
    }

    func testStepsAppleCountVsStrapCounter() {
        let f = Repository.fusionByDay(imported: [], computed: [dm("2026-07-04", steps: 8420)],
                                       apple: [],
                                       appleAgg: [agg("2026-07-04", steps: 8100)], stepsEst: [:])
        let p = f["2026-07-04"]?["steps"]
        XCTAssertEqual(p?.agreement, .agree)                // 3.95% < 10%
        XCTAssertEqual(p?.value, 8100)                      // Apple's pedometer count wins (FER-663)
        XCTAssertEqual(p?.winningSource, .appleHealth)
    }

    func testStepsEstFillsWhenNoRealCounter() {
        // WHOOP 4.0: no strap counter — the on-device estimate is the strap-side input.
        let f = Repository.fusionByDay(imported: [], computed: [dm("2026-07-04")],
                                       apple: [],
                                       appleAgg: [agg("2026-07-04", steps: 8000)],
                                       stepsEst: ["2026-07-04": 14000])
        XCTAssertEqual(f["2026-07-04"]?["steps"]?.agreement, .conflict)   // 75% over
    }

    func testKcalUsesAppleAggregateAndStrapEstimate() {
        let f = Repository.fusionByDay(imported: [], computed: [dm("2026-07-04", kcal: 431)],
                                       apple: [],
                                       appleAgg: [agg("2026-07-04", kcal: 512)], stepsEst: [:])
        let p = f["2026-07-04"]?["active_kcal"]
        XCTAssertEqual(p?.winningSource, .appleHealth)
        XCTAssertEqual(p?.agreement, .minorDelta)           // 15.8% — beyond ±15%, inside ±40%
    }

    func testSingleSourceDaysProduceNoEntry() {
        let f = Repository.fusionByDay(imported: [dm("2026-07-04", sleep: 432)],
                                       computed: [], apple: [], appleAgg: [], stepsEst: [:])
        XCTAssertNil(f["2026-07-04"])                       // nothing to cross-check → no row shown
    }

    func testCrossSourceVitalsNeverFused() {
        // Both sources carry HRV — the fusion map must NOT grow an hrv key (SourceLens governs it).
        let f = Repository.fusionByDay(imported: [dm("2026-07-04", hrv: 50)],
                                       computed: [],
                                       apple: [dm("2026-07-04", hrv: 90)],
                                       appleAgg: [], stepsEst: [:])
        XCTAssertNil(f["2026-07-04"]?["hrv"])
        XCTAssertEqual(f["2026-07-04"], nil)                // no fused metric at all on this day
    }
}
