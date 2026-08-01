import XCTest
import StrandModels
@testable import StrandAnalytics

/// Locks the three optional v3 Input extensions (nocturnal RHR series, luteal asOf-day allowance,
/// dense nocturnal RMSSD co-vote) — each defaulted so today's call sites stay byte-identical.
final class PreparednessV3InputsTests: XCTestCase {

    // MARK: Fixtures

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

    private var noHyst: Preparedness.Config {
        var c = Preparedness.Config()
        c.hysteresisDays = 1
        return c
    }

    private func read(_ days: [DailyMetric], asOf: String, config: Preparedness.Config? = nil,
                      nocturnalRestingHr: [String: Double] = [:],
                      cyclePhase: CyclePhaseEngine.Phase? = nil,
                      nocturnalRmssd: Preparedness.DenseRmssd? = nil) -> Preparedness.Read {
        Preparedness.evaluate(
            .init(days: days, strainByDay: [:], trend: nil, asOf: asOf,
                  nocturnalRestingHr: nocturnalRestingHr,
                  cyclePhase: cyclePhase,
                  nocturnalRmssd: nocturnalRmssd),
            config: config ?? .default)
    }

    // MARK: B-CA1 — nocturnal resting HR drives z (not Apple awake)

    /// Two different nocturnal RHR values for the same asOf day flip the autonomic read; the Apple
    /// `restingHr` on the DailyMetric is intentionally calm so only the nocturnal map can be the cause.
    func testNocturnalRHR_drivesZ_notAppleAwake() {
        let asOf = "2026-06-21"
        // Apple awake RHR on the metric is calm (55); nocturnal map disagrees on purpose.
        var calm = baseline()
        calm.append(dm(asOf, rhr: 55))
        let inRange = read(calm, asOf: asOf, config: noHyst,
                           nocturnalRestingHr: [asOf: 55])
        XCTAssertEqual(inRange.verdict, .full)
        XCTAssertEqual(inRange.drivers.first { $0.axis == .autonomic }?.state, .inRange)

        var hot = baseline()
        hot.append(dm(asOf, rhr: 55))  // Apple says calm…
        let out = read(hot, asOf: asOf, config: noHyst,
                       nocturnalRestingHr: [asOf: 90])  // …nocturnal says elevated
        XCTAssertEqual(out.drivers.first { $0.axis == .autonomic }?.state, .low,
                       "nocturnal 90 bpm (not Apple 55) must drive the axis low")
        XCTAssertNotEqual(out.verdict, inRange.verdict,
                          "two nocturnal values far apart must flip the read")
        // Oriented z for 90 bpm vs ~55 baseline must be clearly worse than the calm case.
        let zCalm = inRange.signals.first { $0.signal == .rhr }?.orientedZ
        let zHot = out.signals.first { $0.signal == .rhr }?.orientedZ
        XCTAssertNotNil(zCalm); XCTAssertNotNil(zHot)
        XCTAssertLessThan(zHot!, zCalm!, "worse nocturnal RHR → lower (worse) oriented z")
        XCTAssertLessThanOrEqual(zHot!, -1.0, "90 bpm must cross the out cut against a flat baseline")
    }

    // MARK: B-CA2 — luteal allowance is partial credit, not amnesty

    /// A modest asOf RHR bump that would read `.low` without the phase is brought `.inRange` by
    /// `.lutealLean` (within the 2.0 bpm allowance); a larger bump still reads `.low` after discount.
    func testLutealRHR_allowanceWithinInRange_largerStillOut() {
        let asOf = "2026-06-21"
        // floorSpread for resting_hr is 2.0; baseline ~55. Raw RHR 58 → ~1.5 SD worse → low without
        // allowance; after −2.0 bpm luteal discount → 56 → ~0.5 SD → inRange.
        var modest = baseline()
        modest.append(dm(asOf, rhr: 58))
        let without = read(modest, asOf: asOf, config: noHyst, cyclePhase: nil)
        XCTAssertEqual(without.drivers.first { $0.axis == .autonomic }?.state, .low,
                       "precondition: modest bump without luteal must be out")
        let withLuteal = read(modest, asOf: asOf, config: noHyst, cyclePhase: .lutealLean)
        XCTAssertEqual(withLuteal.drivers.first { $0.axis == .autonomic }?.state, .inRange,
                       "luteal allowance of 2 bpm must bring a within-allowance bump in range")

        // Larger shift: 65 − 2 = 63 still well past the cut → stays low.
        var large = baseline()
        large.append(dm(asOf, rhr: 65))
        let largeLuteal = read(large, asOf: asOf, config: noHyst, cyclePhase: .lutealLean)
        XCTAssertEqual(largeLuteal.drivers.first { $0.axis == .autonomic }?.state, .low,
                       "shift larger than allowance is partial credit, not amnesty")
    }

    /// Analogous partial credit for high-side skin temp vs `lutealTempAllowanceC` (0.3 °C) and
    /// `thermalOutC` (0.8 °C): 1.0 → 0.7 inRange; 1.2 → 0.9 still high. Cold side untouched.
    func testLutealTemp_allowanceWithinInRange_largerStillHigh() {
        let asOf = "2026-06-21"
        var within = baseline()
        within.append(dm(asOf, temp: 1.0))
        XCTAssertEqual(read(within, asOf: asOf, config: noHyst).drivers.first { $0.axis == .thermal }?.state,
                       .high, "precondition: 1.0 °C ≥ 0.8 without luteal")
        XCTAssertEqual(read(within, asOf: asOf, config: noHyst, cyclePhase: .lutealLean)
                        .drivers.first { $0.axis == .thermal }?.state,
                       .inRange, "1.0 − 0.3 = 0.7 < 0.8 → inRange under luteal")

        var larger = baseline()
        larger.append(dm(asOf, temp: 1.2))
        XCTAssertEqual(read(larger, asOf: asOf, config: noHyst, cyclePhase: .lutealLean)
                        .drivers.first { $0.axis == .thermal }?.state,
                       .high, "1.2 − 0.3 = 0.9 ≥ 0.8 → still high after allowance")

        // Cold side must never be discounted (luteal physiology explains warm, not cold).
        var cold = baseline()
        cold.append(dm(asOf, temp: -1.0))
        XCTAssertEqual(read(cold, asOf: asOf, config: noHyst, cyclePhase: .lutealLean)
                        .drivers.first { $0.axis == .thermal }?.state,
                       .low, "cold side unchanged under luteal")
    }

