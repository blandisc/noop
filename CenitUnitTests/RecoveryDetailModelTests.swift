import XCTest
import WhoopStore
import StrandAnalytics
@testable import Cenit

/// FER-632 — the Recovery detail must score its «vs your base» σ against the BAND-only baseline, the same
/// history the recovery SCORE uses (`IntelligenceEngine.strapOnlyHistory`). Before the fix `build` passed
/// raw `repo.days` to `ReadinessEngine.evaluate`, so the σ the user saw was measured against a baseline
/// contaminated with Apple SDNN/offsets and diverged from the score's own (owner DB 27-jun: HRV −0.72σ shown
/// vs −3.56σ real). The fix routes the history through `SourceLens.maskForBaseline(keep:.band)` (FER-631).
/// It also ranks the headline driver by |z·weight| (contribution) rather than |z| alone.
@MainActor
final class RecoveryDetailModelTests: XCTestCase {

    private func dm(_ day: String, hrv: Double?, rhr: Int?, resp: Double? = 14,
                    recovery: Double? = 60) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 90,
                    lightMin: 240, disturbances: 2, restingHr: rhr, avgHrv: hrv, recovery: recovery,
                    strain: 10, exerciseCount: 1, spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: resp)
    }

    // MARK: I2 — the detail σ equals the score's band-only σ

    /// With Apple SDNN/RHR-offset nights interleaved, a raw baseline is contaminated. The detail must read
    /// each band signal against the band-only baseline — identical to the row-drop the scorer does (FER-631
    /// I4 pins column-mask ≡ row-drop), and measurably different from the old contaminated read.
    func testDetailSigmaMatchesScoreBandOnlyBaseline() {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        for i in 1...28 {
            let isApple = i % 3 == 0
            let key = String(format: "2026-06-%02d", i)
            if isApple { appleDays.insert(key) }
            days.append(dm(key, hrv: isApple ? 75 : 50, rhr: isApple ? 47 : 52))   // SDNN~75, band RMSSD~50
        }
        let todayKey = "2026-06-29"
        let today = dm(todayKey, hrv: 44, rhr: 58, recovery: 30)   // a suppressed BAND morning
        days.append(today)

        let model = RecoveryDetailModel.build(days: days, today: today, todayKey: todayKey,
                                              appleHealthDays: appleDays, loaded: true)

        // The recovery SCORE's baseline is the band-only (row-drop) history.
        let scoreBaseline = ReadinessEngine.evaluate(
            days: days.filter { !appleDays.contains($0.day) }, today: todayKey)

        for key in ["hrv", "rhr"] {
            let detailZ = model.drivers.first { $0.key == key }?.z
            let scoreZ = scoreBaseline.signals.first { $0.key == key }?.z
            XCTAssertNotNil(detailZ, "\(key): the detail driver must carry a σ")
            XCTAssertNotNil(scoreZ, "\(key): the score signal must be present")
            XCTAssertEqual(detailZ!, scoreZ!, accuracy: 1e-9,
                           "\(key): the detail σ must equal the score's band-only σ (I2)")
        }

        // And the fix must actually move the σ off the old contaminated (raw) baseline — not a no-op. RHR is
        // the reliably-large tell: the Apple RHR (~47) pulls the raw baseline down, so today reads further
        // above it than against the band-only base. (HRV's robust log-fold winsorizes the SDNN outliers, so
        // its own contamination is smaller and fixture-sensitive — I2's exact equality above is its proof.)
        let contaminated = ReadinessEngine.evaluate(days: days, today: todayKey)
        let rawRhrZ = contaminated.signals.first { $0.key == "rhr" }?.z
        let detailRhrZ = model.drivers.first { $0.key == "rhr" }?.z
        XCTAssertNotNil(rawRhrZ)
        XCTAssertGreaterThan(abs(detailRhrZ! - rawRhrZ!), 0.3,
                             "the fix must move the RHR σ away from the contaminated baseline")
    }

    /// On an Apple-only day, today's own row is masked under keep:.band — the band never took that reading,
    /// so no band σ is invented (the estimate carries its own caveat elsewhere).
    func testAppleOnlyDayInventsNoBandSigma() {
        var days: [DailyMetric] = []
        var appleDays: Set<String> = []
        for i in 1...28 {
            let isApple = i % 3 == 0
            let key = String(format: "2026-06-%02d", i)
            if isApple { appleDays.insert(key) }
            days.append(dm(key, hrv: isApple ? 75 : 50, rhr: isApple ? 47 : 52,
                           recovery: isApple ? nil : 60))
        }
        let todayKey = "2026-06-29"
        appleDays.insert(todayKey)                       // today is an Apple-only night
        let today = dm(todayKey, hrv: 70, rhr: 48, recovery: 55)
        days.append(today)

        let model = RecoveryDetailModel.build(days: days, today: today, todayKey: todayKey,
                                              appleHealthDays: appleDays, loaded: true, isEstimated: true)
        XCTAssertNil(model.drivers.first { $0.key == "hrv" }?.z, "no band HRV σ on an Apple-only day")
        XCTAssertNil(model.drivers.first { $0.key == "rhr" }?.z, "no band RHR σ on an Apple-only day")
    }

    // MARK: Headline ranks by |z·weight| (contribution), not |z|

    /// The old sort crowned the largest DEVIATION; a +2σ respiration at 5% weight beat a −1σ HRV at 60%.
    /// Ranking by |z·weight| puts HRV first — the driver that actually moved the composite most.
    func testAxisDriversRankByContributionNotDeviation() {
        let drivers: [RecoveryDetailModel.DriverState] = [
            .init(key: "hrv",      label: "HRV",         weightPct: 60, flag: .watch,   z: -1.0),  // |z·w| = 60
            .init(key: "rhr",      label: "Resting HR",  weightPct: 20, flag: .neutral, z: 0.3),   // |z·w| = 6
            .init(key: "respRate", label: "Respiration", weightPct: 5,  flag: .watch,   z: 2.0),   // |z·w| = 10
            .init(key: "sleep",    label: "Sleep",       weightPct: 15, flag: .good,    z: nil),    // state-only
        ]
        let model = RecoveryDetailModel(
            score: 40, calibration: nil, nightsNeeded: 4, drivers: drivers, series: [], heat: [],
            load: nil, loaded: true, isAppleHealth: false, forecast: nil, isEstimated: false, confidence: nil)

        XCTAssertEqual(model.axisDrivers.first?.key, "hrv",
                       "|z·weight| must crown HRV (60%·1.0=60) over Respiration (5%·2.0=10)")
        XCTAssertEqual(model.axisDrivers.map(\.key), ["hrv", "respRate", "rhr"],
                       "ordered by contribution; the no-σ sleep driver is excluded from the axis")
        XCTAssertEqual(model.otherDrivers.map(\.key), ["sleep"], "sleep (z nil) is a state-only row")
    }
}
