import XCTest
import GRDB
import StrandTraining
import WhoopProtocol
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

    /// v5 added `synced` to 8 decoded tables; v21 (FER-513) drops it from the 5 rebuilt 1 Hz tables but
    /// leaves it on event/battery/spo2Sample (not rebuilt). Drives the migrator to see both states.
    func testV5AddsSyncedColumnToDecodedTables() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()

        // At v20, all 8 v5 tables still carry `synced`.
        try migrator.migrate(dbQueue, upTo: "v20")
        try await dbQueue.read { db in
            for table in ["hrSample", "rrInterval", "event", "battery",
                          "spo2Sample", "skinTempSample", "respSample", "gravitySample"] {
                XCTAssertTrue(try db.columns(in: table).map(\.name).contains("synced"),
                              "\(table) missing synced at v20")
            }
        }

        // After v21, the 5 rebuilt tables drop `synced`; the non-rebuilt v5 tables keep it.
        try migrator.migrate(dbQueue)
        try await dbQueue.read { db in
            for table in ["hrSample", "rrInterval", "skinTempSample", "respSample", "gravitySample"] {
                XCTAssertFalse(try db.columns(in: table).map(\.name).contains("synced"),
                               "\(table) should drop synced at v21")
            }
            for table in ["event", "battery", "spo2Sample"] {
                XCTAssertTrue(try db.columns(in: table).map(\.name).contains("synced"),
                              "\(table) keeps synced (not rebuilt)")
            }
        }
        XCTAssertEqual(WhoopStoreInfo.schemaVersion, 26)
    }

    /// v23 (FER-531): the weekly-split table exists with `weekday` as its PRIMARY KEY (one routine per
    /// day), and the migration is append-only — the prior routine/folder tables still stand.
    func testV23CreatesWeeklySplitTableWithWeekdayPK() async throws {
        let store = try await WhoopStore.inMemory()   // migrated to v23
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("routineSchedule"), "v23 must create routineSchedule")
        for prior in ["routine", "routineFolder", "routineExercise", "learnedExerciseAlias"] {
            XCTAssertTrue(tables.contains(prior), "v23 is append-only — \(prior) must survive")
        }
        let pk = try await store.primaryKeyColumns("routineSchedule")
        XCTAssertEqual(pk, ["weekday"], "weekday is the PK → at most one routine per day")
    }

    /// v23 preserves existing data: seed a routine + folder at v22, migrate to v23, and assert the rows
    /// survive intact (the split is a brand-new table — it must not disturb prior data on upgrade).
    func testV23PreservesExistingRoutineRows() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v22")
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO routineFolder (id, name, sortOrder) VALUES ('f1', 'Empuje', 0)")
            try db.execute(sql: """
                INSERT INTO routine (id, name, folderId, createdTs, updatedTs, sortOrder)
                VALUES ('rt1', 'Torso', 'f1', 0, 0, 0)
                """)
        }
        try migrator.migrate(dbQueue)   // → v23
        try await dbQueue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM routine WHERE id = 'rt1'"), "Torso")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT folderId FROM routine WHERE id = 'rt1'"), "f1")
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM routineFolder WHERE id = 'f1'"), "Empuje")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM routineSchedule"), 0, "new split starts empty")
        }
    }

    /// v24 (FER-541): the exercise-type-override table exists with `exerciseId` as its PRIMARY KEY (one
    /// override per exercise), append-only — the prior strength tables still stand.
    func testV24CreatesOverrideTableAppendOnly() async throws {
        let store = try await WhoopStore.inMemory()   // migrated to v24
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("exerciseTypeOverride"), "v24 must create exerciseTypeOverride")
        for prior in ["customExercise", "routine", "routineExercise", "setEntry", "routineSchedule"] {
            XCTAssertTrue(tables.contains(prior), "v24 is append-only — \(prior) must survive")
        }
        let pk = try await store.primaryKeyColumns("exerciseTypeOverride")
        XCTAssertEqual(pk, ["exerciseId"], "exerciseId is the PK → at most one override per exercise")
    }

    /// v25 (FER-712): the circadianPhase table exists with a (deviceId, day) composite PK (≤ 1 record per
    /// day), append-only — every prior table still stands.
    func testV25CreatesCircadianPhaseTableAppendOnly() async throws {
        let store = try await WhoopStore.inMemory()   // migrated to v25
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("circadianPhase"), "v25 must create circadianPhase")
        for prior in ["hrSample", "experiment", "exerciseTypeOverride", "routineSchedule"] {
            XCTAssertTrue(tables.contains(prior), "v25 is append-only — \(prior) must survive")
        }
        let pk = try await store.primaryKeyColumns("circadianPhase")
        XCTAssertEqual(pk, ["deviceId", "day"], "PK is (deviceId, day) → at most one record per day")
        XCTAssertEqual(WhoopStoreInfo.schemaVersion, 26)
    }

    /// v25 upsert is idempotent by (deviceId, day): writing the same day twice keeps one row, latest wins.
    func testV25UpsertIsIdempotentPerDay() async throws {
        let store = try await WhoopStore.inMemory()
        let first = CircadianPhaseRow(day: "2026-07-05", tempMinHour: 5.5, acrophaseHours: 15,
                                      offsetMinutes: 23, confidence: "solid", daysObserved: 20,
                                      bedtimeHour: 23.3, wakeHour: 7, computedAt: 1)
        try await store.upsertCircadianPhase(first, deviceId: "dev")
        let updated = CircadianPhaseRow(day: "2026-07-05", tempMinHour: 4.0, acrophaseHours: 13,
                                        offsetMinutes: -30, confidence: "wide", daysObserved: 9,
                                        bedtimeHour: 22.0, wakeHour: 7, computedAt: 2)
        try await store.upsertCircadianPhase(updated, deviceId: "dev")
        let latest = try await store.latestCircadianPhase(deviceId: "dev")
        XCTAssertEqual(latest, updated)   // second write overwrote the first, not appended
    }

    /// v24 preserves existing data: seed a custom exercise at v23, migrate to v24, assert it survives and
    /// the new override table starts empty (a brand-new table must not disturb prior data on upgrade).
    func testV24PreservesExistingData() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v23")
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO customExercise (id, name, type, equipment, primaryMuscles, secondaryMuscles, cues)
                VALUES ('cx1', 'Mi ejercicio', 'weightReps', 'barbell', '[]', '[]', '[]')
                """)
        }
        try migrator.migrate(dbQueue)   // → v24
        try await dbQueue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM customExercise WHERE id = 'cx1'"), "Mi ejercicio")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exerciseTypeOverride"), 0, "new override table starts empty")
        }
    }

    /// v22 (FER-523) adds the learned-exercise-alias table; the CRUD round-trips and re-mapping a name
    /// overwrites (PK on the normalized name).
    func testV22LearnedAliasTableRoundTripsAndOverwrites() async throws {
        let store = try await WhoopStore.inMemory()   // migrated to v22
        // A successful read proves the table exists (it'd throw otherwise); it starts empty.
        var aliases = try await store.learnedExerciseAliases()
        XCTAssertTrue(aliases.isEmpty)

        try await store.saveLearnedExerciseAlias(name: "press plano", exerciseId: "Some_Id", ts: 100)
        try await store.saveLearnedExerciseAlias(name: "sentadilla rara", exerciseId: "Squat_Id", ts: 100)
        aliases = try await store.learnedExerciseAliases()
        XCTAssertEqual(aliases["press plano"], "Some_Id")
        XCTAssertEqual(aliases["sentadilla rara"], "Squat_Id")

        // Re-mapping the same normalized name overwrites (one mapping per name).
        try await store.saveLearnedExerciseAlias(name: "press plano", exerciseId: "Other_Id", ts: 200)
        aliases = try await store.learnedExerciseAliases()
        XCTAssertEqual(aliases["press plano"], "Other_Id")
        XCTAssertEqual(aliases.count, 2)
    }

    /// v21 (FER-513) rebuilds the five 1 Hz tables as WITHOUT ROWID + integer `deviceId`, with ZERO data
    /// loss: seed at v20 (TEXT deviceId), migrate to v21, assert structure + preserved counts + the int
    /// surrogate + preserved natural PKs.
    func testV21RebuildsWithoutRowidIntDeviceIdNoLoss() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v20")
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES ('my-whoop',1,60),('my-whoop',2,61)")
            try db.execute(sql: "INSERT INTO rrInterval (deviceId, ts, rrMs) VALUES ('my-whoop',1,800),('my-whoop',1,820)")
            try db.execute(sql: "INSERT INTO skinTempSample (deviceId, ts, raw) VALUES ('my-whoop',1,900)")
            try db.execute(sql: "INSERT INTO respSample (deviceId, ts, raw) VALUES ('my-whoop',1,3000)")
            try db.execute(sql: "INSERT INTO gravitySample (deviceId, ts, x, y, z) VALUES ('my-whoop',1,0.1,0.2,0.3)")
        }

        try migrator.migrate(dbQueue)   // → v21

        try await dbQueue.read { db in
            for t in ["hrSample", "rrInterval", "skinTempSample", "respSample", "gravitySample"] {
                let sql = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = ?", arguments: [t]) ?? ""
                XCTAssertTrue(sql.contains("WITHOUT ROWID"), "\(t) must be WITHOUT ROWID — sql: \(sql)")
                XCTAssertThrowsError(try Int.fetchOne(db, sql: "SELECT rowid FROM \(t)"), "\(t) must have no rowid")
            }
            // Zero loss: counts preserved exactly.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rrInterval"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM skinTempSample"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM respSample"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gravitySample"), 1)
            // deviceId is now an INTEGER, mapped via deviceIdMap.
            let myId = try Int64.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'my-whoop'")
            XCTAssertNotNil(myId)
            XCTAssertEqual(try Int64.fetchOne(db, sql: "SELECT deviceId FROM hrSample LIMIT 1"), myId)
            // Natural PKs preserved → ON CONFLICT DO NOTHING still dedupes.
            XCTAssertEqual(try db.primaryKey("hrSample").columns, ["deviceId", "ts"])
            XCTAssertEqual(try db.primaryKey("rrInterval").columns, ["deviceId", "ts", "rrMs"])
        }
    }

    /// Post-v21 the public String-keyed API round-trips through the integer surrogate, and the WRITE
    /// path maps a never-seen deviceId ON DEMAND (no `upsertDevice` first) — so the Backfiller, which
    /// acks+trims history even if `insert` fails, can never lose acked data to a missing mapping.
    func testV21StringApiRoundTripAndOnDemandMapping() async throws {
        let store = try await WhoopStore.inMemory()   // migrated to v21
        _ = try await store.insert(
            Streams(hr: [HRSample(ts: 1, bpm: 60), HRSample(ts: 2, bpm: 61)],
                    rr: [RRInterval(ts: 1, rrMs: 800)],
                    gravity: [GravitySample(ts: 1, x: 0.1, y: 0.2, z: 0.3)]),
            deviceId: "dev1")   // never registered via upsertDevice
        let hr = try await store.hrSamples(deviceId: "dev1", from: 0, to: 10, limit: 100)
        XCTAssertEqual(hr, [HRSample(ts: 1, bpm: 60), HRSample(ts: 2, bpm: 61)])
        let grav = try await store.gravitySamples(deviceId: "dev1", from: 0, to: 10, limit: 100)
        XCTAssertEqual(grav, [GravitySample(ts: 1, x: 0.1, y: 0.2, z: 0.3)])
        // A different, also-unseen deviceId is isolated (its own surrogate; reads empty).
        let other = try await store.hrSamples(deviceId: "dev2", from: 0, to: 10, limit: 100)
        XCTAssertTrue(other.isEmpty)
    }

    /// Atomicity: if v21 fails mid-way (here: a needed table is missing so its INSERT…SELECT throws after
    /// earlier tables were already rebuilt in the same transaction), GRDB ROLLBACKs the WHOLE migration —
    /// `grdb_migrations` never records v21, the already-touched tables revert to their v20 shape, and
    /// `deviceIdMap` is gone. Proves the irreversible rebuild is all-or-nothing.
    func testV21IsAtomicOnFailure() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v20")
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES ('my-whoop', 1, 60)")
            // Sabotage: drop a table v21 rebuilds AFTER hrSample, so its INSERT…SELECT throws mid-migration.
            try db.execute(sql: "DROP TABLE gravitySample")
        }

        XCTAssertThrowsError(try migrator.migrate(dbQueue), "v21 must fail when gravitySample is missing")

        try await dbQueue.read { db in
            // hrSample reverted to its v20 shape: still a rowid table, still has `synced`, row intact.
            XCTAssertNoThrow(try Int.fetchOne(db, sql: "SELECT rowid FROM hrSample"), "hrSample must still be a rowid table")
            XCTAssertTrue(try db.columns(in: "hrSample").map(\.name).contains("synced"), "hrSample `synced` must survive the rollback")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample"), 1)
            // deviceIdMap was created inside the rolled-back transaction → must not exist.
            XCTAssertNil(try Int.fetchOne(db, sql: "SELECT 1 FROM sqlite_master WHERE name = 'deviceIdMap'"))
            // v21 not recorded; v20 is.
            let applied = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
            XCTAssertFalse(applied.contains("v21"), "grdb_migrations must not record a rolled-back v21")
            XCTAssertTrue(applied.contains("v20"))
        }
    }

    /// After v21 (WITHOUT ROWID + int deviceId) + a VACUUM, the file SHRINKS materially — the structural
    /// win the issue exists for. Bloat hr on a real file, migrate, vacuum, assert page_count drops.
    func testV21PlusVacuumShrinksFile() async throws {
        let path = NSTemporaryDirectory() + "whoopstore-v21vac-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let dbQueue = try DatabaseQueue(path: path)
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v20")
        try await dbQueue.write { db in
            for i in 0..<20_000 {
                try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES (?,?,?)",
                               arguments: ["my-whoop", i, 60])
            }
        }
        let before = try await dbQueue.read { db in try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0 }

        try migrator.migrate(dbQueue)   // → v21 rebuilds hrSample WITHOUT ROWID + int deviceId
        try await dbQueue.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }

        let after = try await dbQueue.read { db in try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0 }
        XCTAssertLessThan(after, before * 2 / 3,
                          "WITHOUT ROWID + int deviceId + VACUUM must shrink the file (page_count before=\(before) after=\(after))")
    }

    /// v20 (FER-511) DELETEs the write-only `spo2Sample` rows and KEEPS the (now-empty) table. Append-only:
    /// a DB that reached v19 with spo2 + the other four 1 Hz streams upgrades, spo2 ends empty, the table
    /// still exists, and every other decoded stream is preserved untouched.
    func testV20PurgesSpo2AndPreservesOtherStreams() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v19")

        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO spo2Sample (deviceId, ts, red, ir) VALUES ('d',1,10,20),('d',2,11,21)")
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES ('d',1,60),('d',2,61)")
            try db.execute(sql: "INSERT INTO skinTempSample (deviceId, ts, raw) VALUES ('d',1,900)")
            try db.execute(sql: "INSERT INTO respSample (deviceId, ts, raw) VALUES ('d',1,3000)")
            try db.execute(sql: "INSERT INTO gravitySample (deviceId, ts, x, y, z) VALUES ('d',1,0.1,0.2,0.3)")
            try db.execute(sql: "INSERT INTO rrInterval (deviceId, ts, rrMs) VALUES ('d',1,800)")
        }

        try migrator.migrate(dbQueue)   // → v20

        try await dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("spo2Sample"), "v20 keeps the (empty) spo2Sample table")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM spo2Sample"), 0, "v20 purges spo2 rows")
            // Every other decoded stream is preserved untouched.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample"), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rrInterval"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM skinTempSample"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM respSample"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gravitySample"), 1)
        }
    }

    /// Criterion: after the v20 purge + a VACUUM the file actually SHRINKS (pages returned to the OS),
    /// not just marked reusable. Bloat spo2 on a real file, record page_count, migrate (purge) + VACUUM,
    /// assert page_count drops materially.
    func testV20PlusVacuumShrinksFile() async throws {
        let path = NSTemporaryDirectory() + "whoopstore-vacuum-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let dbQueue = try DatabaseQueue(path: path)
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v19")

        try await dbQueue.write { db in
            for i in 0..<20_000 {
                try db.execute(sql: "INSERT INTO spo2Sample (deviceId, ts, red, ir) VALUES (?,?,?,?)",
                               arguments: ["d", i, 18000, 17000])
            }
        }
        let before = try await dbQueue.read { db in try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0 }

        try migrator.migrate(dbQueue)   // → v20 DELETEs the spo2 rows
        try await dbQueue.writeWithoutTransaction { db in try db.execute(sql: "VACUUM") }

        let after = try await dbQueue.read { db in try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0 }
        XCTAssertLessThan(after, before / 2,
                          "VACUUM must return the purged spo2 pages (page_count before=\(before) after=\(after))")
    }

    /// The public `vacuum()` maintenance method (what AppModel calls once after the v20 purge) runs on a
    /// real file store without throwing — VACUUM must execute outside a transaction.
    func testVacuumMethodRunsOnFileStore() async throws {
        let path = NSTemporaryDirectory() + "whoopstore-vac-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try await WhoopStore(path: path)
        try await store.upsertDevice(id: "d", mac: nil, name: nil)
        try await store.vacuum()   // must not throw
        let pages = try await store.pageCountForTest()
        XCTAssertGreaterThan(pages, 0)
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

    /// v19 (FER-495) adds `hrRestReference`/`hrRestValue` to `routineExercise`; append-only, and an
    /// existing heartRate row gets the FER-348 defaults (`restingMargin` / 0) — zero behavior change.
    func testV19AddsHRRestColumnsWithFER348Defaults() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v18")

        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, warmupPercents, restMode, restSeconds)
                VALUES ('re1','r1','ex1',0,3,'[]','heartRate',90)
                """)
        }

        try migrator.migrate(dbQueue)   // → v19

        try await dbQueue.read { db in
            let cols = try db.columns(in: "routineExercise").map(\.name)
            XCTAssertTrue(cols.contains("hrRestReference"))
            XCTAssertTrue(cols.contains("hrRestValue"))
            let row = try Row.fetchOne(db, sql:
                "SELECT hrRestReference, hrRestValue FROM routineExercise WHERE id='re1'")
            XCTAssertNotNil(row, "the v18 row must survive the upgrade")
            XCTAssertEqual(row?["hrRestReference"] as String?, "restingMargin", "old rows default to FER-348")
            XCTAssertEqual(row?["hrRestValue"] as Double?, 0)
        }
    }

    /// v26 (FER-715) adds four nullable rest columns to `routineSet` and copies each `routineExercise`'s
    /// rest onto ALL its sets, plus nullable energyKcal/energySource to `strengthSession`. Append-only:
    /// old data keeps behavior bit-for-bit (a set inherits its exercise's exact rest), an orphan set (no
    /// parent) stays NULL to inherit at runtime, and a pre-v26 session keeps NULL energy. Drives the
    /// migrator (upTo v25 → insert v25-shaped rows → v26).
    func testV26CopiesExerciseRestToAllSetsAndAddsSessionEnergy() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = WhoopStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v25")

        try await dbQueue.write { db in
            try db.execute(sql:
                "INSERT INTO routine (id, name, createdTs, updatedTs, sortOrder) VALUES ('r1','Old',0,0,0)")
            // An exercise with a NON-default rest, and three sets under it.
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, warmupPercents,
                     restMode, restSeconds, hrRestReference, hrRestValue)
                VALUES ('re1','r1','ex1',0,3,'[]','fixed',120,'peakDrop',0.25)
                """)
            for i in 0..<3 {
                try db.execute(sql: """
                    INSERT INTO routineSet (id, routineExerciseId, position, kind, reps, weightKg)
                    VALUES (?, 're1', ?, 'work', 8, 60.0)
                    """, arguments: ["s\(i)", i])
            }
            // An orphan set: its parent exercise doesn't exist. It must survive with NULL rest.
            try db.execute(sql: """
                INSERT INTO routineSet (id, routineExerciseId, position, kind, reps, weightKg)
                VALUES ('orphan','missing',0,'work',5,40.0)
                """)
            // A pre-v26 session — must keep NULL energy after the upgrade.
            try db.execute(sql: """
                INSERT INTO strengthSession (id, routineId, startTs, endTs, deviceId, strain, avgHr, notes)
                VALUES ('sess1','r1',100,200,'d1',5.5,120,NULL)
                """)
        }

        try migrator.migrate(dbQueue)   // → v26

        try await dbQueue.read { db in
            let setCols = try db.columns(in: "routineSet").map(\.name)
            for expected in ["restMode", "restSeconds", "hrRestReference", "hrRestValue"] {
                XCTAssertTrue(setCols.contains(expected), "v26 must add routineSet.\(expected)")
            }
            // All three sets inherited re1's exact rest — zero behavior change.
            let sets = try Row.fetchAll(db, sql:
                "SELECT * FROM routineSet WHERE routineExerciseId='re1' ORDER BY position")
            XCTAssertEqual(sets.count, 3)
            XCTAssertTrue(sets.allSatisfy { ($0["restMode"] as String?) == "fixed" })
            XCTAssertTrue(sets.allSatisfy { ($0["restSeconds"] as Int?) == 120 })
            XCTAssertTrue(sets.allSatisfy { ($0["hrRestReference"] as String?) == "peakDrop" })
            XCTAssertTrue(sets.allSatisfy { ($0["hrRestValue"] as Double?) == 0.25 })
            // The orphan set survives with NULL rest (it inherits at runtime instead of being lost).
            let orphan = try Row.fetchOne(db, sql: "SELECT * FROM routineSet WHERE id='orphan'")
            XCTAssertNotNil(orphan, "an orphan set must not be dropped")
            XCTAssertNil(orphan?["restMode"] as String?, "an orphan set's rest stays NULL = inherit")
            // No rows lost.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM routineSet") ?? 0, 4)

            // strengthSession gained energy columns; the pre-v26 session keeps NULL for both.
            let sessCols = try db.columns(in: "strengthSession").map(\.name)
            XCTAssertTrue(sessCols.contains("energyKcal"))
            XCTAssertTrue(sessCols.contains("energySource"))
            let sess = try Row.fetchOne(db, sql:
                "SELECT * FROM strengthSession WHERE id='sess1'")
            XCTAssertNotNil(sess, "the pre-v26 session must survive")
            XCTAssertNil(sess?["energyKcal"] as Double?, "a pre-v26 session has NULL energy")
            XCTAssertNil(sess?["energySource"] as String?)
            XCTAssertEqual(sess?["strain"] as Double?, 5.5, "existing columns untouched")
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
