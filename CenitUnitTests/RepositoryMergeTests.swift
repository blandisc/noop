import XCTest
import WhoopStore
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
}
