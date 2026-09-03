import XCTest
import GRDB
import StrandTraining
import BiometricStreams
@testable import CenitStore

final class MigrationTests: XCTestCase {
    func testMigratorRegistersContiguousVersions() {
        XCTAssertEqual(CenitStore.makeMigrator().migrations, (1...43).map { "v\($0)" })
        XCTAssertEqual(CenitStoreInfo.schemaVersion, 43)
        XCTAssertEqual(CenitStoreInfo.latestMigration, "v43")
    }

    /// v41 (FER-226): `strengthHrSample` doesn't exist at v40 and does at v41; re-migrating past HEAD
    /// (append-only / migrator idempotence) doesn't throw.
    func testV41CreatesStrengthHrSampleTable() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v40")
        try await dbQueue.read { db in
            XCTAssertFalse(try db.tableExists("strengthHrSample"), "must not exist before v41")
        }
        try migrator.migrate(dbQueue)   // → v41
        try await dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("strengthHrSample"), "v41 must create strengthHrSample")
            XCTAssertEqual(try db.primaryKey("strengthHrSample").columns, ["sessionId", "ts"])
        }
        XCTAssertNoThrow(try migrator.migrate(dbQueue), "re-migrating past HEAD must not throw")
    }

    func testInMemoryRunsMigrations() async throws {
        let store = try await CenitStore.inMemory()
        let tables = try await store.tableNames()
        // F7 (v37): device/event/battery/rawBatch are dropped (band-only, zero live consumer) —
        // covered by testV37DropsDeadBandTablesOnUpgradeAndFresh below.
        for t in ["hrSample", "rrInterval", "cursors", "dailyMetric"] {
            XCTAssertTrue(tables.contains(t), "missing table \(t)")
        }
    }

    /// F7 (reduced scope, "la banda nunca existió"): v37 DROPs the 9 dead band-only raw-stream tables
    /// — on both an upgrade from the pre-v37 schema and a fresh install — while every live table
    /// (dieta/fuerza/sueño/journal/workout/dailyMetric/metricSeries/hrSample/rrInterval/deviceIdMap/
    /// cursors/experiment) survives untouched. Append-only: v1…v36 are not touched by v37.
    func testV37DropsDeadBandTablesOnUpgradeAndFresh() async throws {
        let deadTables = ["device", "event", "battery", "rawBatch",
                          "spo2Sample", "skinTempSample", "respSample", "gravitySample",
                          "stepSample", "circadianPhase"]
        let liveTables = ["hrSample", "rrInterval", "dailyMetric", "metricSeries", "sleepSession",
                          "journal", "workout", "appleDaily", "cursors", "experiment",
                          "dietPlan", "dietAdherence", "customExercise", "routine",
                          "routineExercise", "strengthSession", "setEntry", "personalRecord",
                          "deviceIdMap"]

        // Upgrade path: seed a DB at v36 (old schema, dead tables present) then migrate to HEAD.
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v36")
        try await dbQueue.read { db in
            for t in deadTables {
                XCTAssertTrue(try db.tableExists(t), "\(t) must exist at v36 (pre-drop)")
            }
        }
        try migrator.migrate(dbQueue)   // → v37
        try await dbQueue.read { db in
            for t in deadTables {
                XCTAssertFalse(try db.tableExists(t), "\(t) must be dropped by v37")
            }
            for t in liveTables {
                XCTAssertTrue(try db.tableExists(t), "\(t) must survive v37 (upgrade path)")
            }
        }

        // Fresh install: same end state, reached directly.
        let fresh = try await CenitStore.inMemory()
        let freshTables = try await fresh.tableNames()
        for t in deadTables {
            XCTAssertFalse(freshTables.contains(t), "\(t) must not exist on a fresh install")
        }
        for t in liveTables {
            XCTAssertTrue(freshTables.contains(t), "\(t) must exist on a fresh install")
        }
    }

    func testFileInitRunsMigrations() async throws {
        let path = NSTemporaryDirectory() + "whoopstore-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try await CenitStore(path: path)
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("hrSample"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testHrSamplePrimaryKeyIsDeviceIdTs() async throws {
        let store = try await CenitStore.inMemory()
        let cols = try await store.primaryKeyColumns("hrSample")
        XCTAssertEqual(cols, ["deviceId", "ts"])
    }

    func testRrIntervalPrimaryKeyIncludesRrMs() async throws {
        let store = try await CenitStore.inMemory()
        let cols = try await store.primaryKeyColumns("rrInterval")
        XCTAssertEqual(cols, ["deviceId", "ts", "rrMs"])
    }

    /// v5 added `synced` to 8 decoded tables; v21 (FER-513) drops it from the 5 rebuilt 1 Hz tables but
    /// leaves it on event/battery/spo2Sample (not rebuilt). Drives the migrator to see both states.
    func testV5AddsSyncedColumnToDecodedTables() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()

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
        try migrator.migrate(dbQueue, upTo: "v21")   // pinned — v37 later drops event/battery/spo2Sample
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
    }

    /// v23 (FER-531): the weekly-split table exists with `weekday` as its PRIMARY KEY (one routine per
    /// day), and the migration is append-only — the prior routine/folder tables still stand.
    func testV23CreatesWeeklySplitTableWithWeekdayPK() async throws {
        let store = try await CenitStore.inMemory()   // migrated to v23
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
        let migrator = CenitStore.makeMigrator()
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
        let store = try await CenitStore.inMemory()   // migrated to v24
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("exerciseTypeOverride"), "v24 must create exerciseTypeOverride")
        for prior in ["customExercise", "routine", "routineExercise", "setEntry", "routineSchedule"] {
            XCTAssertTrue(tables.contains(prior), "v24 is append-only — \(prior) must survive")
        }
        let pk = try await store.primaryKeyColumns("exerciseTypeOverride")
        XCTAssertEqual(pk, ["exerciseId"], "exerciseId is the PK → at most one override per exercise")
    }

    /// Pinned to v25 (not HEAD): v37 later DROPs `circadianPhase` (F7, "Tu reloj corporal" retired in
    /// F2) — this only re-verifies v25's OWN historical output, matching the v21/v20 pinning pattern
    /// elsewhere in this file.
    func testV25CreatesCircadianPhaseTableAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        try CenitStore.makeMigrator().migrate(dbQueue, upTo: "v25")
        try await dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("circadianPhase"), "v25 must create circadianPhase")
            for prior in ["hrSample", "experiment", "exerciseTypeOverride", "routineSchedule"] {
                XCTAssertTrue(try db.tableExists(prior), "v25 is append-only — \(prior) must survive")
            }
            XCTAssertEqual(try db.primaryKey("circadianPhase").columns, ["deviceId", "day"],
                           "PK is (deviceId, day) → at most one record per day")
        }
    }

    /// v29 (FER-A): the four load-progression columns exist on `routineExercise`, and a routine seeded at
    /// v28 (before the columns existed) survives the upgrade with progression OFF by default — no data loss.
    func testV29AddsProgressionColumnsAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v28")
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO routine (id, name, folderId, createdTs, updatedTs, sortOrder)
                VALUES ('rt1', 'Torso', NULL, 0, 0, 0)
                """)
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, targetReps, targetWeightKg,
                     warmupPercents, restMode, restSeconds, supersetGroup, hrRestReference, hrRestValue)
                VALUES ('re1', 'rt1', 'squat', 0, 4, 8, 100.0, '[]', 'heartRate', 90, NULL, 'restingMargin', 0)
                """)
        }
        try migrator.migrate(dbQueue)   // → v29
        try await dbQueue.read { db in
            // The prior row survives and reads back with the OFF defaults.
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT progressionEnabled FROM routineExercise WHERE id = 're1'"), 0,
                "pre-v29 exercise defaults to progression OFF")
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT progressionSessions FROM routineExercise WHERE id = 're1'"), 2)
            XCTAssertNil(try Double.fetchOne(db, sql:
                "SELECT progressionIncrementKg FROM routineExercise WHERE id = 're1'"),
                "NULL increment = derive from inventory")
            XCTAssertEqual(try String.fetchOne(db, sql:
                "SELECT progressionDeload FROM routineExercise WHERE id = 're1'"), "propose")
            XCTAssertEqual(try Double.fetchOne(db, sql:
                "SELECT targetWeightKg FROM routineExercise WHERE id = 're1'"), 100.0, "no data loss")
            // v30: the recovery-gate override defaults to 0 (defer on low recovery).
            XCTAssertEqual(try Int.fetchOne(db, sql:
                "SELECT progressionIgnoreRecovery FROM routineExercise WHERE id = 're1'"), 0,
                "pre-v30 exercise defaults to deferring on low recovery")
        }
    }

    /// v31 (FER-835): the progressionOptOut table exists with a (sessionId, exerciseId) composite PK,
    /// append-only — and re-running the migration against a DB that already grew the table (iterating
    /// locally, FER-791 pattern) is a no-op, not a crash.
    func testV31CreatesProgressionOptOutTableAppendOnly() async throws {
        let store = try await CenitStore.inMemory()   // migrated to v31
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("progressionOptOut"), "v31 must create progressionOptOut")
        for prior in ["strengthSession", "setEntry", "routineExercise", "inProgressStrengthSession"] {
            XCTAssertTrue(tables.contains(prior), "v31 is append-only — \(prior) must survive")
        }
        let pk = try await store.primaryKeyColumns("progressionOptOut")
        XCTAssertEqual(pk, ["sessionId", "exerciseId"], "one opt-out row per (session, exercise)")
    }

    /// v31 re-run safety: a DB where the table already exists (pre-created at v30) migrates cleanly.
    func testV31IsNoOpWhenTableAlreadyExists() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v30")
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE progressionOptOut (
                    sessionId TEXT NOT NULL, exerciseId TEXT NOT NULL,
                    PRIMARY KEY (sessionId, exerciseId))
                """)
            try db.execute(sql:
                "INSERT INTO progressionOptOut (sessionId, exerciseId) VALUES ('s1', 'bench')")
        }
        try migrator.migrate(dbQueue)   // → v31, must not crash on the existing table
        try await dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM progressionOptOut"), 1,
                           "the pre-existing row survives the no-op migration")
        }
    }

    /// v24 preserves existing data: seed a custom exercise at v23, migrate to v24, assert it survives and
    /// the new override table starts empty (a brand-new table must not disturb prior data on upgrade).
    func testV24PreservesExistingData() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
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
        let store = try await CenitStore.inMemory()   // migrated to v22
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
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v20")
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES ('my-whoop',1,60),('my-whoop',2,61)")
            try db.execute(sql: "INSERT INTO rrInterval (deviceId, ts, rrMs) VALUES ('my-whoop',1,800),('my-whoop',1,820)")
            try db.execute(sql: "INSERT INTO skinTempSample (deviceId, ts, raw) VALUES ('my-whoop',1,900)")
            try db.execute(sql: "INSERT INTO respSample (deviceId, ts, raw) VALUES ('my-whoop',1,3000)")
            try db.execute(sql: "INSERT INTO gravitySample (deviceId, ts, x, y, z) VALUES ('my-whoop',1,0.1,0.2,0.3)")
        }

        // Pinned to v21: this case asserts v21's OWN output, and v36 later relabels the 'my-whoop'
        // partition to 'strap' (that relabel has its own test below).
        try migrator.migrate(dbQueue, upTo: "v21")

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

    /// v36 (FER-993) relabels the strap source partition 'my-whoop' → 'strap' with ZERO row loss.
    /// Seeds a DB in the **v21 state** (the migration that wrote the 'my-whoop' label) with real rows in
    /// both the integer-surrogate tables and every TEXT-`deviceId` table, migrates to HEAD, and asserts:
    /// every row survives, the label moved, the derived '-noop' partition followed, `workout.source` moved
    /// with it, the surrogate `intId` is UNCHANGED (so the 1 Hz samples still resolve), and a foreign
    /// partition ('apple-health') is untouched.
    func testV36RelabelsStrapPartitionWithoutLosingRows() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v21")

        // The intId v21 assigned to 'my-whoop' — the 1 Hz tables reference it, and it must NOT change.
        let intId = try await dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'my-whoop'")
        }
        XCTAssertNotNil(intId, "v21 must have seeded the 'my-whoop' floor row")

        try await dbQueue.write { db in
            // Integer-surrogate tables (v21 shape): rows point at the map, not at the label.
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES (?,1,60),(?,2,61)",
                           arguments: [intId, intId])
            try db.execute(sql: "INSERT INTO rrInterval (deviceId, ts, rrMs) VALUES (?,1,800)", arguments: [intId])
            // TEXT-deviceId tables, under BOTH the strap label and its derived computed partition.
            try db.execute(sql: """
                INSERT INTO dailyMetric (deviceId, day) VALUES
                ('my-whoop','2026-07-01'), ('my-whoop-noop','2026-07-01'), ('apple-health','2026-07-01')
                """)
            try db.execute(sql: """
                INSERT INTO metricSeries (deviceId, day, key, value) VALUES
                ('my-whoop','2026-07-01','hrv',65.0), ('my-whoop-noop','2026-07-01','steps_est',9000.0),
                ('apple-health','2026-07-01','steps',8000.0)
                """)
            try db.execute(sql: """
                INSERT INTO journal (deviceId, day, question, answeredYes) VALUES ('my-whoop','2026-07-01','alcohol',1)
                """)
            try db.execute(sql: """
                INSERT INTO sleepSession (deviceId, startTs, endTs) VALUES ('my-whoop',100,200), ('my-whoop-noop',300,400)
                """)
            // `device` keeps its partition label in the PRIMARY KEY `id`, not in a `deviceId` column, so
            // the schema sweep walks right past it unless it is handled by name (QA found it orphaned).
            try db.execute(sql: "INSERT INTO device (id, firstSeen) VALUES ('my-whoop',1), ('apple-health',2)")
            // workout: `source` carries the computed partition id for detected bouts.
            try db.execute(sql: """
                INSERT INTO workout (deviceId, startTs, sport, endTs, source) VALUES
                ('my-whoop',1000,'Running',2000,'whoop'),
                ('my-whoop-noop',3000,'detected',4000,'my-whoop-noop'),
                ('apple-health',5000,'Walking',6000,'apple-health')
                """)
        }

        let before = try await dbQueue.read { db in try Self.rowCounts(db) }

        try migrator.migrate(dbQueue, upTo: "v36")   // pinned — v37 later drops `device`, out of scope here

        try await dbQueue.read { db in
            // ZERO loss: every table that existed at v21 has exactly the count it had before the relabel.
            // (v22…v35 CREATE further tables on the way to HEAD; those are new and empty, not our ledger.)
            let after = try Self.rowCounts(db).filter { before.keys.contains($0.key) }
            XCTAssertEqual(after, before, "v36 must not add or drop a single row")

            // The label moved, and the OLD label is gone everywhere.
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT deviceId FROM deviceIdMap WHERE deviceId = 'my-whoop'"))
            // …and the surrogate is unchanged, so the 1 Hz samples still resolve through it.
            XCTAssertEqual(try Int64.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = 'strap'"), intId)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample WHERE deviceId = ?", arguments: [intId]), 2)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rrInterval WHERE deviceId = ?", arguments: [intId]), 1)

            // Every TEXT table relabelled, and the derived '-noop' partition followed its parent.
            for t in ["dailyMetric", "metricSeries", "journal", "sleepSession", "workout"] {
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(t) WHERE deviceId LIKE 'my-whoop%'"), 0,
                               "\(t) must have no row left under the old label")
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dailyMetric WHERE deviceId = 'strap'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dailyMetric WHERE deviceId = 'strap-noop'"), 1)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT value FROM metricSeries WHERE deviceId = 'strap' AND key = 'hrv'"), 65.0)
            XCTAssertEqual(try Double.fetchOne(db, sql: "SELECT value FROM metricSeries WHERE deviceId = 'strap-noop' AND key = 'steps_est'"), 9000.0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sleepSession WHERE deviceId = 'strap-noop'"), 1)

            // workout.source moved in lockstep, so WorkoutSource.classify still reads '-noop' → detected.
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT source FROM workout WHERE sport = 'detected'"), "strap-noop")
            // A legacy import source that merely CONTAINS the brand is not a partition id → untouched.
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT source FROM workout WHERE sport = 'Running'"), "whoop")

            // `device.id` — the PK-as-label case — moved too, so the next connect finds its row instead
            // of writing a fresh one with `firstSeen` reset.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM device WHERE id LIKE 'my-whoop%'"), 0,
                           "device.id must not be left orphaned under the old label")
            XCTAssertEqual(try Int64.fetchOne(db, sql: "SELECT firstSeen FROM device WHERE id = 'strap'"), 1)

            // A foreign partition is never collateral damage.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dailyMetric WHERE deviceId = 'apple-health'"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout WHERE deviceId = 'apple-health'"), 1)
        }
    }

    /// v36 is idempotent and safe on a DB that never held the old label (fresh install): running the
    /// relabel again is a no-op, and the strap partition still resolves.
    func testV36IsIdempotent() async throws {
        let dbQueue = try DatabaseQueue()
        try CenitStore.makeMigrator().migrate(dbQueue, upTo: "v36")   // fresh → v36 (pinned; v37 drops `device`, which `renameDevicePartition` still writes)
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO dailyMetric (deviceId, day) VALUES ('strap','2026-07-01')")
            // Re-run the relabel by hand; nothing matches the old label any more.
            try CenitStore.renameDevicePartition(db, from: "my-whoop", to: "strap")
        }
        try await dbQueue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM dailyMetric WHERE deviceId = 'strap'"), 1)
            XCTAssertEqual(try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM deviceIdMap WHERE deviceId = 'strap'"), 1)
        }
    }

    /// Row count of every user table, keyed by table name — the zero-loss ledger for the v36 relabel.
    private static func rowCounts(_ db: Database) throws -> [String: Int] {
        let tables = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            """)
        return try tables.reduce(into: [:]) { acc, t in
            acc[t] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(t)\"") ?? -1
        }
    }

    /// F7: the gravity leg of this test was removed — `gravitySample` is dropped by v37 (band-only,
    /// zero live consumer), so `insert()` no longer writes it. hr/rr still cover the on-demand mapping.
    func testV21StringApiRoundTripAndOnDemandMapping() async throws {
        let store = try await CenitStore.inMemory()
        _ = try await store.insert(
            Streams(hr: [HRSample(ts: 1, bpm: 60), HRSample(ts: 2, bpm: 61)],
                    rr: [RRInterval(ts: 1, rrMs: 800)]),
            deviceId: "dev1")   // never registered via upsertDevice
        let hr = try await store.hrSamples(deviceId: "dev1", from: 0, to: 10, limit: 100)
        XCTAssertEqual(hr, [HRSample(ts: 1, bpm: 60), HRSample(ts: 2, bpm: 61)])
        let rr = try await store.rrIntervals(deviceId: "dev1", from: 0, to: 10, limit: 100)
        XCTAssertEqual(rr, [RRInterval(ts: 1, rrMs: 800)])
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
        let migrator = CenitStore.makeMigrator()
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
        let migrator = CenitStore.makeMigrator()
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
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v19")

        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO spo2Sample (deviceId, ts, red, ir) VALUES ('d',1,10,20),('d',2,11,21)")
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES ('d',1,60),('d',2,61)")
            try db.execute(sql: "INSERT INTO skinTempSample (deviceId, ts, raw) VALUES ('d',1,900)")
            try db.execute(sql: "INSERT INTO respSample (deviceId, ts, raw) VALUES ('d',1,3000)")
            try db.execute(sql: "INSERT INTO gravitySample (deviceId, ts, x, y, z) VALUES ('d',1,0.1,0.2,0.3)")
            try db.execute(sql: "INSERT INTO rrInterval (deviceId, ts, rrMs) VALUES ('d',1,800)")
        }

        try migrator.migrate(dbQueue, upTo: "v20")   // pinned — v37 later drops these tables

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
        let migrator = CenitStore.makeMigrator()
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
        let store = try await CenitStore(path: path)
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
        let migrator = CenitStore.makeMigrator()
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
        let migrator = CenitStore.makeMigrator()
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
        let store = try await CenitStore.inMemory()
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
        let store = try await CenitStore.inMemory()
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
        let migrator = CenitStore.makeMigrator()
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
        let store = try await CenitStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("routineSet"))
        let cols = try await store.columnNamesForTest(table: "routineSet")
        for expected in ["id", "routineExerciseId", "position", "kind", "reps", "weightKg"] {
            XCTAssertTrue(cols.contains(expected), "routineSet missing column \(expected)")
        }
    }

    /// v18 (FER-494) creates `routineFolder` and adds a nullable `folderId` to `routine`.
    func testV18CreatesRoutineFolderAndFolderIdColumn() async throws {
        let store = try await CenitStore.inMemory()
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
        let migrator = CenitStore.makeMigrator()
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
        let migrator = CenitStore.makeMigrator()
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
        let migrator = CenitStore.makeMigrator()
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

    /// v27 (FER-779): custom exercises gain `bodyParts`/`gifUrl` for the ExerciseDB model. Append-only —
    /// a pre-v27 row survives with the new columns at their defaults (empty parts, no gif), and the v13
    /// `cues` column (reused for `instructions`) is untouched.
    func testV27AddsCustomExerciseColumnsAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v26")

        // A pre-v27 custom exercise (v13 schema: no bodyParts / gifUrl).
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO customExercise (id, name, type, equipment, primaryMuscles, secondaryMuscles, cues)
                VALUES ('ex1','Jalón neutro','weightReps','cable','["lats"]','["biceps"]','["Baja controlado"]')
                """)
        }

        try migrator.migrate(dbQueue)   // → v27

        try await dbQueue.read { db in
            let cols = try db.columns(in: "customExercise").map(\.name)
            XCTAssertTrue(cols.contains("bodyParts"), "v27 must add customExercise.bodyParts")
            XCTAssertTrue(cols.contains("gifUrl"), "v27 must add customExercise.gifUrl")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM customExercise WHERE id='ex1'")
            XCTAssertNotNil(row, "the pre-v27 custom exercise must survive")
            XCTAssertEqual(row?["bodyParts"] as String?, "[]", "new bodyParts column defaults to empty JSON array")
            XCTAssertNil(row?["gifUrl"] as String?, "new gifUrl column defaults to NULL")
            XCTAssertEqual(row?["cues"] as String?, "[\"Baja controlado\"]", "the reused cues column is untouched")
            XCTAssertEqual(row?["name"] as String?, "Jalón neutro", "existing columns untouched")
        }
    }

    /// v27 must be idempotent: if a partial pre-release build already grew `bodyParts`/`gifUrl`
    /// without recording v27, re-running the migration must be a no-op, not a "duplicate column"
    /// crash that wedges startup on every launch.
    func testV27IsIdempotentWhenColumnsAlreadyExist() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v26")

        // Simulate the wedged device: the columns exist but v27 was never recorded.
        try await dbQueue.write { db in
            try db.alter(table: "customExercise") { t in
                t.add(column: "bodyParts", .text).notNull().defaults(to: "[]")
                t.add(column: "gifUrl", .text)
            }
        }

        try migrator.migrate(dbQueue)   // → v27; must not throw

        try await dbQueue.read { db in
            let cols = try db.columns(in: "customExercise").map(\.name)
            XCTAssertTrue(cols.contains("bodyParts"))
            XCTAssertTrue(cols.contains("gifUrl"))
            // The whole point: v27 must now be RECORDED, not just non-throwing — otherwise it would
            // re-run and wedge on every launch. GRDB records it iff the block didn't throw.
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v27"),
                          "v27 must be recorded so it never re-runs and re-wedges startup")
        }
    }

    /// `addColumnIfMissing` (FER-792) is the reusable guard behind idempotent migrations: adding a column
    /// that's absent works; calling it again once the column exists is a silent no-op, never a
    /// "duplicate column" throw.
    func testAddColumnIfMissingIsIdempotent() async throws {
        let dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.create(table: "t") { $0.column("id", .integer).primaryKey() }

            // First call adds the column.
            try CenitStore.addColumnIfMissing(db, "note", on: "t") { $0.add(column: "note", .text) }
            XCTAssertTrue(try db.columns(in: "t").contains { $0.name == "note" }, "first call must add it")

            // Second call, column already present → must NOT throw (a plain ALTER would).
            try CenitStore.addColumnIfMissing(db, "note", on: "t") { $0.add(column: "note", .text) }
            XCTAssertEqual(try db.columns(in: "t").filter { $0.name == "note" }.count, 1,
                           "second call is a no-op, no duplicate column")
        }
    }

    /// v12 (FER-307) creates the `experiment` table with `id` as the sole primary key.
    func testV12CreatesExperimentTable() async throws {
        let store = try await CenitStore.inMemory()
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
        let store = try await CenitStore.inMemory()
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

    /// v28 (FER-798) creates `inProgressStrengthSession` (singleton control table, PK `id`).
    func testV28CreatesInProgressStrengthSessionTable() async throws {
        let store = try await CenitStore.inMemory()
        let tables = try await store.tableNames()
        XCTAssertTrue(tables.contains("inProgressStrengthSession"), "missing inProgressStrengthSession table")
        let pk = try await store.primaryKeyColumns("inProgressStrengthSession")
        XCTAssertEqual(pk, ["id"])
        let cols = try await store.columnNamesForTest(table: "inProgressStrengthSession")
        for expected in ["id", "snapshot", "updatedTs"] {
            XCTAssertTrue(cols.contains(expected), "inProgressStrengthSession missing column \(expected)")
        }
    }

    /// v32 (FER-676) adds the per-score confidence tiers to `dailyMetric`, append-only: a pre-v32 row
    /// survives with both new columns NULL, and existing columns untouched.
    func testV32AddsConfidenceColumnsAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v31")

        // A pre-v32 daily row (no confidence columns yet).
        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO dailyMetric (deviceId, day, strain, totalSleepMin)
                VALUES ('dev1', '2026-07-01', 12.5, 420)
                """)
        }

        try migrator.migrate(dbQueue)   // → v32

        try await dbQueue.read { db in
            let cols = try db.columns(in: "dailyMetric").map(\.name)
            XCTAssertTrue(cols.contains("effortConfidence"), "v32 must add dailyMetric.effortConfidence")
            XCTAssertTrue(cols.contains("restConfidence"), "v32 must add dailyMetric.restConfidence")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM dailyMetric WHERE day='2026-07-01'")
            XCTAssertNotNil(row, "the pre-v32 row must survive")
            XCTAssertNil(row?["effortConfidence"] as String?, "new column defaults to NULL")
            XCTAssertNil(row?["restConfidence"] as String?, "new column defaults to NULL")
            XCTAssertEqual(row?["strain"] as Double?, 12.5, "existing columns untouched")
        }
    }

    /// v32 must be idempotent (FER-791 discipline): columns already present but v32 unrecorded →
    /// re-running records it without a "duplicate column" crash.
    func testV32IsIdempotentWhenColumnsAlreadyExist() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v31")

        try await dbQueue.write { db in
            try db.alter(table: "dailyMetric") { t in
                t.add(column: "effortConfidence", .text)
                t.add(column: "restConfidence", .text)
            }
        }

        try migrator.migrate(dbQueue)   // → v32; must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v32"),
                          "v32 must be recorded so it never re-runs and wedges startup")
        }
    }

    /// The confidence tiers round-trip through upsert → read, and the monotonic COALESCE update
    /// preserves an existing tier when a later partial upsert carries nil (same FER-407 semantics
    /// as every other dailyMetric column).
    func testV32ConfidenceTiersRoundTripAndStayMonotonic() async throws {
        let store = try await CenitStore.inMemory()
        let day = DailyMetric(day: "2026-07-02", totalSleepMin: 420, efficiency: 0.9, deepMin: 70,
                              remMin: 90, lightMin: 200, disturbances: nil, restingHr: 52,
                              avgHrv: 65, recovery: 71, strain: 13.1, exerciseCount: 1,
                              effortConfidence: "solid", restConfidence: "building")
        _ = try await store.upsertDailyMetrics([day], deviceId: "dev1")

        var rows = try await store.dailyMetrics(deviceId: "dev1", from: "2026-07-02", to: "2026-07-02")
        XCTAssertEqual(rows.first?.effortConfidence, "solid")
        XCTAssertEqual(rows.first?.restConfidence, "building")

        // A later partial pass with nil tiers must NOT blank the stored ones.
        let partial = day.with(effortConfidence: .set(nil), restConfidence: .set(nil))
        _ = try await store.upsertDailyMetrics([partial], deviceId: "dev1")
        rows = try await store.dailyMetrics(deviceId: "dev1", from: "2026-07-02", to: "2026-07-02")
        XCTAssertEqual(rows.first?.effortConfidence, "solid", "nil upsert must preserve, not blank")
        XCTAssertEqual(rows.first?.restConfidence, "building", "nil upsert must preserve, not blank")

        // A real new value still overwrites (building → solid as the day accumulates coverage).
        let updated = day.with(restConfidence: .set("solid"))
        _ = try await store.upsertDailyMetrics([updated], deviceId: "dev1")
        rows = try await store.dailyMetrics(deviceId: "dev1", from: "2026-07-02", to: "2026-07-02")
        XCTAssertEqual(rows.first?.restConfidence, "solid", "a non-nil upsert overwrites")
    }

    /// v33 (FER-923): the exercise-catalog remap. Seed history at v32 referencing three kinds of old id —
    /// one WITH a new-catalog match, one legacy id with NO match, one unknown/custom id — then migrate to
    /// v33 and assert: matched refs are rewritten to the new slug across every table (incl. personalRecord's
    /// composite id), the no-match legacy id is materialized as a customExercise (so its refs still resolve),
    /// and the unknown id is left untouched. Invariant: zero orphans — every in-use id resolves.
    func testV33Remap() async throws {
        // Old ExerciseDB ids drawn from the shipped remap/legacy resources:
        let matched = "2gPfomN"        // → "3_4_Sit-Up" (in exercise-id-remap, exists in new catalog)
        let matchedNew = "3_4_Sit-Up"
        let legacy = "Hy9D21L"         // "45° side bend" — in legacy-exercise-data, no new-catalog match
        let unknown = "user-custom-xyz" // in neither map → left as-is (e.g. a user-created custom)

        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v32")
        try await dbQueue.write { db in
            // The unknown id is a genuine user-created custom exercise (the only way it reaches history).
            try db.execute(sql: """
                INSERT INTO customExercise
                    (id, name, type, equipment, primaryMuscles, secondaryMuscles, cues, bodyParts, gifUrl)
                VALUES (?, 'Mi ejercicio', 'weightReps', NULL, '[]', '[]', '[]', '[]', NULL)
                """, arguments: [unknown])
            for id in [matched, legacy, unknown] {
                try db.execute(sql: """
                    INSERT INTO routineExercise
                        (id, routineId, exerciseId, position, targetSets, warmupPercents, restMode, restSeconds)
                    VALUES (?, 'rt1', ?, 0, 3, '[]', 'fixed', 90)
                    """, arguments: ["re-\(id)", id])
                try db.execute(sql: """
                    INSERT INTO setEntry (id, sessionId, exerciseId, position, kind, ts)
                    VALUES (?, 's1', ?, 0, 'work', 0)
                    """, arguments: ["se-\(id)", id])
                try db.execute(sql: """
                    INSERT INTO personalRecord (id, exerciseId, metric, ts)
                    VALUES (?, ?, 'maxWeight', 0)
                    """, arguments: ["\(id):maxWeight", id])
                try db.execute(sql: """
                    INSERT INTO learnedExerciseAlias (name, exerciseId, ts) VALUES (?, ?, 0)
                    """, arguments: ["alias-\(id)", id])
                try db.execute(sql: """
                    INSERT INTO exerciseTypeOverride (exerciseId, type, ts) VALUES (?, 'time', 0)
                    """, arguments: [id])
                try db.execute(sql: """
                    INSERT INTO progressionOptOut (sessionId, exerciseId) VALUES ('s1', ?)
                    """, arguments: [id])
            }
        }

        try migrator.migrate(dbQueue)   // → v33
        try await dbQueue.read { db in
            // Matched id rewritten to the new slug in every plain table.
            for table in ["routineExercise", "setEntry", "learnedExerciseAlias",
                          "exerciseTypeOverride", "progressionOptOut"] {
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE exerciseId = ?",
                                                arguments: [matched]), 0, "\(table): old id must be gone")
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE exerciseId = ?",
                                                arguments: [matchedNew]), 1, "\(table): new slug must be present")
            }
            // personalRecord: exerciseId AND composite id rebuilt.
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT id FROM personalRecord WHERE exerciseId = ?",
                                               arguments: [matchedNew]), "\(matchedNew):maxWeight")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM personalRecord WHERE exerciseId = ?",
                                            arguments: [matched]), 0)

            // Legacy no-match id materialized as a customExercise; its refs left pointing at the same id.
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM customExercise WHERE id = ?",
                                               arguments: [legacy]), "45° side bend")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM setEntry WHERE exerciseId = ?",
                                            arguments: [legacy]), 1, "legacy ref stays, now resolves to custom")

            // Unknown (pre-existing custom) id left untouched — refs kept, custom row not clobbered.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM setEntry WHERE exerciseId = ?",
                                            arguments: [unknown]), 1)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT name FROM customExercise WHERE id = ?",
                                               arguments: [unknown]), "Mi ejercicio")

            // Zero-orphan invariant: every in-use id resolves to the catalog OR a customExercise row.
            let customIds = Set(try String.fetchAll(db, sql: "SELECT id FROM customExercise"))
            var inUse = Set<String>()
            for table in ["routineExercise", "setEntry", "personalRecord",
                          "learnedExerciseAlias", "exerciseTypeOverride", "progressionOptOut"] {
                inUse.formUnion(try String.fetchAll(db, sql: "SELECT DISTINCT exerciseId FROM \(table)"))
            }
            for id in inUse {
                XCTAssertTrue(ExerciseCatalog.byID(id) != nil || customIds.contains(id),
                              "orphan: \(id) resolves to neither catalog nor custom")
            }
        }
    }

    /// v34 (FER-930): setEntry.rpe added append-only, nullable with no default — an existing row must
    /// survive the migration untouched and the new column must read back as NULL, never 0.
    func testV34AddsRpeToSetEntryAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v33")

        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO setEntry (id, sessionId, exerciseId, position, kind, weightKg, reps, done, ts)
                VALUES ('se1', 's1', 'bench-press', 0, 'work', 60, 8, 1, 0)
                """)
        }

        try migrator.migrate(dbQueue)   // → v34

        try await dbQueue.read { db in
            let cols = try db.columns(in: "setEntry").map(\.name)
            XCTAssertTrue(cols.contains("rpe"), "v34 must add setEntry.rpe")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM setEntry WHERE id='se1'")
            XCTAssertNotNil(row, "the pre-v34 row must survive")
            XCTAssertNil(row?["rpe"] as Double?, "new column defaults to NULL, never 0")
            XCTAssertEqual(row?["weightKg"] as Double?, 60, "existing columns untouched")
        }
    }

    /// v34 must be idempotent (FER-791 discipline): column already present but v34 unrecorded →
    /// re-running records it without a "duplicate column" crash.
    func testV34IsIdempotentWhenColumnsAlreadyExist() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v33")

        try await dbQueue.write { db in
            try db.alter(table: "setEntry") { t in
                t.add(column: "rpe", .double)
            }
        }

        try migrator.migrate(dbQueue)   // → v34; must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v34"),
                          "v34 must be recorded so it never re-runs and wedges startup")
        }
    }

    /// v35 (FER-932): the new `strengthExerciseNote` table must exist with its two indices after
    /// migrating from v34.
    func testV35CreatesStrengthExerciseNoteTable() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v34")

        try migrator.migrate(dbQueue)   // → v35

        try await dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("strengthExerciseNote"), "v35 must create strengthExerciseNote")
            let cols = try db.columns(in: "strengthExerciseNote").map(\.name)
            XCTAssertEqual(Set(cols), ["id", "sessionId", "exerciseId", "setPosition", "text", "ts"])
            let indexes = try db.indexes(on: "strengthExerciseNote").map(\.name)
            XCTAssertTrue(indexes.contains("idx_exNote_ex"))
            XCTAssertTrue(indexes.contains("idx_exNote_sess"))
        }
    }

    /// v35 must be idempotent (FER-791 discipline): `CREATE TABLE/INDEX IF NOT EXISTS` means re-running
    /// against a DB that already has the table is a no-op, not a crash.
    func testV35IsIdempotent() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v34")

        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS strengthExerciseNote (
                    id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, exerciseId TEXT NOT NULL,
                    setPosition INTEGER, text TEXT NOT NULL, ts INTEGER NOT NULL)
                """)
        }

        try migrator.migrate(dbQueue)   // → v35; must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v35"),
                          "v35 must be recorded so it never re-runs and wedges startup")
        }
    }

    /// v38 (E13/FER-94): routineSet.repsRangeTop added append-only, nullable with no default — an
    /// existing row must survive the migration untouched and the new column must read back as NULL,
    /// never 0 (NULL = "no range", exactly today's behavior).
    func testV38AddsRepsRangeTopToRoutineSetAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v37")

        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO routineSet (id, routineExerciseId, position, kind, reps, weightKg)
                VALUES ('rs1', 're1', 0, 'work', 8, 60)
                """)
        }

        try migrator.migrate(dbQueue)   // → v38

        try await dbQueue.read { db in
            let cols = try db.columns(in: "routineSet").map(\.name)
            XCTAssertTrue(cols.contains("repsRangeTop"), "v38 must add routineSet.repsRangeTop")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM routineSet WHERE id='rs1'")
            XCTAssertNotNil(row, "the pre-v38 row must survive")
            XCTAssertNil(row?["repsRangeTop"] as Int?, "new column defaults to NULL, never 0")
            XCTAssertEqual(row?["reps"] as Int?, 8, "existing columns untouched")
            XCTAssertEqual(row?["weightKg"] as Double?, 60, "existing columns untouched")
        }
    }

    /// v38 must be idempotent (FER-791/792 discipline): column already present but v38 unrecorded →
    /// re-running records it without a "duplicate column" crash.
    func testV38IsIdempotentWhenColumnsAlreadyExist() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v37")

        try await dbQueue.write { db in
            try db.alter(table: "routineSet") { t in
                t.add(column: "repsRangeTop", .integer)
            }
        }

        try migrator.migrate(dbQueue)   // → v38; must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v38"),
                          "v38 must be recorded so it never re-runs and wedges startup")
        }
    }

    // MARK: - v39 (FER-166): fixed per-exercise note on routineExercise

    /// v39 adds `routineExercise.note` (nullable, append-only via `addColumnIfMissing`): the pre-v39
    /// row survives untouched and the new column reads back NULL, never an empty string.
    func testV39AddsNoteToRoutineExerciseAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v38")

        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, warmupPercents, restMode, restSeconds)
                VALUES ('re1', 'rt1', 'ex1', 0, 3, '[]', 'fixed', 90)
                """)
        }

        try migrator.migrate(dbQueue)   // → v39

        try await dbQueue.read { db in
            let cols = try db.columns(in: "routineExercise").map(\.name)
            XCTAssertTrue(cols.contains("note"), "v39 must add routineExercise.note")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM routineExercise WHERE id='re1'")
            XCTAssertNotNil(row, "the pre-v39 row must survive")
            XCTAssertNil(row?["note"] as String?, "new column defaults to NULL, never empty string")
            XCTAssertEqual(row?["restSeconds"] as Int?, 90, "existing columns untouched")
        }
    }

    /// v39 must be idempotent (FER-791/792 discipline): column already present but v39 unrecorded →
    /// re-running records it without a "duplicate column" crash.
    func testV39IsIdempotentWhenColumnAlreadyExists() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v38")

        try await dbQueue.write { db in
            try db.alter(table: "routineExercise") { t in
                t.add(column: "note", .text)
            }
        }

        try migrator.migrate(dbQueue)   // → v39; must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v39"),
                          "v39 must be recorded so it never re-runs and wedges startup")
        }
    }

    // MARK: - v40 (FER-167): real rest per set on setEntry

    /// v40 adds `setEntry.restTakenS` (nullable, append-only via `addColumnIfMissing`): the pre-v40
    /// row survives untouched and the new column reads back NULL, never a default 0.
    func testV40AddsRestTakenSToSetEntryAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v39")

        try await dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO setEntry (id, sessionId, exerciseId, position, kind, ts)
                VALUES ('se1', 's1', 'bench-press', 0, 'work', 1000)
                """)
        }

        try migrator.migrate(dbQueue)   // → v40

        try await dbQueue.read { db in
            let cols = try db.columns(in: "setEntry").map(\.name)
            XCTAssertTrue(cols.contains("restTakenS"), "v40 must add setEntry.restTakenS")
            let row = try Row.fetchOne(db, sql: "SELECT * FROM setEntry WHERE id='se1'")
            XCTAssertNotNil(row, "the pre-v40 row must survive")
            XCTAssertNil(row?["restTakenS"] as Int?, "new column defaults to NULL, never 0")
            XCTAssertEqual(row?["ts"] as Int?, 1000, "existing columns untouched")
        }
    }

    /// v40 must be idempotent (FER-791/792 discipline): column already present but v40 unrecorded →
    /// re-running records it without a "duplicate column" crash.
    func testV40IsIdempotentWhenColumnAlreadyExists() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v39")

        try await dbQueue.write { db in
            try db.alter(table: "setEntry") { t in
                t.add(column: "restTakenS", .integer)
            }
        }

        try migrator.migrate(dbQueue)   // → v40; must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v40"),
                          "v40 must be recorded so it never re-runs and wedges startup")
        }
    }

    // MARK: - v42 / v43 (ola 1 · FER-324)

    /// v42 must be append-only: rows written before it survive with the new columns NULL (and
    /// `progressionUseRPE` = 0, so no existing routine changes behavior).
    func testV42AddsOla1ColumnsAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v41")

        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO strengthSession (id, startTs) VALUES ('s1', 1000)")
            try db.execute(sql: """
                INSERT INTO routineExercise
                    (id, routineId, exerciseId, position, targetSets, warmupPercents, restMode, restSeconds)
                VALUES ('re1', 'r1', 'bench-press', 0, 3, '[]', 'fixed', 90)
                """)
            try db.execute(sql: """
                INSERT INTO routineSet (id, routineExerciseId, position, kind) VALUES ('rs1', 're1', 0, 'work')
                """)
            try db.execute(sql: """
                INSERT INTO setEntry (id, sessionId, exerciseId, position, kind, ts)
                VALUES ('se1', 's1', 'bench-press', 0, 'work', 1000)
                """)
        }

        try migrator.migrate(dbQueue)   // → v43

        try await dbQueue.read { db in
            let sessionCols = try db.columns(in: "strengthSession").map(\.name)
            for c in ["strainSource", "sessionRpe", "sessionRpeSource", "trimpPerAU", "source", "title",
                      "programWeek", "deload"] {
                XCTAssertTrue(sessionCols.contains(c), "v42 must add strengthSession.\(c)")
            }
            XCTAssertTrue(try db.columns(in: "routineExercise").map(\.name).contains("progressionUseRPE"))
            XCTAssertTrue(try db.columns(in: "routineSet").map(\.name).contains("mode"))
            XCTAssertTrue(try db.columns(in: "setEntry").map(\.name).contains("mode"))

            let s = try Row.fetchOne(db, sql: "SELECT * FROM strengthSession WHERE id='s1'")
            XCTAssertNotNil(s, "the pre-v42 session must survive")
            XCTAssertNil(s?["strainSource"] as String?, "new columns default to NULL")
            XCTAssertNil(s?["sessionRpe"] as Double?, "never a defaulted 7")
            XCTAssertNil(s?["deload"] as Int?)
            let re = try Row.fetchOne(db, sql: "SELECT * FROM routineExercise WHERE id='re1'")
            XCTAssertEqual(re?["progressionUseRPE"] as Int?, 0, "existing routines keep the old rhythm")
            let rs = try Row.fetchOne(db, sql: "SELECT * FROM routineSet WHERE id='rs1'")
            XCTAssertNil(rs?["mode"] as String?, "NULL mode = standard")
            let se = try Row.fetchOne(db, sql: "SELECT * FROM setEntry WHERE id='se1'")
            XCTAssertNil(se?["mode"] as String?)
            XCTAssertEqual(se?["ts"] as Int?, 1000, "existing columns untouched")
        }
    }

    /// v42 must be idempotent (FER-791/792 discipline): all 11 columns already present but v42
    /// unrecorded → re-running records it without a "duplicate column" crash.
    func testV42IsIdempotentWhenColumnsAlreadyExist() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v41")

        try await dbQueue.write { db in
            try db.alter(table: "strengthSession") { t in
                t.add(column: "strainSource", .text); t.add(column: "sessionRpe", .double)
                t.add(column: "sessionRpeSource", .text); t.add(column: "trimpPerAU", .double)
                t.add(column: "source", .text); t.add(column: "title", .text)
                t.add(column: "programWeek", .integer); t.add(column: "deload", .integer)
            }
            try db.alter(table: "routineExercise") { t in
                t.add(column: "progressionUseRPE", .integer).notNull().defaults(to: 0)
            }
            try db.alter(table: "routineSet") { t in t.add(column: "mode", .text) }
            try db.alter(table: "setEntry") { t in t.add(column: "mode", .text) }
        }

        try migrator.migrate(dbQueue)   // → v43; must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v42"),
                          "v42 must be recorded so it never re-runs and wedges startup")
        }
    }

    /// v43 creates the singleton `program` table with its 8 columns; a pre-v43 DB keeps everything else.
    func testV43CreatesProgramTableAppendOnly() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v42")
        try await dbQueue.write { db in
            try db.execute(sql: "INSERT INTO strengthSession (id, startTs) VALUES ('s1', 1000)")
        }

        try migrator.migrate(dbQueue)   // → v43

        try await dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("program"))
            let cols = try db.columns(in: "program").map(\.name)
            XCTAssertEqual(Set(cols), ["id", "name", "weeks", "startTs", "deloadRule", "endMode", "templateId", "createdTs"])
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM strengthSession"), 1)
        }
    }

    /// v43 must be idempotent: the table already there but v43 unrecorded → re-running records it.
    func testV43IsIdempotentWhenTableAlreadyExists() async throws {
        let dbQueue = try DatabaseQueue()
        let migrator = CenitStore.makeMigrator()
        try migrator.migrate(dbQueue, upTo: "v42")
        try await dbQueue.write { db in
            try db.create(table: "program") { t in
                t.column("id", .text).primaryKey(); t.column("name", .text).notNull()
                t.column("weeks", .integer).notNull(); t.column("startTs", .integer).notNull()
                t.column("deloadRule", .text).notNull(); t.column("endMode", .text).notNull()
                t.column("templateId", .text); t.column("createdTs", .integer).notNull()
            }
        }

        try migrator.migrate(dbQueue)   // must not throw

        try await dbQueue.read { db in
            XCTAssertTrue(try migrator.appliedIdentifiers(db).contains("v43"))
        }
    }

    /// The v42 storage contract round-trips through the store: `mode` writes NULL for standard and the
    /// raw value otherwise, and reads back `.standard` for NULL; the session provenance columns survive.
    func testOla1ColumnsRoundTripThroughStore() async throws {
        let store = try await CenitStore.inMemory()
        let routine = Routine(id: "r1", name: "Empuje", createdTs: 0, updatedTs: 0)
        let re = RoutineExercise(id: "re1", routineId: "r1", exerciseId: "bench-press", position: 0,
                                 targetSets: 3, sets: [
                                    RoutineSet(id: "a", position: 0, reps: 8, weightKg: 80),
                                    RoutineSet(id: "b", position: 1, reps: 8, weightKg: 80, mode: .amrap)
                                 ], progressionUseRPE: true)
        try await store.saveRoutine(routine, exercises: [re])
        let back = try await store.routineExercises(routineId: "r1")
        XCTAssertEqual(back.first?.progressionUseRPE, true)
        XCTAssertEqual(back.first?.sets.map(\.mode) ?? [], [SetMode.standard, .amrap])

        let session = StrengthSession(id: "s1", routineId: "r1", startTs: 1000, endTs: 4120, strain: 11.4,
                                      strainSource: .rpe, sessionRpe: 8, sessionRpeSource: .prefill,
                                      trimpPerAU: 0.29, source: "hevy", title: "Push Day",
                                      programWeek: 5, deload: true)
        let sets = [
            SetEntry(id: "e1", sessionId: "s1", exerciseId: "bench-press", position: 0, weightKg: 80, reps: 8, done: true, ts: 1100),
            SetEntry(id: "e2", sessionId: "s1", exerciseId: "bench-press", position: 1, weightKg: 64, reps: 9, done: true, ts: 1200, mode: .drop)
        ]
        try await store.saveSession(session, sets: sets)
        let saved = try await store.session(id: "s1")
        XCTAssertEqual(saved?.strainSource, .rpe)
        XCTAssertEqual(saved?.sessionRpe, 8)
        XCTAssertEqual(saved?.sessionRpeSource, .prefill)
        XCTAssertEqual(saved?.trimpPerAU, 0.29)
        XCTAssertEqual(saved?.source, "hevy")
        XCTAssertEqual(saved?.title, "Push Day")
        XCTAssertEqual(saved?.programWeek, 5)
        XCTAssertEqual(saved?.deload, true)
        let savedSets = try await store.setEntries(sessionId: "s1")
        XCTAssertEqual(savedSets.map(\.mode), [SetMode.standard, .drop])
        // The storage contract is «NULL = standard»: a standard set must persist as NULL, never as the
        // literal 'standard', so a pre-ola-1 reader and a future writer agree on the same byte.
        let rawModes = try await store.dbWriter.read { db in
            try String?.fetchAll(db, sql: "SELECT mode FROM setEntry WHERE sessionId = 's1' ORDER BY position")
        }
        XCTAssertEqual(rawModes, [nil, "drop"])
    }
}
