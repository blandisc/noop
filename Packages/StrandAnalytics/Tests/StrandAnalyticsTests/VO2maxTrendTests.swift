import XCTest
@testable import StrandAnalytics

// FER-679 — the fitness TRAJECTORY: a robust (Theil–Sen) slope with a noise floor tied to the
// estimator's SEE (~5.7). The point of the floor is that pure jitter must NOT read as a trend, while
// a sustained real move must. Copy is a direction only — never a longevity claim.
final class VO2maxTrendTests: XCTestCase {

    private func pts(_ vals: [Double], everyDays: Int = 7, start: Int = 0) -> [VO2maxTrend.Point] {
        vals.enumerated().map { VO2maxTrend.Point(day: start + $0.offset * everyDays, value: $0.element) }
    }

    func testClearRiseDetected() {
        // 10 weekly estimates climbing ~1 ml/kg/min per week over ~9 weeks (~+9 total) → rising.
        let vals = (0..<10).map { 40.0 + Double($0) * 1.0 }
        let r = try! XCTUnwrap(VO2maxTrend.assess(pts(vals)))
        XCTAssertEqual(r.direction, .rising)
        XCTAssertGreaterThan(r.slopePerWeek, 0.5)
        XCTAssertGreaterThan(r.changeOverWindow, r.noiseFloor)
        XCTAssertTrue(r.note.contains("subiendo"))
        XCTAssertFalse(r.note.lowercased().contains("años"))   // no longevity claim
    }

    func testClearDeclineDetected() {
        let vals = (0..<10).map { 50.0 - Double($0) * 0.9 }
        let r = try! XCTUnwrap(VO2maxTrend.assess(pts(vals)))
        XCTAssertEqual(r.direction, .falling)
        XCTAssertLessThan(r.slopePerWeek, 0)
        XCTAssertTrue(r.note.contains("bajando"))
    }

    func testFlatSeriesIsStable() {
        let vals = [Double](repeating: 45.0, count: 10)
        let r = try! XCTUnwrap(VO2maxTrend.assess(pts(vals)))
        XCTAssertEqual(r.direction, .stable)
        XCTAssertEqual(r.changeOverWindow, 0, accuracy: 0.001)
    }

    func testJitterDoesNotReadAsTrend() {
        // Level 45 with ±4 ml/kg/min zig-zag (within the SEE ~5.7 jitter) and ZERO real slope → stable.
        let noise = [4.0, -4.0, 3.0, -3.5, 4.0, -4.0, 3.0, -3.0, 4.0, -4.0, 3.5, -3.0]
        let vals = noise.map { 45.0 + $0 }
        let r = try! XCTUnwrap(VO2maxTrend.assess(pts(vals)))
        XCTAssertEqual(r.direction, .stable, "SEE-scale jitter with no real slope must not read as a trend")
    }

    func testTinyRealSlopeBelowFloorIsStable() {
        // A real but tiny climb (~0.1 ml/kg/min per week ≈ +1 over the window) under the noise floor → stable.
        let vals = (0..<10).map { 45.0 + Double($0) * 0.1 }
        let r = try! XCTUnwrap(VO2maxTrend.assess(pts(vals)))
        XCTAssertLessThan(abs(r.changeOverWindow), r.noiseFloor)
        XCTAssertEqual(r.direction, .stable)
    }

    func testTooFewPointsHidden() {
        XCTAssertNil(VO2maxTrend.assess(pts([40, 41, 42, 43, 44])))   // 5 < minPoints
    }

    func testSpanTooShortHidden() {
        // 6 points but packed into 10 days (< minSpanDays) → hidden.
        let vals = [40.0, 41, 42, 43, 44, 45]
        XCTAssertNil(VO2maxTrend.assess(pts(vals, everyDays: 2)))
    }

    func testNoiseFloorShrinksWithMoreData() {
        XCTAssertGreaterThan(VO2maxTrend.noiseFloor(pointCount: 6),
                             VO2maxTrend.noiseFloor(pointCount: 24))
        XCTAssertEqual(VO2maxTrend.noiseFloor(pointCount: 1), VO2maxTrend.seeMlKgMin, accuracy: 1e-9)
    }

    func testConfidenceScalesWithPoints() {
        let thin = try! XCTUnwrap(VO2maxTrend.assess(pts((0..<7).map { 40.0 + Double($0) })))
        XCTAssertEqual(thin.confidence, .estimate)
        let rich = try! XCTUnwrap(VO2maxTrend.assess(pts((0..<14).map { 40.0 + Double($0) })))
        XCTAssertEqual(rich.confidence, .solid)
    }

    func testOutlierDoesNotFlipRobustSlope() {
        // A flat series with ONE wild outlier — Theil–Sen's median slope stays ~0 → stable.
        var vals = [Double](repeating: 45.0, count: 11)
        vals[5] = 80.0   // a single absurd estimate
        let r = try! XCTUnwrap(VO2maxTrend.assess(pts(vals)))
        XCTAssertEqual(r.direction, .stable, "one outlier must not create a trend under a robust slope")
    }

    func testDuplicateDaysCollapsed() {
        // Two estimates on the same day are averaged, not double-counted into the pairwise set.
        var vals = pts((0..<8).map { 40.0 + Double($0) })
        vals.append(VO2maxTrend.Point(day: vals[3].day, value: vals[3].value + 2))
        let r = try! XCTUnwrap(VO2maxTrend.assess(vals))
        XCTAssertEqual(r.direction, .rising)
    }
}
