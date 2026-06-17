import XCTest
@testable import StrandAnalytics

/// FER-215 — the population VO₂max reference that contextualizes Apple Health's measured number.
/// Values track the FRIEND p50 medians by decade; the curve declines with age and men sit above women.
final class VO2maxReferenceTests: XCTestCase {

    func testMenAndWomenKnownPoints() {
        // Men: 58.3 − 0.42·age. Women: 45.8 − 0.32·age.
        XCTAssertEqual(VO2maxReference.expected(age: 40, sex: "male"), 41.5, accuracy: 0.6)
        XCTAssertEqual(VO2maxReference.expected(age: 40, sex: "female"), 33.0, accuracy: 0.6)
        XCTAssertEqual(VO2maxReference.expected(age: 25, sex: "male"), 47.8, accuracy: 0.6)
    }

    func testDeclinesWithAge() {
        XCTAssertGreaterThan(VO2maxReference.expected(age: 30, sex: "male"),
                             VO2maxReference.expected(age: 60, sex: "male"))
        XCTAssertGreaterThan(VO2maxReference.expected(age: 30, sex: "female"),
                             VO2maxReference.expected(age: 60, sex: "female"))
    }

    func testMenAboveWomenAtSameAge() {
        for age in [25, 40, 55, 70] {
            XCTAssertGreaterThan(VO2maxReference.expected(age: age, sex: "male"),
                                 VO2maxReference.expected(age: age, sex: "female"), "age \(age)")
        }
    }

    func testNonBinaryUsesMenCurve() {
        XCTAssertEqual(VO2maxReference.expected(age: 45, sex: "nonbinary"),
                       VO2maxReference.expected(age: 45, sex: "male"), accuracy: 1e-9)
    }

    func testAgeClampedToCohortRange() {
        // Below 20 / above 80 clamp to the cohort edges (no wild extrapolation).
        XCTAssertEqual(VO2maxReference.expected(age: 10, sex: "male"),
                       VO2maxReference.expected(age: 20, sex: "male"), accuracy: 1e-9)
        XCTAssertEqual(VO2maxReference.expected(age: 95, sex: "male"),
                       VO2maxReference.expected(age: 80, sex: "male"), accuracy: 1e-9)
    }

    func testNeverImplausiblyLow() {
        XCTAssertGreaterThanOrEqual(VO2maxReference.expected(age: 80, sex: "female"), 15)
    }
}
