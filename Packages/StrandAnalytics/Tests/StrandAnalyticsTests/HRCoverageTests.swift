import XCTest
import BiometricStreams
@testable import StrandAnalytics

/// Ola 1 · E2 / gate estadístico H1: «measured» is time WITH pulse, not «the stream cleared an
/// absolute floor». Anchors from the gate: a 50-minute session with 12 minutes of watch is NOT
/// measured (it would have been billed a quarter of its TRIMP as if it were whole); with 41 minutes
/// it is.
final class HRCoverageTests: XCTestCase {

    private func samples(seconds: Int, from start: Int = 0, bpm: Int = 130) -> [HRSample] {
        (0...seconds).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    func testCoverageIsPlausibleIntervalTime() {
        let elapsed = 50 * 60                       // 3000 s
        let thin = samples(seconds: 12 * 60)        // 720 s of pulse
        XCTAssertEqual(HRCoverage.fraction(thin, elapsedSeconds: elapsed), 0.24, accuracy: 0.001)
        XCTAssertFalse(HRCoverage.isMeasured(thin, elapsedSeconds: elapsed))

        let dense = samples(seconds: 41 * 60)       // 2460 s of pulse
        XCTAssertEqual(HRCoverage.fraction(dense, elapsedSeconds: elapsed), 0.82, accuracy: 0.001)
        XCTAssertTrue(HRCoverage.isMeasured(dense, elapsedSeconds: elapsed))
    }

    /// A gap longer than `maxPlausibleGapS` is a hole: the two covered blocks count, the hole does not.
    func testLongGapIsNotCoveredTime() {
        let a = samples(seconds: 600, from: 0)
        let b = samples(seconds: 600, from: 2000)   // 1400 s hole between the blocks
        XCTAssertEqual(HRCoverage.fraction(a + b, elapsedSeconds: 3000),
                       1200.0 / 3000.0, accuracy: 0.001)
    }

    /// Both gates, never one: a dense-but-short stream can clear coverage and still fail
    /// `hasEnoughData`, and a long thin one clears `hasEnoughData` and fails coverage.
    func testCoverageAloneIsNotEnoughData() {
        let short = samples(seconds: 120)           // 121 samples, 100 % of a 2-minute session
        XCTAssertEqual(HRCoverage.fraction(short, elapsedSeconds: 120), 1.0, accuracy: 0.001)
        XCTAssertFalse(HRCoverage.isMeasured(short, elapsedSeconds: 120))
    }

    func testDegenerateInputsAreZero() {
        XCTAssertEqual(HRCoverage.fraction([], elapsedSeconds: 3000), 0)
        XCTAssertEqual(HRCoverage.fraction(samples(seconds: 600), elapsedSeconds: 0), 0)
    }
}
