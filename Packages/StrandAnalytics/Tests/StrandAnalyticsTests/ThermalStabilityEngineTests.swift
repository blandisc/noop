import XCTest
@testable import StrandAnalytics

/// FER-681 — nocturnal distal warming magnitude + its night-to-night stability.
///
/// Method: reuse the shipped `Baselines` EWMA over the per-night warming magnitudes to get a robust
/// personal center (typical warming) and spread (night-to-night dispersion), then a scale-free
/// coefficient of variation (σ / typical) drives a DESCRIPTIVE 3-band stability label. The distal
/// warming that accompanies sleep onset is the thermoregulatory sleep-gating signal (Kräuchi et al.,
/// Nature 1999). Framed strictly as nocturnal thermal stability — NOT a 24 h circadian amplitude — and
/// never a disease read (Skarke 2023 is a preprint, association only).
final class ThermalStabilityEngineTests: XCTestCase {

    /// The per-night magnitude helper is just plateau − onset.
    func testWarmingMagnitudeHelper() {
        XCTAssertEqual(ThermalStabilityEngine.warmingMagnitude(onsetTempC: 33.0, plateauTempC: 34.5),
                       1.5, accuracy: 1e-9)
    }

    /// Steady ~1.0 °C warming every night ⇒ tight spread ⇒ low CV ⇒ `.consistent`.
    func testConsistentNights() {
        let r = ThermalStabilityEngine.evaluate(magnitudes: Array(repeating: 1.0, count: 20))
        XCTAssertEqual(r.stability, .consistent)
        XCTAssertLessThanOrEqual(r.coefficientOfVariation, ThermalStabilityEngine.consistentMaxCV)
        XCTAssertEqual(r.typicalWarmingC, 1.0, accuracy: 0.1)
    }

    /// Warming that swings 0.4 ↔ 1.6 every night ⇒ large spread ⇒ high CV ⇒ `.variable`.
    func testVariableNights() {
        let swing: [Double?] = (0..<20).map { $0 % 2 == 0 ? 0.4 : 1.6 }
        let r = ThermalStabilityEngine.evaluate(magnitudes: swing)
        XCTAssertEqual(r.stability, .variable)
        XCTAssertGreaterThanOrEqual(r.coefficientOfVariation, ThermalStabilityEngine.variableMinCV)
    }

    /// A middling swing (0.7 ↔ 1.3) lands in the descriptive middle band.
    func testModerateNights() {
        let swing: [Double?] = (0..<20).map { $0 % 2 == 0 ? 0.7 : 1.3 }
        let r = ThermalStabilityEngine.evaluate(magnitudes: swing)
        XCTAssertEqual(r.stability, .moderate)
        XCTAssertGreaterThan(r.coefficientOfVariation, ThermalStabilityEngine.consistentMaxCV)
        XCTAssertLessThan(r.coefficientOfVariation, ThermalStabilityEngine.variableMinCV)
    }

    /// Fewer than a week of nights ⇒ no read yet (`.learning`).
    func testColdStartLearning() {
        let r = ThermalStabilityEngine.evaluate(magnitudes: [1.0, 1.0, 1.0, 1.0])
        XCTAssertEqual(r.stability, .learning)
        XCTAssertLessThan(r.nights, ThermalStabilityEngine.minNightsForStability)
    }

    /// Near-zero typical warming makes the CV ill-defined ⇒ stay `.learning` rather than divide by ~0.
    func testIllDefinedRatioStaysLearning() {
        let r = ThermalStabilityEngine.evaluate(magnitudes: Array(repeating: 0.05, count: 15))
        XCTAssertEqual(r.stability, .learning)
    }

    /// Copy is honest: never claims a 24 h circadian amplitude and never names a disease.
    func testCopyHonesty() {
        let r = ThermalStabilityEngine.evaluate(magnitudes: Array(repeating: 1.0, count: 20))
        let c = r.copy.lowercased()
        XCTAssertTrue(c.contains("warming") || c.contains("descent"))
        for banned in ["24", "circadian amplitude", "disease", "mortality", "diabetes", "nafld", "illness"] {
            XCTAssertFalse(c.contains(banned), "copy must stay honest/non-clinical: found \(banned)")
        }
    }
}
