import XCTest
import GRDB
@testable import WhoopStore

/// FER-29 — verify (and pin) that every hot read uses an index instead of a full-table scan.
///
/// The diagnosis was that the three v8 tables "probably already" had their hot reads covered by the
/// composite primary keys. These tests confirm it with `EXPLAIN QUERY PLAN` and act as a regression
/// guard: a future change to a WHERE/ORDER BY that silently dropped the index (forcing a full scan
/// over a multi-year history) would fail here.
///
/// The SQL below mirrors the read methods in Reads.swift / MetricSeriesStore.swift /
/// JournalWorkoutAppleCache.swift / MetricsCache.swift verbatim. The planner picks the same plan
/// regardless of row count, so an empty in-memory store is enough; the bound values are dummies.
final class QueryPlanTests: XCTestCase {

    /// Assert the plan reaches `table` through an index step (`… USING …`) and never via a bare
    /// full-table `SCAN <table>` (a `SCAN … USING COVERING INDEX` is an index scan and is fine).
    private func assertIndexed(_ plan: [String], table: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let joined = plan.joined(separator: " | ")
        let fullScan = plan.contains {
            $0.hasPrefix("SCAN") && $0.contains(table) && !$0.contains("USING")
        }
        XCTAssertFalse(fullScan, "\(table): unexpected full-table SCAN — plan: [\(joined)]",
                       file: file, line: line)
        let indexed = plan.contains {
            ($0.contains("SEARCH") || $0.contains("SCAN")) && $0.contains(table) && $0.contains("USING")
        }
        XCTAssertTrue(indexed, "\(table): expected an indexed access — plan: [\(joined)]",
                      file: file, line: line)
    }

    // MARK: - metricSeries (idx_metricSeries_device_key_day)

    func testMetricSeriesRangeReadUsesIndex() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, key, value FROM metricSeries
            WHERE deviceId = ? AND key = ? AND day >= ? AND day <= ?
            ORDER BY day ASC
            """, arguments: ["d", "recovery", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "metricSeries")
    }

    func testMetricKeysDistinctUsesIndex() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT DISTINCT key FROM metricSeries WHERE deviceId = ? ORDER BY key ASC
            """, arguments: ["d"])
        assertIndexed(plan, table: "metricSeries")
    }

    func testMetricDaysMinMaxUsesIndex() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT MIN(day) AS earliest, MAX(day) AS latest FROM metricSeries
            WHERE deviceId = ? AND key = ?
            """, arguments: ["d", "recovery"])
        assertIndexed(plan, table: "metricSeries")
    }

    // MARK: - v8 cache tables (composite PK)

    func testJournalRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, question, answeredYes, notes FROM journal
            WHERE deviceId = ? AND day >= ? AND day <= ?
            ORDER BY day ASC, question ASC
            """, arguments: ["d", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "journal")
    }

    func testWorkoutsRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT startTs, endTs, sport, source, durationS, energyKcal, avgHr, maxHr,
                   strain, distanceM, zonesJSON, notes FROM workout
            WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
            ORDER BY startTs ASC LIMIT ?
            """, arguments: ["d", 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "workout")
    }

    func testDeleteWorkoutsBySportUsesPrimaryKey() async throws {
        // PK is (deviceId, startTs, sport): deviceId + startTs range seek, sport filtered after —
        // still an indexed search, not a full scan.
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            DELETE FROM workout WHERE deviceId = ? AND sport = ? AND startTs >= ? AND startTs <= ?
            """, arguments: ["d", "detected", 0, 9_999_999_999])
        assertIndexed(plan, table: "workout")
    }

    func testAppleDailyRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, steps, activeKcal, basalKcal, vo2max, avgHr, maxHr, walkingHr, weightKg
            FROM appleDaily
            WHERE deviceId = ? AND day >= ? AND day <= ?
            ORDER BY day ASC
            """, arguments: ["d", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "appleDaily")
    }

    // MARK: - server-metric cache (composite PK)

    func testDailyMetricsRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT day, totalSleepMin, efficiency, deepMin, remMin, lightMin, disturbances,
                   restingHr, avgHrv, recovery, strain, exerciseCount, steps, activeKcalEst
            FROM dailyMetric
            WHERE deviceId = ? AND day >= ? AND day <= ?
            ORDER BY day ASC
            """, arguments: ["d", "2020-01-01", "2030-01-01"])
        assertIndexed(plan, table: "dailyMetric")
    }

    func testSleepSessionsRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT startTs, endTs, efficiency, restingHr, avgHrv, stagesJSON FROM sleepSession
            WHERE deviceId = ? AND endTs >= ? AND startTs <= ?
            ORDER BY startTs ASC LIMIT ?
            """, arguments: ["d", 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "sleepSession")
    }

    // MARK: - biometric streams (PK (deviceId, ts))

    func testHRSamplesRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT ts, bpm FROM hrSample
            WHERE deviceId = ? AND ts >= ? AND ts <= ?
            ORDER BY ts ASC LIMIT ?
            """, arguments: ["d", 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "hrSample")
    }

    func testHRBucketsAggregateUsesPrimaryKey() async throws {
        // The GROUP BY may add a temp b-tree, but the table access itself must stay indexed.
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT (ts / ?) * ? AS bucket, AVG(bpm) AS avgBpm FROM hrSample
            WHERE deviceId = ? AND ts >= ? AND ts <= ?
            GROUP BY ts / ?
            ORDER BY bucket ASC
            """, arguments: [300, 300, "d", 0, 9_999_999_999, 300])
        assertIndexed(plan, table: "hrSample")
    }

    func testLatestHRSampleTsUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest(
            "SELECT MAX(ts) FROM hrSample WHERE deviceId = ?", arguments: ["d"])
        assertIndexed(plan, table: "hrSample")
    }

    // v21 (FER-513): the 1 Hz tables are now WITHOUT ROWID — the PK *is* the table. The range reads must
    // still seek through it, not full-scan. rrInterval is the risky one (3-column PK (deviceId, ts, rrMs)).

    func testRRIntervalsRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT ts, rrMs FROM rrInterval
            WHERE deviceId = ? AND ts >= ? AND ts <= ?
            ORDER BY ts ASC, rrMs ASC LIMIT ?
            """, arguments: [1, 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "rrInterval")
    }

    func testGravitySamplesRangeReadUsesPrimaryKey() async throws {
        let store = try await WhoopStore.inMemory()
        let plan = try await store.queryPlanForTest("""
            SELECT ts, x, y, z FROM gravitySample
            WHERE deviceId = ? AND ts >= ? AND ts <= ?
            ORDER BY ts ASC LIMIT ?
            """, arguments: [1, 0, 9_999_999_999, 100])
        assertIndexed(plan, table: "gravitySample")
    }
}
