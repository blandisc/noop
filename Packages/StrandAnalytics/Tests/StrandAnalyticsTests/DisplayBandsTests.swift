import XCTest
@testable import StrandAnalytics

/// Pins `MetricLevels.displayBands` (FER-29 · contrato 1): the levels table is DERIVED from the engine
/// cuts, so there is exactly one ladder per metric and the range text can't drift from the number.
/// These are the four metrics the requirement calls out (sleep/spo2/resp/strain) plus the shape rules.
final class DisplayBandsTests: XCTestCase {

    func testBandsMirrorEngineLevelsExactly() {
        // Same count, same keys, same bounds as the engine — this is a pure projection, not a restatement.
        for metric in MetricLevels.FixedMetric.allCases {
            let engine = MetricLevels.levels(for: metric)
            let bands = MetricLevels.displayBands(for: metric)
            XCTAssertEqual(bands.map(\.key), engine.map(\.key), "\(metric) keys")
            XCTAssertEqual(bands.map(\.lower), engine.map(\.lower), "\(metric) lower")
            XCTAssertEqual(bands.map(\.upper), engine.map(\.upper), "\(metric) upper")
            // The name is the engine's ONE key→label home, never re-invented.
            XCTAssertEqual(bands.map(\.name),
                           engine.map { MetricLevels.name(for: $0.key) }, "\(metric) names")
        }
    }

    func testSleepIsOneClockLadderNotHours() {
        // The old catalog said «7–9 h»; the engine says 360/420/510 min. Derived text is clock, one ladder.
        let bands = MetricLevels.displayBands(for: .sleep)
        XCTAssertEqual(bands.map(\.key), ["short", "adequate", "optimal", "extended"])
        XCTAssertEqual(bands.map(\.range), ["< 6:00", "6:00 – 7:00", "7:00 – 8:30", "≥ 8:30"])
    }

    func testBloodOxygenIsTwoBandsNotThree() {
        // The catalog had Normal / Borderline / Low (three); the engine has low / normal (two).
        let bands = MetricLevels.displayBands(for: .bloodOxygen)
        XCTAssertEqual(bands.map(\.key), ["low", "normal"])
        XCTAssertEqual(bands.map(\.range), ["< 95%", "≥ 95%"])
    }

    func testRespirationIsTwoHalfOpenBands() {
        // Kills the residual closed-interval «<= 18»: two bands, half-open, «≥ 20 rpm» on top.
        let bands = MetricLevels.displayBands(for: .respiration)
        XCTAssertEqual(bands.map(\.key), ["normal", "elevated"])
        XCTAssertEqual(bands.map(\.range), ["< 20 rpm", "≥ 20 rpm"])
    }

    func testStrainTopBandIsHonestlyOpen() {
        // The declared scale runs to 21, but the engine's top level is open above — the text says «≥ 18».
        let bands = MetricLevels.displayBands(for: .strain)
        XCTAssertEqual(bands.map(\.key), ["rest", "light", "moderate", "hard", "extreme"])
        XCTAssertEqual(bands.map(\.range), ["< 6", "6 – 10", "10 – 14", "14 – 18", "≥ 18"])
    }

    func testAcceptsACustomFormat() {
        // The default format is per-metric, but a caller can pass its own (the app injects one place).
        let custom = MetricFormat(valueStyle: .integer, boundaryStyle: .integer, unit: nil)
        let bands = MetricLevels.displayBands(for: .restingHR, format: custom)
        XCTAssertEqual(bands.map(\.range), ["< 50", "50 – 60", "60 – 80", "≥ 80"])  // no unit
    }
}
