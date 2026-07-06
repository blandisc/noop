import XCTest
import WhoopStore
import StrandAnalytics

/// Pins FER-224: `DailyStressModel` must anchor "today" to the device's LOCAL day and ignore a
/// future-dated daily row (the UTC-bucketed ghost row of FER-226) — otherwise `days.last` reads that
/// empty row and the tile falls to "—" even when today has RHR/HRV. It must also derive from whatever
/// the layered `displayDays` provides (Apple-health fallback) on a strap-partial night.
final class DailyStressModelTests: XCTestCase {

    private func dm(_ day: String, rhr: Int? = nil, hrv: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    /// 10 past days with a little spread so the baseline mean/SD are well-defined.
    private func baseline() -> [DailyMetric] {
        (1...10).map { i in dm(String(format: "2026-06-%02d", i), rhr: 58 + i % 4, hrv: 48 + Double(i % 5)) }
    }

    /// The reported bug: a future-dated row (e.g. a UTC "2026-06-18" while it's still the 17th
    /// locally) must NOT stand in for today. Today (17) has RHR/HRV, so the model derives.
    func testFutureRowIsIgnoredAndTodayDerives() {
        var days = baseline()
        days.append(dm("2026-06-17", rhr: 58, hrv: 38))   // real local "today"
        days.append(dm("2026-06-18", rhr: nil, hrv: nil)) // UTC ghost "tomorrow", empty
        let model = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertNotNil(model, "the empty future row (18) must be ignored; today (17) has signal")
        XCTAssertEqual(model?.rhrToday, 58)
        XCTAssertEqual(model?.hrvToday, 38)
    }

    /// Strap-partial night where the layered row (displayDays) carries Apple's RHR/HRV: the tile
    /// must show a value, like HRV / resting-HR do — not "—".
    func testPartialTodayWithFallbackDerives() {
        var days = baseline()
        days.append(dm("2026-06-17", rhr: 57, hrv: 41))   // value present via the Apple-backed twin
        let model = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.hrvToday, 41)
    }

    /// No RHR/HRV anywhere and no stored value → honest nil (the tile renders "—").
    func testNoSignalReturnsNil() {
        let days = [dm("2026-06-16"), dm("2026-06-17")]   // every field nil
        XCTAssertNil(DailyStressModel(days: days, stored: [], todayKey: "2026-06-17"))
    }

    /// Only future rows exist (none at or before today) → nil, never a future read.
    func testAllFutureReturnsNil() {
        let days = [dm("2026-06-18", rhr: 60, hrv: 50)]
        XCTAssertNil(DailyStressModel(days: days, stored: [], todayKey: "2026-06-17"))
    }

    // MARK: - FER-397 — fall back to the most recent reading (cap: yesterday), never blank the screen

