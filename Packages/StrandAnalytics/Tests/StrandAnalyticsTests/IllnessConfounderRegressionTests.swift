import XCTest
@testable import StrandAnalytics

/// FER-667 regression: the same hangover / sauna night that the old blunt 2-of-4 `IllnessWatch`
/// rule would have fired on (≥ 2 univariate anomalies at ≥ 2σ, no cross-checks) is now SUPPRESSED
/// by `IllnessSignalEngine` because a confounder logged the same day explains it — fewer false
/// positives, which is the whole point of the port.
///
/// Each test builds a realistic baseline sample + a recent value that trips two independent signals
/// past the 2σ firing line (so the retired rule WOULD fire), then shows the engine reads the same
/// z-scores but downgrades to `.suppressed` once the journal tag is present.
final class IllnessConfounderRegressionTests: XCTestCase {

    private let labels = [
        "restingHR": "resting HR +6 bpm",
        "skinTemp": "skin temp +0.7 °C",
        "hrv": "HRV −22%",
    ]

    /// A stable baseline (small dispersion) and a recent value pushed `sigmas` past the mean in the
    /// concerning direction, returning both the sample and the illness-ward z the engine would see.
    private func spike(base: [Double], recent: Double, higherIsWorse: Bool)
    -> (firesOldRule: Bool, z: Double) {
        let dev = IllnessWatch.deviation(recentMean: recent, base: base, higherIsWorse: higherIsWorse)!
        return (dev.z >= IllnessWatch.zThreshold, dev.z)
    }

    func testHangoverNightThatOldRuleWouldFireIsSuppressed() {
        // RHR baseline ~58 bpm, recent 66 → several σ up. HRV baseline ~65 ms, recent 45 → σ down.
        let rhr = spike(base: [57, 58, 59, 58, 57, 58, 59, 58], recent: 66, higherIsWorse: true)
        let hrv = spike(base: [64, 65, 66, 65, 64, 66, 65, 64], recent: 45, higherIsWorse: false)

        // The retired IllnessWatch behaviour: ≥ 2 univariate anomalies ⇒ banner. Both fire here.
        XCTAssertTrue(rhr.firesOldRule)
        XCTAssertTrue(hrv.firesOldRule)
        let oldRuleWouldFire = [rhr.firesOldRule, hrv.firesOldRule].filter { $0 }.count >= 2
        XCTAssertTrue(oldRuleWouldFire, "the old 2-of-4 rule fires on this hangover night")

        let inputs = IllnessSignalEngine.Inputs(
            restingHR: .init(zIllnessward: rhr.z),
            hrv: .init(zIllnessward: hrv.z))

        // No tag: the engine agrees it looks strained (raised) — the signals ARE real.
        let untagged = IllnessSignalEngine.evaluate(inputs, context: .init(), firedLabels: labels)
        XCTAssertEqual(untagged.level, .raised)

        // Same night, alcohol logged: engine suppresses. No banner, score damped ×0.45.
        let tagged = IllnessSignalEngine.evaluate(
            inputs, context: .init(alcohol: true), firedLabels: labels)
        XCTAssertEqual(tagged.level, .suppressed)
        XCTAssertEqual(tagged.suppressedBy, ["alcohol"])
        XCTAssertLessThan(tagged.score, untagged.score)
    }

    func testSaunaNightIsSuppressed() {
        // Sauna elevates skin temp + RHR the same evening — exactly the illness look.
        let rhr = spike(base: [57, 58, 59, 58, 57, 58, 59, 58], recent: 65, higherIsWorse: true)
        let temp = spike(base: [-0.1, 0.0, 0.1, 0.0, -0.1, 0.1, 0.0, -0.1], recent: 0.8, higherIsWorse: true)
        XCTAssertTrue(rhr.firesOldRule && temp.firesOldRule)

        let inputs = IllnessSignalEngine.Inputs(
            restingHR: .init(zIllnessward: rhr.z),
            skinTemp: .init(zIllnessward: temp.z))
        let tagged = IllnessSignalEngine.evaluate(
            inputs, context: .init(sauna: true), firedLabels: labels)
        XCTAssertEqual(tagged.level, .suppressed)
        XCTAssertEqual(tagged.suppressedBy, ["sauna"])
    }

    func testHardWorkoutNightIsSuppressed() {
        // A hard/late session raises RHR and drops HRV overnight; wired via `hardOrLateWorkout`.
        let rhr = spike(base: [57, 58, 59, 58, 57, 58, 59, 58], recent: 66, higherIsWorse: true)
        let hrv = spike(base: [64, 65, 66, 65, 64, 66, 65, 64], recent: 44, higherIsWorse: false)
        let inputs = IllnessSignalEngine.Inputs(
            restingHR: .init(zIllnessward: rhr.z),
            hrv: .init(zIllnessward: hrv.z))
        let tagged = IllnessSignalEngine.evaluate(
            inputs, context: .init(hardOrLateWorkout: true), firedLabels: labels)
        XCTAssertEqual(tagged.level, .suppressed)
        XCTAssertEqual(tagged.suppressedBy, ["a hard or late workout"])
    }
}
