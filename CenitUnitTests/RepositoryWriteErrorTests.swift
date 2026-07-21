import XCTest
import CenitStore
@testable import Cenit

/// Pins L2-A1b write contracts: `saveManualWorkout` upserts before deleting a replaced row
/// (edit never loses the only copy), and `resetContributedPatrones` wipes every user-contributed
/// partition (journal, experiments, diet adherence, diet-adherence metric series).
@MainActor
final class RepositoryWriteErrorTests: XCTestCase {

    private var store: CenitStore!
    private var repo: Repository!
    private let deviceId = "test-device"

    override func setUp() async throws {
        store = try await CenitStore.inMemory()
        repo = Repository(deviceId: deviceId)
        repo.attachStoreForTesting(store)
    }

    // MARK: - saveManualWorkout order (upsert before delete)

    /// Editing a manual row whose natural key (startTs/sport) changes must land the new row first,
    /// then remove the old one. After a successful edit the new row is present and the old is gone.
    func testSaveManualWorkoutUpsertsBeforeDeleteOnEdit() async throws {
        let old = WorkoutRow(startTs: 1_700_000_000, endTs: 1_700_003_600, sport: "Run",
                             source: "manual", durationS: 3600, energyKcal: 400,
                             avgHr: 140, maxHr: nil, strain: nil, distanceM: nil,
                             zonesJSON: nil, notes: "old")
        try await repo.saveManualWorkout(old)

        let edited = WorkoutRow(startTs: 1_700_000_600, endTs: 1_700_004_200, sport: "Cycle",
                                source: "manual", durationS: 3600, energyKcal: 420,
                                avgHr: 145, maxHr: nil, strain: nil, distanceM: nil,
                                zonesJSON: nil, notes: "edited")
        try await repo.saveManualWorkout(edited, replacing: old)

        let lo = 1_700_000_000 - 100
        let hi = 1_700_004_200 + 100
        let rows = try await store.workouts(deviceId: deviceId, from: lo, to: hi, limit: 50)
        XCTAssertEqual(rows.count, 1, "edit must not leave the old natural key alongside the new one")
        XCTAssertEqual(rows[0].startTs, edited.startTs)
        XCTAssertEqual(rows[0].sport, edited.sport)
        XCTAssertEqual(rows[0].notes, "edited")
        XCTAssertFalse(rows.contains { $0.startTs == old.startTs && $0.sport == old.sport },
                       "the replaced natural key must be gone after a successful edit")
    }

    // MARK: - resetContributedPatrones

    /// Seeds journal + experiment + diet adherence + diet-adherence metric point, resets, and
    /// asserts every contributed partition is empty under `noop-journal`.
    func testResetContributedPatronesWipesJournalExperimentAdherenceAndMetricSeries() async throws {
        let jid = Repository.journalDeviceId

        try await store.upsertJournal(
            [JournalEntry(day: "2026-07-01", question: "alcohol", answeredYes: true, notes: nil)],
            deviceId: jid)

        let exp = ExperimentRow(id: "exp-1", behavior: "alcohol", outcome: "Recovery",
                                expectedSign: -1, startDay: "2026-07-01", windowDays: 7,
                                status: .running, createdAt: 1_700_000_000)
        try await store.upsertExperiment(exp, deviceId: jid)

        try await store.upsertDietAdherence(
            DietAdherenceRow(day: "2026-07-01", mealId: "m1", status: .cumpli),
            deviceId: jid)

        try await store.upsertMetricSeries(
            [MetricPoint(day: "2026-07-01", key: Repository.dietAdherenceKey, value: 80)],
            deviceId: jid)

        // Sanity: seed landed. (awaits bound first: XCTAssert autoclosures aren't async)
        var journalCount = try await store.journalEntries(deviceId: jid, from: "2026-01-01", to: "2026-12-31").count
        var expCount = try await store.experiments(deviceId: jid).count
        var dietCount = try await store.dietAdherence(deviceId: jid, day: "2026-07-01").count
        var seriesCount = try await store.metricSeries(deviceId: jid, key: Repository.dietAdherenceKey,
                                                       from: "2026-01-01", to: "2026-12-31").count
        XCTAssertEqual(journalCount, 1)
        XCTAssertEqual(expCount, 1)
        XCTAssertEqual(dietCount, 1)
        XCTAssertEqual(seriesCount, 1)

        try await repo.resetContributedPatrones()

        journalCount = try await store.journalEntries(deviceId: jid, from: "2026-01-01", to: "2026-12-31").count
        expCount = try await store.experiments(deviceId: jid).count
        dietCount = try await store.dietAdherence(deviceId: jid, day: "2026-07-01").count
        seriesCount = try await store.metricSeries(deviceId: jid, key: Repository.dietAdherenceKey,
                                                   from: "2026-01-01", to: "2026-12-31").count
        XCTAssertEqual(journalCount, 0, "native journal must be wiped")
        XCTAssertEqual(expCount, 0, "experiments must be wiped")
        XCTAssertEqual(dietCount, 0, "diet adherence marks must be wiped")
        XCTAssertEqual(seriesCount, 0, "diet-adherence metric series must be wiped")
    }
}
