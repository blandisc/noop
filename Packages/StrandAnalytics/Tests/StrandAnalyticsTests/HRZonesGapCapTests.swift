import XCTest
import WhoopProtocol
@testable import StrandAnalytics

// FER-647 — HRZones.timeInZone must cap each per-sample duration at the median inter-sample
// gap, so a large POSITIVE gap (a strap disconnection recorded as one interval) is NOT credited
// in full to the zone of the sample that precedes it. Before the fix, `timeInZone` substituted
// the median only when the gap was <= 0; a big positive gap inflated the bucket by the whole
// disconnection (the CDO audit measured 3607 s where the robust value is ~4 s).
final class HRZonesGapCapTests: XCTestCase {

    func testMidStreamGapIsCappedAtMedian() {
        let zs = HRZones.zones(maxHR: 200)     // z1 lower edge = 100 bpm
        // Three 1 Hz z1 samples, then a ~1 h disconnection, then one more z1 sample.
        let hr = [
            HRSample(ts: 0, bpm: 110),
            HRSample(ts: 1, bpm: 110),
            HRSample(ts: 2, bpm: 110),
            HRSample(ts: 3606, bpm: 110),      // 3604 s after the previous sample
        ]
        let tiz = HRZones.timeInZone(hr, zoneSet: zs)

        // Median plausible gap = 1 s (the two 1-s gaps; the 3604-s gap is > 300 s so excluded
        // from medianInterval). Each of the 4 samples is now credited at most the median (1 s):
        // 1 + 1 + min(3604, 1) + 1 (tail) = 4 s. The disconnection no longer inflates z1.
        XCTAssertEqual(tiz.seconds(inZone: 1), 4.0, accuracy: 1e-6,
            "A large positive gap must be capped at the median, not credited in full.")
    }

    func testRegularSamplingUnaffected() {
        let zs = HRZones.zones(maxHR: 200)
        // Evenly-spaced 1 Hz samples: capping at the median (1 s) is a no-op.
        let hr = (0..<10).map { HRSample(ts: $0, bpm: 110) }
        let tiz = HRZones.timeInZone(hr, zoneSet: zs)
        XCTAssertEqual(tiz.seconds(inZone: 1), 10.0, accuracy: 1e-6,
            "10 samples × 1 s median each = 10 s; regular sampling is unchanged.")
    }
}
