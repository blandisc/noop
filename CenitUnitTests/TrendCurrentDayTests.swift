import XCTest
import WhoopStore
@testable import Cenit

/// Pins FER-630: with the in-progress day's row present in the daily rows, the Esfuerzo/Estrés trend
/// series include it as their LAST point — the line must end on the same day as the hero, never a day
/// behind it. Two mechanisms caused the lag:
///   1. Day Strain's levels series deliberately dropped today's partial point while its hero showed it.
///   2. The stress levels series re-keyed UTC-midnight-anchored trend dates through `localDayKey`,
///      which shifts every point one day back west of UTC (CDMX, UTC−6).
/// Steps' drop-today guard (FER-264 / FER-471) is intentional and must survive.
final class TrendCurrentDayTests: XCTestCase {

    private func dm(_ day: String, rhr: Int? = nil, hrv: Double? = nil,
                    strain: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: strain, exerciseCount: nil)
    }

    /// 10 past days with spread, so the stress baseline mean/SD are well-defined.
    private func baseline() -> [DailyMetric] {
        (1...10).map { i in
            dm(String(format: "2026-06-%02d", i), rhr: 58 + i % 4, hrv: 48 + Double(i % 5),
               strain: 6 + Double(i % 5))
        }
    }

    // MARK: - Day-key round-trip (the stress mislabel)

    /// `utcDayKey` must be the exact inverse of `parseDayKey`. With `localDayKey` this fails on any
    /// device west of UTC (a UTC-midnight jun-27 is still jun-26 in CDMX) — the FER-630 stress shift.
    func testUtcDayKeyIsInverseOfParseDayKey() {
        for key in ["2026-06-27", "2026-01-01", "2025-12-31"] {
            let date = Repository.parseDayKey(key)
            XCTAssertNotNil(date)
            XCTAssertEqual(Repository.utcDayKey(date!), key)
        }
    }

    // MARK: - Esfuerzo

    /// Rich detail (StrainDetailScreen): today's row present in `days` → the series ends on today.
    func testStrainDetailSeriesIncludesInProgressToday() {
        var days = baseline()
        days.append(dm("2026-06-27", strain: 1.9))   // in-progress today, partial score
        let model = StrainDetailModel.build(days: days, today: days.last, loaded: true)
        XCTAssertEqual(model.series.last?.day, "2026-06-27",
                       "the trend's last point must be the hero's day (today), not yesterday")
        XCTAssertEqual(model.series.last?.value, 1.9)
    }

    /// Resumen sheet (Hoy → MetricInfoSheet levels): Day Strain KEEPS today's partial point — its hero
    /// shows the in-progress score, so a line ending yesterday contradicted it (FER-630).
    func testStrainLevelsSeriesKeepsInProgressToday() {
        var days = baseline()
        days.append(dm("2026-06-27", strain: 1.9))
        let series = TodayView.levelsSeries(rows: days, todayKey: "2026-06-27",
                                            dropsIncompleteToday: false, pick: { $0.strain })
        XCTAssertEqual(series.last?.day, "2026-06-27")
        XCTAssertEqual(series.last?.value, 1.9)
    }

    /// A running daily total (steps) still DROPS today's in-progress point (FER-264 / FER-471 —
    /// deliberate, its sheet has no in-progress hero over this series). The FER-630 fix must not widen
    /// the drop to non-accumulating metrics.
    func testRunningTotalLevelsSeriesDropsInProgressToday() {
        var days = baseline()
        days.append(dm("2026-06-27", hrv: 50))
        let series = TodayView.levelsSeries(rows: days, todayKey: "2026-06-27",
                                            dropsIncompleteToday: true, pick: { $0.avgHrv })
        XCTAssertEqual(series.last?.day, "2026-06-10",
                       "a running total must keep dropping the in-progress day")
    }

    /// The «who drops today» policy has a single source: `MetricDetailSpec.accumulatesToday`. Only steps
    /// accumulates; the rich detail's `currentDayIncomplete` reads from the same predicate, so the
    /// resumen and rich sheets can't diverge (FER-630 altitude).
    func testAccumulatesTodaySingleSource() {
        XCTAssertTrue(MetricDetailSpec.accumulatesToday("steps"))
        for id in ["strain", "stress", "hrv", "rhr", "spo2", "sleep", "recovery", "resp_rate"] {
            XCTAssertFalse(MetricDetailSpec.accumulatesToday(id), "\(id) is not a running daily total")
        }
        XCTAssertEqual(MetricDetailSpec.steps(1234).currentDayIncomplete,
                       MetricDetailSpec.accumulatesToday("steps"),
                       "the steps spec must derive currentDayIncomplete from the shared predicate")
    }

    /// A metric whose newest row is NOT today (no data yet) keeps its honest last point — no invented
    /// today point.
    func testLevelsSeriesWithoutTodayRowEndsOnNewestRealDay() {
        let series = TodayView.levelsSeries(rows: baseline(), todayKey: "2026-06-27",
                                            dropsIncompleteToday: false, pick: { $0.strain })
        XCTAssertEqual(series.last?.day, "2026-06-10")
    }

    // MARK: - Estrés

    /// Today's row carries signal (RHR/HRV) → `fullTrend` includes today, and mapping its dates back
    /// through `utcDayKey` (the levels-series path) labels the last point TODAY. Through `localDayKey`
    /// this read a day behind on any device west of UTC.
    func testStressLevelsSeriesLastDayIsToday() {
        var days = baseline()
        days.append(dm("2026-06-27", rhr: 60, hrv: 44))
        let model = StressModel(days: days, stored: [], todayKey: "2026-06-27")
        XCTAssertNotNil(model)
        let series = (model?.fullTrend ?? []).map { (day: Repository.utcDayKey($0.date), value: $0.value) }
        XCTAssertEqual(series.last?.day, "2026-06-27",
                       "the stress levels series must end on the hero's day")
    }
}
