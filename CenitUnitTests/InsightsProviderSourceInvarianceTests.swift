import XCTest
import WhoopStore
import StrandAnalytics
@testable import Cenit

/// FER-639 — `InsightsProvider` (Patrones + «La conexión de hoy» del Daily Brief) must mask every
/// cross-source column to the BAND source before `InsightEngine` folds any HRV/RHR/resp baseline,
/// anomaly or correlation. Before the fix it passed raw `repo.days`, so the HRV night-anomaly baseline
/// («anoche tu HRV corrió bajo tu base, base X ms») mixed band RMSSD with Apple SDNN — two instruments
/// with no published conversion (Task Force 1996; Shaffer & Ginsberg 2017). The fix routes `days`
/// through `SourceLens.maskForBaseline(keep:.band)` (FER-631), the same lens the Recovery detail uses.
@MainActor
final class InsightsProviderSourceInvarianceTests: XCTestCase {

    private func key(_ i: Int) -> String { String(format: "2026-06-%02d", i) }

    private func dm(_ day: String, hrv: Double?, rhr: Int?, resp: Double? = 14,
                    recovery: Double? = 60) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 90,
                    lightMin: 240, disturbances: 2, restingHr: rhr, avgHrv: hrv, recovery: recovery,
                    strain: 10, exerciseCount: 1, spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: resp)
    }

    /// A band history + interleaved Apple-only travel nights on a DIFFERENT instrument's scale
    /// (SDNN ~85 vs band RMSSD ~50; Apple RHR ~44 vs band ~52), then tonight back on the strap.
    private func mixedHistory() -> (days: [DailyMetric], apple: Set<String>, todayKey: String) {
        var days: [DailyMetric] = []
        var apple: Set<String> = []
        for i in 1...20 { days.append(dm(key(i), hrv: 50, rhr: 52)) }            // band nights
        for i in 21...30 {                                                        // Apple-only nights
            let k = key(i); apple.insert(k)
            days.append(dm(k, hrv: 85, rhr: 44, resp: 16))
        }
        return (days, apple, key(31))
    }

    private let vitals: Set<String> = ["HRV", "FC en reposo", "Respiración"]
    private func vitalAnomalies(_ xs: [Insight]) -> [Insight] {
        xs.filter { $0.kind == .nightAnomaly && vitals.contains($0.datum.metric) }
          .sorted { $0.datum.metric < $1.datum.metric }
    }

    // MARK: I4 — the consumer's HRV/RHR/resp baseline equals the band-only (Apple-rows-dropped) one

    /// Tonight's BAND reading breaks from the band baseline (RHR 58 vs base 52 → an anomaly). The masked
    /// consumer must read it against the band-only baseline — identical to dropping the Apple rows whole —
    /// and NOT against the contaminated mix.
    func testVitalAnomaliesMatchBandOnlyBaseline() {
        var (days, apple, todayKey) = mixedHistory()
        days.append(dm(todayKey, hrv: 50, rhr: 58))   // back on the strap: RHR jumps, HRV at base

        let masked = InsightsProvider.rank(days: days, appleDays: apple, behaviors: [:],
                                           eligibleDaysByBehavior: [:], proven: [], today: todayKey)
        // The band-only history (Apple rows dropped) — the baseline the fix must reproduce (FER-631 I4).
        let bandOnly = InsightEngine.generate(
            .init(days: days.filter { !apple.contains($0.day) }, referenceDay: todayKey))

        XCTAssertEqual(vitalAnomalies(masked), vitalAnomalies(bandOnly),
                       "the HRV/RHR/resp night-anomaly insights must match the band-only baseline (I4)")
        XCTAssertFalse(vitalAnomalies(masked).isEmpty, "the RHR jump must surface as an anomaly")

        // Load-bearing: without the mask the engine folds the Apple RHR (~44) into the baseline, so
        // tonight's 58 reads against a different, pulled-down base → a different anomaly set.
        let unmasked = InsightEngine.generate(.init(days: days, referenceDay: todayKey))
        XCTAssertNotEqual(vitalAnomalies(unmasked), vitalAnomalies(masked),
                          "the Apple nights bias the raw baseline — proving the source mask is load-bearing")
    }

    // MARK: I1 — a band reading at its own baseline raises no anomaly, however many Apple days there are

    /// Tonight's band reading sits exactly on the band baseline (HRV 50, RHR 52). No vital anomaly may
    /// fire, regardless of the 10 Apple SDNN nights in `repo.days` — the classic I1 invariant.
    func testBandReadingAtBaselineRaisesNoAnomalyDespiteAppleDays() {
        var (days, apple, todayKey) = mixedHistory()
        days.append(dm(todayKey, hrv: 50, rhr: 52))   // on-baseline band night

        let masked = InsightsProvider.rank(days: days, appleDays: apple, behaviors: [:],
                                           eligibleDaysByBehavior: [:], proven: [], today: todayKey)
        XCTAssertTrue(vitalAnomalies(masked).isEmpty,
                      "a band reading at its own baseline must raise no anomaly (I1)")
    }
}
