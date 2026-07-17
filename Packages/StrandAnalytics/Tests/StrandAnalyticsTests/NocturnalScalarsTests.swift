import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// FER-972 (P-05) — the per-night display scalars the nightly pass persists (`night_dc_ms`,
/// `night_warming_c`): the warming math moved verbatim from the app layer into
/// `ThermalStabilityEngine`, and `analyzeDay` harvests both over the night's MAIN session.
final class NocturnalScalarsTests: XCTestCase {

    // MARK: - ThermalStabilityEngine.warmingMagnitudeC (the moved math)

    /// A synthetic ramp: onset plateau at raw 4480 (35.0 °C) for the first 20%, rising to raw 4608
    /// (36.0 °C) from 40% on. Expected = (plateauMean − onsetMean) / 128.
    private func rampSamples(n: Int, offset: Int = 0) -> [SkinTempSample] {
        (0..<n).map { i in
            let raw = i < n * 30 / 100 ? 4480 : 4608
            return SkinTempSample(ts: 1_700_000_000 + i * 60, raw: raw + offset)
        }
    }

    func testWarmingMagnitudeRampMatchesHandComputation() {
        let n = 200
        let samples = rampSamples(n: n)
        // Reproduce the documented windows by hand: onset = first 15%, plateau = 40–90%.
        let onsetHi = max(1, n * 15 / 100)
        let plateauLo = n * 40 / 100
        let plateauHi = max(plateauLo + 1, n * 90 / 100)
        let onset = Double(samples[0..<onsetHi].reduce(0) { $0 + $1.raw }) / Double(onsetHi)
        let plateau = Double(samples[plateauLo..<plateauHi].reduce(0) { $0 + $1.raw })
            / Double(plateauHi - plateauLo)
        let expected = (plateau - onset) / 128.0
        let got = ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: samples)
        XCTAssertNotNil(got)
        XCTAssertEqual(got!, expected, accuracy: 1e-9)
        XCTAssertEqual(got!, 1.0, accuracy: 1e-9, "the 128-raw step is exactly 1 °C on this ramp")
    }

    func testWarmingMagnitudeCancelsAdditiveOffset() {
        // A band calibration is additive on raw — the magnitude (a difference) must not move.
        let a = ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 180))
        let b = ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 180, offset: 3648))
        XCTAssertEqual(a!, b!, accuracy: 1e-9)
    }

    func testWarmingMagnitudeNeedsSixtySamples() {
        XCTAssertNil(ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 59)))
        XCTAssertNotNil(ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: rampSamples(n: 60)))
    }

    // MARK: - analyzeDay harvests both scalars over the main session

    /// The same still, low-HR synthetic night AnalyticsEngineTests uses, plus a warming skin ramp.
    func testAnalyzeDayEmitsNocturnalScalars() {
        let day = "2021-06-15"
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let dayMidnight = Int(fmt.date(from: day)!.timeIntervalSince1970)
        let end = dayMidnight + 6 * 3600
        let start = end - 7 * 3600

        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        for t in start..<end {
            hr.append(HRSample(ts: t, bpm: 50))
            grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
        }
        var rr: [RRInterval] = []
        var toggle = false
        for t in stride(from: start, to: end, by: 2) {
            rr.append(RRInterval(ts: t, rrMs: toggle ? 1205 : 1195))
            toggle.toggle()
        }
        let skins = (0..<((end - start) / 60)).map { i -> SkinTempSample in
            let raw = i < 80 ? 4480 : 4608
            return SkinTempSample(ts: start + i * 60, raw: raw)
        }
        let profile = UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male")

        let result = AnalyticsEngine.analyzeDay(day: day, hr: hr, rr: rr, gravity: grav,
                                                skinTemp: skins, profile: profile)
        XCTAssertEqual(result.sleepSessions.count, 1, "precondition: the night was detected")

        // Warming: exactly the moved function over the session-sliced samples.
        let s = result.sleepSessions[0]
        let inBed = skins.filter { $0.ts >= s.start && $0.ts <= s.end }
        XCTAssertEqual(result.warmingMagnitudeC,
                       ThermalStabilityEngine.warmingMagnitudeC(inBedRaw: inBed))
        XCTAssertNotNil(result.warmingMagnitudeC)

        // DC: exactly NocturnalDC over the session's R-R (readable on this clean night).
        let sessionRR = rr.filter { $0.ts >= s.start && $0.ts <= s.end }.map { Double($0.rrMs) }
        let dc = NocturnalDC.compute(rawRR: sessionRR)
        if dc.confidence == .unreadable {
            XCTAssertNil(result.nocturnalDCms)
        } else {
            XCTAssertEqual(result.nocturnalDCms, dc.dcMs)
        }

        // No session → both nil.
        let empty = AnalyticsEngine.analyzeDay(day: day, profile: profile)
        XCTAssertNil(empty.nocturnalDCms)
        XCTAssertNil(empty.warmingMagnitudeC)
    }
}
