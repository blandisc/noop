import XCTest
@testable import StrandAnalytics
import WhoopStore

// Synthetic validation suite for the InsightEngine (FER-290).
//
// No real WHOOP data exists yet, so every dataset here is generated with a known
// ground truth and a deterministic seeded RNG: a planted effect MUST be recovered,
// pure noise MUST NOT be reported as significant (with the family-wise false-positive
// rate held near α after FDR), and a known trend MUST forecast the right direction.

final class InsightEngineTests: XCTestCase {

    // MARK: - Deterministic RNG (no system randomness — reproducible across runs)

    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
        mutating func unit() -> Double {   // [0, 1)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) * (1.0 / 9007199254740992.0)
        }
        mutating func gauss(_ mean: Double, _ sd: Double) -> Double {
            let u1 = Swift.max(unit(), 1e-12), u2 = unit()
            let z = (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
            return mean + sd * z
        }
    }

    // MARK: - Day-key helper

    private static let baseDate: Date = {
        var c = DateComponents(); c.year = 2024; c.month = 1; c.day = 1
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    private func day(_ offset: Int) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(byAdding: .day, value: offset, to: Self.baseDate)!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func metric(_ offset: Int, recovery: Double?, hrv: Double? = nil,
                        sleep: Double? = 480, rhr: Int? = nil) -> DailyMetric {
        DailyMetric(day: day(offset), totalSleepMin: sleep, efficiency: nil, deepMin: nil,
                    remMin: nil, lightMin: nil, disturbances: nil, restingHr: rhr,
                    avgHrv: hrv, recovery: recovery, strain: nil, exerciseCount: nil)
    }

    // MARK: - Test 1 — planted effect is recovered and marked significant

    func testPlantedEffectRecovered() {
        var rng = LCG(seed: 42)
        var days: [DailyMetric] = []
        var alcoholDays: Set<String> = []
        let n = 140
        for i in 0..<n {
            let logged = (i % 3 == 0)              // ~47 behavior days, deterministic
            // Planted: alcohol drags recovery down ~15 pts. Strong, well-separated effect.
            let rec = logged ? rng.gauss(55, 9) : rng.gauss(70, 9)
            if logged { alcoholDays.insert(day(i)) }
            days.append(metric(i, recovery: rec))
        }

        let out = InsightEngine.generate(.init(days: days, behaviors: ["Alcohol": alcoholDays]))
        let hit = out.first { $0.kind == .behavior && $0.title.contains("Alcohol") && $0.datum.metric == "Recuperación" }
        let found = try? XCTUnwrap(hit, "should surface an Alcohol→Recuperación behavior insight")
        guard let found else { return }

        XCTAssertTrue(found.evidence.significant, "a 15-pt planted effect must clear FDR + floors")
        XCTAssertEqual(found.confidence, .candidate, "a significant association is a candidate")
        XCTAssertLessThan(found.evidence.effectSize ?? 0, 0, "effect direction is negative (recovery drops)")
        let q = try? XCTUnwrap(found.evidence.pAdjusted)
        if let q { XCTAssertLessThan(q, InsightEngine.alpha) }
        // It should rank at the very top (significant findings outrank descriptive).
        XCTAssertEqual(out.first?.kind, .behavior)
    }

    // MARK: - Test 2 — noise produces no significant effect; FP rate ≈ α after FDR

    func testNoiseFalsePositiveRateNearAlpha() {
        let seeds = 200
        var seedsWithAnyFalsePositive = 0

        for s in 0..<seeds {
            var rng = LCG(seed: UInt64(s) &* 7919 &+ 13)
            var days: [DailyMetric] = []
            let n = 100
            // Four behaviors logged on random days, INDEPENDENT of every outcome.
            var behaviors: [String: Set<String>] = ["A": [], "B": [], "C": [], "D": []]
            for i in 0..<n {
                // Outcomes are pure noise, mutually independent.
                let rec = rng.gauss(65, 10)
                let hrv = rng.gauss(60, 12)
                let rhr = Int(rng.gauss(58, 5).rounded())
                let sleep = rng.gauss(450, 40)
                days.append(metric(i, recovery: rec, hrv: hrv, sleep: sleep, rhr: rhr))
                for key in behaviors.keys {
                    if rng.unit() < 0.4 { behaviors[key]!.insert(day(i)) }   // ~40 days each
                }
            }
            let out = InsightEngine.generate(.init(days: days, behaviors: behaviors))
            // ANY association flagged significant on pure noise is a false positive.
            if out.contains(where: { ($0.kind == .behavior || $0.kind == .correlation) && $0.evidence.significant }) {
                seedsWithAnyFalsePositive += 1
            }
        }

        let rate = Double(seedsWithAnyFalsePositive) / Double(seeds)
        // Under the global null, BH at α bounds the family-wise false-positive rate at α.
        // Allow generous slack for the normal-approximation p-values and finite seeds,
        // but it must be controlled — nowhere near the uncorrected ~60% a naive pass gives.
        XCTAssertLessThanOrEqual(rate, 0.10, "FDR must hold the FP rate near α=0.05 (got \(rate))")
    }

    // MARK: - Test 3 — known trend forecasts the right direction

    func testForecastDirection() {
        func forecast(rising: Bool) -> Insight? {
            var rng = LCG(seed: rising ? 7 : 9)
            var days: [DailyMetric] = []
            let n = 21
            for i in 0..<n {
                // Clean linear ramp ± small noise, well within 0…100.
                let base = rising ? 45.0 + Double(i) * 1.5 : 80.0 - Double(i) * 1.5
                days.append(metric(i, recovery: base + rng.gauss(0, 1.5)))
            }
            return InsightEngine.generate(.init(days: days)).first { $0.kind == .forecast }
        }

        let up = forecast(rising: true)
        let down = forecast(rising: false)
        XCTAssertEqual(up?.kind, .forecast)
        XCTAssertEqual(down?.kind, .forecast)
        // The detector encodes direction in evidence.effectSize: + rising, − falling.
        XCTAssertGreaterThan(up?.evidence.effectSize ?? 0, 0, "rising series → rising forecast")
        XCTAssertLessThan(down?.evidence.effectSize ?? 0, 0, "falling series → falling forecast")
    }

    // MARK: - Test 4 — every emitted insight carries all required fields

    func testAllFieldsPopulated() {
        var rng = LCG(seed: 3)
        var days: [DailyMetric] = []
        var alcohol: Set<String> = []
        for i in 0..<120 {
            let logged = (i % 4 == 0)
            let rec = logged ? rng.gauss(58, 9) : rng.gauss(72, 9)
            if logged { alcohol.insert(day(i)) }
            days.append(metric(i, recovery: rec, hrv: rng.gauss(60, 10),
                               sleep: rng.gauss(430, 30), rhr: Int(rng.gauss(56, 4).rounded())))
        }
        let out = InsightEngine.generate(.init(days: days, behaviors: ["Alcohol": alcohol]))
        XCTAssertFalse(out.isEmpty)
        for ins in out {
            XCTAssertFalse(ins.title.isEmpty, "title required")
            XCTAssertFalse(ins.reading.isEmpty, "reading required")
            XCTAssertFalse(ins.datum.metric.isEmpty, "datum.metric required")
            XCTAssertFalse(ins.datum.unit.isEmpty, "datum.unit required")
            XCTAssertGreaterThanOrEqual(ins.evidence.n, 0)
            XCTAssertTrue(ins.datum.value.isFinite)
        }
        // Ranking is descending by relevance.
        for i in 1..<out.count { XCTAssertGreaterThanOrEqual(out[i - 1].relevance, out[i].relevance) }
    }

    // MARK: - Test 5 — FDR is actually applied across the family

    func testFDRAdjustmentApplied() {
        var rng = LCG(seed: 11)
        var days: [DailyMetric] = []
        var b: [String: Set<String>] = ["A": [], "B": [], "C": []]
        for i in 0..<100 {
            days.append(metric(i, recovery: rng.gauss(65, 10), hrv: rng.gauss(60, 10),
                               sleep: rng.gauss(450, 40), rhr: Int(rng.gauss(58, 5).rounded())))
            for k in b.keys { if rng.unit() < 0.4 { b[k]!.insert(day(i)) } }
        }
        let out = InsightEngine.generate(.init(days: days, behaviors: b))
        let assoc = out.filter { $0.kind == .behavior || $0.kind == .correlation }
        XCTAssertFalse(assoc.isEmpty, "should produce association candidates")
        for a in assoc {
            let p = try? XCTUnwrap(a.evidence.pValue)
            let q = try? XCTUnwrap(a.evidence.pAdjusted, "every association carries an FDR q-value")
            if let p, let q { XCTAssertGreaterThanOrEqual(q + 1e-12, p, "q ≥ raw p (correction inflates)") }
        }
    }

    // MARK: - Test 6 — empty input is safe

    func testEmptyInputs() {
        XCTAssertTrue(InsightEngine.generate(.init(days: [])).isEmpty)
    }
}
