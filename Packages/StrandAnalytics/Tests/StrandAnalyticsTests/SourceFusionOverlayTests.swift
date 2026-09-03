import XCTest
import StrandModels
@testable import StrandAnalytics

/// Ola 1 · E2 — the strength load overlay: Cénit sessions enter the daily strain series IN READING.
/// Gate estadístico H5 (sum when disjoint, max when overlapping), H6 (a trained day with no load is
/// a hold, never a zero) and H7 (an imported era must not seed the chronic leg).
final class SourceFusionOverlayTests: XCTestCase {

    private let epoch = DayKey.parseUTC("2026-03-01")!

    private func key(_ offset: Int) -> String {
        DayKey.utc(DayKey.utcCalendar.date(byAdding: .day, value: offset, to: epoch)!)
    }

    private func row(_ offset: Int, strain: Double?) -> DailyMetric {
        DailyMetric(day: key(offset), totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: strain, exerciseCount: nil)
    }

    /// A session on day `offset`, 18:00–19:00 local-agnostic (the timestamps only decide overlap).
    private func load(_ offset: Int, strain: Double?, estimated: Bool = true,
                      startTs: Int = 1_000_000, durationS: Int = 3600) -> SourceFusion.StrengthDayLoad {
        SourceFusion.StrengthDayLoad(day: key(offset), startTs: startTs, endTs: startTs + durationS,
                                     strain: strain, estimated: estimated)
    }

    // MARK: H5 — sum when disjoint, max when overlapping

    func testDisjointWorkoutsAddInTrimp() {
        let days = [row(0, strain: 12.0)]
        let session = load(0, strain: 10.9, startTs: 1_000_000)
        // Apple's workout that day was a RUN at a different hour: nothing overlaps.
        let run = SourceFusion.WorkoutInterval(startTs: 2_000_000, endTs: 2_003_600)
        let out = SourceFusion.overlayStrengthLoad(days: days, loads: [session], workouts: [run],
                                                   today: key(1))
        let expected = StrainScorer.trimpToStrain(StrainScorer.strainToTrimp(12.0)
                                                  + StrainScorer.strainToTrimp(10.9))
        XCTAssertEqual(out.days.first!.strain!, expected, accuracy: 0.01)
        XCTAssertGreaterThan(out.days.first!.strain!, 12.0)
        XCTAssertEqual(out.estimatedDays, [key(0)])
    }

    func testOverlappingWorkoutTakesMax() {
        let days = [row(0, strain: 12.0)]
        let session = load(0, strain: 10.9, startTs: 1_000_000)
        // The Watch recorded the SAME lifting session: Apple's 12.0 already contains it.
        let mirrored = SourceFusion.WorkoutInterval(startTs: 1_000_600, endTs: 1_004_000)
        let out = SourceFusion.overlayStrengthLoad(days: days, loads: [session], workouts: [mirrored],
                                                   today: key(1))
        XCTAssertEqual(out.days.first!.strain!, 12.0, accuracy: 0.02)
        XCTAssertTrue(out.estimatedDays.isEmpty, "the max came from Apple, not from the estimate")
    }

    // MARK: H6 — trained, load unknown → hold, never a zero

    func testSessionWithoutStrainTurnsRestIntoMissing() {
        let days = [row(0, strain: 0)]
        let out = SourceFusion.overlayStrengthLoad(days: days, loads: [load(0, strain: nil)],
                                                   workouts: [], today: key(1))
        XCTAssertNil(out.days.first!.strain, "a day you trained is not a rest day")
        XCTAssertTrue(out.estimatedDays.isEmpty)
    }

    func testMeasuredDayKeepsItsNumberWhenTheSessionHasNoLoad() {
        let days = [row(0, strain: 9.5)]
        let out = SourceFusion.overlayStrengthLoad(days: days, loads: [load(0, strain: nil)],
                                                   workouts: [], today: key(1))
        XCTAssertEqual(out.days.first!.strain!, 9.5, accuracy: 1e-9)
    }

    // MARK: Closed days only

