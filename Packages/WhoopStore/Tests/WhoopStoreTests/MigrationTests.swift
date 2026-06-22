import XCTest
import GRDB
import StrandTraining
@testable import WhoopStore

final class MigrationTests: XCTestCase {
    func testInMemoryRunsMigrations() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["device", "hrSample", "rrInterval", "event", "battery", "rawBatch"] {
            XCTAssertTrue(tables.contains(t), "missing table \(t)")
        }
    }

    func testFileInitRunsMigrations() async throws {
        let path = NSTemporaryDirectory() + "whoopstore-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try await WhoopStore(path: path)
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("hrSample"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testHrSamplePrimaryKeyIsDeviceIdTs() async throws {
        let store = try await WhoopStore.inMemory()
        let cols = try await store.primaryKeyColumns("hrSample")
        XCTAssertEqual(cols, ["deviceId", "ts"])
    }

    func testRrIntervalPrimaryKeyIncludesRrMs() async throws {
        let store = try await WhoopStore.inMemory()
        let cols = try await store.primaryKeyColumns("rrInterval")
        XCTAssertEqual(cols, ["deviceId", "ts", "rrMs"])
    }

    /// v5 adds a `synced` column to all 8 decoded tables.
    func testV5AddsSyncedColumnToDecodedTables() async throws {
        let store = try await WhoopStore.inMemory()
        for table in ["hrSample", "rrInterval", "event", "battery",
                      "spo2Sample", "skinTempSample", "respSample", "gravitySample"] {
            let cols = try await store.columnNamesForTest(table: table)
            XCTAssertTrue(cols.contains("synced"), "\(table) missing synced column")
        }
        XCTAssertEqual(WhoopStoreInfo.schemaVersion, 18)
    }

    /// v15 (FER-346) adds a nullable `supersetGroup` to `routineExercise` via ALTER ADD COLUMN, and
    /// must be append-only: a DB that only reached v13 upgrades without losing rows, and the old row
    /// gets NULL. Drives the migrator directly (upTo v13 → insert a v13-shaped row → migrate to v15).
    func testV15AddsSupersetGroupAndPreservesV13Rows() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v13")

        // A v13-shaped routine + exercise (no supersetGroup column exists yet).
        try await dbQueue.write { db in
            try db.execute(sql:
                "INSERT INTO routine (id, name, createdTs, updatedTs, sortOrder) VALUES ('r1','Old',0,0,0)")
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, warmupPercents, restMode, restSeconds)
                VALUES ('re1','r1','ex1',0,3,'[]','fixed',90)
                """)
        }

        try migrator.migrate(dbQueue)   // → v15 (through v14 Diet, which doesn't touch routineExercise)

        try await dbQueue.read { db in
            let cols = try db.columns(in: "routineExercise").map(\.name)
            XCTAssertTrue(cols.contains("supersetGroup"), "v15 must add supersetGroup")
            let row = try Row.fetchOne(db, sql: "SELECT supersetGroup FROM routineExercise WHERE id='re1'")
            XCTAssertNotNil(row, "the v13 row must survive the upgrade")
            XCTAssertNil(row?["supersetGroup"] as Int?, "an old row's supersetGroup is NULL (standalone)")
        }

        // Both NULL and an Int insert cleanly post-migration.
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, warmupPercents, restMode, restSeconds, supersetGroup)
                VALUES ('re2','r1','ex2',1,3,'[]','fixed',90,1)
                """)
        }
    }

    /// v16 (FER-401) adds a nullable `optionIndex` to `dietAdherence` via ALTER ADD COLUMN, append-only:
    /// a DB that only reached v14 upgrades without losing rows, and the old row gets NULL.
    func testV16AddsOptionIndexAndPreservesV14Rows() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v14")

        // A v14-shaped adherence row (no optionIndex column exists yet).
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO dietAdherence (deviceId, day, mealId, status, note)
                VALUES ('noop-journal','2026-06-01','m1','cumpli',NULL)
                """)
        }

        try migrator.migrate(dbQueue)   // → v16 (through v15, which doesn't touch dietAdherence)

        try await dbQueue.read { db in
            let cols = try db.columns(in: "dietAdherence").map(\.name)
            XCTAssertTrue(cols.contains("optionIndex"), "v16 must add optionIndex")
            let row = try Row.fetchOne(db, sql: "SELECT optionIndex FROM dietAdherence WHERE mealId='m1'")
            XCTAssertNotNil(row, "the v14 row must survive the upgrade")
            XCTAssertNil(row?["optionIndex"] as Int?, "an old row's optionIndex is NULL")
        }
    }

    /// The chosen equivalent option round-trips through the public store API; a mark without a specific
    /// option (skip) reads back nil.
    func testDietOptionIndexRoundTrip() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: "2026-06-01", mealId: "m1", status: .cumpli, optionIndex: 1),
            deviceId: "noop-journal")
        try await store.upsertDietAdherence(
            DietAdherenceRow(day: "2026-06-01", mealId: "m2", status: .salte),
            deviceId: "noop-journal")
        let rows = try await store.dietAdherence(deviceId: "noop-journal", day: "2026-06-01")
        XCTAssertEqual(rows.first(where: { $0.mealId == "m1" })?.optionIndex, 1)
        XCTAssertNil(rows.first(where: { $0.mealId == "m2" })?.optionIndex)
    }

    /// Superset grouping round-trips through the public store API, in `position` order. `[1, 1, nil]` =
    /// a two-exercise superset followed by a standalone exercise.
    func testSupersetGroupRoundTrip() async throws {
        let store = try await WhoopStore.inMemory()
        let routine = Routine(id: "r1", name: "Empuje", createdTs: 0, updatedTs: 0)
        let exs = [
            RoutineExercise(id: "a", routineId: "r1", exerciseId: "ex1", position: 0, targetSets: 4, supersetGroup: 1),
            RoutineExercise(id: "b", routineId: "r1", exerciseId: "ex2", position: 1, targetSets: 4, supersetGroup: 1),
            RoutineExercise(id: "c", routineId: "r1", exerciseId: "ex3", position: 2, targetSets: 3, supersetGroup: nil),
        ]
        try await store.saveRoutine(routine, exercises: exs)
        let read = try await store.routineExercises(routineId: "r1")
        XCTAssertEqual(read.map(\.supersetGroup), [1, 1, nil])
    }

    /// v17 (FER-492) creates `routineSet` and back-fills it from each existing `routineExercise`'s
    /// target* columns: MAX(targetSets,1) 'work' rows carrying the single legacy reps/weight, 1:1, with
    /// the old routineExercise rows surviving. Drives the migrator (upTo v13 → insert v13 rows → v17).
    func testV17BackfillsRoutineSetsFromTargets() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v13")

        try await dbQueue.write { db in
            try db.execute(sql:
                "INSERT INTO routine (id, name, createdTs, updatedTs, sortOrder) VALUES ('r1','Old',0,0,0)")
            // A 3-set exercise with reps/weight, and a 1-set exercise with both NULL.
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, targetReps, targetWeightKg,
                     warmupPercents, restMode, restSeconds)
                VALUES ('re1','r1','ex1',0,3,8,60.0,'[]','fixed',90)
                """)
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, targetReps, targetWeightKg,
                     warmupPercents, restMode, restSeconds)
                VALUES ('re2','r1','ex2',1,1,NULL,NULL,'[]','fixed',90)
                """)
        }

        try migrator.migrate(dbQueue)   // → v17

        try await dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("routineSet"), "v17 must create routineSet")
            // re1 → exactly 3 work rows, all reps=8 / weight=60, positions 0,1,2.
            let re1 = try Row.fetchAll(db, sql:
                "SELECT * FROM routineSet WHERE routineExerciseId='re1' ORDER BY position")
            XCTAssertEqual(re1.count, 3)
            XCTAssertEqual(re1.map { $0["position"] as Int }, [0, 1, 2])
            XCTAssertTrue(re1.allSatisfy { ($0["reps"] as Int?) == 8 })
            XCTAssertTrue(re1.allSatisfy { ($0["weightKg"] as Double?) == 60.0 })
            XCTAssertTrue(re1.allSatisfy { ($0["kind"] as String) == "work" })
            // re2 → exactly 1 row with NULL reps/weight.
            let re2 = try Row.fetchAll(db, sql: "SELECT * FROM routineSet WHERE routineExerciseId='re2'")
            XCTAssertEqual(re2.count, 1)
            XCTAssertNil(re2.first?["reps"] as Int?)
            XCTAssertNil(re2.first?["weightKg"] as Double?)
            // The old routineExercise rows survive untouched.
            let reCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM routineExercise") ?? 0
            XCTAssertEqual(reCount, 2)
        }
    }

    /// `routineSet` has the (routineExerciseId, position) index, mirroring setEntry's grain.
    func testV17CreatesRoutineSetIndex() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("routineSet"))
        let cols = try await store.columnNamesForTest(table: "routineSet")
        for expected in ["id", "routineExerciseId", "position", "kind", "reps", "weightKg"] {
            XCTAssertTrue(cols.contains(expected), "routineSet missing column \(expected)")
        }
    }

    /// v18 (FER-494) creates `routineFolder` and adds a nullable `folderId` to `routine`.
    func testV18CreatesRoutineFolderAndFolderIdColumn() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("routineFolder"), "v18 must create routineFolder")
        let folderCols = try await store.columnNamesForTest(table: "routineFolder")
        for expected in ["id", "name", "sortOrder"] {
            XCTAssertTrue(folderCols.contains(expected), "routineFolder missing column \(expected)")
        }
        let routineCols = try await store.columnNamesForTest(table: "routine")
        XCTAssertTrue(routineCols.contains("folderId"), "v18 must add routine.folderId")
    }

    /// v18 is append-only: a DB that only reached v17 upgrades without losing routines, and the old
    /// rows get folderId NULL (they fall to «Sin carpeta»). Drives the migrator directly.
    func testV18PreservesRoutinesAndDefaultsFolderIdNull() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v17")

        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO routine (id, name, tag, createdTs, updatedTs, sortOrder)
                VALUES ('r1','Old',NULL,0,0,0)
                """)
        }

        try migrator.migrate(dbQueue)   // → v18

        try await dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT folderId FROM routine WHERE id='r1'")
            XCTAssertNotNil(row, "the v17 routine must survive the upgrade")
            XCTAssertNil(row?["folderId"] as String?, "an old routine's folderId is NULL")
        }
    }

    /// v12 (FER-307) creates the `experiment` table with `id` as the sole primary key.
    func testV12CreatesExperimentTable() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("experiment"), "missing experiment table")
        let pk = try await store.primaryKeyColumns("experiment")
        XCTAssertEqual(pk, ["id"])
        let cols = try await store.columnNamesForTest(table: "experiment")
        for expected in ["behavior", "outcome", "expectedSign", "startDay", "windowDays",
                         "status", "result", "createdAt"] {
            XCTAssertTrue(cols.contains(expected), "experiment missing column \(expected)")
        }
    }

    /// v14 (FER-370) creates `dietPlan` (PK `id`) and `dietAdherence` (PK `deviceId,day,mealId`).
    func testV14CreatesDietTables() async throws {
        let store = try await WhoopStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("dietPlan"), "missing dietPlan table")
        XCTAssertTrue(tables.contains("dietAdherence"), "missing dietAdherence table")

        let planPK = try await store.primaryKeyColumns("dietPlan")
        XCTAssertEqual(planPK, ["id"])
        let planCols = try await store.columnNamesForTest(table: "dietPlan")
        for expected in ["deviceId", "nombre", "idioma", "ciclo", "payloadJSON", "createdAt"] {
            XCTAssertTrue(planCols.contains(expected), "dietPlan missing column \(expected)")
        }

        let adherencePK = try await store.primaryKeyColumns("dietAdherence")
        XCTAssertEqual(adherencePK, ["deviceId", "day", "mealId"])
        let adherenceCols = try await store.columnNamesForTest(table: "dietAdherence")
        for expected in ["status", "note"] {
            XCTAssertTrue(adherenceCols.contains(expected), "dietAdherence missing column \(expected)")
        }
    }
}
