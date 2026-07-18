import XCTest
@testable import StrandAnalytics
import BiometricStreams

final class HRZonesTests: XCTestCase {

    func testTanakaMaxHR() {
        XCTAssertEqual(HRZones.tanakaMaxHR(age: 30), 187.0, accuracy: 1e-9)
        XCTAssertEqual(HRZones.tanakaMaxHR(age: 40), 180.0, accuracy: 1e-9)
    }

    func testZonesFromAge() {
        let zs = HRZones.zones(age: 30)
        XCTAssertEqual(zs.source, "tanaka")
        XCTAssertEqual(zs.maxHR, 187.0, accuracy: 1e-9)
        XCTAssertEqual(zs.zones.count, 5)
        // Zone 1 lower = 50% of 187 = 93.5; Zone 5 upper = 187.
        XCTAssertEqual(zs.zones[0].lower, 93.5, accuracy: 1e-9)
        XCTAssertEqual(zs.zones[4].upper, 187.0, accuracy: 1e-9)
    }

    func testManualOverride() {
        let zs = HRZones.zones(age: 30, maxHROverride: 200)
        XCTAssertEqual(zs.source, "manual")
        XCTAssertEqual(zs.maxHR, 200.0, accuracy: 1e-9)
        XCTAssertEqual(zs.zones[0].lower, 100.0, accuracy: 1e-9)  // 50% of 200
    }

    func testZonesPartitionContiguously() {
        // Each zone's upper edge must equal the next zone's lower edge (no gaps/overlap).
        let zs = HRZones.zones(maxHR: 200)
        for i in 0..<4 {
            XCTAssertEqual(zs.zones[i].upper, zs.zones[i + 1].lower, accuracy: 1e-9)
        }
    }

    func testZoneNumberForBPM() {
        let zs = HRZones.zones(maxHR: 200)  // edges: 100,120,140,160,180,200
        XCTAssertEqual(zs.zoneNumber(forBPM: 90), 0)    // below zone 1
        XCTAssertEqual(zs.zoneNumber(forBPM: 100), 1)   // zone 1 lower edge
        XCTAssertEqual(zs.zoneNumber(forBPM: 119), 1)
        XCTAssertEqual(zs.zoneNumber(forBPM: 120), 2)
        XCTAssertEqual(zs.zoneNumber(forBPM: 150), 3)
        XCTAssertEqual(zs.zoneNumber(forBPM: 170), 4)
        XCTAssertEqual(zs.zoneNumber(forBPM: 185), 5)
        XCTAssertEqual(zs.zoneNumber(forBPM: 200), 5)   // top edge inclusive
        XCTAssertEqual(zs.zoneNumber(forBPM: 250), 5)   // above max still z5
    }

    func testTimeInZoneAccountsForAllTime() {
        let zs = HRZones.zones(maxHR: 200)  // edges 100/120/140/160/180/200
        // 1 Hz samples: 3 in z1 (110), 2 in z3 (150), 1 below (90).
        let hr = [
            HRSample(ts: 0, bpm: 110),
            HRSample(ts: 1, bpm: 110),
            HRSample(ts: 2, bpm: 110),
            HRSample(ts: 3, bpm: 150),
            HRSample(ts: 4, bpm: 150),
            HRSample(ts: 5, bpm: 90),
        ]
        let tiz = HRZones.timeInZone(hr, zoneSet: zs)
        // Each of the first 5 samples holds 1 s; tail (90 bpm) gets median gap (1 s).
        XCTAssertEqual(tiz.seconds(inZone: 1), 3.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.seconds(inZone: 3), 2.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.belowZone1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.seconds(inZone: 2), 0.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.total, 6.0, accuracy: 1e-9)
    }

    func testTimeInZoneEmpty() {
        let zs = HRZones.zones(maxHR: 200)
        let tiz = HRZones.timeInZone([], zoneSet: zs)
        XCTAssertEqual(tiz.total, 0.0)
    }

    func testTimeInZoneSortsDefensively() {
        let zs = HRZones.zones(maxHR: 200)
        // Out-of-order, evenly-spaced (1 s) input must sort then partition correctly:
        // ts 0,1,2 at 110 bpm (zone 1) → 3 s in zone 1 (each holds 1 s incl. the tail).
        let hr = [
            HRSample(ts: 2, bpm: 110),
            HRSample(ts: 0, bpm: 110),
            HRSample(ts: 1, bpm: 110),
        ]
        let tiz = HRZones.timeInZone(hr, zoneSet: zs)
        XCTAssertEqual(tiz.seconds(inZone: 1), 3.0, accuracy: 1e-9)
        XCTAssertEqual(tiz.total, 3.0, accuracy: 1e-9)  // all time accounted for
    }

    func testMedianIntervalEvenCountAveragesTwoCentral() {
        // Gaps 2,4,6,10 → true median is (4+6)/2 = 5, not the upper-mid 6.
        let hr = [
            HRSample(ts: 0, bpm: 100),
            HRSample(ts: 2, bpm: 100),
            HRSample(ts: 6, bpm: 100),
            HRSample(ts: 12, bpm: 100),
            HRSample(ts: 22, bpm: 100),
        ]
        XCTAssertEqual(HRZones.medianInterval(hr), 5.0, accuracy: 1e-9)
    }

    func testMedianIntervalOddCountTakesCenter() {
        // Gaps 2,4,6 → median 4.
        let hr = [
            HRSample(ts: 0, bpm: 100),
            HRSample(ts: 2, bpm: 100),
            HRSample(ts: 6, bpm: 100),
            HRSample(ts: 12, bpm: 100),
        ]
        XCTAssertEqual(HRZones.medianInterval(hr), 4.0, accuracy: 1e-9)
    }
}
