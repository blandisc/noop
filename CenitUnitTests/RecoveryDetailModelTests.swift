import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

/// FER-642 — `RecoveryDetailModel` replaced the old per-driver `drivers` API with two band-only
/// decompositions the Detalle draws: `impact` (`RecoveryImpact` — today's per-signal contributions to the
/// score, «Hoy, vs tu normal») and `change` (`RecoveryChange` — the day-over-day movement, «Qué cambió vs
/// ayer»). The guarantee these tests pin is that the model routes BOTH band-only — Apple-only rows dropped
/// whole-row — so the Detalle and the recovery SCORE can never tell two stories about the same night
/// (FER-519 / FER-629 / FER-632): the model's `impact` is exactly the standalone band-only decomposition and
/// diverges from a contaminated (raw) one; an Apple-only today invents no impact; and `change` reads the
/// previous CALENDAR day, band-only.
@MainActor
final class RecoveryDetailModelTests: XCTestCase {

    private func dm(_ day: String, hrv: Double?, rhr: Int?, resp: Double? = 14,
                    recovery: Double? = 60) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 90,
                    lightMin: 240, disturbances: 2, restingHr: rhr, avgHrv: hrv, recovery: recovery,
                    strain: 10, exerciseCount: 1, spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: resp)
    }

    /// 28 nights of band history (RMSSD ~50, RHR ~52) with every third night an Apple-sourced SDNN
    /// reading (~75, RHR ~47) interleaved — a baseline that is contaminated unless the Apple rows are
    /// dropped whole-row. Returns `(days, appleDays)`; the caller appends today.
    private func interleavedHistory() -> (days: [DailyMetric], appleDays: Set<String>) {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        for i in 1...28 {
            let isApple = i % 3 == 0
            let key = String(format: "2026-06-%02d", i)
            if isApple { appleDays.insert(key) }
            days.append(dm(key, hrv: isApple ? 75 : 50, rhr: isApple ? 47 : 52))
        }
        return (days, appleDays)
    }

    // MARK: impact — band-only «Hoy, vs tu normal»

    /// The model's `impact` must be exactly the standalone band-only decomposition (`RecoveryImpact.compute`
    /// with the Apple set) — the same currency the summary draws — and measurably different from a raw,
    /// contaminated read. Before FER-642/FER-632 the detail scored its σ against a baseline polluted with
    /// Apple SDNN/RHR-offsets and diverged from the score's own.
    func testImpactIsBandOnlyDecomposition() {
        var (days, appleDays) = interleavedHistory()
        let todayKey = "2026-06-29"
        let today = dm(todayKey, hrv: 44, rhr: 58, recovery: 30)   // a suppressed BAND morning
        days.append(today)

        let model = RecoveryDetailModel.build(days: days, today: today, todayKey: todayKey,
                                              appleHealthDays: appleDays, loaded: true)

        // The Detalle's impact is the band-only decomposition, verbatim — not recomputed differently.
        let bandOnly = RecoveryImpact.compute(days: days, todayKey: todayKey, appleDays: appleDays)
        XCTAssertNotNil(model.impact, "a band morning must carry an impact decomposition")
        XCTAssertEqual(model.impact, bandOnly,
                       "the model's impact must equal the standalone band-only RecoveryImpact")

        // And the band-only read must actually move off the contaminated (raw) one — not a no-op. The
        // Apple RHR (~47) pulls the raw baseline down, so today reads differently against it.
        let contaminated = RecoveryImpact.compute(days: days, todayKey: todayKey, appleDays: [])
        XCTAssertNotNil(contaminated)
        XCTAssertNotEqual(model.impact, contaminated,
                          "the band-only impact must diverge from the contaminated (raw) baseline")
    }

    /// The impact's signals are ranked by |contribution| (|z·weight|), not raw |z| — so the first row is the
    /// driver that actually moved today's composite most (HRV at 60% weight), the FER-628/FER-632 headline.
    func testImpactRanksByContribution() {
        var (days, appleDays) = interleavedHistory()
        let todayKey = "2026-06-29"
        let today = dm(todayKey, hrv: 44, rhr: 58, recovery: 30)
        days.append(today)

        let model = RecoveryDetailModel.build(days: days, today: today, todayKey: todayKey,
                                              appleHealthDays: appleDays, loaded: true)
        let signals = try! XCTUnwrap(model.impact).signals
        XCTAssertFalse(signals.isEmpty, "a band morning decomposes into ≥1 signal")

        // Ordered by |contribution| descending; the top row is `impact.top`.
        let contributions = signals.map { abs($0.contribution) }
        XCTAssertEqual(contributions, contributions.sorted(by: >),
                       "signals must be ranked by |contribution| (|z·weight|), not |z|")
        XCTAssertEqual(model.impact?.top?.key, signals.first?.key)
    }

    /// On an Apple-only day today's own row is dropped whole-row — the band never took that reading — so no
    /// band decomposition is invented. `impact` is nil.
    func testAppleOnlyDayHasNoImpact() {
        var (days, appleDays) = interleavedHistory()
        let todayKey = "2026-06-29"
        appleDays.insert(todayKey)                       // today is an Apple-only night
        let today = dm(todayKey, hrv: 70, rhr: 48, recovery: 55)
        days.append(today)

        let model = RecoveryDetailModel.build(days: days, today: today, todayKey: todayKey,
                                              appleHealthDays: appleDays, loaded: true)
        XCTAssertNil(model.impact, "no band impact is invented on an Apple-only day")
    }

    // MARK: change — band-only «Qué cambió vs ayer»

    /// With a band row + score on both today and the previous CALENDAR day, `change` is present and its
    /// `deltaScore` is exactly today's shown score minus yesterday's — the app's own displayed scores.
    func testChangeVsPreviousCalendarDay() {
        var (days, appleDays) = interleavedHistory()   // days 01..28, day 28 (i=28) is a band night
        let yesterdayKey = "2026-06-28"                 // i=28 → not Apple (28 % 3 ≠ 0), recovery 60
        let todayKey = "2026-06-29"
        let today = dm(todayKey, hrv: 44, rhr: 58, recovery: 30)
        days.append(today)

        let model = RecoveryDetailModel.build(days: days, today: today, todayKey: todayKey,
                                              appleHealthDays: appleDays, loaded: true)
        let change = try! XCTUnwrap(model.change, "a band today over a band yesterday must carry a change")
        XCTAssertFalse(appleDays.contains(yesterdayKey), "sanity: yesterday is a band night")
        XCTAssertEqual(change.deltaScore, 30 - 60,
                       "deltaScore is today's shown score (30) minus yesterday's (60)")
    }

    /// «vs ayer» must mean literally yesterday, band-only: when the previous calendar day is Apple-only,
    /// there is nothing honest to diff against, so `change` is nil (the block hides).
    func testAppleOnlyYesterdayHasNoChange() {
        var (days, appleDays) = interleavedHistory()
        let yesterdayKey = "2026-06-28"
        appleDays.insert(yesterdayKey)                   // yesterday becomes an Apple-only night
        let todayKey = "2026-06-29"
        let today = dm(todayKey, hrv: 44, rhr: 58, recovery: 30)
        days.append(today)

        let model = RecoveryDetailModel.build(days: days, today: today, todayKey: todayKey,
                                              appleHealthDays: appleDays, loaded: true)
        XCTAssertNil(model.change, "no day-over-day change when yesterday is Apple-only")
    }
}