    /// Today's row is still empty (midnight boundary, pre-sync) but yesterday has a reading → the hero
    /// anchors to yesterday, flagged NOT-today so the view dates it. The screen is not blanked.
    func testTodayEmptyFallsBackToYesterdayDated() {
        var days = baseline()
        days.append(dm("2026-06-16", rhr: 60, hrv: 40))   // yesterday: a real reading
        days.append(dm("2026-06-17"))                      // today: still empty
        let model = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.heroIsFresh, true)
        XCTAssertEqual(model?.anchorIsToday, false, "yesterday's reading must be dated, not passed as today's")
        XCTAssertEqual(model?.anchorDayKey, "2026-06-16")
        XCTAssertEqual(model?.rhrToday, 60)
    }

    /// The fallback also works off a STORED stress value on yesterday (no RHR/HRV needed).
    func testStoredYesterdayFallbackWhenTodayEmpty() {
        var days = baseline()
        days.append(dm("2026-06-16"))                      // yesterday: no RHR/HRV
        days.append(dm("2026-06-17"))                      // today: empty
        let model = DailyStressModel(days: days, stored: [("2026-06-16", 2.2)], todayKey: "2026-06-17")
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.anchorDayKey, "2026-06-16")
        XCTAssertEqual(model?.heroIsFresh, true)
        XCTAssertEqual(model?.anchorIsToday, false)
        XCTAssertEqual(model?.usingStored, true)
        XCTAssertEqual(model?.score ?? 0, 2.2, accuracy: 0.001)
    }

    /// Neither today nor yesterday has a reading, but older history does → the model is still built (the
    /// trend renders) but the hero is NOT fresh, so the view shows the empty hero instead of a stale one.
    func testStaleAnchorKeepsTrendButHeroNotFresh() {
        var days = baseline()                              // 2026-06-01…10 carry signal
        days.append(dm("2026-06-16"))                      // yesterday empty
        days.append(dm("2026-06-17"))                      // today empty
        let model = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.heroIsFresh, false, "anchor (2026-06-10) is older than yesterday → hide hero")
        XCTAssertEqual(model?.anchorDayKey, "2026-06-10")
        XCTAssertGreaterThanOrEqual(model?.fullTrend.count ?? 0, 2, "the history must still be there")
    }

    /// Today has a reading → fresh and NOT dated (no regression to the normal path).
    func testTodayPresentIsFreshAndNotDated() {
        var days = baseline()
        days.append(dm("2026-06-17", rhr: 59, hrv: 39))
        let model = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertEqual(model?.heroIsFresh, true)
        XCTAssertEqual(model?.anchorIsToday, true)
        XCTAssertEqual(model?.anchorDayKey, "2026-06-17")
    }

    // MARK: - FER-623 — HRV baseline split by source (RMSSD band vs SDNN Apple)

    /// Solo-banda identity: an empty `appleDays` set leaves every reading on the single (RMSSD) base, so
    /// the score and HRV delta are bit-for-bit the default-parameter behavior — a strap-only user unchanged.
    func testSoloBandaIdentity() {
        var days = baseline()
        days.append(dm("2026-06-17", rhr: 58, hrv: 38))
        let withParam = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17", appleDays: [])
        let noParam   = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17")
        XCTAssertEqual(withParam?.score ?? -1, noParam?.score ?? -2, accuracy: 1e-9)
        XCTAssertEqual(withParam?.hrvDelta ?? .nan, noParam?.hrvDelta ?? .nan, accuracy: 1e-9)
    }

    /// An Apple night (SDNN) in the baseline must NOT enter the band's RMSSD base. Marking a high-HRV
    /// outlier night as Apple lowers the band mean, so today (a band night) reads less far below it —
    /// proving the night was excluded from the band base (FER-519 policy, no SDNN→RMSSD mixing).
    func testAppleNightExcludedFromBandBase() {
        var days = (1...9).map { i in dm(String(format: "2026-06-%02d", i), rhr: 58 + i % 4, hrv: 48 + Double(i % 5)) }
        days.append(dm("2026-06-10", rhr: 60, hrv: 90))   // an "SDNN" outlier night (~1.8× the RMSSD band)
        days.append(dm("2026-06-17", rhr: 58, hrv: 50))   // today: a band night
        let mixed = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17", appleDays: [])
        let clean = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17", appleDays: ["2026-06-10"])
        XCTAssertNotNil(mixed); XCTAssertNotNil(clean)
        // Excluding the outlier lowers the band mean → today's delta (today − mean) is higher (less negative).
        XCTAssertGreaterThan(clean!.hrvDelta!, mixed!.hrvDelta!)
    }

    // MARK: - FER-633 — RHR baseline ALSO split by source (band sleep-nadir vs Apple awake-sedentary)

    /// An Apple night (awake-sedentary RHR) must NOT enter the band's sleep-nadir RHR base. Marking a
    /// high-RHR outlier night as Apple removes it from the band base, lowering the band mean, so today
    /// (a band night) reads FURTHER above it — proving the night was excluded (FER-633, ~10–13 bpm gap;
    /// Fenland Study 2023). Mirrors `testAppleNightExcludedFromBandBase` for HRV.
    func testAppleNightExcludedFromBandRhrBase() {
        var days = (1...9).map { i in dm(String(format: "2026-06-%02d", i), rhr: 58 + i % 4, hrv: 48 + Double(i % 5)) }
        days.append(dm("2026-06-10", rhr: 80, hrv: 50))   // an "awake" RHR outlier night (~20 bpm high)
        days.append(dm("2026-06-17", rhr: 62, hrv: 50))   // today: a band night
        let mixed = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17", appleDays: [])
        let clean = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17", appleDays: ["2026-06-10"])
        XCTAssertNotNil(mixed); XCTAssertNotNil(clean)
        // Excluding the high outlier lowers the band RHR mean → today's delta (today − mean) is higher.
        XCTAssertGreaterThan(clean!.rhrDelta!, mixed!.rhrDelta!)
    }

    /// An Apple day is z-scored against the APPLE RHR base, never a merged one. With a band base ~58 (sleep
    /// nadir) and an Apple base ~68 (awake), today's Apple RHR of 67 reads slightly BELOW its own base
    /// (−1 bpm); a merged base (~63) would have read it +4 above — the sign flip proves the split.
    func testAppleDayScoresAgainstAppleRhrBaseNotBand() {
        var days = (1...8).map { i in dm(String(format: "2026-06-%02d", i), rhr: 58, hrv: 48) }         // band nights
        days += (9...14).map { i in dm(String(format: "2026-06-%02d", i), rhr: 68, hrv: 60) }           // Apple nights
        days.append(dm("2026-06-17", rhr: 67, hrv: 60))                                                 // today: Apple
        let appleDays = Set((9...14).map { String(format: "2026-06-%02d", $0) } + ["2026-06-17"])
        let model = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17", appleDays: appleDays)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.rhrDelta ?? .nan, -1, accuracy: 0.001,
                       "today's Apple RHR is scored against the Apple base (~68), not a merged base")
    }

    /// Today is an Apple-only day and every baseline night is a band night → there is NO same-source base
    /// behind EITHER metric (no Apple RHR base, no SDNN base). The band base is never used for an Apple
    /// reading (sleep-nadir vs awake RHR aren't comparable), so the model has nothing honest to compare
    /// against and returns nil (the tile shows "—") rather than mixing sources (FER-633, supersedes the
    /// old merged-RHR fallback).
    func testAppleOnlyAnchorWithNoSameSourceBaseIsNil() {
        var days = baseline()                              // all band (RMSSD + sleep-nadir RHR) nights
        days.append(dm("2026-06-17", rhr: 64, hrv: 80))   // today: Apple-only, no Apple base behind it
        let model = DailyStressModel(days: days, stored: [], todayKey: "2026-06-17", appleDays: ["2026-06-17"])
        XCTAssertNil(model, "no same-source base for RHR or HRV → nil, never a cross-source comparison")
    }
}
