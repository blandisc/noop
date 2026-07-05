import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// Tests for the app-facing `NightRhythmAssembler` — the wiring that slices a night's raw
/// R-R + gravity into resting windows and feeds each to the pure `RhythmScreener`. These
/// pin the WIRING (windowing, the motion gate, empty-window handling, the night roll-up),
/// not the classification math itself (that is `RhythmScreenerTests`).
///
/// All fixtures are SYNTHETIC and deterministic (same integer-ms LCG series the engine tests
/// use), so the assembled labels reproduce byte-identically. No real data.
final class NightRhythmAssemblerTests: XCTestCase {

    // MARK: - Deterministic R-R fixtures (mirror RhythmScreenerTests)

    struct LCG {
        var state: UInt32
        init(_ seed: UInt32) { state = seed }
        mutating func nextU32() -> UInt32 { state = state &* 1664525 &+ 1013904223; return state }
        mutating func jitter(_ amp: Int) -> Int { Int(nextU32() % UInt32(2 * amp + 1)) - amp }
    }

    /// Tight, elongated comet → `.steady` (see RhythmScreenerTests.regularSinus).
    static func regularSinus(count: Int = 240) -> [Double] {
        var rng = LCG(1)
        var out: [Double] = []
        let period = 8
        for i in 0..<count {
            let phase = i % period, half = period / 2
            let tri = phase < half ? Double(phase) / Double(half) : Double(period - phase) / Double(half)
            out.append((1000.0 + (tri * 2.0 - 1.0) * 30.0 + Double(rng.jitter(2))).rounded())
        }
        return out
    }

    /// Diffuse round cloud → `.varied`.
    static func afibLike(count: Int = 240) -> [Double] {
        var rng = LCG(7)
        var out: [Double] = []
        for _ in 0..<count { out.append(min(1900.0, max(400.0, 1000.0 + Double(rng.jitter(180)))).rounded()) }
        return out
    }

    // MARK: - Builders: lay a ms series into timestamped rows; still / moving gravity

    /// Lay a ms R-R series end-to-end as `RRInterval` rows starting at `start` (unix s),
    /// advancing the wall clock by each interval — so `count` ~1000 ms beats span ~`count` s.
    func rows(_ rrMs: [Double], start: Int) -> [RRInterval] {
        var out: [RRInterval] = []
        var t = Double(start)
        for v in rrMs {
            out.append(RRInterval(ts: Int(t), rrMs: Int(v.rounded())))
            t += v / 1000.0
        }
        return out
    }

    /// Perfectly still gravity over `[from, to)`: a constant vector → every delta is 0.
    func stillGravity(from: Int, to: Int, step: Int = 30) -> [GravitySample] {
        stride(from: from, to: to, by: step).map { GravitySample(ts: $0, x: 0, y: 0, z: 1.0) }
    }

    /// Moving gravity over `[from, to)`: z toggles by 0.5 g each sample → every delta ≫ the
    /// still threshold, so the window fails the motion gate.
    func movingGravity(from: Int, to: Int, step: Int = 30) -> [GravitySample] {
        Array(stride(from: from, to: to, by: step)).enumerated().map { i, ts in
            GravitySample(ts: ts, x: 0, y: 0, z: i % 2 == 0 ? 1.0 : 1.5)
        }
    }

    // MARK: - Windowing + roll-up

    func testSteadyNightAssemblesReadableSteadyWindows() {
        // Two 5-min windows of steady sinus, both firmly still → both readable, night steady.
        var rr = rows(Self.regularSinus(), start: 0)
        rr += rows(Self.regularSinus(), start: 300)
        let grav = stillGravity(from: 0, to: 600)
        let nr = NightRhythmAssembler.assemble(rr: rr, gravity: grav, from: 0, to: 600)

        XCTAssertEqual(nr.windows.count, 2)
        XCTAssertTrue(nr.windows.allSatisfy { $0.label == .steady })
        XCTAssertEqual(nr.summary.readableWindows, 2)
        XCTAssertEqual(nr.summary.steadyWindows, 2)
        XCTAssertEqual(nr.summary.overall, .steady)
    }

    func testMotionContaminatedWindowReadsUnreadable() {
        // Window 1 still, window 2 moving. Same clean beats in both — only motion differs.
        var rr = rows(Self.regularSinus(), start: 0)
        rr += rows(Self.regularSinus(), start: 300)
        let grav = stillGravity(from: 0, to: 300) + movingGravity(from: 300, to: 600)
        let nr = NightRhythmAssembler.assemble(rr: rr, gravity: grav, from: 0, to: 600)

        XCTAssertEqual(nr.windows.count, 2)
        XCTAssertEqual(nr.windows[0].label, .steady, "still window reads")
        XCTAssertEqual(nr.windows[1].label, .unreadable, "motion gate discards the moving window")
        XCTAssertEqual(nr.summary.readableWindows, 1)
    }

    func testEmptyWindowsAreSkipped() {
        // Beats only in the first window; the second window has none → only one screened window.
        let rr = rows(Self.regularSinus(), start: 0)
        let grav = stillGravity(from: 0, to: 600)
        let nr = NightRhythmAssembler.assemble(rr: rr, gravity: grav, from: 0, to: 600)

        XCTAssertEqual(nr.windows.count, 1, "the empty second window is not a screened result")
        XCTAssertEqual(nr.windows[0].label, .steady)
    }

    func testNoBeatsGivesEmptyReadWithUnreadableSummary() {
        let nr = NightRhythmAssembler.assemble(rr: [], gravity: [], from: 0, to: 600)
        XCTAssertTrue(nr.windows.isEmpty)
        XCTAssertEqual(nr.summary.readableWindows, 0)
        XCTAssertEqual(nr.summary.overall, .unreadable)
    }

    func testDegenerateBoundsGiveEmptyRead() {
        let rr = rows(Self.regularSinus(), start: 0)
        let nr = NightRhythmAssembler.assemble(rr: rr, gravity: stillGravity(from: 0, to: 600),
                                               from: 600, to: 0)
        XCTAssertTrue(nr.windows.isEmpty)
        XCTAssertEqual(nr.summary.overall, .unreadable)
    }

    func testVariedNightRollsUpToVaried() {
        // Three still windows of a diffuse rhythm → meets nightMinVariedWindows → overall varied.
        var rr = rows(Self.afibLike(), start: 0)
        rr += rows(Self.afibLike(), start: 300)
        rr += rows(Self.afibLike(), start: 600)
        let nr = NightRhythmAssembler.assemble(rr: rr, gravity: stillGravity(from: 0, to: 900),
                                               from: 0, to: 900)

        XCTAssertEqual(nr.windows.count, 3)
        XCTAssertTrue(nr.windows.allSatisfy { $0.label == .varied })
        XCTAssertEqual(nr.summary.variedWindows, 3)
        XCTAssertTrue(nr.summary.variationRecurred)
        XCTAssertEqual(nr.summary.overall, .varied)
    }

    // MARK: - Motion gate helper

    func testIsStillTrueForStillGravity() {
        XCTAssertTrue(NightRhythmAssembler.isStill(stillGravity(from: 0, to: 300)))
    }

    func testIsStillFalseForMovingGravity() {
        XCTAssertFalse(NightRhythmAssembler.isStill(movingGravity(from: 0, to: 300)))
    }

    func testIsStillFalseWhenTooFewSamples() {
        XCTAssertFalse(NightRhythmAssembler.isStill([GravitySample(ts: 0, x: 0, y: 0, z: 1)]),
                       "one sample can't confirm stillness → treated as motion")
    }
}
