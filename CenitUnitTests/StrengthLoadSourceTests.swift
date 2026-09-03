import XCTest
import BiometricStreams
import StrandAnalytics
import StrandTraining
@testable import Cenit

/// Ola 1 · E2 — the matrix of «where did this session's load come from», at the app seam that
/// decides it. One source per session, never a sum.
final class StrengthLoadSourceTests: XCTestCase {

    private let hrMax = 190.0

    private func pulse(seconds: Int, bpm: Int = 140) -> [HRSample] {
        (0...seconds).map { HRSample(ts: $0, bpm: bpm) }
    }

    /// A watch that actually covered the session and no rating: the measured number, unchanged —
    /// exactly what `StrainScorer.strain` would have stored before this change.
    func testCoveredPulseWithoutAnswerStaysMeasured() {
        let elapsed = 3000
        let samples = pulse(seconds: 2700)      // coverage 0.9
        XCTAssertGreaterThanOrEqual(HRCoverage.fraction(samples, elapsedSeconds: elapsed), 0.9)

        let out = AppModel.resolveStrengthLoad(hrSamples: samples, elapsedSeconds: elapsed,
                                               sessionRpe: nil,
                                               trimpPerAU: SessionRPELoad.defaultTrimpPerAU,
                                               hrMax: hrMax, sex: "male")
        XCTAssertEqual(out.source, .hr)
        XCTAssertEqual(out.strain!, StrainScorer.strain(samples, maxHR: hrMax, sex: "male")!,
                       accuracy: 1e-9)
        XCTAssertNil(out.trimpPerAU, "a measured session has no estimate scale")
    }

    /// A rating turns the session into an estimate on the same 0–21 ruler.
    func testAnsweredSessionIsEstimatedAndLandsInBand() {
        let out = AppModel.resolveStrengthLoad(hrSamples: [], elapsedSeconds: 52 * 60,
                                               sessionRpe: 8,
                                               trimpPerAU: SessionRPELoad.defaultTrimpPerAU,
                                               hrMax: hrMax, sex: "male")
        XCTAssertEqual(out.source, .rpe)
        XCTAssertGreaterThanOrEqual(out.strain!, 10)
        XCTAssertLessThanOrEqual(out.strain!, 12)
        XCTAssertEqual(out.trimpPerAU!, SessionRPELoad.defaultTrimpPerAU, accuracy: 1e-9)
    }

    /// Neither pulse nor rating: nothing. «Entrenaste, carga sin estimar» is a hold, never a zero.
    func testNoPulseNoAnswerStoresNoLoad() {
        let out = AppModel.resolveStrengthLoad(hrSamples: [], elapsedSeconds: 3000, sessionRpe: nil,
                                               trimpPerAU: SessionRPELoad.defaultTrimpPerAU,
                                               hrMax: hrMax, sex: "male")
        XCTAssertNil(out.strain)
        XCTAssertNil(out.source)
    }

    /// A thin pulse is not a measurement: 12 minutes of watch over a 50-minute session would have
    /// been billed a quarter of its TRIMP as if it were whole (gate estadístico H1). With no rating
    /// it stores nothing rather than a number that is wrong by a band and a half.
    func testThinPulseIsNotMeasured() {
        let thin = pulse(seconds: 12 * 60)
        let out = AppModel.resolveStrengthLoad(hrSamples: thin, elapsedSeconds: 3000, sessionRpe: nil,
                                               trimpPerAU: SessionRPELoad.defaultTrimpPerAU,
                                               hrMax: hrMax, sex: "male")
        XCTAssertNil(out.strain)
        // …and with a rating the same session is estimated from the effort instead.
        let rated = AppModel.resolveStrengthLoad(hrSamples: thin, elapsedSeconds: 3000, sessionRpe: 8,
                                                 trimpPerAU: SessionRPELoad.defaultTrimpPerAU,
                                                 hrMax: hrMax, sex: "male")
        XCTAssertEqual(rated.source, .rpe)
    }

    /// The recovery COST stays cardiovascular: a covered pulse feeds it even when the load was
    /// estimated from effort.
    func testMeasuredStrainSurvivesForTheRecoveryCost() {
        let samples = pulse(seconds: 2700)
        let measured = AppModel.measuredStrain(hrSamples: samples, elapsedSeconds: 3000,
                                               hrMax: hrMax, sex: "male")
        XCTAssertNotNil(measured)
        XCTAssertNil(AppModel.measuredStrain(hrSamples: pulse(seconds: 60), elapsedSeconds: 3000,
                                             hrMax: hrMax, sex: "male"))
    }
}
