import XCTest
import WhoopStore
import WhoopProtocol
import StrandAnalytics
@testable import Cenit

/// Pins the pure decisions of `NightRhythmProvider` (FER-666): picking last night's MAIN sleep
/// (excluding naps) and resolving the coarse read state (needs-band / no-sleep / a reading) from
/// already-fetched inputs. The async `load(from:)` glue is not unit-tested; its logic lives here.
final class NightRhythmProviderTests: XCTestCase {

    private func session(_ start: Int, minutes: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: start + minutes * 60,
                           efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
    }

    /// A handful of ~1000 ms beats laid end-to-end from `start` (enough to fill one window).
    private func rr(from start: Int, count: Int = 120) -> [RRInterval] {
        (0..<count).map { RRInterval(ts: start + $0, rrMs: 1000) }
    }

    // MARK: - lastNight

    func testLastNightPicksMostRecentMainNight() {
        let older = session(1_000_000, minutes: 420)   // 7 h
        let newer = session(1_100_000, minutes: 400)    // 6.7 h, later
        XCTAssertEqual(NightRhythmProvider.lastNight([older, newer])?.startTs, newer.startTs)
    }

    func testLastNightExcludesNaps() {
        let nap = session(1_200_000, minutes: 90)        // 1.5 h — below the main-night floor
        let night = session(1_000_000, minutes: 420)     // 7 h, earlier but a real night
        XCTAssertEqual(NightRhythmProvider.lastNight([nap, night])?.startTs, night.startTs,
                       "a later nap must not out-rank an earlier main night")
    }

    func testLastNightNilWhenOnlyNaps() {
        XCTAssertNil(NightRhythmProvider.lastNight([session(1_200_000, minutes: 90)]))
        XCTAssertNil(NightRhythmProvider.lastNight([]))
    }

    // MARK: - read

    func testReadNeedsBandWhenNotWhoop() {
        let r = NightRhythmProvider.read(usesWhoop: false, night: session(0, minutes: 420),
                                         rr: rr(from: 0), gravity: [])
        XCTAssertEqual(r, .needsBand)
    }

    func testReadNoSleepWhenNightNil() {
        let r = NightRhythmProvider.read(usesWhoop: true, night: nil, rr: rr(from: 0), gravity: [])
        XCTAssertEqual(r, .noSleepLastNight)
    }

    func testReadNoSleepWhenNightHasNoBeats() {
        let r = NightRhythmProvider.read(usesWhoop: true, night: session(0, minutes: 420),
                                         rr: [], gravity: [])
        XCTAssertEqual(r, .noSleepLastNight)
    }

    func testReadReturnsReadingWhenBeatsPresent() {
        let night = session(0, minutes: 420)
        let r = NightRhythmProvider.read(usesWhoop: true, night: night,
                                         rr: rr(from: night.startTs), gravity: [])
        guard case let .reading(nr) = r else { return XCTFail("expected a reading") }
        XCTAssertFalse(nr.windows.isEmpty)
        XCTAssertEqual(nr.from, night.startTs)
        XCTAssertEqual(nr.to, night.endTs)
    }
}
