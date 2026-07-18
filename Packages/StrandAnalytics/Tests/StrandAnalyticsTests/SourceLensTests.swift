import XCTest
@testable import StrandAnalytics
import CenitStore

/// FER-623 / FER-631 / FER-882 — the source lens keeps a baseline pure by source (RMSSD band vs SDNN Apple),
/// the same policy FER-519/FER-543 applied to Recovery and the illness sentinel. RMSSD and SDNN are two
/// time-domain HRV constructs with no published conversion (Task Force 1996, Circulation 93:1043; Shaffer &
/// Ginsberg 2017, Front Public Health 5:258), so Apple SDNN must never enter the band's RMSSD baseline; RHR /
/// resp / sleep stages carry measured band↔Apple offsets too (FER-629); `skinTempDevC` is source-specific as
/// of FER-882 (Apple wrist-temp Δ vs its own baseline). `maskForBaseline` nils every cross-source column.
final class SourceLensTests: XCTestCase {

    private func d(_ i: Int, hrv: Double?, rhr: Int? = 52, resp: Double? = 14,
                   skinTemp: Double? = 0.1) -> DailyMetric {
        DailyMetric(day: String(format: "2024-03-%02d", i), totalSleepMin: 420, efficiency: 0.9,
                    deepMin: 90, remMin: 90, lightMin: 240, disturbances: 2, restingHr: rhr,
                    avgHrv: hrv, recovery: 60, strain: 10, exerciseCount: 1,
                    spo2Pct: 97, skinTempDevC: skinTemp, respRateBpm: resp)
    }

    // MARK: maskHrv — Identity (strap-only user)

    func testBandKeepWithNoAppleDaysIsIdentity() {
        let days = (1...10).map { d($0, hrv: 60) }
        let out = SourceLens.maskHrv(days, keep: .band, appleDays: [])
        XCTAssertEqual(out, days)   // value-equal …
        // … and the engine verdict over it is unchanged from the raw history (the whole point of the fast path).
        XCTAssertEqual(ReadinessEngine.evaluate(days: out, today: "2024-03-10"),
                       ReadinessEngine.evaluate(days: days, today: "2024-03-10"))
    }

    // MARK: maskHrv — keep one source's HRV, nil the other; everything else intact

    func testBandLensNilsAppleHrvButKeepsOtherColumns() {
        let days = (1...6).map { d($0, hrv: 60) }
        let appleDays: Set<String> = ["2024-03-02", "2024-03-05"]
        let out = SourceLens.maskHrv(days, keep: .band, appleDays: appleDays)
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
        let out = SourceLens.maskHrv(days, keep: .apple, appleDays: appleDays)
        for row in out {
            if appleDays.contains(row.day) { XCTAssertEqual(row.avgHrv, 60) }
            else { XCTAssertNil(row.avgHrv) }
        }
    }

