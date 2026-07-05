import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class HRVFreqDomainTests: XCTestCase {

    /// Build a synthetic R-R series whose instantaneous interval is sinusoidally modulated at `modHz` around
    /// a `baseMs` mean, sampled for `durationSec` seconds. The beat times are the running cumulative sum of
    /// the generated intervals, so the result is a genuine (unevenly sampled) tachogram, exactly what
    /// Lomb-Scargle is meant to handle.
    private func modulatedRR(baseMs: Double, ampMs: Double, modHz: Double, durationSec: Double) -> [Double] {
        var out: [Double] = []
        var t = 0.0
        while t < durationSec {
            let rr = baseMs + ampMs * sin(2.0 * Double.pi * modHz * t)
            out.append(rr)
            t += rr / 1000.0
        }
        return out
    }

    // MARK: - Span gates (Task Force 1996)

    func testAbstainsUnderSixtySecondSpan() {
        // ~40 s of beats: span < minSpanForHFSec(60) → nil entirely (no HF, no LF).
        let rr = modulatedRR(baseMs: 1000, ampMs: 20, modHz: 0.25, durationSec: 40)
        XCTAssertNil(HRVFreqDomain.freqDomain(rawRR: rr))
    }

    func testTooFewBeatsAbstains() {
        // Long span in wall-time can't help if there are simply too few clean beats.
        let rr = Array(repeating: 1000.0, count: HRVFreqDomain.minBeats - 1)
        XCTAssertNil(HRVFreqDomain.freqDomain(rawRR: rr))
    }

    func testShortSpanGivesHFButNilLF() {
        // Between 60 s and 250 s of span: HF present, LF and LF/HF nil.
        let rr = modulatedRR(baseMs: 900, ampMs: 25, modHz: 0.25, durationSec: 120)
        let bands = HRVFreqDomain.freqDomain(rawRR: rr)
        XCTAssertNotNil(bands)
        XCTAssertNil(bands?.lf, "LF must be nil below the 250 s span gate")
        XCTAssertNil(bands?.lfhf, "LF/HF must be nil when LF is nil")
        XCTAssertNotNil(bands?.hf)
        XCTAssertGreaterThan(bands!.hf, 0)
        // On a HF-only window totalPower reports the HF band, not a misleading partial sum.
        XCTAssertEqual(bands!.totalPower, bands!.hf, accuracy: 1e-9)
    }

    func testLongSpanGivesLFAndRatio() {
        // >= 250 s of span → LF present and LF/HF computable.
        let rr = modulatedRR(baseMs: 900, ampMs: 25, modHz: 0.25, durationSec: 300)
        let bands = HRVFreqDomain.freqDomain(rawRR: rr)
        XCTAssertNotNil(bands)
        XCTAssertNotNil(bands?.lf)
        XCTAssertNotNil(bands?.lfhf)
        XCTAssertGreaterThan(bands!.totalPower, bands!.hf, "wide total power must exceed HF alone once LF is in")
    }

    func testTotalPowerEqualsSumOfSubBands() {
        // Acceptance criterion: on a long window totalPower is exactly VLF + LF + HF (the sum of the reported
        // sub-band integrals), never a separate wide integral that could drift below the parts.
        let rr = modulatedRR(baseMs: 900, ampMs: 25, modHz: 0.25, durationSec: 300)
        let bands = HRVFreqDomain.freqDomain(rawRR: rr)!
        XCTAssertNotNil(bands.lf)

        // Re-derive the tachogram the exact way freqDomain does, then integrate each sub-band and sum.
        let clean = HRVAnalyzer.cleanRR(rr)
        var times = [Double](repeating: 0, count: clean.count)
        var acc = 0.0
        for i in 0..<clean.count { times[i] = acc / 1000.0; acc += clean[i] }
        let mean = clean.reduce(0, +) / Double(clean.count)
        let y = clean.map { $0 - mean }
        let vlf = HRVFreqDomain.bandPower(times: times, y: y,
                                          fLow: HRVFreqDomain.vlfLowHz, fHigh: HRVFreqDomain.lfLowHz)
        let lf = HRVFreqDomain.bandPower(times: times, y: y,
                                         fLow: HRVFreqDomain.lfLowHz, fHigh: HRVFreqDomain.lfHighHz)
        let hf = HRVFreqDomain.bandPower(times: times, y: y,
                                         fLow: HRVFreqDomain.hfLowHz, fHigh: HRVFreqDomain.hfHighHz)
        XCTAssertEqual(bands.totalPower, vlf + lf + hf, accuracy: 1e-9,
                       "total power must equal the sum of the VLF + LF + HF sub-band integrals")
        XCTAssertEqual(bands.hf, hf, accuracy: 1e-9)
        XCTAssertEqual(bands.lf!, lf, accuracy: 1e-9)
    }

    // MARK: - Peak lands in the expected band

    func testHFModulationConcentratesPowerInHF() {
        // A 0.25 Hz modulation (squarely inside HF 0.15–0.40) must put far more power in HF than LF.
        let rr = modulatedRR(baseMs: 900, ampMs: 30, modHz: 0.25, durationSec: 300)
        let bands = HRVFreqDomain.freqDomain(rawRR: rr)!
        XCTAssertNotNil(bands.lf)
        XCTAssertGreaterThan(bands.hf, bands.lf! * 3.0, "HF-band modulation must dominate the HF band")
        XCTAssertNotNil(bands.lfhf)
        XCTAssertLessThan(bands.lfhf!, 1.0, "an HF-dominant rhythm has LF/HF < 1")
    }

    func testLFModulationConcentratesPowerInLF() {
        // A 0.10 Hz modulation (inside LF 0.04–0.15) must put far more power in LF than HF.
        let rr = modulatedRR(baseMs: 900, ampMs: 30, modHz: 0.10, durationSec: 300)
        let bands = HRVFreqDomain.freqDomain(rawRR: rr)!
        XCTAssertNotNil(bands.lf)
        XCTAssertGreaterThan(bands.lf!, bands.hf * 3.0, "LF-band modulation must dominate the LF band")
        XCTAssertGreaterThan(bands.lfhf!, 1.0, "an LF-dominant rhythm has LF/HF > 1")
    }

    // MARK: - Additivity guard (does not perturb the time-domain analyzer)

    func testCleanRRSharedWithTimeDomainPath() {
        // The freq-domain estimator must clean with the SAME pipeline; an injected artifact beat is dropped
        // and does not blow up the spectrum. Sanity: a clean modulated series still yields finite bands.
        var rr = modulatedRR(baseMs: 900, ampMs: 25, modHz: 0.25, durationSec: 300)
        rr.insert(50.0, at: rr.count / 2)   // out-of-range artifact, range-filtered away
        let bands = HRVFreqDomain.freqDomain(rawRR: rr)
        XCTAssertNotNil(bands)
        XCTAssertTrue(bands!.hf.isFinite && bands!.hf > 0)
    }
}
