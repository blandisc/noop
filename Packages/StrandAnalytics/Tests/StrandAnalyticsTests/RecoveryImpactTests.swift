import XCTest
@testable import StrandAnalytics
import StrandModels

/// FER-628 — «Qué la movió hoy»: the per-signal decomposition of today's recovery score. The
/// contributions must (a) rank by |z·weight|, not |z|; (b) fold their baselines on the BAND-ONLY
/// slice (FER-519 / FER-629), so they never disagree with the persisted score; and (c) read ≈ 0 on
/// a day that sits exactly on the user's band baseline.
final class RecoveryImpactTests: XCTestCase {

    private func d(_ i: Int, hrv: Double? = 60, rhr: Int? = 52, resp: Double? = 14,
                   eff: Double? = 0.9, skinDev: Double? = 0.0, month: Int = 3) -> DailyMetric {
        DailyMetric(day: String(format: "2024-%02d-%02d", month, i), totalSleepMin: 420,
                    efficiency: eff, deepMin: 90, remMin: 90, lightMin: 240, disturbances: 2,
                    restingHr: rhr, avgHrv: hrv, recovery: 60, strain: 10, exerciseCount: 1,
                    spo2Pct: 97, skinTempDevC: skinDev, respRateBpm: resp)
    }

    /// 20 identical band nights + today identical to all of them → every signal sits on its base, so
    /// every contribution is ≈ 0 (criterion 4's testable clause).
    func testDayAtBandBaselineHasNearZeroImpact() {
        let days = (1...20).map { d($0) } + [d(21)]
        let out = RecoveryImpact.compute(days: days, todayKey: "2024-03-21")
        XCTAssertNotNil(out)
        for s in out!.signals {
            XCTAssertLessThan(abs(s.contribution), 0.1, "\(s.key) should be ≈ 0 at baseline")
        }
    }

    /// The renormalized weights of the present signals always sum to 1 — the scorer's missing-term
    /// rule (the nominal weights sum to 1.10, so even the full set renormalizes, exactly like
    /// `RecoveryScorer.recovery` divides by `totalWeight`).
    func testWeightsRenormalizeOverPresentSignals() {
        let all = (1...20).map { d($0) } + [d(21)]
        let full = RecoveryImpact.compute(days: all, todayKey: "2024-03-21")!
        XCTAssertEqual(full.signals.count, 5)
        XCTAssertEqual(full.signals.reduce(0) { $0 + $1.weight }, 1.0, accuracy: 1e-9)
        XCTAssertEqual(full.signals.first { $0.key == "hrv" }!.weight, 0.60 / 1.10, accuracy: 1e-9)

        // Drop resp + skin temp + sleep from today → only HRV/RHR remain, shares 0.75 / 0.25.
        let sparse = (1...20).map { d($0) } +
            [d(21, resp: nil, eff: nil, skinDev: nil)]
        let out = RecoveryImpact.compute(days: sparse, todayKey: "2024-03-21")!
        XCTAssertEqual(Set(out.signals.map(\.key)), ["hrv", "rhr"])
        XCTAssertEqual(out.signals.reduce(0) { $0 + $1.weight }, 1.0, accuracy: 1e-9)
        XCTAssertEqual(out.signals.first { $0.key == "hrv" }!.weight, 0.75, accuracy: 1e-9)
    }

    /// The headline must name the biggest |z·weight|, not the biggest |z| (the FER-632 ranking bug):
    /// a wild respiration night (huge z, 5% weight) must NOT outrank a clearly-low HRV (60% weight).
    func testRanksByContributionNotByZ() {
        var days = (1...20).map { d($0) }
        days.append(d(21, hrv: 45, resp: 20))   // HRV low-ish; respiration way up
        let out = RecoveryImpact.compute(days: days, todayKey: "2024-03-21")!
        let hrv = out.signals.first { $0.key == "hrv" }!
        let resp = out.signals.first { $0.key == "respRate" }!
        XCTAssertGreaterThan(abs(resp.z), abs(hrv.z), "premise: resp must carry the bigger |z|")
        XCTAssertEqual(out.top?.key, "hrv", "ranking must be |z·w|, so HRV (60%) leads")
    }

    /// Band-only purity (FER-519 / FER-629): inflated Apple-sourced rows interleaved in the history
    /// must not move the contributions — masking them via `appleDays` yields the same result as a
    /// history that never contained them.
    func testAppleDaysDoNotContaminateTheBaseline() {
        let bandDays = (1...20).map { d($0) }
        let today = d(21, hrv: 40)                       // a clearly-low band night
        // Apple rows: SDNN-style inflated HRV + higher RHR, interleaved on other day keys.
        let appleRows = (1...10).map { d($0, hrv: 95, rhr: 68, month: 2) }
        let appleKeys = Set(appleRows.map(\.day))

        let pure = RecoveryImpact.compute(days: bandDays + [today], todayKey: "2024-03-21")!
        let masked = RecoveryImpact.compute(days: appleRows + bandDays + [today],
                                            todayKey: "2024-03-21", appleDays: appleKeys)!
        XCTAssertEqual(masked, pure, "Apple rows must be dropped whole-row before folding")

        // And the unmasked (contaminated) fold must differ — the bug this exists to prevent.
        let dirty = RecoveryImpact.compute(days: appleRows + bandDays + [today],
                                           todayKey: "2024-03-21")!
        let zPure = pure.signals.first { $0.key == "hrv" }!.z
        let zDirty = dirty.signals.first { $0.key == "hrv" }!.z
        XCTAssertNotEqual(zPure, zDirty, accuracy: 0.01,
                          "premise: contamination must actually move the HRV z")
    }

    /// An Apple-only "today" (no band row) has no honest band decomposition → nil.
    func testAppleOnlyTodayReturnsNil() {
        let days = (1...20).map { d($0) } + [d(21)]
        XCTAssertNil(RecoveryImpact.compute(days: days, todayKey: "2024-03-21",
                                            appleDays: ["2024-03-21"]))
    }

    /// Cold-start: without a usable band HRV baseline there is no decomposition (the scorer's gate).
    func testColdStartReturnsNil() {
        let days = (1...2).map { d($0) } + [d(3)]
        XCTAssertNil(RecoveryImpact.compute(days: days, todayKey: "2024-03-03"))
    }

    /// A suppressed HRV pulls the score down: negative contribution, and Σ contribution (the composite
    /// z) is negative too.
    func testLowHrvYieldsNegativeContribution() {
        var days = (1...20).map { d($0) }
        days.append(d(21, hrv: 40))
        let out = RecoveryImpact.compute(days: days, todayKey: "2024-03-21")!
        let hrv = out.signals.first { $0.key == "hrv" }!
        XCTAssertLessThan(hrv.contribution, -0.3)
        XCTAssertLessThan(out.compositeZ, 0)
        // Elevated RHR flips: raw z positive (above base), oriented/contribution negative.
        var days2 = (1...20).map { d($0) }
        days2.append(d(21, rhr: 62))
        let out2 = RecoveryImpact.compute(days: days2, todayKey: "2024-03-21")!
        let rhr = out2.signals.first { $0.key == "rhr" }!
        XCTAssertGreaterThan(rhr.z, 0)
        XCTAssertLessThan(rhr.contribution, 0)
    }
}
