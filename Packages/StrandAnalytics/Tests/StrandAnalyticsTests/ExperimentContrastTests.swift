import XCTest
@testable import StrandAnalytics

/// Locks the tag-experiment contrast (FER-1034): the two-sided verdict, the ≥5-per-arm floor, the
/// two-directional trigger, and confounder restriction. The legacy `evaluate` path is untouched.
final class ExperimentContrastTests: XCTestCase {

    private func days(_ prefix: String, _ range: ClosedRange<Int>) -> Set<String> {
        Set(range.map { String(format: "\(prefix)-%02d", $0) })
    }

    /// Build an outcomeByDay where the given days get `withVal` and the rest get `withoutVal`.
    private func outcomes(with: Set<String>, without: Set<String>,
                          withVal: (Int) -> Double, withoutVal: (Int) -> Double) -> [String: Double] {
        var m: [String: Double] = [:]
        for (i, d) in with.sorted().enumerated() { m[d] = withVal(i) }
        for (i, d) in without.sorted().enumerated() { m[d] = withoutVal(i) }
        return m
    }

    // MARK: Floor

    func testFewerThanFivePerArm_insufficient() {
        let w = days("2026-06", 1...4)          // only 4 with-days
        let wo = days("2026-06", 10...20)
        let out = outcomes(with: w, without: wo, withVal: { 30 + Double($0) }, withoutVal: { 50 + Double($0) })
        let r = ExperimentVerdict.evaluateContrast(withDays: w, withoutDays: wo, outcomeByDay: out)
        XCTAssertEqual(r.verdict, .insufficient)
        XCTAssertNil(r.mwu)
        XCTAssertEqual(r.nWith, 4)
    }

    // MARK: Sustained (both directions)

    func testClearSeparation_sustained_lowerWith() {
        let w = days("2026-06", 1...6)          // with-days: low outcome
        let wo = days("2026-06", 10...16)        // without-days: high outcome
        let out = outcomes(with: w, without: wo, withVal: { 30 + Double($0) }, withoutVal: { 60 + Double($0) })
        let r = ExperimentVerdict.evaluateContrast(withDays: w, withoutDays: wo, outcomeByDay: out)
        XCTAssertEqual(r.verdict, .sustained)
        XCTAssertLessThan(r.mwu!.p, 0.05)
        XCTAssertLessThan(r.mwu!.hlShift, 0)    // with < without
    }

    func testClearSeparation_sustained_higherWith() {
        // Two-sided must fire in the OTHER direction too (the legacy one-sided path could not).
        let w = days("2026-06", 1...6)
        let wo = days("2026-06", 10...16)
        let out = outcomes(with: w, without: wo, withVal: { 70 + Double($0) }, withoutVal: { 30 + Double($0) })
        let r = ExperimentVerdict.evaluateContrast(withDays: w, withoutDays: wo, outcomeByDay: out)
        XCTAssertEqual(r.verdict, .sustained)
        XCTAssertGreaterThan(r.mwu!.hlShift, 0)
    }

    // MARK: Not sustained

    func testInterleavedNoise_notSustained() {
        let w = days("2026-06", 1...6)
        let wo = days("2026-06", 10...16)
        // Interleave so neither arm dominates → no significant separation.
        let out = outcomes(with: w, without: wo, withVal: { 50 + Double($0 % 2) * 2 }, withoutVal: { 51 - Double($0 % 2) * 2 })
        let r = ExperimentVerdict.evaluateContrast(withDays: w, withoutDays: wo, outcomeByDay: out)
        XCTAssertEqual(r.verdict, .notSustained)
        XCTAssertNotNil(r.mwu)
    }

    // MARK: Confounder restriction

    func testConfounderDaysRemovedFromBothArms_andCounted() {
        let w = days("2026-06", 1...7)          // 7 with-days
        let wo = days("2026-06", 10...17)        // 8 without-days
        let confounders: Set<String> = ["2026-06-01", "2026-06-02", "2026-06-10"]   // 2 from with, 1 from without
        let out = outcomes(with: w, without: wo, withVal: { 30 + Double($0) }, withoutVal: { 60 + Double($0) })
        let r = ExperimentVerdict.evaluateContrast(withDays: w, withoutDays: wo,
                                                   outcomeByDay: out, confounderYesDays: confounders)
        XCTAssertEqual(r.nExcluded, 3)
        XCTAssertEqual(r.nWith, 5)              // 7 − 2
        XCTAssertEqual(r.nWithout, 7)           // 8 − 1
        XCTAssertEqual(r.verdict, .sustained)   // still separated after restriction
    }

    func testRestrictConfounders_pureHelper() {
        let with: Set<String> = ["a", "b", "c"]
        let without: Set<String> = ["d", "e"]
        let out = ExperimentVerdict.restrictConfounders(with: with, without: without, confounderYesDays: ["b", "d", "z"])
        XCTAssertEqual(out.with, ["a", "c"])
        XCTAssertEqual(out.without, ["e"])
        XCTAssertEqual(out.excluded, 2)         // "z" isn't in either arm → not counted
    }
}
