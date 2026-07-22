import XCTest
@testable import StrandAnalytics
import BiometricStreams

/// FER-972 (P-05) — the per-night display scalar `night_warming_c`: the warming math moved
/// verbatim from the app layer into `ThermalStabilityEngine`.
final class NocturnalScalarsTests: XCTestCase {

    // MARK: - ThermalStabilityEngine.warmingMagnitudeC (the moved math)

    /// A synthetic ramp: onset plateau at raw 4480 (35.0 °C) for the first 20%, rising to raw 4608
    /// (36.0 °C) from 40% on. Expected = (plateauMean − onsetMean) / 128.
    private func rampSamples(n: Int, offset: Int = 0) -> [SkinTempSample] {
        (0..<n).map { i in
            let raw = i < n * 30 / 100 ? 4480 : 4608
            return SkinTempSample(ts: 1_700_000_000 + i * 60, raw: raw + offset)
        }
    }

    func testWarmingMagnitudeRampMatchesHandComputation() {
        let n = 200
        let samples = rampSamples(n: n)
        // Reproduce the documented windows by hand: onset = first 15%, plateau = 40–90%.
        let onsetHi = max(1, n * 15 / 100)
        let plateauLo = n * 40 / 100
        let plateauHi = max(plateauLo + 1, n * 90 / 100)
        let onset = Double(samples[0..<onsetHi].reduce(0) { $0 + $1.raw }) / Double(onsetHi)
        let plateau = Double(samples[plateauLo..<plateauHi].reduce(0) { $0 + $1.raw })
            / Double(plateauHi - plateauLo)
        let expected = (plateau - onset) / 128.0
        let got = ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: samples)
        XCTAssertNotNil(got)
        XCTAssertEqual(got!, expected, accuracy: 1e-9)
        XCTAssertEqual(got!, 1.0, accuracy: 1e-9, "the 128-raw step is exactly 1 °C on this ramp")
    }

    func testWarmingMagnitudeCancelsAdditiveOffset() {
        // A band calibration is additive on raw — the magnitude (a difference) must not move.
        let a = ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 180))
        let b = ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 180, offset: 3648))
        XCTAssertEqual(a!, b!, accuracy: 1e-9)
    }

    func testWarmingMagnitudeNeedsSixtySamples() {
        XCTAssertNil(ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 59)))
        XCTAssertNotNil(ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 60)))
    }
}
