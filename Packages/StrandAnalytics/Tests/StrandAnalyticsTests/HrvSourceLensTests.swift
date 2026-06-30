import XCTest
@testable import StrandAnalytics
import WhoopStore

/// FER-623 — the HRV source lens keeps a baseline pure by source (RMSSD band vs SDNN Apple), the same
/// policy FER-519/FER-543 applied to Recovery and the illness sentinel. RMSSD and SDNN are two time-domain
/// HRV constructs with no published conversion (Task Force 1996, Circulation 93:1043; Shaffer & Ginsberg
/// 2017, Front Public Health 5:258), so Apple SDNN must never enter the band's RMSSD baseline.
final class HrvSourceLensTests: XCTestCase {

    private func d(_ i: Int, hrv: Double?, rhr: Int? = 52, resp: Double? = 14) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: 420, efficiency: 0.9,
                    deepMin: 90, remMin: 90, lightMin: 240, disturbances: 2, restingHr: rhr,
                    avgHrv: hrv, recovery: 60, strain: 10, exerciseCount: 1,
                    spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: resp)
    }

    // MARK: Identity (strap-only user)

    func testBandKeepWithNoAppleDaysIsIdentity() {
        let days = (1...10).map { d($0, hrv: 60) }
        let out = HrvSourceLens.mask(days, keep: .band, appleDays: [])
        XCTAssertEqual(out, days)   // value-equal …
        // … and the engine verdict over it is unchanged from the raw history (the whole point of the fast path).
        XCTAssertEqual(ReadinessEngine.evaluate(days: out, today: "2024-03-10"),
                       ReadinessEngine.evaluate(days: days, today: "2024-03-10"))
    }

    // MARK: Mask by source — keep one source's HRV, nil the other; everything else intact

    func testBandLensNilsAppleHrvButKeepsOtherColumns() {
        let days = (1...6).map { d($0, hrv: 60) }
        let appleDays: Set<String> = ["2024-03-02", "2024-03-05"]
        let out = HrvSourceLens.mask(days, keep: .band, appleDays: appleDays)
        for row in out {
            if appleDays.contains(row.day) {
                XCTAssertNil(row.avgHrv, "Apple night's HRV must be masked out of the band lens")
            } else {
                XCTAssertEqual(row.avgHrv, 60)
            }
            // Skip-and-hold: a masked night is a "missing HRV" row, NOT a wiped row — RHR/resp/sleep survive.
            XCTAssertEqual(row.restingHr, 52)
            XCTAssertEqual(row.respRateBpm, 14)
            XCTAssertEqual(row.totalSleepMin, 420)
        }
    }

    func testAppleLensIsTheComplement() {
        let days = (1...6).map { d($0, hrv: 60) }
        let appleDays: Set<String> = ["2024-03-02", "2024-03-05"]
        let out = HrvSourceLens.mask(days, keep: .apple, appleDays: appleDays)
        for row in out {
            if appleDays.contains(row.day) { XCTAssertEqual(row.avgHrv, 60) }
            else { XCTAssertNil(row.avgHrv) }
        }
    }

    // MARK: Contamination removed — the bug, reproduced and fixed

    /// With Apple SDNN nights (~1.5× the band's RMSSD) interleaved, the MIXED baseline is pulled up, so
    /// today's band HRV reads further below "its base" than it truly is. The band lens removes those nights
    /// and the z-score lands near zero (today == its own RMSSD base). This is the owner-DB symptom.
    func testBandLensRemovesSdnnContaminationFromVerdictZ() {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        for i in 1...28 {
            let isApple = i % 3 == 0                     // ~1/3 of nights are Apple SDNN
            let key = String(format: "2024-03-%02d", i)
            if isApple { appleDays.insert(key) }
            days.append(d(i, hrv: isApple ? 75 : 50))    // SDNN ~75 ms, RMSSD ~50 ms
        }
        days.append(d(29, hrv: 50))                      // today: a band night exactly at its RMSSD base

        let mixed = ReadinessEngine.evaluate(days: days, today: "2024-03-29")
        let clean = ReadinessEngine.evaluate(
            days: HrvSourceLens.mask(days, keep: .band, appleDays: appleDays), today: "2024-03-29")

        let zMixed = mixed.signals.first { $0.key == "hrv" }?.z
        let zClean = clean.signals.first { $0.key == "hrv" }?.z
        XCTAssertNotNil(zMixed); XCTAssertNotNil(zClean)
        // The mixed base depresses today's HRV (z notably negative); the clean base reads it at base (~0).
        XCTAssertLessThan(zMixed!, -0.4)
        XCTAssertEqual(zClean!, 0, accuracy: 0.15)
        XCTAssertGreaterThan(zClean!, zMixed!)
    }

    // MARK: Cold-start silence — the Apple lens has too few SDNN nights → no HRV signal (no invented σ)

    func testAppleLensColdStartEmitsNoHrvSignal() {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        // Only 3 Apple nights (< minBaseline 7) scattered in a band history.
        for i in 1...28 {
            let isApple = [5, 12, 20].contains(i)
            let key = String(format: "2024-03-%02d", i)
            if isApple { appleDays.insert(key) }
            days.append(d(i, hrv: isApple ? 70 : 55))
        }
        days.append(d(29, hrv: 70))                      // today an Apple night
        appleDays.insert("2024-03-29")
        let r = ReadinessEngine.evaluate(
            days: HrvSourceLens.mask(days, keep: .apple, appleDays: appleDays), today: "2024-03-29")
        XCTAssertNil(r.signals.first { $0.key == "hrv" }, "Too few SDNN nights → engine must stay silent")
    }
}
