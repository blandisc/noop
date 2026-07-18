import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

/// Pins FER-641: the illness early-warning's resting-HR term must score against a STRAP-ONLY
/// baseline, the same masking FER-543 gave the HRV term. Apple reads resting HR from awake
/// sedentary samples excluding sleep, so it sits a systematic ~10–13 bpm above the band's
/// sleep-nadir RHR (Fenland Study; Gonzales et al. 2023, PLoS One 18(5):e0285272) — mixing it
/// into the baseline biases the z-score, firing or (as shown below) silencing the RHR anomaly.
///
/// These tests mirror `AppModel.evaluateIllness`'s RHR term exactly: base = the 28 nights ending
/// 3 days ago (`suffix(31).dropLast(3)`), fed to `IllnessWatch` after `strapOnlyHistory` masks the
/// Apple-only nights. They exercise the real production helpers (`IntelligenceEngine.strapOnlyHistory`
/// + `IllnessWatch.deviation`), not a re-implementation of the math.
final class IllnessWatchSourceTests: XCTestCase {

    private func dm(_ day: String, rhr: Int?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    /// The illness RHR term's baseline sample, replicated verbatim from `evaluateIllness`.
    private func rhrBase(_ src: [DailyMetric]) -> [Double] {
        Array(src.suffix(31).dropLast(3)).compactMap { $0.restingHr.map(Double.init) }
    }

    /// 33 day-ascending nights: a stable band baseline (~58 bpm, sleep-nadir) with FIVE Apple-only
    /// nights carrying the systematically-higher awake RHR (~72 bpm) sprinkled into the base window.
    /// `appleDays` is the set of those five day-keys, exactly what `repo.appleHealthDays` holds.
    private func history() -> (days: [DailyMetric], appleDays: Set<String>) {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        let bandCycle = [57, 58, 59]
        for i in 0..<33 {
            let day = String(format: "2026-06-%02d", i + 1)
            // Nights 4,9,14,19,24 (inside the base window suffix(31).dropLast(3) = indices 2…29) are Apple.
            if [4, 9, 14, 19, 24].contains(i) {
                days.append(dm(day, rhr: 72))   // Apple: awake sedentary RHR, ~13 bpm high
                appleDays.insert(day)
            } else {
                days.append(dm(day, rhr: bandCycle[i % 3]))
            }
        }
        return (days, appleDays)
    }

    /// Criterion: the Apple night's high RHR is excluded from the strap-only baseline. The full-history
    /// baseline is contaminated (its mean is pulled up and its dispersion inflated); the masked one is not.
    func testAppleNightExcludedFromRhrBaseline() {
        let (days, appleDays) = history()
        let strapDays = IntelligenceEngine.strapOnlyHistory(days, appleHealthDays: appleDays)

        let contaminated = rhrBase(days)
        let cleaned = rhrBase(strapDays)

        XCTAssertTrue(contaminated.contains(72), "full history carries the Apple 72 bpm nights")
        XCTAssertFalse(cleaned.contains(72), "strap-only baseline must exclude the Apple RHR")

        let contaminatedMean = contaminated.reduce(0, +) / Double(contaminated.count)
        let cleanedMean = cleaned.reduce(0, +) / Double(cleaned.count)
        XCTAssertGreaterThan(contaminatedMean, 59, "Apple's high RHR inflates the full-history mean")
        XCTAssertEqual(cleanedMean, 58, accuracy: 0.6, "the strap-only mean stays at the band's sleep-nadir")
    }

    /// Criterion (the concrete harm): a genuinely elevated recent band RHR fires the anomaly against the
    /// clean strap-only baseline, but is SILENCED against the Apple-contaminated one (its inflated mean and
    /// σ swallow the signal). Same recent value, opposite verdict — proving the mask changes the outcome.
    func testContaminatedBaselineSilencesRealRhrAnomaly() {
        let (days, appleDays) = history()
        let strapDays = IntelligenceEngine.strapOnlyHistory(days, appleHealthDays: appleDays)
        let recentBandRhr = 64.0   // a real early-illness RHR rise, +6 over the band baseline

        XCTAssertTrue(
            IllnessWatch.isAnomaly(recentMean: recentBandRhr, base: rhrBase(strapDays), higherIsWorse: true),
            "against the strap-only baseline, +6 bpm is several σ → the RHR anomaly fires (correct)")
        XCTAssertFalse(
            IllnessWatch.isAnomaly(recentMean: recentBandRhr, base: rhrBase(days), higherIsWorse: true),
            "against the Apple-contaminated baseline, the same rise is sub-2σ noise → silenced (the bug)")
    }

    /// FER-884: in Apple-only mode every night is Apple, so `strapOnlyHistory` returns EMPTY — the illness
    /// RHR/HRV terms would have no baseline and could never fire (illness collapses to <2 signals). The fix
    /// routes them through `SourceLens.maskForBaseline(keep: .apple)`, which PRESERVES Apple's own RHR/HRV: a
    /// within-source z-score is valid despite Apple's awake-RHR offset (it compares Apple to the user's own
    /// Apple norm). This pins that a real Apple RHR rise is detectable in Apple-only mode after the fix, and
    /// was undetectable under the old strap-only path.
    func testAppleOnlyModeRoutesRhrThroughAppleLens() {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        let cycle = [71, 72, 73]   // a stable Apple RHR baseline (~72 bpm awake sedentary)
        for i in 0..<33 {
            let day = String(format: "2026-06-%02d", i + 1)
            days.append(dm(day, rhr: cycle[i % 3]))
            appleDays.insert(day)
        }
        // OLD path: strap-only history is empty in Apple-only mode → no baseline → the term can never fire.
        let strapDays = IntelligenceEngine.strapOnlyHistory(days, appleHealthDays: appleDays)
        XCTAssertTrue(strapDays.isEmpty, "Apple-only mode: strap-only history is empty")
        XCTAssertTrue(rhrBase(strapDays).isEmpty, "so the RHR term has no baseline — the gap FER-884 closes")

        // NEW path: the Apple lens preserves Apple's own RHR, so a real +8 bpm rise fires the anomaly.
        let appleLens = SourceLens.maskForBaseline(days, keep: .apple, appleDays: appleDays)
        XCTAssertFalse(rhrBase(appleLens).isEmpty, "the Apple-isolated baseline carries Apple's own RHR")
        XCTAssertTrue(
            IllnessWatch.isAnomaly(recentMean: 80.0, base: rhrBase(appleLens), higherIsWorse: true),
            "against the Apple baseline, +8 bpm is several σ → the RHR anomaly fires in Apple-only mode")
    }
}
