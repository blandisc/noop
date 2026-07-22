import XCTest
import StrandModels
@testable import StrandAnalytics

/// Locks the STRUCTURE of the Preparedness verdict (FER-1030): consensus by axis (no double-count),
/// oriented thresholds (better-than-normal is never penalized), cold-start = null vote, and
/// hysteresis. The exact weights / cut-offs are `/cso`-gated knobs and are NOT asserted here — only
/// the behavior that must hold for any reasonable calibration.
final class PreparednessTests: XCTestCase {

    // MARK: Fixtures

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, temp: Double? = 0.0) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp, respRateBpm: resp)
    }

    /// `n` prior nights (01..n June) with a little spread so baselines are well-defined & trusted.
    /// Sub-expressions are explicitly typed: the mixed Int/Double arithmetic inside the `dm(…)` call
    /// blows the Linux Swift type-checker's per-expression budget when inlined (CI runs StrandAnalytics
    /// on ubuntu only — it type-checks fine on macOS, so a local `swift test` won't catch it).
    private func baseline(_ n: Int = 20) -> [DailyMetric] {
        (1...n).map { (i: Int) -> DailyMetric in
            let hrv: Double = 52 + Double(i % 5)
            let rhr: Int = 54 + i % 3
            let resp: Double = 13 + Double(i % 3)
            let sleep: Double = 440 + Double(i % 4) * 5
            return dm(String(format: "2026-06-%02d", i), hrv: hrv, rhr: rhr, resp: resp, sleep: sleep, temp: 0.0)
        }
    }

    /// Hysteresis disabled — isolates the pure per-day consensus.
    private var noHyst: Preparedness.Config { var c = Preparedness.Config(); c.hysteresisDays = 1; return c }

    private func read(_ days: [DailyMetric], asOf: String, strain: [String: Double] = [:],
                      trend: AutonomicTrend.Read? = nil, config: Preparedness.Config? = nil) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: strain, trend: trend, asOf: asOf),
                              config: config ?? .default)
    }

    // MARK: Consensus

    func testAllInRange_full() {
        var days = baseline(); days.append(dm("2026-06-21"))
        XCTAssertEqual(read(days, asOf: "2026-06-21").verdict, .full)
    }

    /// The FER-1010 trap: a single bad night drives HRV DOWN, RHR UP and respiration UP together.
    /// Counting signals would read "3 out → easy". Counting AXES reads "1 out → caution".
    func testBadNight_oneAxisVote_isCautionNotEasy() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20, sleep: 450, temp: 0.0))
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        XCTAssertEqual(r.verdict, .caution, "3 correlated signals = 1 autonomic vote, not 3")
        XCTAssertEqual(r.drivers.first { $0.axis == .autonomic }?.state, .low)
        XCTAssertEqual(r.drivers.first { $0.axis == .sleep }?.state, .inRange)
    }

    /// Two genuinely independent axes out (autonomic + sleep) → easy.
    func testTwoAxesOut_easy() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20, sleep: 300, temp: 0.0))
        XCTAssertEqual(read(days, asOf: "2026-06-21", config: noHyst).verdict, .easy)
    }

    /// Oriented: HRV WAY up and RHR WAY down is *better* than your normal — never counted as out.
    func testBetterThanNormal_notPenalized_full() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 95, rhr: 42, resp: 11, sleep: 460, temp: 0.0))
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        XCTAssertEqual(r.verdict, .full)
        XCTAssertEqual(r.drivers.first { $0.axis == .autonomic }?.state, .inRange)
    }

    // MARK: Cold start

    func testColdStart_lowSignal_notFalseFull() {
        var days = (1...3).map { dm(String(format: "2026-06-%02d", $0)) }   // < seed (4)
        days.append(dm("2026-06-21"))
        let r = read(days, asOf: "2026-06-21")
        XCTAssertEqual(r.verdict, .lowSignal, "too few nights → null vote, never a fake 'Dale con todo'")
        XCTAssertEqual(r.maturity, .calibrating)
    }

    // MARK: Hysteresis

    func testHysteresis_singleBadDayDoesNotFlip() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20))   // one isolated bad day
        XCTAssertEqual(read(days, asOf: "2026-06-21").verdict, .full,
                       "an isolated borderline day must not flip the hero (default 2-day hysteresis)")
    }

    func testHysteresis_twoBadDaysFlip() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20))
        days.append(dm("2026-06-22", hrv: 30, rhr: 75, resp: 20))   // sustained → flips
        XCTAssertEqual(read(days, asOf: "2026-06-22").verdict, .caution)
    }

    // MARK: Trend nudge

    func testTrendFalling_pushesCautionToEasy() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20, sleep: 450))   // caution on body alone
        let falling = AutonomicTrend.Read(direction: .below, confidence: .solid, nightsUsable: 20,
                                          nightsToTrend: 0, recentDenseNights: 5, z7d: -1.3,
                                          spark: [], asOfWasDense: true)
        XCTAssertEqual(read(days, asOf: "2026-06-21", trend: falling, config: noHyst).verdict, .easy)
    }

    // MARK: Frozen hysteresis sequence (FER-1040 — no-regression after the O(n)→ rewrite)

    /// Freezes the DETERMINISTIC hysteresis output across a run of as-of days, so the single-pass
    /// rewrite can never silently move the smoothing. Fixture: 20 settled good nights, then
    /// bad·bad·good·good. With the default 2-day hysteresis the hero must read full → caution →
    /// caution → full (a new verdict needs 2 consecutive days to take, in BOTH directions).
    func testHysteresisVerdictSequence_frozen() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20))   // bad 1
        days.append(dm("2026-06-22", hrv: 30, rhr: 75, resp: 20))   // bad 2 → flips
        days.append(dm("2026-06-23"))                               // good 1 (holds caution)
        days.append(dm("2026-06-24"))                               // good 2 → flips back
        XCTAssertEqual(read(days, asOf: "2026-06-21").verdict, .full)
        XCTAssertEqual(read(days, asOf: "2026-06-22").verdict, .caution)
        XCTAssertEqual(read(days, asOf: "2026-06-23").verdict, .caution)
        XCTAssertEqual(read(days, asOf: "2026-06-24").verdict, .full)
    }

    // MARK: Confidence depth (FER-1040 — D2: the arc measures the verdict's OWN maturity)

    /// `autonomicNights` is the depth of the SDNN baseline the verdict actually stands on (nights
    /// strictly before as-of), NOT the nocturnal-RMSSD trend's `nightsUsable`. It rises with history
    /// and pairs with `maturity`.
    func testAutonomicNights_reflectsVerdictBaselineDepth() {
        var days = baseline(20)             // 20 prior nights
        days.append(dm("2026-06-21"))
        let mature = read(days, asOf: "2026-06-21")
        XCTAssertEqual(mature.autonomicNights, 20, "20 nights strictly before as-of feed the baseline")
        XCTAssertEqual(mature.maturity, .trusted)

        // Cold start: 3 priors (< seed) → the verdict stands on almost nothing, and says so.
        var few = (1...3).map { dm(String(format: "2026-06-%02d", $0)) }
        few.append(dm("2026-06-21"))
        let cold = read(few, asOf: "2026-06-21")
        XCTAssertEqual(cold.autonomicNights, 3)
        XCTAssertEqual(cold.maturity, .calibrating)
        XCTAssertEqual(cold.verdict, .lowSignal)
    }

    // MARK: Signed knobs (/cso gate) — any change here must be an intentional re-gate

    /// Locks the values `/cso` signed for FER-1030 so a future retune can't drift silently.
    func testSignedKnobs_lockedByCSO() {
        let c = Preparedness.Config.default
        XCTAssertEqual(c.wHRV, 0.35); XCTAssertEqual(c.wRHR, 0.40); XCTAssertEqual(c.wResp, 0.25)
        XCTAssertEqual(c.autonomicOutZ, -1.0)
        XCTAssertEqual(c.respBadZ, 1.5)
        XCTAssertEqual(c.thermalOutC, 0.8)
        XCTAssertEqual(c.hysteresisDays, 2)
        XCTAssertEqual(c.sdnnCfgKey, "sdnn")
    }

    /// The SDNN baseline config exists and is byte-identical to the HRV machinery (signed: SDNN is
    /// log-normal like RMSSD), but kept under its OWN key so an RMSSD retune never moves it.
    func testSdnnBaselineConfig_existsAndIdentical() {
        XCTAssertNotNil(Baselines.metricCfg["sdnn"])
        XCTAssertEqual(Baselines.metricCfg["sdnn"], Baselines.metricCfg["hrv"])
    }
}
