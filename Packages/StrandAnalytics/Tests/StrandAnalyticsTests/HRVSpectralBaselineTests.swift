import XCTest
@testable import StrandAnalytics

final class HRVSpectralBaselineTests: XCTestCase {

    // A stable log-normal-ish history around ~700 ms² (30 nights, all valid) so the baseline is trusted.
    private func steadyHistory(center: Double = 700, nights: Int = 30) -> [Double?] {
        // Small deterministic wobble around the center; no RNG (Date/random are unavailable in tests).
        (0..<nights).map { i in center * (1.0 + 0.02 * Double((i % 5) - 2)) }
    }

    func testColdStartReturnsNilLabel() {
        // Fewer than the trust threshold of valid nights → no trusted baseline → nil (calibrating).
        let history: [Double?] = Array(repeating: 700.0, count: 5)
        XCTAssertNil(HRVSpectralBaseline.label(value: 700, history: history))
    }

    func testValueNearBaselineIsNormal() {
        let h = steadyHistory()
        XCTAssertEqual(HRVSpectralBaseline.label(value: 705, history: h), .normal)
    }

    func testMuchHigherValueIsHigher() {
        let h = steadyHistory()
        // ~3x the geometric center is far beyond +2σ in log-domain.
        XCTAssertEqual(HRVSpectralBaseline.label(value: 2100, history: h), .higher)
    }

    func testMuchLowerValueIsLower() {
        let h = steadyHistory()
        XCTAssertEqual(HRVSpectralBaseline.label(value: 230, history: h), .lower)
    }

    func testBaselineIsLogDomain() {
        // The band config folds in log-domain (powers are log-normal, Plews 2013).
        XCTAssertTrue(HRVSpectralBaseline.bandCfg.logDomain)
    }
}
