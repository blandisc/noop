import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-1049 · fase 1a — multi-night smoothing of the resting-HR backbone. A CAPACITY (`Config
/// .rhrSmoothingNights`), default 1 = byte-identical pre-v4. Numeric CAs from
/// `docs/_plan-veredicto-v4.md` → PARTE A → FASE 1a. The N* crossover is MEASURED by execution
/// here, never hand-derived (the plan's quoted 8/9 were arithmetic that the executed audit corrected).
final class PreparednessV4SmoothingTests: XCTestCase {

    // MARK: Fixtures (duplicated — PreparednessTests.baseline() is private, per the plan's CA1 note)

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, temp: Double? = 0.0) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp, respRateBpm: resp)
    }

    /// The exact `PreparednessTests.baseline()` fixture, duplicated (20 nights, small spread).
    private func baselineVaried(_ n: Int = 20) -> [DailyMetric] {
        (1...n).map { (i: Int) -> DailyMetric in
            let hrv: Double = 52 + Double(i % 5)
            let rhr: Int = 54 + i % 3
            let resp: Double = 13 + Double(i % 3)
            let sleep: Double = 440 + Double(i % 4) * 5
            return dm(String(format: "2026-06-%02d", i), hrv: hrv, rhr: rhr, resp: resp, sleep: sleep, temp: 0.0)
        }
    }

    /// 20 perfectly FLAT nights (rhr = 55, everything else nominal).
    private func flat20() -> [DailyMetric] {
        (1...20).map { dm(String(format: "2026-06-%02d", $0), hrv: 55, rhr: 55, resp: 14, sleep: 450, temp: 0.0) }
    }

    private func cfg(_ n: Int, hysteresis: Int = 1) -> Preparedness.Config {
        var c = Preparedness.Config(); c.rhrSmoothingNights = n; c.hysteresisDays = hysteresis; return c
    }

    private func read(_ days: [DailyMetric], asOf: String, config: Preparedness.Config) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: nil, asOf: asOf), config: config)
    }

    private func autonomicState(_ r: Preparedness.Read) -> Preparedness.AxisState? {
        r.drivers.first { $0.axis == .autonomic }?.state
    }

    private func autonomicZ(_ r: Preparedness.Read) -> Double? {
        r.drivers.first { $0.axis == .autonomic }?.orientedZ
    }

    /// Smallest N in 1…limit for which today's autonomic axis is no longer `.low`, or nil.
    private func firstNNotLow(days: [DailyMetric], asOf: String, limit: Int = 20) -> Int? {
        for n in 1...limit where autonomicState(read(days, asOf: asOf, config: cfg(n))) != .low { return n }
        return nil
    }

    // MARK: - CA1 (paridad): N=1 is identical to the default

    func testCA1_parityAtN1() {
        var days = baselineVaried(); days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20))
        let def = read(days, asOf: "2026-06-21", config: .default)
        let n1 = read(days, asOf: "2026-06-21", config: cfg(1, hysteresis: 2))
        XCTAssertEqual(def.verdict, n1.verdict)
        XCTAssertEqual(def.drivers, n1.drivers)
        XCTAssertEqual(def.signals, n1.signals)
    }

    // MARK: - CA2: monotone effect + a measured N* where an isolated spike stops moving the axis

    func testCA2_monotoneAndNStar_flat20() {
        var days = flat20(); days.append(dm("2026-06-21", hrv: 55, rhr: 75, resp: 14, temp: 0.0)) // +20 bpm today
        let asOf = "2026-06-21"
        // Monotone: today's oriented autonomic z rises (less negative) as N grows.
        var prev = -Double.infinity
        for n in 1...12 {
            let z = autonomicZ(read(days, asOf: asOf, config: cfg(n))) ?? -.infinity
            XCTAssertGreaterThan(z, prev - 1e-9, "z must not decrease as N grows (N=\(n))")
            prev = z
        }
        // N=1 leaves the axis .low; a crossover N* exists.
        XCTAssertEqual(autonomicState(read(days, asOf: asOf, config: cfg(1))), .low)
        guard let nStar = firstNNotLow(days: days, asOf: asOf) else {
            return XCTFail("expected a crossover N*")
        }
        // MEASURED by execution (not derived by hand). Pin it so a future change that moves the
        // smoothing math fails loudly.
        XCTAssertEqual(nStar, 8, "N* for the flat-20 fixture (measured by execution)")
    }

    func testCA2_nStar_variedBaseline() {
        var days = baselineVaried(); days.append(dm("2026-06-21", hrv: 55, rhr: 75, resp: 14, temp: 0.0))
        let asOf = "2026-06-21"
        XCTAssertEqual(autonomicState(read(days, asOf: asOf, config: cfg(1))), .low)
        guard let nStar = firstNNotLow(days: days, asOf: asOf) else {
            return XCTFail("expected a crossover N*")
        }
        XCTAssertEqual(nStar, 9, "N* for the baseline() fixture (measured by execution)")
    }

    // MARK: - CA2b: the knob demonstrably does something — same series, two configs, two results

    func testCA2b_knobChangesTheAxis() {
        var days = flat20(); days.append(dm("2026-06-21", hrv: 55, rhr: 75, resp: 14, temp: 0.0))
        let asOf = "2026-06-21"
        let nStar = firstNNotLow(days: days, asOf: asOf)!
        XCTAssertEqual(autonomicState(read(days, asOf: asOf, config: cfg(1))), .low)
        XCTAssertNotEqual(autonomicState(read(days, asOf: asOf, config: cfg(nStar))), .low)
    }

    // MARK: - CA3: smoothing silences the autonomic axis, NOT the sentinel (mutation-proof wording)

    func testCA3_sentinelIsIndependentOfSmoothing() {
        // Flat 20 + today: rhr +20 (axis spike) AND temp/resp elevated (sentinel corroborated).
        var days = flat20()
        days.append(dm("2026-06-21", hrv: 55, rhr: 75, resp: 20, sleep: 450, temp: 1.0))
        let asOf = "2026-06-21"
        let nStar = firstNNotLow(days: days, asOf: asOf)!
        // N=1: autonomic .low (spike) + sentinel (temp+resp) = 2 votes → easy.
        XCTAssertEqual(read(days, asOf: asOf, config: cfg(1)).verdict, .easy)
        // N=N*: smoothing flattened the autonomic axis, but temp/resp are NOT smoothed — the sentinel
        // still fires, so exactly one vote remains → caution, and crucially NOT full. A .full here
        // would mean the smoothing had (wrongly) silenced the sentinel too.
        let atNStar = read(days, asOf: asOf, config: cfg(nStar))
        XCTAssertEqual(autonomicState(atNStar), .inRange, "the spike axis is smoothed away at N*")
        XCTAssertEqual(atNStar.verdict, .caution, "the sentinel's lone vote survives; not full")
    }

    // MARK: - CA4: the frozen hysteresis sequence still holds at the default (guards N=1 = pre-v4)

    func testCA4_frozenHysteresisAtDefault() {
        var days = baselineVaried()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20))
        days.append(dm("2026-06-22", hrv: 30, rhr: 75, resp: 20))
        days.append(dm("2026-06-23"))
        days.append(dm("2026-06-24"))
        XCTAssertEqual(read(days, asOf: "2026-06-21", config: .default).verdict, .full)
        XCTAssertEqual(read(days, asOf: "2026-06-22", config: .default).verdict, .caution)
        XCTAssertEqual(read(days, asOf: "2026-06-23", config: .default).verdict, .caution)
        XCTAssertEqual(read(days, asOf: "2026-06-24", config: .default).verdict, .full)
    }
}
