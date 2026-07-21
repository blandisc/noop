import XCTest
@testable import StrandAnalytics
import StrandModels

/// FER-642 — «Qué cambió vs ayer»: the day-over-day movement of the recovery score, attributed to the
/// 1–2 signals whose CONTRIBUTION moved the most. The `deltaScore` must be exactly (today shown −
/// yesterday shown); the movers must rank by |Δ contribution| (NOT by raw-unit swing across different
/// units); the oriented sign must be honest; and a missing yesterday (row/score/impact) must return nil.
final class RecoveryChangeTests: XCTestCase {

    /// One band night. `i` gives it a unique calendar day so a history sorts chronologically.
    private func d(_ i: Int, hrv: Double? = 60, rhr: Int? = 52, resp: Double? = 14,
                   eff: Double? = 0.9, skinDev: Double? = 0.0, recovery: Double? = 60) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: 420,
                    efficiency: eff, deepMin: 90, remMin: 90, lightMin: 240, disturbances: 2,
                    restingHr: rhr, avgHrv: hrv, recovery: recovery, strain: 10, exerciseCount: 1,
                    spo2Pct: 97, skinTempDevC: skinDev, respRateBpm: resp)
    }

    /// Build 20 identical baseline nights (days 1…20), then a yesterday (21) and a today (22). Returns the
    /// full history plus the two impacts computed exactly as production does (band-only, whole `days`).
    private func scenario(yest: DailyMetric, today: DailyMetric)
        -> (days: [DailyMetric], yImpact: RecoveryImpact.Result?, tImpact: RecoveryImpact.Result?) {
        let base = (1...20).map { d($0) }
        let days = base + [yest, today]
        let yImpact = RecoveryImpact.compute(days: days, todayKey: yest.day)
        let tImpact = RecoveryImpact.compute(days: days, todayKey: today.day)
        return (days, yImpact, tImpact)
    }

    /// Δ positive: score rose; HRV improved most, so it leads and reads «48 → 61 ms».
    func testPositiveDeltaRanksBiggestContributionMover() {
        let yest = d(21, hrv: 48, rhr: 56, recovery: 48)
        let today = d(22, hrv: 61, rhr: 53, recovery: 61)
        let s = scenario(yest: yest, today: today)
        let out = RecoveryChange.compute(today: today, yesterday: yest,
                                         todayScore: 61, yesterdayScore: 48,
                                         todayImpact: s.tImpact, yesterdayImpact: s.yImpact)
        XCTAssertNotNil(out)
        XCTAssertEqual(out!.deltaScore, 13)
        XCTAssertEqual(out!.movers.first?.key, "hrv", "HRV (60% weight) moved most in contribution")
        XCTAssertEqual(out!.movers.first?.unit, .millis)
        XCTAssertEqual(out!.movers.first?.yesterday, 48)
        XCTAssertEqual(out!.movers.first?.today, 61)
        XCTAssertTrue(out!.movers.first!.improved)
    }

    /// FIX 1 — a huge raw sleep swing (efficiency 0.60 → 0.98) must NOT crown over the real driver of the
    /// Δscore: HRV, whose contribution moved far more (60% weight vs sleep's ~14%). Ranking by raw unit
    /// magnitude (or by sleep DURATION) would wrongly promote sleep; ranking by |Δ contribution| does not.
    func testLargeSleepSwingDoesNotOutrankHRVDriver() {
        let yest = d(21, hrv: 45, eff: 0.60, recovery: 40)
        let today = d(22, hrv: 72, eff: 0.98, recovery: 70)
        let s = scenario(yest: yest, today: today)
        let out = RecoveryChange.compute(today: today, yesterday: yest,
                                         todayScore: 70, yesterdayScore: 40,
                                         todayImpact: s.tImpact, yesterdayImpact: s.yImpact)!
        XCTAssertEqual(out.movers.first?.key, "hrv",
                       "HRV drives the Δscore; a big sleep-% swing at ~14% weight must not outrank it")
        // Sleep is shown as EFFICIENCY %, not duration, and reads whole percent.
        if let sleep = out.movers.first(where: { $0.key == "sleep" }) {
            XCTAssertEqual(sleep.unit, .percent)
            XCTAssertEqual(sleep.yesterday, 60, accuracy: 0.5)
            XCTAssertEqual(sleep.today, 98, accuracy: 0.5)
        }
    }

    /// Δ negative and the oriented Δ contribution is honest: HRV dropped and resting HR rose, so both
    /// worsened (their contribution moved the unhelpful way).
    func testNegativeDeltaOrientsContributionSignsCorrectly() {
        let yest = d(21, hrv: 70, rhr: 50, recovery: 72)
        let today = d(22, hrv: 55, rhr: 58, recovery: 55)
        let s = scenario(yest: yest, today: today)
        let out = RecoveryChange.compute(today: today, yesterday: yest,
                                         todayScore: 55, yesterdayScore: 72,
                                         todayImpact: s.tImpact, yesterdayImpact: s.yImpact)!
        XCTAssertEqual(out.deltaScore, -17)
        XCTAssertEqual(out.movers.first?.key, "hrv")
        XCTAssertFalse(out.movers.first!.improved, "HRV dropped → contribution moved down → not improved")
        let rhr = out.movers.first { $0.key == "rhr" }
        XCTAssertNotNil(rhr)
        XCTAssertFalse(rhr!.improved, "resting HR rose (lower is better) → worsened")
    }

    /// Δ zero with every signal on its baseline → deltaScore 0 and no movers (nothing changed).
    func testZeroDeltaNoMovers() {
        let yest = d(21), today = d(22)
        let s = scenario(yest: yest, today: today)
        let out = RecoveryChange.compute(today: today, yesterday: yest,
                                         todayScore: 60, yesterdayScore: 60,
                                         todayImpact: s.tImpact, yesterdayImpact: s.yImpact)!
        XCTAssertEqual(out.deltaScore, 0)
        XCTAssertTrue(out.movers.isEmpty)
    }

    /// FIX 2 gate (engine side): a nil yesterday impact — what the caller passes when `yesterdayKey` (the
    /// previous CALENDAR day) has no band row — makes the whole thing nil, so the block hides.
    func testMissingYesterdayImpactIsNil() {
        let today = d(22)
        let tImpact = RecoveryImpact.compute(days: (1...20).map { d($0) } + [today], todayKey: today.day)
        XCTAssertNil(RecoveryChange.compute(today: today, yesterday: d(21),
                                            todayScore: 60, yesterdayScore: 58,
                                            todayImpact: tImpact, yesterdayImpact: nil))
    }

    /// No yesterday row or score → nil (honest: nothing to compare against).
    func testMissingYesterdayRowOrScoreIsNil() {
        let today = d(22)
        let s = scenario(yest: d(21), today: today)
        XCTAssertNil(RecoveryChange.compute(today: today, yesterday: nil,
                                            todayScore: 60, yesterdayScore: 58,
                                            todayImpact: s.tImpact, yesterdayImpact: s.yImpact))
        XCTAssertNil(RecoveryChange.compute(today: today, yesterday: d(21),
                                            todayScore: 60, yesterdayScore: nil,
                                            todayImpact: s.tImpact, yesterdayImpact: s.yImpact))
    }

    /// A signal present in only one day's impact can't be a mover (need both contributions to diff).
    func testSignalMissingOnOneDayIsNotAMover() {
        let yest = d(21, resp: nil)                 // respiration absent yesterday → not a term
        let today = d(22, hrv: 61, resp: 15)
        let s = scenario(yest: yest, today: today)
        let out = RecoveryChange.compute(today: today, yesterday: yest,
                                         todayScore: 61, yesterdayScore: 58,
                                         todayImpact: s.tImpact, yesterdayImpact: s.yImpact)!
        XCTAssertFalse(out.movers.contains { $0.key == "respRate" },
                       "respiration had no yesterday contribution")
    }
}
