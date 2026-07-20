import XCTest
@testable import StrandAnalytics

/// FER-1003 science gate — artifact rejection + plausibility symmetry for the nocturnal autonomic trend.
/// Covers the material bug the /estadistico gate reproduced (an in-DB artifact night flipped the visible
/// direction because the base skip-held it but the recent geomean/spark did not) and the coverage gaps it
/// named (.below/.above never asserted to FIRE, no z=±0.5 boundary, no sub-second dt, no range endpoints).
final class AutonomicArtifactGateTests: XCTestCase {

    private func nn(_ pairs: [(Double, Double)]) -> [TimedNN] {
        pairs.map { TimedNN(ts: $0.0, nnMs: $0.1) }
    }
    private func nights(_ vals: [(String, Double)]) -> [(day: String, rmssdMs: Double)] {
        vals.map { (day: $0.0, rmssdMs: $0.1) }
    }
    /// 40 consecutive days of `value` starting 2025-11-01 (all < 2026-01-15), for a settled base.
    private func oldBase(_ value: Double) -> [(String, Double)] {
        let cal = Calendar(identifier: .gregorian)
        var date = cal.date(from: DateComponents(year: 2025, month: 11, day: 1))!
        let df = DateFormatter(); df.calendar = cal; df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0); df.dateFormat = "yyyy-MM-dd"
        var out: [(String, Double)] = []
        for _ in 0..<40 { out.append((df.string(from: date), value)); date = cal.date(byAdding: .day, value: 1, to: date)! }
        return out
    }

    // MARK: - Layer 2: per-pair successive-difference artifact rejection (rmssdSegmented)

    func testArtifactPairRejectedNotBridged() {
        // 800→820 clean (2.5%); 820→1500 and 1500→810 are artifact jumps (>80%) — both dropped, not bridged.
        let beats = nn([(0, 800), (1, 820), (2, 1500), (3, 810)])
        let filtered = HRVAnalyzer.rmssdSegmented(beats)                 // default 0.20
        XCTAssertEqual(filtered.nPairs, 1)
        XCTAssertEqual(filtered.rmssd!, 20.0, accuracy: 1e-12)
        // With the filter effectively off, the monster Δs dominate — proving they were the thing removed.
        let unfiltered = HRVAnalyzer.rmssdSegmented(beats, deltaFraction: 5.0)
        XCTAssertEqual(unfiltered.nPairs, 3)
        XCTAssertGreaterThan(unfiltered.rmssd!, 500)                     // ~559 ms of pure artifact
    }

    func testHighRSABradycardicPreserved() {
        // Genuine high-RSA bradycardic sleep: long RR, large-but-real Δ up to ~17% — must be KEPT
        // (this is the "legitimately above" night the relative threshold protects; an absolute 250 cap
        // would wrongly kill the 200 ms swing here).
        let beats = nn([(0, 1200), (1, 1400), (2, 1250), (3, 1420)])
        let r = HRVAnalyzer.rmssdSegmented(beats)
        XCTAssertEqual(r.nPairs, 3)                                      // nothing rejected
    }

    func testArtifactThresholdBoundaryInclusive() {
        // Exactly 20% of min is KEPT (<=), a hair over is rejected.
        let atBoundary = HRVAnalyzer.rmssdSegmented(nn([(0, 1000), (1, 1200)]))  // 200/1000 = 0.20
        XCTAssertEqual(atBoundary.nPairs, 1)
        XCTAssertEqual(atBoundary.rmssd!, 200.0, accuracy: 1e-12)
        let justOver = HRVAnalyzer.rmssdSegmented(nn([(0, 1000), (1, 1201)]))   // 201/1000 = 0.201
        XCTAssertEqual(justOver.nPairs, 0)
        XCTAssertNil(justOver.rmssd)
    }

    func testExistingGoldenUnaffectedByFilter() {
        // The shipped golden (small Δs) must be byte-identical with the filter on — no clean-night drift.
        let r = HRVAnalyzer.rmssdSegmented(nn([(0, 800), (1, 820), (2, 810), (3, 850)]))
        XCTAssertEqual(r.nPairs, 3)
        XCTAssertEqual(r.rmssd!, 26.457513110645905, accuracy: 1e-12)
    }

    // MARK: - Coverage gaps the /estadistico named

    func testSubSecondFractionalPairCounts() {
        // D5: two beats inside the SAME integer second (10.2, 10.9) — Double ts preserves dt=0.7 and the
        // pair counts; the old Int-truncated ts would collapse to dt=0 and silently drop it.
        let r = HRVAnalyzer.rmssdSegmented(nn([(10.2, 800), (10.9, 820)]))
        XCTAssertEqual(r.nPairs, 1)
        XCTAssertEqual(r.rmssd!, 20.0, accuracy: 1e-12)
    }

    func testRangeEndpointsInclusive() {
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(nn([(0, 300), (1, 330)])).nPairs, 1)   // 300 inclusive
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(nn([(0, 2000), (1, 1900)])).nPairs, 1) // 2000 inclusive
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(nn([(0, 299), (1, 330)])).nPairs, 0)   // below → excluded
        XCTAssertEqual(HRVAnalyzer.rmssdSegmented(nn([(0, 2001), (1, 1900)])).nPairs, 0) // above → excluded
    }

    // MARK: - Direction actually FIRES (both dead-zone branches) + boundary

    func testAboveDirectionFires() {
        let ns = oldBase(50) + [("2026-01-16", 60), ("2026-01-18", 60), ("2026-01-21", 60)]
        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-21", recentCutoff: "2026-01-15")
        XCTAssertEqual(r.confidence, .solid)
        XCTAssertEqual(r.direction, .above)
        XCTAssertGreaterThan(r.z7d!, 0.5)
    }

    func testBelowDirectionFires() {
        let ns = oldBase(50) + [("2026-01-16", 40), ("2026-01-18", 40), ("2026-01-21", 40)]
        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-21", recentCutoff: "2026-01-15")
        XCTAssertEqual(r.direction, .below)
        XCTAssertLessThan(r.z7d!, -0.5)
    }

    func testDeadZoneBoundaryBracket() {
        // base = 50, σ_ln = 1.253·0.08. z = 0.5 ⇔ value = 50·exp(0.5·1.253·0.08) ≈ 52.57.
        // 52.6 → z just above 0.5 → above; 52.5 → z just below → inBase. Brackets the inclusive edge.
        let hi = AutonomicTrend.evaluate(nights: nights(oldBase(50) + [("2026-01-16", 52.6), ("2026-01-18", 52.6), ("2026-01-21", 52.6)]),
                                         asOf: "2026-01-21", recentCutoff: "2026-01-15")
        XCTAssertEqual(hi.direction, .above)
        let lo = AutonomicTrend.evaluate(nights: nights(oldBase(50) + [("2026-01-16", 52.5), ("2026-01-18", 52.5), ("2026-01-21", 52.5)]),
                                         asOf: "2026-01-21", recentCutoff: "2026-01-15")
        XCTAssertEqual(lo.direction, .inBase)
    }

    // MARK: - The reproduced bug, now fixed: an implausible recent night is gated, not surfaced

    func testImplausibleRecentNightGatedNoFlip() {
        // 40 nights at 50 + a recent window of three 50s and ONE 600 ms artifact. Pre-fix the 600 poisoned
        // the geomean (geomean ≈ 93 → z ≈ 6 → "above"); post-fix it is dropped symmetrically with the base,
        // so the direction stays inBase, z ≈ 0, and it does not count toward nightsUsable.
        let ns = oldBase(50) + [("2026-01-16", 50), ("2026-01-18", 50), ("2026-01-20", 50), ("2026-01-21", 600)]
        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-21", recentCutoff: "2026-01-15")
        XCTAssertEqual(r.confidence, .solid)
        XCTAssertEqual(r.direction, .inBase)          // NOT .above
        XCTAssertEqual(r.nightsUsable, 43)            // the 600 night dropped from the count
        XCTAssertEqual(r.recentDenseNights, 3)        // three plausible recent nights remain
        XCTAssertLessThan(abs(r.z7d!), 0.5)
    }

    // MARK: - Layer 1: an implausible-RMSSD night is not dense (NocturnalHRV.night)

    func testImplausibleRmssdNightNotDense() {
        // 61 beats alternating 1300/1560: every Δ = 260 ms is exactly 20% of 1300 (kept by the per-pair
        // filter), so RMSSD = 260 ms — plausible per-pair, but > maxVal (250). The night is NOT dense,
        // proving the plausibility backstop rejects it via value (not via the pairs count, which is 60).
        var beats: [TimedNN] = []
        for i in 0..<61 { beats.append(TimedNN(ts: Double(i), nnMs: i % 2 == 0 ? 1300 : 1560)) }
        let night = NocturnalHRV.night(intervals: beats, windowStart: nil, windowEnd: nil)
        XCTAssertGreaterThanOrEqual(night.nPairs, 30)  // passes the density gate…
        XCTAssertEqual(night.nClean, 61)
        XCTAssertNil(night.rmssdMs)                     // …but rejected as implausible (RMSSD 260 > 250)
        XCTAssertFalse(night.dense)
    }
}
