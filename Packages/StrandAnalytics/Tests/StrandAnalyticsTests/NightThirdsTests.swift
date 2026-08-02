import XCTest
import BiometricStreams
@testable import StrandAnalytics

// FER-7 · Veredicto v4 Fase 4 — first-third vs last-third of the sleeping heart rate.
// A descriptive reading (never votes). These tests exercise the sleep-accumulated partition, the
// median-per-third robustness, the coverage/confidence gate, and the "vs your normal" z (via Baselines).
final class NightThirdsTests: XCTestCase {

    // MARK: - Builders

    private func spans(_ xs: [(Int, Int)]) -> [NightAutonomicShape.AsleepSpan] {
        xs.map { NightAutonomicShape.AsleepSpan(start: $0.0, end: $0.1) }
    }

    /// Samples every `step` s inside each span, bpm from a clock-time function.
    private func hr(_ xs: [(Int, Int)], step: Int = 300, bpm: (Int) -> Int) -> [HRSample] {
        var out: [HRSample] = []
        for (s, e) in xs {
            var t = s
            while t < e { out.append(HRSample(ts: t, bpm: bpm(t))); t += step }
        }
        return out
    }

    // MARK: - CA1 · basic delta

    func testCA1_delta() throws {
        let sp: [(Int, Int)] = [(0, 28_800)]           // single 8 h span
        let hrs = hr(sp) { t in t < 9_600 ? 60 : (t >= 19_200 ? 70 : 65) }
        let r = try XCTUnwrap(NightThirds.compute(hr: hrs, asleep: spans(sp)))
        XCTAssertEqual(r.firstThirdBpm, 60, accuracy: 0.001)
        XCTAssertEqual(r.lastThirdBpm, 70, accuracy: 0.001)
        XCTAssertEqual(r.deltaBpm, 10, accuracy: 0.001)
        XCTAssertEqual(r.confidence, .solid)
    }

    // MARK: - CA2 · no contrast

    func testCA2_flat() throws {
        let sp: [(Int, Int)] = [(0, 28_800)]
        let r = try XCTUnwrap(NightThirds.compute(hr: hr(sp) { _ in 65 }, asleep: spans(sp)))
        XCTAssertEqual(r.deltaBpm, 0, accuracy: 0.001)
    }

    // MARK: - CA2b · robustness (median absorbs a PPG artifact; a mean would not)

    func testCA2b_medianAbsorbsArtifact() throws {
        let sp: [(Int, Int)] = [(0, 28_800)]
        var hrs = hr(sp) { t in t < 9_600 ? 60 : (t >= 19_200 ? 70 : 65) }
        hrs.append(HRSample(ts: 20_000, bpm: 140))      // one arousal spike in the last third
        let r = try XCTUnwrap(NightThirds.compute(hr: hrs, asleep: spans(sp)))
        // Median is unmoved (last third stays 70) → delta stays +10, |Δ| < 1.
        // A simple MEAN would give last third ≈ (32·70 + 140)/33 ≈ 72.1 → delta ≈ +12.1 (a +2 shift).
        XCTAssertEqual(r.deltaBpm, 10, accuracy: 1.0)
    }

    // MARK: - CA3 · partition by SLEEP time, not clock

    func testCA3_partitionBySleepNotClock() throws {
        // 1 h asleep, a 4 h awake gap, then 2 h asleep whose second hour jumps 60→80 bpm.
        let sp: [(Int, Int)] = [(0, 3_600), (18_000, 25_200)]
        let hrs = hr(sp) { t in
            if t < 3_600 { return 60 }                  // span A
            return t < 21_600 ? 60 : 80                 // span B: first hour 60, second hour 80
        }
        let r = try XCTUnwrap(NightThirds.compute(hr: hrs, asleep: spans(sp)))
        // SLEEP partition: last-third boundary is at 2/3 of ASLEEP time → t ≥ 21_600 → all 80.
        XCTAssertEqual(r.firstThirdBpm, 60, accuracy: 0.001)
        XCTAssertEqual(r.lastThirdBpm, 80, accuracy: 0.001)
        XCTAssertEqual(r.deltaBpm, 20, accuracy: 0.001)
        // A CLOCK partition (the wrong impl) would put the boundary at 2/3 of the CLOCK span, sweeping
        // ALL of span B into the last third → median avg(60,80)=70 → delta +10. X (=80) ≠ X' (=70).
    }

    // MARK: - CA4 · pure / deterministic

    func testCA4_deterministic() throws {
        let sp: [(Int, Int)] = [(0, 28_800)]
        let hrs = hr(sp) { t in t < 9_600 ? 58 : (t >= 19_200 ? 71 : 64) }
        let a = NightThirds.compute(hr: hrs, asleep: spans(sp))
        let b = NightThirds.compute(hr: hrs, asleep: spans(sp))
        XCTAssertEqual(a, b)
    }

    // MARK: - CA5 · coverage gate

    func testCA5_estimateWhenThirdSparse() throws {
        let sp: [(Int, Int)] = [(0, 28_800)]
        var hrs = hr([(9_600, 28_800)]) { t in t >= 19_200 ? 70 : 65 }   // middle+last dense
        hrs += [0, 1_500, 3_000, 4_500, 6_000].map { HRSample(ts: $0, bpm: 60) } // 5 in first third
        let r = try XCTUnwrap(NightThirds.compute(hr: hrs, asleep: spans(sp)))
        XCTAssertEqual(r.confidence, .estimate)          // first third has 5 (< 12)
        XCTAssertEqual(r.firstThirdBpm, 60, accuracy: 0.001)
    }

    func testCA5_nilWhenThirdEmpty() {
        let sp: [(Int, Int)] = [(0, 28_800)]
        var hrs = hr([(9_600, 28_800)]) { _ in 65 }
        hrs.append(HRSample(ts: 0, bpm: 60))             // only ONE sample in the first third
        XCTAssertNil(NightThirds.compute(hr: hrs, asleep: spans(sp)))
    }

    func testShortNightIsNil() {
        let sp: [(Int, Int)] = [(0, 7_200)]              // 2 h < minAsleepSec (3 h)
        XCTAssertNil(NightThirds.compute(hr: hr(sp) { _ in 60 }, asleep: spans(sp)))
    }

    // MARK: - CA7 · "vs your normal" z (Baselines), with the maturity gate

    func testCA7_zVsNormal() {
        let cfg = Baselines.metricCfg["night_thirds_delta"]!
        let state = Baselines.rollingMeanSD(Array(repeating: Double?(2.0), count: 30), cfg: cfg, window: 30)
        XCTAssertTrue(state.trusted)
        let high = Baselines.deviation(12.0, state: state)      // "más de lo típico"
        XCTAssertEqual(high.z, 3.19, accuracy: 0.05)
        XCTAssertFalse(high.inNormalRange)
        let usual = Baselines.deviation(2.0, state: state)      // "como de costumbre"
        XCTAssertEqual(usual.z, 0.0, accuracy: 0.001)
        XCTAssertTrue(usual.inNormalRange)
    }

    func testCA7b_maturityGate() {
        let cfg = Baselines.metricCfg["night_thirds_delta"]!
        for n in [2, 4, 13] {
            let st = Baselines.rollingMeanSD(Array(repeating: Double?(2.0), count: n), cfg: cfg, window: 30)
            XCTAssertFalse(st.trusted, "nValid \(n) debe quedar en 'calibrando', no descriptor")
        }
        let st14 = Baselines.rollingMeanSD(Array(repeating: Double?(2.0), count: 14), cfg: cfg, window: 30)
        XCTAssertTrue(st14.trusted)
    }
}
