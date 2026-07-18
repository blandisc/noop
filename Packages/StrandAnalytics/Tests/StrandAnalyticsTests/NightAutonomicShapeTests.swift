import XCTest
import BiometricStreams
@testable import StrandAnalytics

// FER-678 — the shape of the nocturnal HR fall: dip%, nadir hour, % of night below RHR.
// Synthetic nights exercise the nadir search, the dip math, the clock-time conversion, the
// coverage/confidence gates, and the honest es-MX copy (a pattern, never a diagnosis).
final class NightAutonomicShapeTests: XCTestCase {

    /// Build a night of 1-Hz-ish HR samples: a V-shaped fall from `startBpm` down to `nadirBpm`
    /// at the midpoint and back up, over `hours`, starting at wall-clock `start`. Every `stepSec`.
    private func vNight(start: Int, hours: Double, startBpm: Int, nadirBpm: Int,
                        stepSec: Int = 30) -> [HRSample] {
        let total = Int(hours * 3600)
        let mid = total / 2
        var out: [HRSample] = []
        var t = 0
        while t <= total {
            let frac: Double = t <= mid ? Double(t) / Double(mid) : Double(total - t) / Double(total - mid)
            let bpm = Double(startBpm) - Double(startBpm - nadirBpm) * frac
            out.append(HRSample(ts: start + t, bpm: Int(bpm.rounded())))
            t += stepSec
        }
        return out
    }

    func testDipAndNadirTimingBasic() {
        // Night from 22:00 local; use UTC (offset 0) so ts hour == local hour.
        // Start 00:00 UTC to keep arithmetic clean: nadir at midpoint.
        let start = 0                       // 1970-01-01 00:00 UTC
        let hr = vNight(start: start, hours: 8, startBpm: 70, nadirBpm: 48)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 8 * 3600)]
        let r = NightAutonomicShape.compute(hr: hr, asleep: asleep,
                                            wakingReferenceHR: 70, rhrBaseline: 60,
                                            tzOffsetSeconds: 0)
        let res = try! XCTUnwrap(r)
        XCTAssertEqual(res.confidence, .solid)
        // Nadir ≈ 48 bpm (5-min mean around the valley), so dip ≈ (70-48)/70 ≈ 31%.
        XCTAssertEqual(res.nadirBpm, 48, accuracy: 2.0)
        XCTAssertGreaterThan(res.dipPct, 25)
        XCTAssertEqual(res.dipShape, .pronounced)
        // Nadir at the midpoint = 4 h after 00:00 → ~4:00 local.
        XCTAssertEqual(res.nadirHour, 4.0, accuracy: 0.25)
    }

    func testBluntedDipDescriptor() {
        let start = 0
        // Falls only from 62 → 58: dip ≈ (62-58)/62 ≈ 6.5% < 10% ⇒ blunted.
        let hr = vNight(start: start, hours: 7, startBpm: 62, nadirBpm: 58)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 7 * 3600)]
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 62, rhrBaseline: 60, tzOffsetSeconds: 0))
        XCTAssertLessThan(res.dipPct, NightAutonomicShape.bluntedDipPct)
        XCTAssertEqual(res.dipShape, .blunted)
        XCTAssertTrue(res.note.contains("poco marcado"))
    }

    func testFractionBelowRHR() {
        let start = 0
        let hr = vNight(start: start, hours: 8, startBpm: 70, nadirBpm: 48)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 8 * 3600)]
        // With RHR = 55, roughly the deeper part of the V is below it — expect a meaningful fraction.
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 70, rhrBaseline: 55, tzOffsetSeconds: 0))
        XCTAssertGreaterThan(res.fractionBelowRHR, 0.2)
        XCTAssertLessThan(res.fractionBelowRHR, 0.8)
        XCTAssertTrue(res.note.contains("por debajo de tu ritmo en reposo"))
    }

    func testLocalHourUsesTZOffset() {
        // Nadir wall-clock ts at 04:00 UTC; with a −6 h offset the LOCAL nadir is 22:00.
        let start = 0
        let hr = vNight(start: start, hours: 8, startBpm: 70, nadirBpm: 50)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 8 * 3600)]
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 70, rhrBaseline: 60, tzOffsetSeconds: -6 * 3600))
        XCTAssertEqual(res.nadirHour, 22.0, accuracy: 0.25)
    }

    func testNightTooShortIsUnreadable() {
        let start = 0
        let hr = vNight(start: start, hours: 2, startBpm: 70, nadirBpm: 50)   // < 3 h
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 2 * 3600)]
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 70, rhrBaseline: 60, tzOffsetSeconds: 0))
        XCTAssertEqual(res.confidence, .unreadable)
    }

    func testGappyCoverageIsUnreadable() {
        // A full 8-h span but samples only in the first ~1.5 h → coverage < 0.35 → unreadable.
        let start = 0
        let hr = vNight(start: start, hours: 1.5, startBpm: 70, nadirBpm: 55)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 8 * 3600)]
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 70, rhrBaseline: 60, tzOffsetSeconds: 0))
        XCTAssertEqual(res.confidence, .unreadable)
    }

    func testNoWakingReferenceWithholdsShape() {
        let start = 0
        let hr = vNight(start: start, hours: 8, startBpm: 70, nadirBpm: 50)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 8 * 3600)]
        XCTAssertNil(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: nil, rhrBaseline: 60, tzOffsetSeconds: 0))
        XCTAssertNil(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 0, rhrBaseline: 60, tzOffsetSeconds: 0))
    }

    func testDipClampedAtZeroWhenNoFall() {
        // Waking reference BELOW the nadir → raw dip negative → clamped to 0, shape blunted.
        let start = 0
        let hr = vNight(start: start, hours: 7, startBpm: 60, nadirBpm: 58)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 7 * 3600)]
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 50, rhrBaseline: 55, tzOffsetSeconds: 0))
        XCTAssertEqual(res.dipPct, 0, accuracy: 0.001)
        XCTAssertEqual(res.dipShape, .blunted)
    }

    func testNoRHRBaselineOmitsThatClauseFromNote() {
        let start = 0
        let hr = vNight(start: start, hours: 8, startBpm: 70, nadirBpm: 48)
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 8 * 3600)]
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 70, rhrBaseline: nil, tzOffsetSeconds: 0))
        XCTAssertEqual(res.fractionBelowRHR, 0)
        XCTAssertFalse(res.note.contains("por debajo"))
    }

    func testEmptyAsleepReturnsNil() {
        XCTAssertNil(NightAutonomicShape.compute(
            hr: [], asleep: [], wakingReferenceHR: 70, rhrBaseline: 60, tzOffsetSeconds: 0))
    }

    func testSamplesOutsideAsleepSpanExcluded() {
        // A wake-time spike of very low HR OUTSIDE the asleep span must not become the nadir.
        let start = 100_000
        var hr = vNight(start: start, hours: 8, startBpm: 70, nadirBpm: 52)
        // Add a bogus 30-bpm reading well before the asleep span (should be ignored).
        hr.append(HRSample(ts: start - 3600, bpm: 30))
        let asleep = [NightAutonomicShape.AsleepSpan(start: start, end: start + 8 * 3600)]
        let res = try! XCTUnwrap(NightAutonomicShape.compute(
            hr: hr, asleep: asleep, wakingReferenceHR: 70, rhrBaseline: 60, tzOffsetSeconds: 0))
        XCTAssertGreaterThan(res.nadirBpm, 45)   // ~52, not the excluded 30
    }
}
