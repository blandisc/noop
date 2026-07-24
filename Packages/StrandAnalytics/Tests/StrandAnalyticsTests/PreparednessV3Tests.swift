import XCTest
import StrandModels
@testable import StrandAnalytics

/// Locks the v3 re-gate of the Preparedness verdict (2026-07-24, CSO+Grok deep science
/// investigation): SDNN out of the vote, resting-HR backbone, graded sleep vs need (no 6h cliff),
/// respiration + temp fused into a corroborated illness sentinel, and the provisional cold-start
/// tier. These assert the NEW behavior — they are the intentional inverse of the v2 locks.
final class PreparednessV3Tests: XCTestCase {

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, temp: Double? = 0.0, eff: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: eff, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp, respRateBpm: resp)
    }

    private func baseline(_ n: Int = 20) -> [DailyMetric] {
        (1...n).map { (i: Int) -> DailyMetric in
            let hrv: Double = 52 + Double(i % 5)
            let rhr: Int = 54 + i % 3
            let resp: Double = 13 + Double(i % 3)
            let sleep: Double = 440 + Double(i % 4) * 5
            return dm(String(format: "2026-06-%02d", i), hrv: hrv, rhr: rhr, resp: resp, sleep: sleep, temp: 0.0)
        }
    }

    private var noHyst: Preparedness.Config { var c = Preparedness.Config(); c.hysteresisDays = 1; return c }

    private func read(_ days: [DailyMetric], asOf: String, config: Preparedness.Config? = nil) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: nil, asOf: asOf),
                              config: config ?? .default)
    }

    // MARK: CA1 — SDNN (avgHrv) is OUT of the vote

    /// Two nights identical except the all-day SDNN produce the SAME verdict: the SDNN no longer
    /// moves the vote (its MAPE ~29% is why — O'Grady 2024). It still SHOWS with share 0.
    func testSdnnDoesNotMoveVerdict() {
        var goodHrv = baseline(); goodHrv.append(dm("2026-06-21", hrv: 90))   // SDNN way up
        var badHrv  = baseline(); badHrv.append(dm("2026-06-21", hrv: 20))    // SDNN way down
        XCTAssertEqual(read(goodHrv, asOf: "2026-06-21", config: noHyst).verdict,
                       read(badHrv,  asOf: "2026-06-21", config: noHyst).verdict,
                       "the all-day SDNN must not change the verdict in v3")
        let r = read(badHrv, asOf: "2026-06-21", config: noHyst)
        XCTAssertEqual(r.signals.first { $0.signal == .hrv }?.share, 0, "SDNN shows but does not vote")
        XCTAssertEqual(r.verdict, .full, "a bad SDNN with calm resting-HR is still full")
    }

    /// Only HRV present (no resting-HR reading) → the autonomic core has no vote, so `lowSignal` —
    /// v3 never falls back to voting on the SDNN "by accident".
    func testNoRestingHr_lowSignal_notSdnnFallback() {
        var days = baseline(); days.append(dm("2026-06-21", rhr: nil))
        XCTAssertEqual(read(days, asOf: "2026-06-21", config: noHyst).verdict, .lowSignal)
    }

    // MARK: CA2 — graded sleep vs need, the 6h cliff is dead

    /// The binary 360-min cliff is gone: a 370-min night (which cleared the old <360 cliff as "not
    /// short") now reads `low` because it is materially below the 420-min need (−45 slack → 375). A
    /// 400-min night stays in range. Duration is graded vs need, not a hard step (Van Dongen 2003).
    func testSleepGradedVsNeed_cliffDead() {
        var below = baseline(); below.append(dm("2026-06-21", sleep: 370))
        XCTAssertEqual(read(below, asOf: "2026-06-21", config: noHyst).drivers.first { $0.axis == .sleep }?.state, .low)
        var okay = baseline(); okay.append(dm("2026-06-21", sleep: 400))
        XCTAssertEqual(read(okay, asOf: "2026-06-21", config: noHyst).drivers.first { $0.axis == .sleep }?.state, .inRange)
    }

    /// A full-duration night with poor efficiency reads `low` (continuity matters — Ohayon 2017);
    /// efficiency == nil never forces low (a missing measure is not a bad one).
    func testSleepEfficiency_lowWhenPoor_nilNeverForces() {
        var poor = baseline(); poor.append(dm("2026-06-21", sleep: 460, eff: 0.70))
        XCTAssertEqual(read(poor, asOf: "2026-06-21", config: noHyst).drivers.first { $0.axis == .sleep }?.state, .low)
        var missing = baseline(); missing.append(dm("2026-06-21", sleep: 460, eff: nil))
        XCTAssertEqual(read(missing, asOf: "2026-06-21", config: noHyst).drivers.first { $0.axis == .sleep }?.state, .inRange)
    }

    // MARK: CA3 — illness sentinel (temp + resp corroborated), lone signals don't vote

    /// Temp elevated ALONE (resp normal) does not vote → still `full` (kills the warm-room false
    /// positive). Temp + resp elevated together corroborate → `caution`.
    func testSentinel_requiresCorroboration() {
        var tempOnly = baseline(); tempOnly.append(dm("2026-06-21", temp: 1.0))
        XCTAssertEqual(read(tempOnly, asOf: "2026-06-21", config: noHyst).verdict, .full,
                       "a lone temperature rise no longer votes")
        var both = baseline(); both.append(dm("2026-06-21", resp: 22, temp: 1.0))
        XCTAssertEqual(read(both, asOf: "2026-06-21", config: noHyst).verdict, .caution,
                       "temp + resp corroborated → sentinel nudges to caution")
    }

    /// A cold temperature deviation is not an illness sign — the sentinel only fires on the HIGH side.
    func testSentinel_coldTempDoesNotVote() {
        var cold = baseline(); cold.append(dm("2026-06-21", resp: 22, temp: -1.0))
        XCTAssertEqual(read(cold, asOf: "2026-06-21", config: noHyst).verdict, .full)
    }

    /// The sentinel counts as one axis: sentinel out + autonomic out (two independent axes) → `easy`,
    /// proving it participates in the consensus count (not a cosmetic post-process).
    func testSentinel_plusAutonomic_easy() {
        var days = baseline(); days.append(dm("2026-06-21", rhr: 75, resp: 22, temp: 1.0))
        XCTAssertEqual(read(days, asOf: "2026-06-21", config: noHyst).verdict, .easy)
    }

    // MARK: Provisional cold-start tier

    /// Between seed (4) and trust (14) nights the verdict is real but flagged `provisional`
    /// (the resting-HR baseline isn't mature). Below seed it is `lowSignal` (not provisional); at
    /// trust the flag lifts.
    func testProvisionalTier() {
        var mid = baseline(8); mid.append(dm("2026-06-21"))
        let m = read(mid, asOf: "2026-06-21")
        XCTAssertNotEqual(m.verdict, .lowSignal)
        XCTAssertTrue(m.provisional, "seed..<trust nights → provisional verdict")

        var mature = baseline(20); mature.append(dm("2026-06-21"))
        XCTAssertFalse(read(mature, asOf: "2026-06-21").provisional, "a trusted baseline is not provisional")

        var cold = (1...3).map { dm(String(format: "2026-06-%02d", $0)) }
        cold.append(dm("2026-06-21"))
        XCTAssertFalse(read(cold, asOf: "2026-06-21").provisional, "below seed is lowSignal, not provisional")
    }
}
