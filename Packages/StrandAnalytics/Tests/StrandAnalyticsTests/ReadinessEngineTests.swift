import XCTest
@testable import StrandAnalytics
import WhoopStore

final class ReadinessEngineTests: XCTestCase {

    private func d(_ i: Int, hrv: Double?, rhr: Int?, strain: Double?, resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: nil, efficiency: nil,
                    deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: rhr,
                    avgHrv: hrv, recovery: nil, strain: strain, exerciseCount: nil,
                    spo2Pct: nil, skinTempDevC: nil, respRateBpm: resp)
    }

    /// 28 baseline days with gentle variation (so SD > 0), then `today` as day 29.
    private func baseline(todayHrv: Double?, todayRhr: Int?, todayStrain: Double?,
                          todayResp: Double? = nil, baseStrain: Double = 10) -> [DailyMetric] {
        var days: [DailyMetric] = []
        for i in 1...28 {
            days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: i % 2 == 0 ? 54 : 50,
                          strain: baseStrain, resp: i % 2 == 0 ? 14.5 : 13.5))
        }
        days.append(d(29, hrv: todayHrv, rhr: todayRhr, strain: todayStrain, resp: todayResp))
        return days
    }

    func testInsufficientWhenEmpty() {
        XCTAssertEqual(ReadinessEngine.evaluate(days: []).level, .insufficient)
    }

    func testPrimedWhenSignalsAligned() {
        // Today: HRV well above baseline, resting HR below, load steady.
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))
        XCTAssertEqual(r.level, .primed)
        XCTAssertEqual(r.signals.first { $0.key == "hrv" }?.flag, .good)
        XCTAssertEqual(r.signals.first { $0.key == "rhr" }?.flag, .good)
        XCTAssertEqual(r.signals.first { $0.key == "acwr" }?.flag, .good)
    }

    func testRundownWhenTwoRecoverySignalsDown() {
        // Today: HRV suppressed AND resting HR elevated → two "bad" recovery signals.
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 50, todayRhr: 60, todayStrain: 10))
        XCTAssertEqual(r.level, .rundown)
    }

    func testAcwrSpikeStrains() {
        // Recovery signals neutral, but acute load spikes above chronic.
        var days: [DailyMetric] = []
        for i in 1...21 { days.append(d(i, hrv: 60, rhr: 52, strain: 5)) }
        for i in 22...28 { days.append(d(i, hrv: 60, rhr: 52, strain: 15)) }
        days.append(d(29, hrv: 60, rhr: 52, strain: 15))
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertEqual(r.signals.first { $0.key == "acwr" }?.flag, .bad)
        XCTAssertEqual(r.level, .strained)
        XCTAssertNotNil(r.acwr)
        XCTAssertGreaterThan(r.acwr!, 1.5)
    }

    func testRespRateRiseFlags() {
        // Today resp rate well above baseline (~14) → illness-ish watch/bad signal present.
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10, todayResp: 18))
        XCTAssertTrue(r.signals.contains { $0.key == "respRate" })
    }

    func testExplicitTodayWithoutMatchingRowIsInsufficient() {
        // Stale historical import: newest row is 2024-03-29, but the device's real calendar day is later.
        // An explicit `today` with no matching row must read INSUFFICIENT — NOT synthesize off the newest
        // stored (stale) row (issue #23/#24).
        let days = baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10)
        XCTAssertEqual(ReadinessEngine.evaluate(days: days, today: "2026-06-08").level, .insufficient)
        // The day that IS present still computes (no regression for current data).
        XCTAssertNotEqual(ReadinessEngine.evaluate(days: days, today: "2024-03-29").level, .insufficient)
        // The legacy no-`today` path is unchanged — still falls back to the most recent row.
        XCTAssertNotEqual(ReadinessEngine.evaluate(days: days).level, .insufficient)
    }

    func testSkinTempRiseFlagsIllness() {
        // Today's skin temp well above the personal baseline (≥0.8 °C) → a "bad" illness
        // signal, which (now counted as a recovery-down driver) pushes readiness to strained.
        var days = baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10)
        days[days.count - 1] = DailyMetric(day: "2024-03-29", totalSleepMin: nil, efficiency: nil,
            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
            avgHrv: 60, recovery: nil, strain: 10, exerciseCount: nil,
            spo2Pct: nil, skinTempDevC: 1.0, respRateBpm: nil)
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertEqual(r.signals.first { $0.key == "skinTemp" }?.flag, .bad)
        XCTAssertEqual(r.level, .strained)
    }

    // MARK: - Compact signal value (the «Señales» read-out, FER-292 v2)

    func testSignalValueIsRawDirectionalDeviation() {
        // HRV well above baseline (good), resting HR well below (good), load steady.
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))

        // HRV: above baseline → a POSITIVE σ, even though "above" is the GOOD direction here.
        let hrv = r.signals.first { $0.key == "hrv" }
        XCTAssertEqual(hrv?.flag, .good)
        XCTAssertEqual(hrv?.value?.hasSuffix("σ"), true)
        XCTAssertEqual(hrv?.value?.hasPrefix("+"), true, "HRV above baseline should read as +Nσ")

        // Resting HR: below baseline → a NEGATIVE σ (raw direction), and that's the GOOD direction for RHR.
        // The number is direction, the flag is valence — they can disagree in sign.
        let rhr = r.signals.first { $0.key == "rhr" }
        XCTAssertEqual(rhr?.flag, .good)
        XCTAssertEqual(rhr?.value?.hasSuffix("σ"), true)
        XCTAssertEqual(rhr?.value?.hasPrefix("-"), true, "Resting HR below baseline should read as -Nσ")

        // Load: the bare acute:chronic ratio — no σ, parses as a number near 1.0.
        let acwr = r.signals.first { $0.key == "acwr" }
        XCTAssertNotNil(acwr?.value)
        XCTAssertEqual(acwr?.value?.contains("σ"), false)
        XCTAssertNotNil(acwr?.value.flatMap { Double($0) }, "Load value should parse as a plain ratio")
    }

    func testSkinTempSignalValueIsCelsius() {
        var days = baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10)
        days[days.count - 1] = DailyMetric(day: "2024-03-29", totalSleepMin: nil, efficiency: nil,
            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
            avgHrv: 60, recovery: nil, strain: 10, exerciseCount: nil,
            spo2Pct: nil, skinTempDevC: 1.0, respRateBpm: nil)
        let r = ReadinessEngine.evaluate(days: days)
        let skin = r.signals.first { $0.key == "skinTemp" }
        XCTAssertEqual(skin?.value?.contains("°C"), true)
    }

    // MARK: - Confidence (short-night) flag

    /// Replace the last day of a baseline with one carrying `sleepMin` of sleep (everything else neutral).
    private func baselineWithSleep(_ sleepMin: Double?) -> [DailyMetric] {
        var days = baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10)
        days[days.count - 1] = DailyMetric(day: "2024-03-29", totalSleepMin: sleepMin, efficiency: nil,
            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
            avgHrv: 60, recovery: nil, strain: 10, exerciseCount: nil,
            spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
        return days
    }

    func testShortNightFlagsLowConfidence() {
        // 5h12m last night (< 6h) → the morning read is honestly flagged low-confidence.
        let r = ReadinessEngine.evaluate(days: baselineWithSleep(312))
        XCTAssertTrue(r.confidenceLow)
        XCTAssertNotNil(r.confidenceNote)
    }

    func testFullNightIsHighConfidence() {
        // 7h24m → normal confidence, no caveat.
        let r = ReadinessEngine.evaluate(days: baselineWithSleep(444))
        XCTAssertFalse(r.confidenceLow)
        XCTAssertNil(r.confidenceNote)
    }

    func testMissingSleepIsNotLowConfidence() {
        // No sleep duration recorded (strap-only / HR-only day) → we don't claim low confidence.
        let r = ReadinessEngine.evaluate(days: baselineWithSleep(nil))
        XCTAssertFalse(r.confidenceLow)
    }

    // MARK: - Reconciliation (recovery vs. verdict bridge)

    /// ACWR spike (→ strained, acwr `.bad`) with an explicit recovery score on today's row, so we
    /// can drive the high/low divergence gate. Recovery signals stay neutral, so `acwr` is the lead.
    private func acwrSpike(todayRecovery: Double?) -> [DailyMetric] {
        var days: [DailyMetric] = []
        for i in 1...21 { days.append(d(i, hrv: 60, rhr: 52, strain: 5)) }
        for i in 22...28 { days.append(d(i, hrv: 60, rhr: 52, strain: 15)) }
        days.append(DailyMetric(day: "2024-03-29", totalSleepMin: nil, efficiency: nil,
            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
            avgHrv: 60, recovery: todayRecovery, strain: 15, exerciseCount: nil,
            spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil))
        return days
    }

    func testBridgeNoneWhenInsufficient() {
        let r = ReadinessEngine.evaluate(days: [])
        XCTAssertEqual(r.bridgeKind, .none)
        XCTAssertNil(r.bridge)
    }

    func testBridgeAlignedWhenPrimed() {
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 72, todayRhr: 46, todayStrain: 10))
        XCTAssertEqual(r.level, .primed)
        XCTAssertEqual(r.bridgeKind, .aligned)
        XCTAssertNotNil(r.bridge)
        XCTAssertNil(r.culpritNoun)   // nothing to blame on an aligned day
    }

    func testBridgeRundownWhenSeveralDown() {
        let r = ReadinessEngine.evaluate(days: baseline(todayHrv: 50, todayRhr: 60, todayStrain: 10))
        XCTAssertEqual(r.level, .rundown)
        XCTAssertEqual(r.bridgeKind, .rundown)
    }

    func testBridgeDivergenceLoadWhenRecoveryHighAndLoadSpikes() {
        // Strained by an ACWR spike, but the user woke up well recovered → the load is the culprit,
        // not the body: the "great everywhere except your load" case.
        let r = ReadinessEngine.evaluate(days: acwrSpike(todayRecovery: 80))
        XCTAssertEqual(r.level, .strained)
        XCTAssertEqual(r.bridgeKind, .divergenceLoad)
        XCTAssertNotNil(r.bridge)
        XCTAssertTrue(r.bridge!.lowercased().contains("load"))
        XCTAssertEqual(r.culpritNoun?.lowercased().contains("load"), true)   // sublabel names the load
    }

    func testBridgeStrainedFlatWhenRecoveryNotHigh() {
        // Same ACWR spike, but recovery is not in the green band → no divergence to explain.
        XCTAssertEqual(ReadinessEngine.evaluate(days: acwrSpike(todayRecovery: nil)).bridgeKind, .strainedFlat)
        XCTAssertEqual(ReadinessEngine.evaluate(days: acwrSpike(todayRecovery: 40)).bridgeKind, .strainedFlat)
    }

    func testBridgeDivergenceGateBoundaryAtYellowMax() {
        // The high-recovery gate is exactly RecoveryScorer.bandYellowMax (67): below → flat, at → divergence.
        XCTAssertEqual(ReadinessEngine.evaluate(days: acwrSpike(todayRecovery: 66)).bridgeKind, .strainedFlat)
        XCTAssertEqual(ReadinessEngine.evaluate(days: acwrSpike(todayRecovery: 67)).bridgeKind, .divergenceLoad)
    }

    func testBridgeDivergenceBodyWhenRecoveryHighAndBodySignalFlags() {
        // High recovery, but a body signal (skin temp) flags → divergence framed on the body, not load.
        var days = baseline(todayHrv: 60, todayRhr: 52, todayStrain: 10)
        days[days.count - 1] = DailyMetric(day: "2024-03-29", totalSleepMin: nil, efficiency: nil,
            deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
            avgHrv: 60, recovery: 80, strain: 10, exerciseCount: nil,
            spo2Pct: nil, skinTempDevC: 1.0, respRateBpm: nil)
        let r = ReadinessEngine.evaluate(days: days)
        XCTAssertEqual(r.level, .strained)
        XCTAssertEqual(r.bridgeKind, .divergenceBody)
        XCTAssertNotNil(r.bridge)
    }

    func testStatsHelpers() {
        XCTAssertEqual(ReadinessEngine.mean([2, 4, 6]), 4)
        XCTAssertEqual(ReadinessEngine.sampleSD([2, 4, 6])!, 2.0, accuracy: 0.0001)
        XCTAssertNil(ReadinessEngine.sampleSD([5]))
        XCTAssertNil(ReadinessEngine.mean([]))
    }

    // MARK: - Confidence shrinkage (FER-13)

    /// `n` baseline days with the same gentle ±2 HRV variation (mean ≈ 60), then `today`.
    private func hrvHistory(days n: Int, todayHrv: Double) -> [DailyMetric] {
        var days: [DailyMetric] = []
        for i in 1...n { days.append(d(i, hrv: i % 2 == 0 ? 62 : 58, rhr: 52, strain: 10)) }
        days.append(d(n + 1, hrv: todayHrv, rhr: 52, strain: 10))
        return days
    }

    private func severity(_ flag: ReadinessEngine.Flag?) -> Int {
        switch flag {
        case .good, .neutral, .none: return 0
        case .watch: return 1
        case .bad:   return 2
        }
    }

    private func hrvFlag(days n: Int, todayHrv: Double) -> ReadinessEngine.Flag? {
        ReadinessEngine.evaluate(days: hrvHistory(days: n, todayHrv: todayHrv))
            .signals.first { $0.key == "hrv" }?.flag
    }

    /// Across a sweep of suppressed-HRV nights, a thin (provisional) baseline never
    /// flags MORE severely than a long (trusted) one, and for at least one night it
    /// flags strictly LESS severely — the z is shrunk toward neutral on weak evidence
    /// so the engine doesn't sound the alarm prematurely (FER-13).
    func testThinBaselineNeverMoreSevereAndSometimesLess() {
        var sawDowngrade = false
        for today in stride(from: 58.0, through: 50.0, by: -1.0) {
            let thin = severity(hrvFlag(days: 9, todayHrv: today))      // provisional → shrunk
            let trusted = severity(hrvFlag(days: 28, todayHrv: today))  // trusted → unshrunk
            XCTAssertLessThanOrEqual(thin, trusted, "thin baseline more severe at hrv=\(today)")
            if thin < trusted { sawDowngrade = true }
        }
        XCTAssertTrue(sawDowngrade, "shrinkage never downgraded a flag across the sweep")
    }
}
