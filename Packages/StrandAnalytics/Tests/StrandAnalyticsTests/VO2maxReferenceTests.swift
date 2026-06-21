import XCTest
@testable import StrandAnalytics

/// FER-215 — the population VO₂max reference that contextualizes Apple Health's measured number.
/// Values track the FRIEND p50 medians by decade; the curve declines with age and men sit above women.
final class VO2maxReferenceTests: XCTestCase {

    func testMenAndWomenKnownPoints() {
        // Men: 59.25 − 0.474·age. Women: 44.66 − 0.373·age (least-squares over the FRIEND decade medians).
        XCTAssertEqual(VO2maxReference.expected(age: 40, sex: "male"), 40.3, accuracy: 0.6)
        XCTAssertEqual(VO2maxReference.expected(age: 40, sex: "female"), 29.7, accuracy: 0.6)
        XCTAssertEqual(VO2maxReference.expected(age: 25, sex: "male"), 47.4, accuracy: 0.6)
    }

    func testTracksFriendDecadeMedians() {
        // The fitted curve should stay within ~2 ml/kg/min of the published FRIEND p50 medians.
        let men: [(Int, Double)] = [(25, 48.0), (35, 42.4), (45, 37.8), (55, 32.6), (65, 28.2), (75, 24.4)]
        let women: [(Int, Double)] = [(25, 37.6), (35, 30.2), (45, 26.7), (55, 23.4), (65, 20.0), (75, 18.3)]
        for (age, p50) in men {
            XCTAssertEqual(VO2maxReference.expected(age: age, sex: "male"), p50, accuracy: 2.0, "men \(age)")
        }
        for (age, p50) in women {
            XCTAssertEqual(VO2maxReference.expected(age: age, sex: "female"), p50, accuracy: 2.5, "women \(age)")
        }
    }

    func testFriendMedianWomanClassifiesAverage() {
        // FER fix: a woman measuring the real FRIEND p50 for her age must read "average", not "low"
        // (the old curve over-stated the women's median by ~+4–5 and pushed age-peer-median women to "low").
        for (age, p50) in [(35, 30.2), (45, 26.7), (55, 23.4), (65, 20.0)] {
            XCTAssertEqual(VO2maxReference.category(value: p50, age: age, sex: "female"), .average, "age \(age)")
        }
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

    // MARK: - Category (FER-257)

    func testCategoryThresholdsAscending() {
        let t = VO2maxReference.categoryThresholds(age: 35, sex: "male")
        XCTAssertLessThan(t.low, t.good)
        XCTAssertLessThan(t.good, t.excellent)
    }

    func testMedianValueLandsAverage() {
        // A value equal to the age/sex median sits in the middle band.
        for (age, sex) in [(30, "male"), (45, "female"), (60, "male")] {
            let mid = VO2maxReference.expected(age: age, sex: sex)
            XCTAssertEqual(VO2maxReference.category(value: mid, age: age, sex: sex), .average, "age \(age) \(sex)")
        }
    }

    func testHighValueIsExcellentLowValueIsLow() {
        let age = 35, sex = "male"
        let mid = VO2maxReference.expected(age: age, sex: sex)
        XCTAssertEqual(VO2maxReference.category(value: mid + 25, age: age, sex: sex), .excellent)
        XCTAssertEqual(VO2maxReference.category(value: mid - 25, age: age, sex: sex), .low)
    }

    func testCategoryMonotonicInValue() {
        // Higher VO₂max never lands in a worse band.
        let age = 40, sex = "female"
        let order: [VO2maxReference.Category] = [.low, .average, .good, .excellent]
        func rank(_ v: Double) -> Int { order.firstIndex(of: VO2maxReference.category(value: v, age: age, sex: sex))! }
        var last = -1
        for v in stride(from: 15.0, through: 70.0, by: 1.0) {
            let r = rank(v)
            XCTAssertGreaterThanOrEqual(r, last, "value \(v) dropped a band")
            last = r
        }
    }

    // MARK: - Equivalent age (FER-257)

    func testEquivalentAgeInvertsExpected() {
        // The median value for age A maps back to age A (within rounding).
        for (age, sex) in [(25, "male"), (40, "male"), (50, "female")] {
            let mid = VO2maxReference.expected(age: age, sex: sex)
            XCTAssertEqual(VO2maxReference.equivalentAge(value: mid, sex: sex), age, accuracy: 1, "age \(age) \(sex)")
        }
    }

    func testEquivalentAgeClampedToCohort() {
        // A sky-high value can't read younger than 20; a near-zero one no older than 80.
        XCTAssertEqual(VO2maxReference.equivalentAge(value: 90, sex: "male"), 20)
        XCTAssertEqual(VO2maxReference.equivalentAge(value: 5, sex: "male"), 80)
    }
}
