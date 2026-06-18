import XCTest
@testable import StrandAnalytics

// WhatMovesStrainTests — the gated directional drivers of day strain. (FER-239)
//
// Covers the three behaviours the block depends on: a real relationship surfaces with the correct
// direction (positive AND negative), too few paired days hides everything (the ≥6-week gate), and enough
// days but no real relationship still hides everything (the strength gate). The underlying Pearson/lag/
// gate math is exercised in CorrelationEngineTests; here we test the pair SELECTION + wiring.

final class WhatMovesStrainTests: XCTestCase {

    /// Add `i` days to 2026-01-01 in UTC → "yyyy-MM-dd". Lets fixtures span > a month deterministically.
    private func day(_ i: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let d = cal.date(byAdding: .day, value: i, to: base)!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func series(_ n: Int, _ value: (Int) -> Double) -> [(day: String, value: Double)] {
        (0..<n).map { (day($0), value($0)) }
    }

    func testDriversDetectedWithSignal() {
        // 50 days. Recovery alternates 70/50; strain = 0.1·recovery + 8 (so 15/13), a PERFECT positive
        // same-day relationship → recovery drives strain UP. Because strain then alternates day to day,
        // its lag-1 autocorrelation is strongly NEGATIVE → a hard day tends to be followed by a lighter
        // one. So we expect both drivers, one rising, one falling.
        let recovery = series(50) { $0 % 2 == 0 ? 70 : 50 }
        let strain   = series(50) { 0.1 * ($0 % 2 == 0 ? 70 : 50) + 8 }

        let out = WhatMovesStrainEngine.drivers(strain: strain, recovery: recovery)
        XCTAssertEqual(out, [
            StrainDriverFinding(driver: .sameDayRecovery, trend: .rises),
            StrainDriverFinding(driver: .priorDayStrain, trend: .falls),
        ])
    }

    func testHiddenWhenTooFewDays() {
        // Same strong pattern, but only 20 days — below the gate's 42-pair floor (~6 weeks). The block
        // must stay hidden even though the relationship is perfect: not enough evidence yet.
        let recovery = series(20) { $0 % 2 == 0 ? 70 : 50 }
        let strain   = series(20) { 0.1 * ($0 % 2 == 0 ? 70 : 50) + 8 }

        XCTAssertEqual(WhatMovesStrainEngine.drivers(strain: strain, recovery: recovery), [])
    }

    func testHiddenWhenNoRelationship() {
        // 48 days, enough to clear the count gate, but constructed with no real relationship: recovery is
        // a period-2 zigzag and strain a period-4 square wave, which are orthogonal (corr ≈ 0) and whose
        // lag-1 autocorrelation is also ≈ 0. Neither clears |r| ≥ 0.20 → the block stays hidden.
        let recovery = series(48) { $0 % 2 == 0 ? 60 : 40 }
        let strain   = series(48) { $0 % 4 < 2 ? 13 : 11 }

        XCTAssertEqual(WhatMovesStrainEngine.drivers(strain: strain, recovery: recovery), [])
    }
}
