import XCTest
@testable import StrandAnalytics

/// FER-683 — short-scale DFA exponent α1 of the R-R series (EXPERIMENTAL threshold proxy).
///
/// The DFA core (Peng 1994) is validated by its known response to correlation structure: white noise →
/// α ≈ 0.5, an integrated random walk → α ≈ 1.5, a strongly anti-correlated series → α < 0.5. The
/// engine is gated behind an experimental flag AND a strict artifact/beat-count check (Rogers/Gronwald
/// 2021: α1 is very artifact-sensitive; wrist PPG↔ECG equivalence unresolved), and always carries a
/// visible caveat.
final class DFAAlpha1Tests: XCTestCase {

    /// Deterministic LCG in [0,1) — no Math.random, so the suite is reproducible.
    private struct LCG {
        var state: UInt64
        mutating func next() -> Double {
            state = 6364136223846793005 &* state &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    private func whiteNoise(_ n: Int, seed: UInt64 = 88172645) -> [Double] {
        var g = LCG(state: seed)
        return (0..<n).map { _ in g.next() - 0.5 }
    }

    // MARK: - DFA core responds correctly to correlation structure

    func testWhiteNoiseAlphaNearHalf() {
        let a = DFAAlpha1.alpha1(whiteNoise(1024))
        XCTAssertNotNil(a)
        XCTAssertGreaterThan(a!, 0.30)
        XCTAssertLessThan(a!, 0.75)
    }

    func testRandomWalkAlphaNearOnePointFive() {
        // Cumulative sum of white noise = a random walk (strongly correlated) → α ≈ 1.5.
        var running = 0.0
        let walk = whiteNoise(1024).map { running += $0; return running }
        let a = DFAAlpha1.alpha1(walk)
        XCTAssertNotNil(a)
        XCTAssertGreaterThan(a!, 1.2)
        // And unambiguously above the white-noise exponent.
        XCTAssertGreaterThan(a!, DFAAlpha1.alpha1(whiteNoise(1024))!)
    }

    func testAntiCorrelatedAlphaBelowHalf() {
        let alternating = (0..<512).map { $0 % 2 == 0 ? 1.0 : -1.0 }
        let a = DFAAlpha1.alpha1(alternating)
        XCTAssertNotNil(a)
        XCTAssertLessThan(a!, 0.5)
    }

    // MARK: - Gating

    /// Experimental off ⇒ no α1, signal not ok, but the caveat is still present.
    func testGatedOffWhenExperimentalDisabled() {
        let rr = (0..<150).map { _ in 800.0 }
        let r = DFAAlpha1.evaluate(rawRR: rr, experimentalEnabled: false)
        XCTAssertNil(r.alpha1)
        XCTAssertFalse(r.signalOk)
        XCTAssertFalse(r.caveat.isEmpty)
    }

    /// Enabled but too few clean beats ⇒ gated off.
    func testGatedOffWhenTooFewBeats() {
        let rr = (0..<50).map { i in 800.0 + Double(i % 5) }
        let r = DFAAlpha1.evaluate(rawRR: rr, experimentalEnabled: true)
        XCTAssertNil(r.alpha1)
        XCTAssertFalse(r.signalOk)
        XCTAssertLessThan(r.nClean, DFAAlpha1.minCleanBeats)
    }

    /// Enabled with enough beats but a high artifact fraction ⇒ refused, not best-effort.
    func testGatedOffWhenTooManyArtifacts() {
        var rr = whiteNoise(200).map { 800.0 + $0 * 60.0 }   // ~clean base
        // Corrupt ~12% with out-of-range values the cleaner will drop.
        for i in stride(from: 0, to: 200, by: 8) { rr[i] = 5000.0 }
        let r = DFAAlpha1.evaluate(rawRR: rr, experimentalEnabled: true)
        XCTAssertGreaterThan(r.artifactFraction, DFAAlpha1.maxArtifactFraction)
        XCTAssertNil(r.alpha1)
        XCTAssertFalse(r.signalOk)
    }

    /// Enabled, clean, enough beats ⇒ α1 computed, intensity mapped, caveat present.
    func testHappyPathComputesAlphaAndIntensity() {
        let rr = whiteNoise(150).map { 800.0 + $0 * 40.0 }   // in-range, ectopic-clean
        let r = DFAAlpha1.evaluate(rawRR: rr, experimentalEnabled: true)
        XCTAssertTrue(r.signalOk)
        XCTAssertNotNil(r.alpha1)
        XCTAssertNotNil(r.intensity)
        XCTAssertLessThanOrEqual(r.artifactFraction, DFAAlpha1.maxArtifactFraction)
        XCTAssertFalse(r.caveat.isEmpty)
    }

    // MARK: - Intensity mapping

    func testIntensityBands() {
        XCTAssertEqual(DFAAlpha1.intensity(for: 0.95), .easy)
        XCTAssertEqual(DFAAlpha1.intensity(for: 0.75), .aroundAerobic)
        XCTAssertEqual(DFAAlpha1.intensity(for: 0.62), .moderate)
        XCTAssertEqual(DFAAlpha1.intensity(for: 0.50), .aroundAnaerobic)
        XCTAssertEqual(DFAAlpha1.intensity(for: 0.35), .hard)
    }
}
