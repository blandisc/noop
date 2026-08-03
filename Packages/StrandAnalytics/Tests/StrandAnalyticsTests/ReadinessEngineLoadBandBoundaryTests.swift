import XCTest
@testable import StrandAnalytics

/// FER-33 — the ACWR band cuts, pinned.
///
/// The load sheet is about to repeat these three numbers as a visible ladder of levels, and the
/// verdict, «Tus patrones» and the Tendencias card already share the same words for them. Until now
/// nothing failed if a cut moved: there was no boundary test and no pin on the constants, so a
/// one-character edit could silently re-label every one of those surfaces. This closes that hole.
///
/// Method note: `loadBand` is a half-open ladder — a value exactly ON a cut belongs to the band
/// ABOVE it. These tests state that explicitly, because "0.8 is balance, not easing off" is the kind
/// of edge a refactor flips without noticing.
final class ReadinessEngineLoadBandBoundaryTests: XCTestCase {

    // MARK: The constants themselves

    func testCutsArePinned() {
        XCTAssertEqual(ReadinessEngine.acwrSweetSpotLow, 0.8, accuracy: 1e-9)
        XCTAssertEqual(ReadinessEngine.acwrSweetSpotHigh, 1.3, accuracy: 1e-9)
        XCTAssertEqual(ReadinessEngine.acwrSpikeAt, 1.5, accuracy: 1e-9)
    }

    // MARK: Each side of each cut

    func testBelowSweetSpotLowIsRampingDown() {
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 0.0), .rampingDown)
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 0.79), .rampingDown)
    }

    func testExactlySweetSpotLowIsSweetSpot() {
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 0.8), .sweetSpot,
                       "the low cut belongs to balance, not to easing off")
    }

    func testInsideSweetSpot() {
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 1.0), .sweetSpot)
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 1.29), .sweetSpot)
    }

    func testExactlySweetSpotHighIsBuildingFast() {
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 1.3), .buildingFast,
                       "the high cut leaves balance and enters ramping up")
    }

    func testInsideBuildingFast() {
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 1.49), .buildingFast)
    }

    func testExactlySpikeAtIsSpiking() {
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 1.5), .spiking,
                       "the spike cut belongs to the top band")
    }

    func testAboveSpike() {
        XCTAssertEqual(ReadinessEngine.loadBand(forACWR: 2.4), .spiking)
    }

    // MARK: The ladder is total and ordered

    func testLadderIsMonotonicAcrossTheScale() {
        // Walking the scale upward must never step DOWN a band: a non-monotonic ladder would make
        // the sheet's levels and the chart's bands disagree at some point in the middle.
        let order: [ReadinessEngine.LoadBand: Int] = [.rampingDown: 0, .sweetSpot: 1,
                                                      .buildingFast: 2, .spiking: 3]
        var previous = -1
        for step in 0...240 {
            let ratio = Double(step) / 100.0            // 0.00 … 2.40
            let rank = order[ReadinessEngine.loadBand(forACWR: ratio)] ?? -1
            XCTAssertGreaterThanOrEqual(rank, previous, "band went backwards at ratio \(ratio)")
            previous = rank
        }
        XCTAssertEqual(previous, 3, "the top of the scale must land in the top band")
    }
}
