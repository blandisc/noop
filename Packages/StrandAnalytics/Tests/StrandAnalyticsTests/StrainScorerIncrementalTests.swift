import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// FER-870: the incremental `CumulativeStrainState` fold must equal the from-scratch
/// `StrainScorer.cumulativeStrain` / `StrainScorer.strain` over the same samples — at every hour of
/// the day, not just at the end. These tests feed one synthetic series through the state in many
/// different chunkings and assert the curve, the endpoint strain, the gate, and the median all match.
final class StrainScorerIncrementalTests: XCTestCase {

    // Deterministic LCG so bpm varies (exercising every Edwards zone) without test flakiness.
    private struct LCG { var s: UInt64; mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s } }

    /// A day-ish HR series: `n` samples spaced `stepSec` apart from `start`, bpm wandering 55..185.
    private func series(n: Int, stepSec: Int, start: Int = 1_700_000_000, seed: UInt64 = 42) -> [HRSample] {
        var rng = LCG(s: seed)
        var out: [HRSample] = []
        out.reserveCapacity(n)
        var bpm = 70
        for i in 0..<n {
            bpm += Int(rng.next() % 11) - 5          // ±5 wander
            bpm = min(185, max(55, bpm))
            out.append(HRSample(ts: start + i * stepSec, bpm: bpm))
        }
        return out
    }

    /// Fold `samples` through the state in fixed-size `chunk` slices, returning the final state.
    private func foldChunked(_ samples: [HRSample], chunk: Int,
                             _ seed: StrainScorer.CumulativeStrainState) -> StrainScorer.CumulativeStrainState {
        var state = seed
        var i = 0
        while i < samples.count {
            let end = min(i + chunk, samples.count)
            state.extend(with: Array(samples[i..<end]))
            i = end
        }
        return state
    }

    // MARK: - Core equivalence (Edwards — the production path — is bit-exact)

    func testEdwardsCurveEqualsBatchAcrossChunkings() {
        // 1200 dense 1 Hz samples over ~20 min (crosses the 900 s bucket boundary; > minReadings).
        let samples = series(n: 1200, stepSec: 1)
        let batch = StrainScorer.cumulativeStrain(samples, maxHR: 190, restingHR: 60)
        XCTAssertFalse(batch.isEmpty)

        for chunk in [1, 2, 7, 30, 100, 599, 1200, 5000] {
            let seed = StrainScorer.CumulativeStrainState(maxHR: 190, restingHR: 60)
            let state = foldChunked(samples, chunk: chunk, seed)
            XCTAssertEqual(state.curve, batch, "curve diverged at chunk \(chunk)")
            XCTAssertEqual(state.strain, StrainScorer.strain(samples, maxHR: 190, restingHR: 60),
                           "endpoint strain diverged at chunk \(chunk)")
        }
    }

    func testEdwardsSparseStreamEqualsBatch() {
        // 40 samples at 30 s cadence (WHOOP 5/MG live cadence): sparse-but-sustained (> minSpanSeconds).
        let samples = series(n: 40, stepSec: 30, seed: 7)
        let batch = StrainScorer.cumulativeStrain(samples, maxHR: 188, restingHR: 55)
        XCTAssertFalse(batch.isEmpty)
        for chunk in [1, 3, 40] {
            let state = foldChunked(samples, chunk: chunk,
                                    StrainScorer.CumulativeStrainState(maxHR: 188, restingHR: 55))
            XCTAssertEqual(state.curve, batch, "sparse curve diverged at chunk \(chunk)")
        }
    }

    func testEdwardsSurvivesSignalGaps() {
        // Three worn windows separated by long (> 300 s, non-plausible) gaps — the median must ignore
        // the two big gaps, exactly as the batch does, and the curve must still match.
        var samples = series(n: 700, stepSec: 1, start: 1_700_000_000)
        samples += series(n: 700, stepSec: 1, start: 1_700_010_000, seed: 99)   // +~2.7 h gap
        samples += series(n: 700, stepSec: 1, start: 1_700_050_000, seed: 5)    // +~11 h gap
        let batch = StrainScorer.cumulativeStrain(samples, maxHR: 190, restingHR: 60)
        XCTAssertFalse(batch.isEmpty)
        for chunk in [1, 13, 350, 700, 701, 2100] {
            let state = foldChunked(samples, chunk: chunk,
                                    StrainScorer.CumulativeStrainState(maxHR: 190, restingHR: 60))
            XCTAssertEqual(state.curve, batch, "gapped curve diverged at chunk \(chunk)")
            XCTAssertEqual(state.medianIntervalSeconds(), HRZones.medianInterval(samples), accuracy: 1e-9,
                           "median diverged at chunk \(chunk)")
        }
    }

    func testEmptyFlushIsNoOpAndKeepsMonotonicity() {
        let samples = series(n: 800, stepSec: 1)
        var state = StrainScorer.CumulativeStrainState(maxHR: 190, restingHR: 60)
        state.extend(with: samples)
        let before = state
        state.extend(with: [])                       // a flush with no fresh samples
        XCTAssertEqual(state, before)                // byte-identical: nothing moved
        XCTAssertEqual(state.curve, StrainScorer.cumulativeStrain(samples, maxHR: 190, restingHR: 60))
        // Monotonic non-decreasing (strain only accumulates).
        let ys = state.curve.map(\.strain)
        XCTAssertEqual(ys, ys.sorted())
    }

    // MARK: - Gate parity

    func testGateMatchesBatchBelowThreshold() {
        // 19 samples over 60 s: below BOTH the dense (600) and sparse (20/600 s) gates.
        let samples = series(n: 19, stepSec: 3)
        var state = StrainScorer.CumulativeStrainState(maxHR: 190, restingHR: 60)
        state.extend(with: samples)
        XCTAssertFalse(state.hasEnoughData)
        XCTAssertEqual(state.curve, StrainScorer.cumulativeStrain(samples, maxHR: 190, restingHR: 60)) // both []
        XCTAssertEqual(state.strain, StrainScorer.strain(samples, maxHR: 190, restingHR: 60))          // both nil
        XCTAssertNil(state.strain)
    }

    func testInvalidHRRGivesEmptyLikeBatch() {
        let samples = series(n: 800, stepSec: 1)
        var state = StrainScorer.CumulativeStrainState(maxHR: 60, restingHR: 60)   // HRR = 0
        state.extend(with: samples)
        XCTAssertTrue(state.curve.isEmpty)
        XCTAssertNil(state.strain)
        XCTAssertEqual(state.curve, StrainScorer.cumulativeStrain(samples, maxHR: 60, restingHR: 60))
    }

    // MARK: - Banister (sampleDur factored out ⇒ FP-associativity differs; equal after 2 dp rounding)

    func testBanisterEndpointMatchesBatch() {
        let samples = series(n: 1500, stepSec: 1, seed: 3)
        let state = foldChunked(samples, chunk: 37,
                                StrainScorer.CumulativeStrainState(maxHR: 190, restingHR: 60,
                                                                   method: .banister, sex: "female"))
        let batch = StrainScorer.cumulativeStrain(samples, maxHR: 190, restingHR: 60,
                                                  method: .banister, sex: "female")
        XCTAssertEqual(state.curve.count, batch.count)
        for (a, b) in zip(state.curve, batch) {
            XCTAssertEqual(a.date, b.date)
            XCTAssertEqual(a.strain, b.strain, accuracy: 0.01)   // 2 dp — the value the chart shows
        }
    }

    // MARK: - Median histogram exactness

    func testMedianHistogramMatchesHRZonesEvenAndOdd() {
        // Even gap count.
        let even = [HRSample(ts: 0, bpm: 80), HRSample(ts: 2, bpm: 80),
                    HRSample(ts: 6, bpm: 80), HRSample(ts: 16, bpm: 80)]  // gaps 2,4,10 → wait: 3 gaps (odd)
        var s1 = StrainScorer.CumulativeStrainState(maxHR: 190, restingHR: 60)
        s1.extend(with: even)
        XCTAssertEqual(s1.medianIntervalSeconds(), HRZones.medianInterval(even), accuracy: 1e-9)

        // Explicit even-count set: gaps 2,4,6,10 → median (4+6)/2 = 5.
        let evenGaps = [HRSample(ts: 0, bpm: 80), HRSample(ts: 2, bpm: 80), HRSample(ts: 6, bpm: 80),
                        HRSample(ts: 12, bpm: 80), HRSample(ts: 22, bpm: 80)]
        var s2 = StrainScorer.CumulativeStrainState(maxHR: 190, restingHR: 60)
        s2.extend(with: evenGaps)
        XCTAssertEqual(s2.medianIntervalSeconds(), 5.0, accuracy: 1e-9)
        XCTAssertEqual(s2.medianIntervalSeconds(), HRZones.medianInterval(evenGaps), accuracy: 1e-9)
    }
}