    func testTodayIsNeverOverlaid() {
        let days = [row(0, strain: 0)]
        let out = SourceFusion.overlayStrengthLoad(days: days, loads: [load(0, strain: 10.9)],
                                                   workouts: [], today: key(0))
        XCTAssertEqual(out.days.first!.strain!, 0, accuracy: 1e-9)
        XCTAssertTrue(out.estimatedDays.isEmpty)
    }

    /// A session that runs past midnight belongs to the day it STARTED (the caller keys it); the
    /// overlay must never spill it onto the next day.
    func testSessionCrossingMidnightKeysToStartDay() {
        let days = [row(0, strain: 0), row(1, strain: 0)]
        let midnight = load(0, strain: 10.9, startTs: 1_000_000, durationS: 5400)
        let out = SourceFusion.overlayStrengthLoad(days: days, loads: [midnight], workouts: [],
                                                   today: key(2))
        XCTAssertGreaterThan(out.days[0].strain!, 10)
        XCTAssertEqual(out.days[1].strain!, 0, accuracy: 1e-9)
    }

    // MARK: H7 — an imported era must not seed the chronic leg

    func testOverlayStartsAtFirstBaseRow() {
        // 28 closed Apple days (offsets 1826…1853) — five years of imported sessions sit BEFORE them,
        // in an era with no base rows at all, so every gap there would hold instead of decaying.
        var apple: [DailyMetric] = []
        for i in 0..<28 { apple.append(row(1826 + i, strain: i % 3 == 0 ? 10.0 : 0)) }
        let today = key(1854)
        let baseline = ReadinessEngine.evaluate(days: apple)

        var imported: [SourceFusion.StrengthDayLoad] = []
        for i in stride(from: 0, to: 1825, by: 2) { imported.append(load(i, strain: 10.9)) }
        let out = SourceFusion.overlayStrengthLoad(days: apple, loads: imported, workouts: [],
                                                   today: today)
        let after = ReadinessEngine.evaluate(days: out.days)

        XCTAssertEqual(out.days.count, apple.count, "no synthetic row before the first base row")
        XCTAssertNotNil(baseline.acwr)
        XCTAssertEqual(after.acwr!, baseline.acwr!, accuracy: 0.05)
    }

    /// With no base history at all, the overlay may still synthesize — but only inside the trailing
    /// window, so an import can't invent five years of training history for the chronic leg.
    func testWithoutAnyBaseRowOnlyTheTrailingWindowIsSynthesized() {
        let today = key(1854)
        var imported: [SourceFusion.StrengthDayLoad] = []
        for i in stride(from: 0, to: 1854, by: 2) { imported.append(load(i, strain: 10.9)) }
        let out = SourceFusion.overlayStrengthLoad(days: [], loads: imported, workouts: [], today: today)
        XCTAssertFalse(out.days.isEmpty)
        XCTAssertGreaterThanOrEqual(out.days.first!.day,
                                    key(1854 - SourceFusion.strengthOverlayFallbackWindowDays))
    }

    // MARK: The whole point — estimated days are ACTIVE days for the ACWR

    func testEstimatedDaysCountAsActive() {
        // 14 closed days that Apple read as rest; on four of them the user lifted without a watch.
        var days: [DailyMetric] = []
        for i in 0..<14 { days.append(row(i, strain: 0)) }
        let today = key(14)
        XCTAssertNil(ReadinessEngine.evaluate(days: days).acwr,
                     "before the overlay these four sessions were invisible")

        let lifted = [0, 3, 7, 11].map { load($0, strain: 10.9) }
        let out = SourceFusion.overlayStrengthLoad(days: days, loads: lifted, workouts: [], today: today)
        XCTAssertNotNil(ReadinessEngine.evaluate(days: out.days).acwr)
        XCTAssertEqual(out.estimatedDays.count, 4)

        // The same four sessions with no usable load are holds, not activity: still nothing to say.
        let unrated = [0, 3, 7, 11].map { load($0, strain: nil) }
        let held = SourceFusion.overlayStrengthLoad(days: days, loads: unrated, workouts: [], today: today)
        XCTAssertNil(ReadinessEngine.evaluate(days: held.days).acwr)
    }
}