    // MARK: B-CA3 — defaults are a pure no-op vs the 4-arg Input

    /// Explicit nil/empty new inputs produce the same verdict AND drivers as the legacy 4-arg
    /// `Input.init` for calm, caution, and easy days.
    func testDefaultsParity_withLegacyFourArgInit() {
        let asOf = "2026-06-21"
        let cases: [(name: String, day: DailyMetric)] = [
            ("full",    dm(asOf)),
            ("caution", dm(asOf, rhr: 75)),                         // autonomic out alone
            ("easy",    dm(asOf, rhr: 75, sleep: 300)),              // autonomic + sleep
        ]
        for c in cases {
            var days = baseline()
            days.append(c.day)
            let legacy = Preparedness.evaluate(
                .init(days: days, strainByDay: [:], trend: nil, asOf: asOf),
                config: noHyst)
            let withDefaults = Preparedness.evaluate(
                .init(days: days, strainByDay: [:], trend: nil, asOf: asOf,
                      nocturnalRestingHr: [:], cyclePhase: nil, nocturnalRmssd: nil),
                config: noHyst)
            XCTAssertEqual(withDefaults.verdict, legacy.verdict, "\(c.name): verdict parity")
            XCTAssertEqual(withDefaults.drivers, legacy.drivers, "\(c.name): drivers parity")
            XCTAssertEqual(withDefaults.signals, legacy.signals, "\(c.name): signals parity")
        }
    }

    // MARK: B-CA4 — dense RMSSD co-vote; non-dense is a no-op; share reflects den

    /// A very bad RMSSD z with `dense: false` leaves the composite unchanged; the same z with
    /// `dense: true` moves it (and rhr share drops below 1.0).
    func testDenseRmssd_nonDenseNoOp_denseMovesCompositeAndShare() {
        let asOf = "2026-06-21"
        var days = baseline()
        days.append(dm(asOf, rhr: 55))  // calm RHR → full without RMSSD

        let base = read(days, asOf: asOf, config: noHyst)
        XCTAssertEqual(base.verdict, .full)
        XCTAssertEqual(base.signals.first { $0.signal == .rhr }?.share, 1.0)

        let nonDense = read(days, asOf: asOf, config: noHyst,
                            nocturnalRmssd: .init(z: -3.0, dense: false))
        XCTAssertEqual(nonDense.verdict, base.verdict, "non-dense RMSSD must not move the verdict")
        XCTAssertEqual(nonDense.drivers.first { $0.axis == .autonomic }?.orientedZ,
                       base.drivers.first { $0.axis == .autonomic }?.orientedZ,
                       "non-dense RMSSD must not move the composite")
        XCTAssertEqual(nonDense.signals.first { $0.signal == .rhr }?.share, 1.0)

        // dense + z = −3.0: composite ≈ (1·rhrZ + 0.5·(−3)) / 1.5. With calm rhrZ ≈ 0 → −1.0 at the
        // out cut; use −3.5 so it clearly crosses (composite ≈ −1.167).
        let dense = read(days, asOf: asOf, config: noHyst,
                         nocturnalRmssd: .init(z: -3.5, dense: true))
        let baseZ = base.drivers.first { $0.axis == .autonomic }?.orientedZ
        let denseZ = dense.drivers.first { $0.axis == .autonomic }?.orientedZ
        XCTAssertNotNil(baseZ); XCTAssertNotNil(denseZ)
        XCTAssertNotEqual(denseZ!, baseZ!, "dense bad RMSSD must move the composite")
        XCTAssertEqual(dense.drivers.first { $0.axis == .autonomic }?.state, .low)
        let rhrShare = dense.signals.first { $0.signal == .rhr }?.share
        XCTAssertNotNil(rhrShare)
        XCTAssertEqual(rhrShare!, 1.0 / 1.5, accuracy: 1e-9,
                       "rhr share must be wRHR/(wRHR+wNocturnalRMSSD), not a stale 1.0")
        XCTAssertLessThan(rhrShare!, 1.0)
    }

    // MARK: B-CA5 — RMSSD never votes alone

    /// With no resting-HR reading at all, even a good dense RMSSD leaves autonomic `.noData` and
    /// the overall verdict `.lowSignal` — the 4th term is gated on rhrZ presence.
    func testDenseRmssd_neverVotesAlone_lowSignalWithoutRHR() {
        let asOf = "2026-06-21"
        var days = baseline()
        days.append(dm(asOf, rhr: nil))
        let r = read(days, asOf: asOf, config: noHyst,
                     nocturnalRmssd: .init(z: 2.0, dense: true))
        XCTAssertEqual(r.drivers.first { $0.axis == .autonomic }?.state, .noData,
                       "RMSSD must not enter without rhrZ — axis stays noData")
        XCTAssertEqual(r.verdict, .lowSignal)
    }
}