    // MARK: maskHrv — Contamination removed (the bug, reproduced and fixed)

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
            days: SourceLens.maskHrv(days, keep: .band, appleDays: appleDays), today: "2024-03-29")

        let zMixed = mixed.signals.first { $0.key == "hrv" }?.z
        let zClean = clean.signals.first { $0.key == "hrv" }?.z
        XCTAssertNotNil(zMixed); XCTAssertNotNil(zClean)
        // The mixed base depresses today's HRV (z notably negative); the clean base reads it at base (~0).
        XCTAssertLessThan(zMixed!, -0.4)
        XCTAssertEqual(zClean!, 0, accuracy: 0.15)
        XCTAssertGreaterThan(zClean!, zMixed!)
    }

    // MARK: maskHrv — Cold-start silence (Apple lens with too few SDNN nights → no invented σ)

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
            days: SourceLens.maskHrv(days, keep: .apple, appleDays: appleDays), today: "2024-03-29")
        XCTAssertNil(r.signals.first { $0.key == "hrv" }, "Too few SDNN nights → engine must stay silent")
    }

    // MARK: maskForBaseline — Identity (I3)

    /// I3: `maskForBaseline(days, keep: .band, appleDays: [])` is the identity for a strap-only user, and the
    /// engine verdict over it is bit-for-bit the raw history's (the fast-path guarantee).
    func testBaselineMaskBandIdentityNoAppleDays() {
        let days = (1...10).map { d($0, hrv: 60, skinTemp: 0.1) }
        let out = SourceLens.maskForBaseline(days, keep: .band, appleDays: [])
        XCTAssertEqual(out, days)
        // FER-882: skinTempDevC survives the identity fast path (strap-only / band-only user).
        XCTAssertEqual(out.map(\.skinTempDevC), days.map(\.skinTempDevC))
        XCTAssertEqual(ReadinessEngine.evaluate(days: out, today: "2024-03-10"),
                       ReadinessEngine.evaluate(days: days, today: "2024-03-10"))
    }

    // MARK: maskForBaseline — nils EXACTLY the cross-source columns, nothing else

    /// keep `.band`: on an Apple row, every cross-source column (`avgHrv`, `restingHr`, `respRateBpm`,
    /// `deepMin`/`remMin`/`lightMin`, `skinTempDevC`) is nil; every other column — including sleep DURATION,
    /// which is comparable across sources unlike the STAGES — survives untouched. Band rows pass through
    /// verbatim.
    func testBaselineMaskNilsCrossSourceColumnsOnly() {
        let days = (1...6).map { d($0, hrv: 60) }
        let appleDays: Set<String> = ["2024-03-02", "2024-03-05"]
        let out = SourceLens.maskForBaseline(days, keep: .band, appleDays: appleDays)
        for row in out {
            if appleDays.contains(row.day) {
                // Cross-source columns nilled.
                XCTAssertNil(row.avgHrv,      "avgHrv must be masked on an Apple night")
                XCTAssertNil(row.restingHr,   "restingHr must be masked on an Apple night")
                XCTAssertNil(row.respRateBpm, "respRateBpm must be masked on an Apple night")
                XCTAssertNil(row.deepMin,     "deepMin (stage) must be masked on an Apple night")
                XCTAssertNil(row.remMin,      "remMin (stage) must be masked on an Apple night")
                XCTAssertNil(row.lightMin,    "lightMin (stage) must be masked on an Apple night")
                XCTAssertNil(row.skinTempDevC, "skinTempDevC must be masked on an Apple night (FER-882)")
                // Comparable / single-source columns survive — DURATION is comparable, stages are not.
                XCTAssertEqual(row.totalSleepMin, 420, "sleep duration is comparable across sources → kept")
                XCTAssertEqual(row.efficiency, 0.9)
                XCTAssertEqual(row.disturbances, 2)
                XCTAssertEqual(row.recovery, 60)
                XCTAssertEqual(row.strain, 10)
                XCTAssertEqual(row.exerciseCount, 1)
                XCTAssertEqual(row.spo2Pct, 97)
            } else {
                XCTAssertEqual(row, d(Int(row.day.suffix(2))!, hrv: 60), "band rows pass through verbatim")
            }
        }
    }

    func testBaselineMaskAppleIsTheComplement() {
        let days = (1...6).map { d($0, hrv: 60) }
        let appleDays: Set<String> = ["2024-03-02", "2024-03-05"]
        let out = SourceLens.maskForBaseline(days, keep: .apple, appleDays: appleDays)
        for row in out {
            if appleDays.contains(row.day) {
                XCTAssertEqual(row, d(Int(row.day.suffix(2))!, hrv: 60), "Apple rows pass through verbatim")
            } else {
                XCTAssertNil(row.avgHrv);      XCTAssertNil(row.restingHr); XCTAssertNil(row.respRateBpm)
                XCTAssertNil(row.deepMin);     XCTAssertNil(row.remMin);    XCTAssertNil(row.lightMin)
                XCTAssertNil(row.skinTempDevC, "skinTempDevC must be masked on a band night under keep:.apple (FER-882)")
            }
        }
    }

    // MARK: maskForBaseline — skinTempDevC isolation (FER-882)

    /// Band and Apple each carry a distinguishable skin-temp Δ; the mask keeps only the kept source's
    /// column so a fold can never mix a band-Δ night with an Apple-Δ night.
    func testBaselineMaskIsolatesSkinTempDevCBySource() {
        let appleDays: Set<String> = ["2024-03-02", "2024-03-05"]
        let days = (1...6).map { i -> DailyMetric in
            let isApple = appleDays.contains(String(format: "2024-03-%02d", i))
            // 9.9 is nowhere near a real Δ — contamination is obvious if the mask fails.
            return d(i, hrv: 60, skinTemp: isApple ? 9.9 : 0.1)
        }
        let bandKeep = SourceLens.maskForBaseline(days, keep: .band, appleDays: appleDays)
        for row in bandKeep {
            if appleDays.contains(row.day) {
                XCTAssertNil(row.skinTempDevC, "keep:.band must nil Apple skinTempDevC")
            } else {
                XCTAssertEqual(row.skinTempDevC, 0.1, "keep:.band must preserve band skinTempDevC")
            }
        }
        let appleKeep = SourceLens.maskForBaseline(days, keep: .apple, appleDays: appleDays)
        for row in appleKeep {
            if appleDays.contains(row.day) {
                XCTAssertEqual(row.skinTempDevC, 9.9, "keep:.apple must preserve Apple skinTempDevC")
            } else {
                XCTAssertNil(row.skinTempDevC, "keep:.apple must nil band skinTempDevC")
            }
        }
    }

    // MARK: maskForBaseline — column mask ≡ whole-row drop (I4)

    /// I4: under the engine's skip-and-hold folds, nilling the cross-source columns of an Apple row is
    /// IDENTICAL to dropping the row entirely (`IntelligenceEngine.strapOnlyHistory`, replicated inline here
    /// because StrandAnalyticsTests can't import Cenit). Fixture is ≤ 30 rows so the row-windowed resp
    /// baseline (`suffix(30)`) sees the same nights either way; past 30 rows the two can diverge benignly
    /// (masking keeps fewer, more recent band nights — both stay band-pure).
    func testBaselineMaskEqualsStrapOnlyRowDrop() {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        for i in 1...24 {                                 // 24 history rows + today = 25 ≤ 30
            let isApple = i % 3 == 0
            let key = String(format: "2024-03-%02d", i)
            if isApple { appleDays.insert(key) }
            // Band nights carry small variance (sd > 0 so resp fires); Apple nights sit at contaminating
            // offsets (SDNN ~75, RHR ~47, resp ~16.3 — within the winsor range, so a raw fold WOULD shift).
            let hrv  = isApple ? 75.0 : 50.0 + Double(i % 3)
            let rhr  = isApple ? 47   : 52 + (i % 3)
            let resp = isApple ? 16.3 : 14.0 + Double(i % 2) * 0.6
            days.append(d(i, hrv: hrv, rhr: rhr, resp: resp))
        }
        days.append(d(25, hrv: 53, rhr: 54, resp: 16.4)) // today: band night, resp elevated → resp fires

        let column  = ReadinessEngine.evaluate(
            days: SourceLens.maskForBaseline(days, keep: .band, appleDays: appleDays), today: "2024-03-25")
        // strapOnlyHistory equivalent: drop the Apple rows wholesale.
        let rowDrop = ReadinessEngine.evaluate(
            days: days.filter { !appleDays.contains($0.day) }, today: "2024-03-25")

        for key in ["hrv", "rhr", "respRate"] {
            let zc = column.signals.first { $0.key == key }?.z
            let zr = rowDrop.signals.first { $0.key == key }?.z
            XCTAssertNotNil(zc, "\(key) signal must be present under the column mask (non-vacuous)")
            XCTAssertNotNil(zr, "\(key) signal must be present under the row drop (non-vacuous)")
            XCTAssertEqual(zc!, zr!, accuracy: 1e-9, "\(key): column mask must equal whole-row drop")
        }
    }

    // MARK: maskForBaseline — band at its own base reads ~0 despite Apple contamination (I1)

    /// I1: with a band night sitting exactly at its own band median, the lens makes HRV **and** RHR read
    /// ≈ 0σ no matter how many Apple rows are in `repo.days`. The raw mixed baseline, by contrast, is pulled
    /// off by the Apple RHR — the clean vs mixed RHR z differ by a measurable margin (contamination removed).
    func testBandAtOwnBaseReadsZeroDespiteContamination() {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        for i in 1...28 {
            let isApple = i % 3 == 0
            let key = String(format: "2024-03-%02d", i)
            if isApple { appleDays.insert(key) }
            days.append(d(i, hrv: isApple ? 75 : 50, rhr: isApple ? 47 : 52, resp: 14))
        }
        days.append(d(29, hrv: 50, rhr: 52, resp: 14))   // today: band night at its own HRV & RHR base

        let mixed = ReadinessEngine.evaluate(days: days, today: "2024-03-29")
        let clean = ReadinessEngine.evaluate(
            days: SourceLens.maskForBaseline(days, keep: .band, appleDays: appleDays), today: "2024-03-29")

        let zHrvClean = clean.signals.first { $0.key == "hrv" }?.z
        let zRhrClean = clean.signals.first { $0.key == "rhr" }?.z
        XCTAssertNotNil(zHrvClean); XCTAssertNotNil(zRhrClean)
        XCTAssertEqual(zHrvClean!, 0, accuracy: 0.15, "band HRV at its own median → z ≈ 0")
        XCTAssertEqual(zRhrClean!, 0, accuracy: 0.15, "band RHR at its own median → z ≈ 0")

        // The raw mixed baseline WAS contaminated by the Apple RHR: cleaning it moves the RHR z measurably.
        let zRhrMixed = mixed.signals.first { $0.key == "rhr" }?.z
        XCTAssertNotNil(zRhrMixed)
        XCTAssertGreaterThan(abs(zRhrClean! - zRhrMixed!), 0.3, "the lens removed measurable RHR contamination")
    }

    // MARK: maskForBaseline agrees with maskHrv on the HRV column (shared row classification)

    /// Both lenses share one row-classification predicate, so they can never disagree about WHICH rows lose
    /// their HRV — only about how many other columns go with it. Pin that: the `avgHrv` column is identical.
    func testBaselineMaskAgreesWithMaskHrvOnHrvColumn() {
        let days = (1...12).map { d($0, hrv: 60) }
        let appleDays: Set<String> = ["2024-03-03", "2024-03-07", "2024-03-11"]
        for keep in [SourceLens.Source.band, .apple] {
            let hrvLens  = SourceLens.maskHrv(days, keep: keep, appleDays: appleDays)
            let baseLens = SourceLens.maskForBaseline(days, keep: keep, appleDays: appleDays)
            XCTAssertEqual(hrvLens.map(\.avgHrv), baseLens.map(\.avgHrv),
                           "the two lenses must nil avgHrv on exactly the same rows (keep: \(keep))")
        }
    }
}
