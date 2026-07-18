import XCTest
import GRDB
@testable import CenitStore

final class JournalWorkoutAppleCacheTests: XCTestCase {

    // MARK: - migration (v8 creates the three tables with the right PKs)

    func testV8CreatesTables() async throws {
        let store = try await CenitStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("journal"))
        XCTAssertTrue(tables.contains("workout"))
        XCTAssertTrue(tables.contains("appleDaily"))

        let journalPK = try await store.primaryKeyColumns("journal")
        XCTAssertEqual(journalPK, ["deviceId", "day", "question"])
        let workoutPK = try await store.primaryKeyColumns("workout")
        XCTAssertEqual(workoutPK, ["deviceId", "startTs", "sport"])
        let applePK = try await store.primaryKeyColumns("appleDaily")
        XCTAssertEqual(applePK, ["deviceId", "day"])
    }

    func testExistingTablesStillPresentAfterV8() async throws {
        let store = try await CenitStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["device", "hrSample", "rrInterval", "event", "battery", "rawBatch",
                  "sleepSession", "dailyMetric"] {
            XCTAssertTrue(tables.contains(t), "v8 must not drop \(t)")
        }
    }

    // MARK: - journal

    func testJournalUpsertReadAndIdempotency() async throws {
        let store = try await CenitStore.inMemory()
        let e = JournalEntry(day: "2026-05-23", question: "Did you drink alcohol?",
                             answeredYes: true, notes: "two beers")
        try await store.upsertJournal([e], deviceId: "devA")

        var rows = try await store.journalEntries(deviceId: "devA", from: "2026-05-01", to: "2026-05-31")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], e)

        // Re-upsert same natural key with changed values → no duplicate, value updated.
        let e2 = JournalEntry(day: "2026-05-23", question: "Did you drink alcohol?",
                              answeredYes: false, notes: nil)
        try await store.upsertJournal([e2], deviceId: "devA")
        rows = try await store.journalEntries(deviceId: "devA", from: "2026-05-01", to: "2026-05-31")
        XCTAssertEqual(rows.count, 1, "same (deviceId,day,question) must not duplicate")
        XCTAssertEqual(rows[0].answeredYes, false)
        XCTAssertNil(rows[0].notes)
    }

    func testDeleteJournalTouchesOnlyTheNamedSource() async throws {
        // The native logging card clears under "noop-journal" only — an identical
        // (day, question) imported under "my-whoop" must survive the clear.
        let store = try await CenitStore.inMemory()
        let e = JournalEntry(day: "2026-06-09", question: "Any alcohol?", answeredYes: true, notes: nil)
        try await store.upsertJournal([e], deviceId: "my-whoop")
        try await store.upsertJournal([e], deviceId: "noop-journal")

        let n = try await store.deleteJournal(deviceId: "noop-journal", day: "2026-06-09",
                                              question: "Any alcohol?")
        XCTAssertEqual(n, 1)
        let imported = try await store.journalEntries(deviceId: "my-whoop",
                                                      from: "2026-06-01", to: "2026-06-30")
        XCTAssertEqual(imported.count, 1, "imported row must be untouched")
        let native = try await store.journalEntries(deviceId: "noop-journal",
                                                    from: "2026-06-01", to: "2026-06-30")
        XCTAssertEqual(native.count, 0)
    }

    func testJournalDistinctQuestionsCoexist() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertJournal([
            JournalEntry(day: "2026-05-23", question: "Caffeine?", answeredYes: true, notes: nil),
            JournalEntry(day: "2026-05-23", question: "Alcohol?", answeredYes: false, notes: nil),
        ], deviceId: "devA")
        let rows = try await store.journalEntries(deviceId: "devA", from: "2026-05-23", to: "2026-05-23")
        XCTAssertEqual(rows.map { $0.question }, ["Alcohol?", "Caffeine?"]) // question ASC
    }

    func testJournalDayRangeAndDeviceFilter() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertJournal([
            JournalEntry(day: "2026-05-01", question: "Q", answeredYes: true, notes: nil),
            JournalEntry(day: "2026-05-20", question: "Q", answeredYes: true, notes: nil),
        ], deviceId: "devA")
        try await store.upsertJournal([
            JournalEntry(day: "2026-05-20", question: "Q", answeredYes: false, notes: nil),
        ], deviceId: "devB")
        let rows = try await store.journalEntries(deviceId: "devA", from: "2026-05-10", to: "2026-05-31")
        XCTAssertEqual(rows.map { $0.day }, ["2026-05-20"])
        XCTAssertEqual(rows[0].answeredYes, true, "must not bleed devB's row")
    }

    func testUpsertJournalReturnsChangeCount() async throws {
        let store = try await CenitStore.inMemory()
        let n = try await store.upsertJournal([
            JournalEntry(day: "2026-05-01", question: "A", answeredYes: true, notes: nil),
            JournalEntry(day: "2026-05-01", question: "B", answeredYes: false, notes: nil),
        ], deviceId: "devA")
        XCTAssertEqual(n, 2)
    }

    // MARK: - workout

    func testWorkoutUpsertReadAndIdempotency() async throws {
        let store = try await CenitStore.inMemory()
        let w = WorkoutRow(startTs: 1_000, endTs: 4_600, sport: "run", source: "apple",
                           durationS: 3600, energyKcal: 520.5, avgHr: 148, maxHr: 176,
                           strain: 12.4, distanceM: 8000, zonesJSON: "{\"z1\":10,\"z2\":40}",
                           notes: "easy")
        try await store.upsertWorkouts([w], deviceId: "devA")

        var rows = try await store.workouts(deviceId: "devA", from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], w)

        // Re-upsert same natural key with updated values → no duplicate, value updated.
        let w2 = WorkoutRow(startTs: 1_000, endTs: 5_000, sport: "run", source: "whoop",
                            durationS: 4000, energyKcal: 600, avgHr: 150, maxHr: 180,
                            strain: 14.0, distanceM: 9000, zonesJSON: nil, notes: nil)
        try await store.upsertWorkouts([w2], deviceId: "devA")
        rows = try await store.workouts(deviceId: "devA", from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(rows.count, 1, "same (deviceId,startTs,sport) must not duplicate")
        XCTAssertEqual(rows[0], w2)
        XCTAssertNil(rows[0].zonesJSON)
        XCTAssertNil(rows[0].notes)
    }

    func testWorkoutDistinctSportSameStartCoexist() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertWorkouts([
            WorkoutRow(startTs: 1_000, endTs: 2_000, sport: "run", source: "apple",
                       durationS: nil, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                       distanceM: nil, zonesJSON: nil, notes: nil),
            WorkoutRow(startTs: 1_000, endTs: 2_000, sport: "cycle", source: "apple",
                       durationS: nil, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                       distanceM: nil, zonesJSON: nil, notes: nil),
        ], deviceId: "devA")
        let rows = try await store.workouts(deviceId: "devA", from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(rows.count, 2, "same startTs but different sport are distinct rows")
    }

    func testWorkoutNullableMetricsRoundTripAsNil() async throws {
        let store = try await CenitStore.inMemory()
        let w = WorkoutRow(startTs: 50, endTs: 60, sport: "yoga", source: "apple",
                           durationS: nil, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                           distanceM: nil, zonesJSON: nil, notes: nil)
        try await store.upsertWorkouts([w], deviceId: "devA")
        let rows = try await store.workouts(deviceId: "devA", from: 0, to: 100, limit: 10)
        XCTAssertEqual(rows.count, 1)
        let r = try XCTUnwrap(rows.first)
        XCTAssertNil(r.durationS); XCTAssertNil(r.energyKcal); XCTAssertNil(r.avgHr)
        XCTAssertNil(r.maxHr); XCTAssertNil(r.strain); XCTAssertNil(r.distanceM)
        XCTAssertNil(r.zonesJSON); XCTAssertNil(r.notes)
    }

    func testWorkoutRangeAndLimit() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertWorkouts([
            WorkoutRow(startTs: 100, endTs: 200, sport: "run", source: "a", durationS: nil,
                       energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                       zonesJSON: nil, notes: nil),
            WorkoutRow(startTs: 500, endTs: 600, sport: "run", source: "a", durationS: nil,
                       energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                       zonesJSON: nil, notes: nil),
            WorkoutRow(startTs: 900, endTs: 1000, sport: "run", source: "a", durationS: nil,
                       energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                       zonesJSON: nil, notes: nil),
        ], deviceId: "devA")
        let ranged = try await store.workouts(deviceId: "devA", from: 400, to: 1000, limit: 100)
        XCTAssertEqual(ranged.map { $0.startTs }, [500, 900])
        let limited = try await store.workouts(deviceId: "devA", from: 0, to: 100_000, limit: 1)
        XCTAssertEqual(limited.map { $0.startTs }, [100], "limit honoured, oldest first")
    }

    func testDeleteWorkoutsBySportAndRange() async throws {
        // Pins deleteWorkouts (detected-workout idempotency, port of WhoopDao.deleteWorkoutsBySport):
        // deletes only the matching (deviceId, sport, startTs-range) rows, leaving other sports,
        // other devices and out-of-range rows untouched.
        let store = try await CenitStore.inMemory()
        func row(_ ts: Int, _ sport: String) -> WorkoutRow {
            WorkoutRow(startTs: ts, endTs: ts + 600, sport: sport, source: "devA-noop",
                       durationS: 600, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                       distanceM: nil, zonesJSON: nil, notes: nil)
        }
        try await store.upsertWorkouts([row(1_000, "detected"), row(2_000, "detected"),
                                        row(1_500, "run")], deviceId: "devA-noop")
        try await store.upsertWorkouts([row(1_200, "detected")], deviceId: "devA")

        let n = try await store.deleteWorkouts(deviceId: "devA-noop", sport: "detected",
                                               from: 0, to: 1_800)
        XCTAssertEqual(n, 1, "only the in-range detected row of the computed source")
        let left = try await store.workouts(deviceId: "devA-noop", from: 0, to: 10_000, limit: 100)
        XCTAssertEqual(left.map { $0.startTs }.sorted(), [1_500, 2_000])
        let other = try await store.workouts(deviceId: "devA", from: 0, to: 10_000, limit: 100)
        XCTAssertEqual(other.count, 1, "other device untouched")
    }

    // MARK: - appleDaily

    func testAppleDailyUpsertReadAndIdempotency() async throws {
        let store = try await CenitStore.inMemory()
        let a = AppleDaily(day: "2026-05-23", steps: 9123, activeKcal: 540.2, basalKcal: 1600.0,
                           vo2max: 48.5, avgHr: 62, maxHr: 171, walkingHr: 98, weightKg: 78.4)
        try await store.upsertAppleDaily([a], deviceId: "devA")

        var rows = try await store.appleDaily(deviceId: "devA", from: "2026-05-01", to: "2026-05-31")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], a)

        // Re-upsert same day with new values → no duplicate, value updated.
        let a2 = AppleDaily(day: "2026-05-23", steps: 10000, activeKcal: 600, basalKcal: 1620,
                            vo2max: 49.0, avgHr: 60, maxHr: 175, walkingHr: 95, weightKg: 78.0)
        try await store.upsertAppleDaily([a2], deviceId: "devA")
        rows = try await store.appleDaily(deviceId: "devA", from: "2026-05-01", to: "2026-05-31")
        XCTAssertEqual(rows.count, 1, "same (deviceId,day) must not duplicate")
        XCTAssertEqual(rows[0], a2)
    }

    func testAppleDailyNullableMetricsRoundTripAsNil() async throws {
        let store = try await CenitStore.inMemory()
        let a = AppleDaily(day: "2026-05-25", steps: nil, activeKcal: nil, basalKcal: nil,
                           vo2max: nil, avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
        try await store.upsertAppleDaily([a], deviceId: "devA")
        let rows = try await store.appleDaily(deviceId: "devA", from: "2026-05-01", to: "2026-05-31")
        XCTAssertEqual(rows.count, 1)
        let r = try XCTUnwrap(rows.first)
        XCTAssertNil(r.steps); XCTAssertNil(r.activeKcal); XCTAssertNil(r.basalKcal)
        XCTAssertNil(r.vo2max); XCTAssertNil(r.avgHr); XCTAssertNil(r.maxHr)
        XCTAssertNil(r.walkingHr); XCTAssertNil(r.weightKg)
    }

    func testAppleDailyDayRangeFilter() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertAppleDaily([
            AppleDaily(day: "2026-05-01", steps: 1, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
            AppleDaily(day: "2026-05-20", steps: 2, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
        ], deviceId: "devA")
        let rows = try await store.appleDaily(deviceId: "devA", from: "2026-05-10", to: "2026-05-31")
        XCTAssertEqual(rows.map { $0.day }, ["2026-05-20"])
    }

    // MARK: - batched multi-row upserts (FER-28)
    // The three upserts batch into multi-row INSERTs. These pin two things the per-row version got
    // for free: (1) a batch larger than one chunk still lands every row, and (2) the same natural key
    // appearing twice in ONE call keeps the LAST value — a single multi-row INSERT…ON CONFLICT can't
    // upsert the same key twice, so the upserts dedup their input first.

    func testJournalBatchAcrossChunkBoundaryInsertsEveryRow() async throws {
        let store = try await CenitStore.inMemory()
        // 350 distinct questions on one day crosses the 150-row journal chunk size (3 statements).
        let rows = (0..<350).map {
            JournalEntry(day: "2026-05-23", question: "q\($0)", answeredYes: $0 % 2 == 0, notes: nil)
        }
        let n = try await store.upsertJournal(rows, deviceId: "devA")
        XCTAssertEqual(n, 350)
        let read = try await store.journalEntries(deviceId: "devA", from: "2026-05-23", to: "2026-05-23")
        XCTAssertEqual(read.count, 350)
    }

    func testJournalIntraBatchDuplicateKeepsLast() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertJournal([
            JournalEntry(day: "2026-05-23", question: "Alcohol?", answeredYes: true, notes: "first"),
            JournalEntry(day: "2026-05-23", question: "Alcohol?", answeredYes: false, notes: "last"),
        ], deviceId: "devA")
        let rows = try await store.journalEntries(deviceId: "devA", from: "2026-05-23", to: "2026-05-23")
        XCTAssertEqual(rows.count, 1, "duplicate natural key in one batch must not error or duplicate")
        XCTAssertEqual(rows[0].answeredYes, false)
        XCTAssertEqual(rows[0].notes, "last")
    }

    func testWorkoutBatchAcrossChunkBoundaryInsertsEveryRow() async throws {
        let store = try await CenitStore.inMemory()
        // 200 distinct startTs crosses the 70-row workout chunk size (3 statements).
        let rows = (1...200).map {
            WorkoutRow(startTs: $0, endTs: $0 + 10, sport: "run", source: "apple", durationS: nil,
                       energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                       zonesJSON: nil, notes: nil)
        }
        let n = try await store.upsertWorkouts(rows, deviceId: "devA")
        XCTAssertEqual(n, 200)
        let read = try await store.workouts(deviceId: "devA", from: 0, to: 100_000, limit: 1_000)
        XCTAssertEqual(read.count, 200)
    }

    func testWorkoutIntraBatchDuplicateKeepsLast() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertWorkouts([
            WorkoutRow(startTs: 1_000, endTs: 2_000, sport: "run", source: "a", durationS: nil,
                       energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                       zonesJSON: nil, notes: "first"),
            WorkoutRow(startTs: 1_000, endTs: 9_999, sport: "run", source: "b", durationS: nil,
                       energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                       zonesJSON: nil, notes: "last"),
        ], deviceId: "devA")
        let rows = try await store.workouts(deviceId: "devA", from: 0, to: 100_000, limit: 100)
        XCTAssertEqual(rows.count, 1, "duplicate natural key in one batch must not error or duplicate")
        XCTAssertEqual(rows[0].endTs, 9_999)
        XCTAssertEqual(rows[0].notes, "last")
    }

    func testAppleDailyBatchAcrossChunkBoundaryInsertsEveryRow() async throws {
        let store = try await CenitStore.inMemory()
        // 200 distinct days crosses the 90-row appleDaily chunk size (3 statements). Day strings are
        // stored as TEXT and only need to be distinct + sortable, so a zero-padded synthetic key works.
        let rows = (0..<200).map {
            AppleDaily(day: String(format: "2030-%03d", $0), steps: $0, activeKcal: nil, basalKcal: nil,
                       vo2max: nil, avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
        }
        let n = try await store.upsertAppleDaily(rows, deviceId: "devA")
        XCTAssertEqual(n, 200)
        let read = try await store.appleDaily(deviceId: "devA", from: "2030-000", to: "2030-999")
        XCTAssertEqual(read.count, 200)
    }

    func testAppleDailyIntraBatchDuplicateKeepsLast() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertAppleDaily([
            AppleDaily(day: "2026-05-23", steps: 1, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
            AppleDaily(day: "2026-05-23", steps: 9_999, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
        ], deviceId: "devA")
        let rows = try await store.appleDaily(deviceId: "devA", from: "2026-05-01", to: "2026-05-31")
        XCTAssertEqual(rows.count, 1, "duplicate natural key in one batch must not error or duplicate")
        XCTAssertEqual(rows[0].steps, 9_999)
    }

    // MARK: - appleHealthCoverage (FER-70)
    // Per-metric import coverage powers the live-sync status panel: how many days each metric carries,
    // the distinct-day span across the two daily tables, and "missing" expressed as an absent key.

    func testAppleHealthCoverageCountsDaysPerMetricAndSpan() async throws {
        let store = try await CenitStore.inMemory()
        // appleDaily: steps both days, active_kcal + avg HR only some; dailyMetric: HRV/sleep/resting
        // both days, SpO₂ one. 2026-05-02 appears in BOTH tables, so distinct days = 3.
        try await store.upsertAppleDaily([
            AppleDaily(day: "2026-05-01", steps: 1_000, activeKcal: 200, basalKcal: nil, vo2max: nil,
                       avgHr: 60, maxHr: 120, walkingHr: nil, weightKg: nil),
            AppleDaily(day: "2026-05-02", steps: 2_000, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: 61, maxHr: nil, walkingHr: nil, weightKg: nil),
        ], deviceId: "apple-health")
        try await store.upsertDailyMetrics([
            DailyMetric(day: "2026-05-02", totalSleepMin: 420, efficiency: nil, deepMin: nil,
                        remMin: nil, lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 40,
                        recovery: nil, strain: nil, exerciseCount: nil, spo2Pct: 96, respRateBpm: nil),
            DailyMetric(day: "2026-05-03", totalSleepMin: 400, efficiency: nil, deepMin: nil,
                        remMin: nil, lightMin: nil, disturbances: nil, restingHr: 54, avgHrv: 42,
                        recovery: nil, strain: nil, exerciseCount: nil, spo2Pct: nil, respRateBpm: nil),
        ], deviceId: "apple-health")

        let cov = try await store.appleHealthCoverage(deviceId: "apple-health")
        XCTAssertEqual(cov.firstDay, "2026-05-01")
        XCTAssertEqual(cov.lastDay, "2026-05-03")
        XCTAssertEqual(cov.totalDays, 3, "distinct days across both tables (2026-05-02 overlaps)")
        XCTAssertEqual(cov.daysByMetric["steps"], 2)
        XCTAssertEqual(cov.daysByMetric["avg_hr"], 2)
        XCTAssertEqual(cov.daysByMetric["active_kcal"], 1)
        XCTAssertEqual(cov.daysByMetric["hrv"], 2)
        XCTAssertEqual(cov.daysByMetric["asleep_min"], 2)
        XCTAssertEqual(cov.daysByMetric["resting_hr"], 2)
        XCTAssertEqual(cov.daysByMetric["spo2"], 1)
        XCTAssertNil(cov.daysByMetric["resp_rate"], "no respiration days → key absent, not 0")
        XCTAssertNil(cov.daysByMetric["vo2max"], "no VO₂max days → key absent, not 0")
    }

    func testAppleHealthCoverageEmptyWhenNothingImported() async throws {
        let store = try await CenitStore.inMemory()
        let cov = try await store.appleHealthCoverage(deviceId: "apple-health")
        XCTAssertNil(cov.firstDay)
        XCTAssertNil(cov.lastDay)
        XCTAssertEqual(cov.totalDays, 0)
        XCTAssertTrue(cov.daysByMetric.isEmpty)
    }

    func testAppleHealthCoverageScopedByDevice() async throws {
        let store = try await CenitStore.inMemory()
        try await store.upsertAppleDaily([
            AppleDaily(day: "2026-05-01", steps: 1_000, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
        ], deviceId: "apple-health")
        try await store.upsertAppleDaily([
            AppleDaily(day: "2026-05-01", steps: 5_000, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
            AppleDaily(day: "2026-05-02", steps: 6_000, activeKcal: nil, basalKcal: nil, vo2max: nil,
                       avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil),
        ], deviceId: "my-whoop")
        let cov = try await store.appleHealthCoverage(deviceId: "apple-health")
        XCTAssertEqual(cov.totalDays, 1, "must not bleed another device's rows")
        XCTAssertEqual(cov.daysByMetric["steps"], 1)
    }
}
