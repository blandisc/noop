import XCTest
import CenitStore
import BiometricStreams
import StrandAnalytics
@testable import Cenit

/// Pins the FER-62 dashboard merge: Apple Health is the lowest-precedence base, on-device computed
/// rows fill its gaps, and imported strap rows win over everything — so the strap always beats Apple
/// Health. `appleDays` tracks only the days that stayed Apple-sourced, for the source badge. The
/// FER-149 block below pins the display-only Apple back-fill: an empty-strap day shows Apple's HRV in
/// `displayDays` (sparkline/trend) while `days` (the recovery baseline / ownNights source) stays
/// strap-only.
@MainActor
final class RepositoryMergeTests: XCTestCase {

    private func dm(_ day: String, hrv: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    func testImportedStrapBeatsComputedAndApple() {
        let r = Repository.mergeDaily(imported: [dm("2026-06-10", hrv: 50)],
                                      computed: [dm("2026-06-10", hrv: 99)],
                                      apple: [dm("2026-06-10", hrv: 77)])
        XCTAssertEqual(r.days.count, 1)
        XCTAssertEqual(r.days[0].avgHrv, 50)                 // imported strap wins
        XCTAssertFalse(r.appleDays.contains("2026-06-10"))   // strap-covered → not an Apple day
    }

    func testComputedStrapBeatsAppleWhenNoImport() {
        let r = Repository.mergeDaily(imported: [], computed: [dm("2026-06-10", hrv: 60)],
                                      apple: [dm("2026-06-10", hrv: 77)])
        XCTAssertEqual(r.days[0].avgHrv, 60)                 // on-device strap beats Apple
        XCTAssertFalse(r.appleDays.contains("2026-06-10"))
    }

    func testAppleFillsOnlyDaysNoStrapCovers() {
        let r = Repository.mergeDaily(imported: [dm("2026-06-10", hrv: 50)], computed: [],
                                      apple: [dm("2026-06-09", hrv: 70), dm("2026-06-10", hrv: 77)])
        XCTAssertEqual(r.days.count, 2)
        XCTAssertEqual(r.days.first(where: { $0.day == "2026-06-09" })?.avgHrv, 70)  // apple-only day
        XCTAssertTrue(r.appleDays.contains("2026-06-09"))
        XCTAssertFalse(r.appleDays.contains("2026-06-10"))   // strap day, even though Apple had it too
    }

    func testResultSortedByDayAscending() {
        let r = Repository.mergeDaily(imported: [], computed: [],
                                      apple: [dm("2026-06-12"), dm("2026-06-10"), dm("2026-06-11")])
        XCTAssertEqual(r.days.map(\.day), ["2026-06-10", "2026-06-11", "2026-06-12"])
        XCTAssertEqual(r.appleDays, ["2026-06-10", "2026-06-11", "2026-06-12"])
    }

    // MARK: - FER-149 — display-only Apple back-fill for empty-strap days

    /// A strap-covered day whose HRV is nil (a partial-connection day: IntelligenceEngine wrote a
    /// `daily` with HRV/recovery nil) must show Apple Health's HRV in the DISPLAY rows (sparkline/trend)
    /// while the strap-only `days` keep nil — so the value fills the sparkline without inflating the
    /// recovery calibration (`ownNights` maps `repo.days`, never `displayDays`).
    func testEmptyStrapDayBackfillsHrvFromAppleInDisplayOnly() {
        let r = Repository.mergeDaily(imported: [],
                                      computed: [dm("2026-06-14", hrv: nil)],   // empty strap row
                                      apple: [dm("2026-06-14", hrv: 46.7)])
        // display uses Apple — the sparkline/trend sees the value, no gap
        XCTAssertEqual(r.displayDays.first(where: { $0.day == "2026-06-14" })?.avgHrv, 46.7)
        // ownNights ignores Apple — the strap-only row stays nil (calibration counter untouched)
        XCTAssertNil(r.days.first(where: { $0.day == "2026-06-14" })?.avgHrv)
        // a strap row exists, so the day is NOT badged Apple (unchanged FER-62 semantics)
        XCTAssertFalse(r.appleDays.contains("2026-06-14"))
    }

    /// When the strap DID decode HRV that day, the strap value wins in BOTH `days` and `displayDays` —
    /// Apple never overwrites a real strap reading.
    func testStrapHrvWinsOverAppleInDisplay() {
        let r = Repository.mergeDaily(imported: [],
                                      computed: [dm("2026-06-15", hrv: 57.1)],
                                      apple: [dm("2026-06-15", hrv: 35.7)])
        XCTAssertEqual(r.days.first?.avgHrv, 57.1)          // strap wins for analytics
        XCTAssertEqual(r.displayDays.first?.avgHrv, 57.1)   // strap wins for display (Apple doesn't pisa)
    }

    /// The whole real-data scenario from the issue (jun 14 empty, jun 15 strap, jun 16 empty): the
    /// DISPLAY HRV series has no gaps (46.7, 57.1, 37.9), while the strap-only `days` series the baseline
    /// reads keeps the two empty days nil (only 57.1 survives) — proving the baseline input is unchanged.
    func testIssueScenarioDisplayHasNoGapsButAnalyticsStaysStrapOnly() {
        let r = Repository.mergeDaily(
            imported: [],
            computed: [dm("2026-06-14", hrv: nil), dm("2026-06-15", hrv: 57.1), dm("2026-06-16", hrv: nil)],
            apple:    [dm("2026-06-14", hrv: 46.7), dm("2026-06-15", hrv: 35.7), dm("2026-06-16", hrv: 37.9)])
        XCTAssertEqual(r.displayDays.map(\.avgHrv), [46.7, 57.1, 37.9])   // display: no gaps
        XCTAssertEqual(r.days.compactMap(\.avgHrv), [57.1])               // analytics: strap-only
    }

    /// Back-fill is field-wise and only fills genuine nils — RHR fills from Apple while a present strap
    /// field is untouched. (The sparkline tiles for RHR/sleep/SpO₂ read the same display rows.)
    func testBackfillIsFieldWiseAndOnlyFillsNils() {
        let strap = DailyMetric(day: "2026-06-14", totalSleepMin: nil, efficiency: nil, deepMin: nil,
                                remMin: nil, lightMin: nil, disturbances: nil, restingHr: nil,
                                avgHrv: nil, recovery: nil, strain: 12.3, exerciseCount: nil)
        let apple = DailyMetric(day: "2026-06-14", totalSleepMin: 420, efficiency: nil, deepMin: nil,
                                remMin: nil, lightMin: nil, disturbances: nil, restingHr: 52,
                                avgHrv: 46.7, recovery: nil, strain: 99, exerciseCount: nil)
        let r = Repository.mergeDaily(imported: [], computed: [strap], apple: [apple])
        let d = r.displayDays.first
        XCTAssertEqual(d?.avgHrv, 46.7)          // nil → filled from Apple
        XCTAssertEqual(d?.restingHr, 52)         // nil → filled from Apple
        XCTAssertEqual(d?.totalSleepMin, 420)    // nil → filled from Apple
        XCTAssertEqual(d?.strain, 12.3)          // present strap value wins, NOT overwritten by Apple's 99
    }

    /// An Apple-only day (no strap row at all) is unchanged by the display pass: `displayDays` equals the
    /// Apple row and the day stays badged Apple.
    func testAppleOnlyDayUnchangedInDisplay() {
        let r = Repository.mergeDaily(imported: [], computed: [],
                                      apple: [dm("2026-06-09", hrv: 70)])
        XCTAssertEqual(r.displayDays.first?.avgHrv, 70)
        XCTAssertEqual(r.days.first?.avgHrv, 70)
        XCTAssertTrue(r.appleDays.contains("2026-06-09"))
    }

    // MARK: - FER-484 — the data-source mode filters which sources enter the merge

    /// `combined` is the identity filter: the merge sees exactly the three arrays it sees today, so every
    /// FER-62/149 case above is byte-for-byte unchanged through the mode path. Regression zero.
    func testCombinedModeMatchesUnfilteredMerge() {
        let imp = [dm("2026-06-10", hrv: 50)]
        let cmp = [dm("2026-06-11", hrv: 60)]
        let app = [dm("2026-06-12", hrv: 70)]
        let f = DataSourcePolicy.filter(.combined, imported: imp, computed: cmp, apple: app)
        let viaMode = Repository.mergeDaily(imported: f.imported, computed: f.computed, apple: f.apple)
        let direct  = Repository.mergeDaily(imported: imp, computed: cmp, apple: app)
        XCTAssertEqual(viaMode.days, direct.days)
        XCTAssertEqual(viaMode.displayDays, direct.displayDays)
        XCTAssertEqual(viaMode.appleDays, direct.appleDays)
    }

    /// `whoopOnly` drops Apple before the merge: an Apple-only day vanishes, no day is badged Apple, and
    /// there's no Apple back-fill in `displayDays`.
    func testWhoopOnlyModeExcludesAppleFromMerge() {
        let f = DataSourcePolicy.filter(.whoopOnly,
                                        imported: [dm("2026-06-10", hrv: 50)],
                                        computed: [],
                                        apple: [dm("2026-06-09", hrv: 70), dm("2026-06-10", hrv: 77)])
        let r = Repository.mergeDaily(imported: f.imported, computed: f.computed, apple: f.apple)
        XCTAssertEqual(r.days.map(\.day), ["2026-06-10"])   // the Apple-only day is gone
        XCTAssertEqual(r.days[0].avgHrv, 50)                // strap value, untouched by Apple
        XCTAssertTrue(r.appleDays.isEmpty)                  // nothing badged Apple
        XCTAssertEqual(r.displayDays, r.days)               // no Apple back-fill
    }

    /// `appleHealthOnly` drops the strap before the merge: only Apple rows survive, every day badged Apple.
    func testAppleHealthOnlyModeExcludesStrapFromMerge() {
        let f = DataSourcePolicy.filter(.appleHealthOnly,
                                        imported: [dm("2026-06-10", hrv: 50)],
                                        computed: [dm("2026-06-11", hrv: 60)],
                                        apple: [dm("2026-06-10", hrv: 77), dm("2026-06-11", hrv: 80)])
        let r = Repository.mergeDaily(imported: f.imported, computed: f.computed, apple: f.apple)
        XCTAssertEqual(r.days.map(\.avgHrv), [77, 80])              // Apple values, no strap
        XCTAssertEqual(r.appleDays, ["2026-06-10", "2026-06-11"])  // all Apple-sourced
    }

    // MARK: - FER-153 / FER-529 — Apple estimate is a side map keyed on `recovery == nil`, never folded in

    /// An Apple row with SDNN + sleep, for the estimate tests.
    private func appleRow(_ day: String, hrv: Double, sleep: Double = 420) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil)
    }

    /// A band (on-device computed) row for a day, with an optional measured recovery — `nil` models the
    /// cold-start night where the band is worn but its RMSSD baseline isn't seeded yet.
    private func bandRow(_ day: String, recovery: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 42, recovery: recovery,
                    strain: nil, exerciseCount: nil)
    }

    /// Mirrors `Repository.refresh`'s estimate wiring + the `repo.today` selector (Repository.swift:114),
    /// so a test can pin what the user would SEE for a day without a DB: the band recovery wins; on `nil`
    /// the Apple estimate fills in (band-less OR cold-start); with no estimate it stays «—».
    private func surfaced(day: String, imported: [DailyMetric] = [], computed: [DailyMetric] = [],
                          apple: [DailyMetric]) -> (value: Double?, estimated: Bool) {
        let merged = Repository.mergeDaily(imported: imported, computed: computed, apple: apple)
        let eligible = Set(merged.days.filter { $0.recovery == nil }.map(\.day))
        let estimates = Repository.appleRecoveryEstimates(apple: apple, eligibleDays: eligible)
        guard let row = merged.days.first(where: { $0.day == day }) else { return (nil, false) }
        if row.recovery == nil, let est = estimates[day] { return (est.score, true) }
        return (row.recovery, false)
    }

    /// Eligibility = days whose measured recovery is nil. With ≥ seed Apple nights those days get an
    /// estimate (score + confidence); a day with a band recovery is NOT eligible → no estimate (band wins),
    /// so `isRecoveryEstimated` never lies. (FER-529 keys on eligibility, not on strap coverage.)
    func testEstimatesOnlyForEligibleDays() {
        let apple = (1...5).map { appleRow(String(format: "2026-06-%02d", $0), hrv: 50) }
        let est = Repository.appleRecoveryEstimates(
            apple: apple, eligibleDays: ["2026-06-01", "2026-06-02", "2026-06-04", "2026-06-05"])

        XCTAssertEqual(Set(est.keys), ["2026-06-01", "2026-06-02", "2026-06-04", "2026-06-05"])
        XCTAssertNil(est["2026-06-03"])                          // not eligible (band recovery) → no estimate
        XCTAssertNotNil(est["2026-06-01"]?.score)
        XCTAssertEqual(est["2026-06-01"]?.confidence, .calibrating)   // few nights → low
    }

    /// FER-529 (the new behavior): during the band's cold-start — band worn (a computed row exists) but its
    /// recovery is still nil because the RMSSD baseline isn't seeded — the Apple estimate surfaces instead
    /// of «—», then switches cleanly to the band the moment the band can compute a recovery.
    func testColdStartBandDaySurfacesEstimateThenSwitchesToBand() {
        let apple = (1...5).map { appleRow(String(format: "2026-06-%02d", $0), hrv: 50) }
        let day = "2026-06-05"

        // Cold-start: band on the wrist on 06-05, recovery still nil.
        let cold = surfaced(day: day, computed: [bandRow(day, recovery: nil)], apple: apple)
        XCTAssertTrue(cold.estimated)                           // estimate surfaces (was «—» before FER-529)
        XCTAssertNotNil(cold.value)

        // Baseline ready: the band now has a recovery → clean switch, estimate gone (⌚ marker disappears).
        let ready = surfaced(day: day, computed: [bandRow(day, recovery: 48)], apple: apple)
        XCTAssertFalse(ready.estimated)
        XCTAssertEqual(ready.value, 48)                         // band wins
    }

    /// Cold-start WITHOUT enough Apple history → no estimate available → the day stays «—» (no number).
    func testColdStartWithoutAppleStaysDash() {
        let r = surfaced(day: "2026-06-05", computed: [bandRow("2026-06-05", recovery: nil)], apple: [])
        XCTAssertFalse(r.estimated)
        XCTAssertNil(r.value)
    }

    /// A band-LESS Apple night still surfaces its estimate (FER-153 regression: no strap row that day).
    func testBandlessNightStillSurfacesEstimate() {
        let apple = (1...5).map { appleRow(String(format: "2026-06-%02d", $0), hrv: 50) }
        let r = surfaced(day: "2026-06-03", apple: apple)      // no imported/computed → band-less
        XCTAssertTrue(r.estimated)
        XCTAssertNotNil(r.value)
    }

    /// The estimate is NEVER folded into the merged days — `mergeDaily` is the unchanged band/Apple merge,
    /// so `days`/`displayDays` recovery stays band-measured (no recovery statistic over history sees it).
    func testMergeDailyUnaffectedByEstimates() {
        let apple = (1...5).map { appleRow(String(format: "2026-06-%02d", $0), hrv: 50) }
        let r = Repository.mergeDaily(imported: [], computed: [], apple: apple)
        XCTAssertTrue(r.days.allSatisfy { $0.recovery == nil })   // Apple rows carry no recovery into days
    }

    /// whoopOnly path: the mode filter hands `apple == []`, so there is no estimate at all.
    func testNoEstimateWhenAppleEmpty() {
        XCTAssertTrue(Repository.appleRecoveryEstimates(apple: [], eligibleDays: ["2026-06-01"]).isEmpty)
    }

    /// Below the seed of Apple HRV nights → no estimate even when the day is eligible (UI shows "—").
    func testNoEstimateBelowSeed() {
        let apple = (1...3).map { appleRow(String(format: "2026-06-%02d", $0), hrv: 50) }
        let days: Set<String> = ["2026-06-01", "2026-06-02", "2026-06-03"]
        XCTAssertTrue(Repository.appleRecoveryEstimates(apple: apple, eligibleDays: days).isEmpty)
    }

    // MARK: - FER-883 — Apple workout-HR strain estimate is a side map keyed on `strain == nil`

    /// Dense 1 Hz HR samples at a constant bpm (same pattern as StrainScorerTests).
    private func denseHR(_ bpm: Int, n: Int = 600, start: Int = 1_700_000_000) -> [HRSample] {
        (0..<n).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    /// Sparse HR: fewer samples than both dense and sparse gates → hasEnoughData false.
    private func sparseHR(_ bpm: Int, n: Int = 10, start: Int = 1_700_000_000) -> [HRSample] {
        (0..<n).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    /// Eligible day with dense workout HR → non-nil strain estimate (0–21).
    func testAppleStrainEstimatesDenseHREligibleDay() {
        let day = "2026-06-10"
        // ts around a fixed epoch so DayKey.local grouping isn't under test here — we pass hrByDay pre-grouped.
        let hrByDay = [day: denseHR(150)]
        let out = Repository.appleStrainEstimates(hrByDay: hrByDay, eligibleDays: [day])
        XCTAssertNotNil(out[day])
        XCTAssertGreaterThan(out[day]!, 0)
        XCTAssertLessThanOrEqual(out[day]!, 21)
    }

    /// Sparse/too-few HR → no entry even if the day is eligible.
    func testAppleStrainEstimatesSparseHRNoEntry() {
        let day = "2026-06-10"
        let out = Repository.appleStrainEstimates(hrByDay: [day: sparseHR(150)], eligibleDays: [day])
        XCTAssertNil(out[day])
        XCTAssertTrue(out.isEmpty)
    }

    /// Only days in `eligibleDays` get estimates — mirrors recovery "only eligible days".
    func testAppleStrainEstimatesOnlyForEligibleDays() {
        let d1 = "2026-06-01", d2 = "2026-06-02", d3 = "2026-06-03"
        let hrByDay = [
            d1: denseHR(150, start: 1_700_000_000),
            d2: denseHR(160, start: 1_700_100_000),
            d3: denseHR(155, start: 1_700_200_000),
        ]
        // d2 not eligible (e.g. band already has measured strain that day).
        let out = Repository.appleStrainEstimates(hrByDay: hrByDay, eligibleDays: [d1, d3])
        XCTAssertNotNil(out[d1])
        XCTAssertNil(out[d2])
        XCTAssertNotNil(out[d3])
        XCTAssertEqual(Set(out.keys), [d1, d3])
    }

    /// Band strain present ⇒ day not eligible ⇒ estimate never wins over real strain, even with HR samples.
    func testAppleStrainEstimatesNeverWinsOverBandStrain() {
        let day = "2026-06-10"
        // Contract at appleStrainEstimates level: pass day NOT in eligibleDays despite hrByDay samples.
        let out = Repository.appleStrainEstimates(
            hrByDay: [day: denseHR(180)],
            eligibleDays: []   // band day filtered out of eligibility by assembleDashboard
        )
        XCTAssertNil(out[day])
        XCTAssertTrue(out.isEmpty)
    }

    /// `mergeDaily` is untouched by strain estimates — Apple rows carry no strain into days/displayDays.
    func testMergeDailyUnaffectedByStrainEstimates() {
        let apple = (1...5).map { appleRow(String(format: "2026-06-%02d", $0), hrv: 50) }
        let r = Repository.mergeDaily(imported: [], computed: [], apple: apple)
        XCTAssertTrue(r.days.allSatisfy { $0.strain == nil })
        XCTAssertTrue(r.displayDays.allSatisfy { $0.strain == nil })
    }

    /// Empty hrByDay → empty map (whoopOnly / no workout HR).
    func testAppleStrainEstimatesEmptyHR() {
        XCTAssertTrue(Repository.appleStrainEstimates(hrByDay: [:], eligibleDays: ["2026-06-01"]).isEmpty)
    }

    /// FER-883 (/cso finding 1): the threaded HRmax actually changes the estimate — the Apple «Carga del
    /// día» must use the user's HRmax (the same the strap live path uses), not a fixed default. A lower
    /// HRmax ⇒ higher %HRR ⇒ higher Edwards load.
    func testAppleStrainEstimatesHRmaxAffectsResult() {
        let day = "2026-06-10"
        let hr = [day: denseHR(150)]
        let low  = Repository.appleStrainEstimates(hrByDay: hr, eligibleDays: [day], maxHR: 170)[day]
        let high = Repository.appleStrainEstimates(hrByDay: hr, eligibleDays: [day], maxHR: 210)[day]
        XCTAssertNotNil(low); XCTAssertNotNil(high)
        XCTAssertGreaterThan(low!, high!)
    }
}
