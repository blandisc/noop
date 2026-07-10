import Foundation
import GRDB

/// Thrown inside the v21 migration when a rebuilt table's row count doesn't match the original — a
/// hard stop that forces GRDB to ROLLBACK the whole migration (zero-loss belt; see `registerMigration("v21")`).
enum MigrationError: Error { case rowCountMismatch(table: String, old: Int, new: Int) }

extension WhoopStore {
    /// The schema migrator. v1 creates decoded-stream tables (durable) + the raw outbox.
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "device") { t in
                t.column("id", .text).primaryKey()
                t.column("mac", .text)
                t.column("name", .text)
                t.column("firstSeen", .integer)
                t.column("lastSeen", .integer)
            }
            try db.create(table: "hrSample") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("bpm", .integer).notNull()
                t.primaryKey(["deviceId", "ts"])
            }
            try db.create(table: "rrInterval") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("rrMs", .integer).notNull()
                t.primaryKey(["deviceId", "ts", "rrMs"])
            }
            try db.create(table: "event") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("payloadJSON", .text).notNull()
                t.primaryKey(["deviceId", "ts", "kind"])
            }
            try db.create(table: "battery") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("soc", .double)
                t.column("mv", .integer)
                t.primaryKey(["deviceId", "ts"])
            }
            try db.create(table: "rawBatch") { t in
                t.column("batchId", .text).primaryKey()
                t.column("deviceId", .text).notNull()
                t.column("capturedAt", .integer).notNull()
                t.column("deviceClockRef", .integer).notNull()
                t.column("wallClockRef", .integer).notNull()
                t.column("startTs", .integer).notNull()
                t.column("endTs", .integer).notNull()
                t.column("frameCount", .integer).notNull()
                t.column("byteSize", .integer).notNull()
                t.column("framesBlob", .blob).notNull()
                t.column("syncedAt", .integer)
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "cursors") { t in
                t.column("name", .text).primaryKey()
                t.column("value", .integer)
            }
        }
        migrator.registerMigration("v3") { db in
            // type-47 biometric streams (mirror the existing decoded tables, PK (deviceId, ts)).
            try db.create(table: "spo2Sample") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("red", .integer).notNull()
                t.column("ir", .integer).notNull()
                t.primaryKey(["deviceId", "ts"])
            }
            try db.create(table: "skinTempSample") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("raw", .integer).notNull()
                t.primaryKey(["deviceId", "ts"])
            }
            try db.create(table: "respSample") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("raw", .integer).notNull()
                t.primaryKey(["deviceId", "ts"])
            }
            try db.create(table: "gravitySample") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("x", .double).notNull()
                t.column("y", .double).notNull()
                t.column("z", .double).notNull()
                t.primaryKey(["deviceId", "ts"])
            }
        }
        migrator.registerMigration("v4") { db in
            // Server-derived metrics cached locally (Task 3.1: History = union(phone, server)).
            // sleepSession: one row per sleep session, natural key (deviceId, startTs).
            try db.create(table: "sleepSession") { t in
                t.column("deviceId", .text).notNull()
                t.column("startTs", .integer).notNull()
                t.column("endTs", .integer).notNull()
                t.column("efficiency", .double)
                t.column("restingHr", .integer)
                t.column("avgHrv", .double)
                t.column("stagesJSON", .text)
                t.primaryKey(["deviceId", "startTs"])
            }
            // dailyMetric: one row per calendar day (YYYY-MM-DD), natural key (deviceId, day).
            try db.create(table: "dailyMetric") { t in
                t.column("deviceId", .text).notNull()
                t.column("day", .text).notNull()
                t.column("totalSleepMin", .double)
                t.column("efficiency", .double)
                t.column("deepMin", .double)
                t.column("remMin", .double)
                t.column("lightMin", .double)
                t.column("disturbances", .integer)
                t.column("restingHr", .integer)
                t.column("avgHrv", .double)
                t.column("recovery", .double)
                t.column("strain", .double)
                t.column("exerciseCount", .integer)
                t.primaryKey(["deviceId", "day"])
            }
        }
        migrator.registerMigration("v5") { db in
            // Per-row upload sync flag for the decoded streams (mirrors rawBatch.syncedAt).
            // The OLD upload path used a forward-only highwater per stream, which permanently
            // stranded backfilled (older-ts) rows once the highwater jumped to a recent ts.
            // The fix: `synced` is set to 1 only after a successful upload, so the Uploader can
            // drain WHERE synced=0 regardless of ts order. Existing rows default to 0 → they
            // re-upload once (idempotent server-side), catching up the currently-stranded rows.
            for table in ["hrSample", "rrInterval", "event", "battery",
                          "spo2Sample", "skinTempSample", "respSample", "gravitySample"] {
                try db.alter(table: table) { t in
                    t.add(column: "synced", .integer).notNull().defaults(to: 0)
                }
            }
        }
        migrator.registerMigration("v6") { db in
            // Charging flag for the dense BATTERY_LEVEL-event battery series (nullable: the
            // command-response battery path doesn't report it).
            try db.alter(table: "battery") { t in
                t.add(column: "charging", .boolean)
            }
        }
        migrator.registerMigration("v7") { db in
            // In-sleep signal aggregates cached from /v1/daily so the Sleep tab can display
            // SpO2, skin-temperature deviation, and respiration rate without a network round-trip.
            // All three are nullable: they require sufficient raw biometric data on the server.
            try db.alter(table: "dailyMetric") { t in
                t.add(column: "spo2Pct", .double)
                t.add(column: "skinTempDevC", .double)
                t.add(column: "respRateBpm", .double)
            }
        }
        migrator.registerMigration("v8") { db in
            // Journal, workouts, and Apple-Health daily aggregates.
            // journal: one row per (deviceId, day, question) — user-answered daily prompts.
            try db.create(table: "journal") { t in
                t.column("deviceId", .text).notNull()
                t.column("day", .text).notNull()
                t.column("question", .text).notNull()
                t.column("answeredYes", .integer).notNull()
                t.column("notes", .text)
                t.primaryKey(["deviceId", "day", "question"])
            }
            // workout: one row per (deviceId, startTs, sport). All metric columns nullable.
            try db.create(table: "workout") { t in
                t.column("deviceId", .text).notNull()
                t.column("startTs", .integer).notNull()
                t.column("endTs", .integer).notNull()
                t.column("sport", .text).notNull()
                t.column("source", .text).notNull()
                t.column("durationS", .double)
                t.column("energyKcal", .double)
                t.column("avgHr", .integer)
                t.column("maxHr", .integer)
                t.column("strain", .double)
                t.column("distanceM", .double)
                t.column("zonesJSON", .text)
                t.column("notes", .text)
                t.primaryKey(["deviceId", "startTs", "sport"])
            }
            // appleDaily: Apple-Health-specific daily aggregates, one row per (deviceId, day).
            // All metric columns nullable.
            try db.create(table: "appleDaily") { t in
                t.column("deviceId", .text).notNull()
                t.column("day", .text).notNull()
                t.column("steps", .integer)
                t.column("activeKcal", .double)
                t.column("basalKcal", .double)
                t.column("vo2max", .double)
                t.column("avgHr", .integer)
                t.column("maxHr", .integer)
                t.column("walkingHr", .integer)
                t.column("weightKg", .double)
                t.primaryKey(["deviceId", "day"])
            }
        }
        migrator.registerMigration("v9") { db in
            // Generic long-format metric store: the substrate for a metric explorer where every
            // metric is queryable/comparable uniformly. One row per (deviceId, day, key); `value`
            // is always a REAL so any scalar metric (server-derived, Apple-Health, journal-encoded,
            // …) can be projected into a single tall table and read back by key with no per-metric
            // schema. Natural key (deviceId, day, key).
            try db.create(table: "metricSeries") { t in
                t.column("deviceId", .text).notNull()
                t.column("day", .text).notNull()
                t.column("key", .text).notNull()
                t.column("value", .double).notNull()
                t.primaryKey(["deviceId", "day", "key"])
            }
            // Per-metric range reads scan (deviceId, key) then walk days in order. The PK is
            // (deviceId, day, key) so it can't serve those reads efficiently; this index makes
            // metricSeries(key:from:to:) and metricDays(key:) index-only.
            try db.create(index: "idx_metricSeries_device_key_day",
                          on: "metricSeries", columns: ["deviceId", "key", "day"])
        }

        // v10 (#78): WHOOP5 step_motion_counter persistence (macOS parity with Android's MIGRATION_2_3).
        // Additive only — the strap trims acked history and won't re-send it, so a destructive rebuild
        // would lose it; this preserves every existing row. No `synced` column (unused; see StreamStore).
        migrator.registerMigration("v10") { db in
            try db.create(table: "stepSample") { t in
                t.column("deviceId", .text).notNull()
                t.column("ts", .integer).notNull()
                t.column("counter", .integer).notNull()
                t.primaryKey(["deviceId", "ts"])
            }
        }

        // v11: on-device daily step total + whole-day calorie estimate on dailyMetric (macOS parity
        // with Android's MIGRATION_2_3). Additive only; both nullable, so existing rows are untouched
        // and an old reader that doesn't SELECT them keeps working.
        migrator.registerMigration("v11") { db in
            try db.alter(table: "dailyMetric") { t in
                t.add(column: "steps", .integer)
                t.add(column: "activeKcalEst", .double)
            }
        }

        // v12 (FER-307): N-of-1 experiments. One row per experiment, natural key `id` (UUID).
        // An experiment runs a candidate lever (a logged behavior × an outcome metric) for a fixed
        // window, then a verdict compares the outcome on adherent days against baseline and may
        // promote the lever candidate→proven. Additive only; no existing row is touched. Row status
        // transitions (running → completed/canceled) are ordinary data mutation, like `journal`.
        // MVP is one experiment at a time (enforced by the app), but the table keeps the full history
        // of past experiments. Nullable result columns are filled only when a verdict is computed.
        migrator.registerMigration("v12") { db in
            try db.create(table: "experiment") { t in
                t.column("id", .text).primaryKey()           // UUID string
                t.column("deviceId", .text).notNull()         // source partition (consistent w/ schema)
                t.column("behavior", .text).notNull()         // lever: journal question
                t.column("outcome", .text).notNull()          // target metric label (es-MX)
                t.column("expectedSign", .integer).notNull()  // +1/-1: sign of the candidate's effect
                t.column("startDay", .text).notNull()         // YYYY-MM-DD (local civil day)
                t.column("windowDays", .integer).notNull()    // experiment length (MVP default 7)
                t.column("status", .text).notNull()           // running | completed | canceled
                t.column("result", .text)                     // sustained | notSustained | insufficient
                t.column("effectDelta", .double)              // verdict: meanWith − meanWithout
                t.column("effectSize", .double)               // verdict: Cohen's d
                t.column("pValue", .double)                   // verdict: Welch p
                t.column("nWith", .integer)                   // adherent-day count
                t.column("nWithout", .integer)                // baseline-day count
                t.column("createdAt", .integer).notNull()     // unix seconds
                t.column("decidedAt", .integer)               // unix seconds (verdict time)
            }
        }

        // v13 (FER-345): strength tracker. User-authored, RELATIONAL data with UUID-string PKs —
        // deliberately unlike the sensor streams keyed by (deviceId, ts). Append-only; touches no
        // prior table. The seed exercise catalog is NOT here (it's a bundled resource in
        // StrandTraining); only user-created exercises + routines/sessions/sets/PRs persist.
        // Array fields (muscles, cues, warm-up percents) are GRDB-Codable JSON text columns.
        migrator.registerMigration("v13") { db in
            try db.create(table: "customExercise") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()              // weightReps | bodyweight | time | distance
                t.column("equipment", .text)
                t.column("primaryMuscles", .text).notNull()    // JSON array
                t.column("secondaryMuscles", .text).notNull()  // JSON array
                t.column("cues", .text).notNull()              // JSON array
            }
            try db.create(table: "routine") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("tag", .text)
                t.column("createdTs", .integer).notNull()
                t.column("updatedTs", .integer).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "routineExercise") { t in
                t.column("id", .text).primaryKey()
                t.column("routineId", .text).notNull()
                t.column("exerciseId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("targetSets", .integer).notNull()
                t.column("targetReps", .integer)
                t.column("targetWeightKg", .double)
                t.column("warmupPercents", .text).notNull()    // JSON array
                t.column("restMode", .text).notNull()          // heartRate | fixed
                t.column("restSeconds", .integer).notNull()
            }
            try db.create(index: "idx_routineExercise_routine_pos",
                          on: "routineExercise", columns: ["routineId", "position"])
            try db.create(table: "strengthSession") { t in
                t.column("id", .text).primaryKey()
                t.column("routineId", .text)
                t.column("startTs", .integer).notNull()
                t.column("endTs", .integer)
                t.column("deviceId", .text)                    // strap that supplied HR/strain, if any
                t.column("strain", .double)
                t.column("avgHr", .integer)
                t.column("notes", .text)
            }
            try db.create(table: "setEntry") { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text).notNull()
                t.column("exerciseId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("kind", .text).notNull()              // work | warmup
                t.column("weightKg", .double)
                t.column("reps", .integer)
                t.column("timeS", .double)
                t.column("distanceM", .double)
                t.column("done", .boolean).notNull().defaults(to: false)
                t.column("ts", .integer).notNull()
            }
            try db.create(index: "idx_setEntry_session_pos",
                          on: "setEntry", columns: ["sessionId", "position"])
            try db.create(index: "idx_setEntry_exercise_ts",
                          on: "setEntry", columns: ["exerciseId", "ts"])
            try db.create(table: "personalRecord") { t in
                t.column("id", .text).primaryKey()             // "<exerciseId>:<metric>"
                t.column("exerciseId", .text).notNull()
                t.column("metric", .text).notNull()            // maxWeight | maxReps | maxVolume
                t.column("valueKg", .double)
                t.column("reps", .integer)
                t.column("ts", .integer).notNull()
            }
            try db.create(index: "idx_personalRecord_exercise",
                          on: "personalRecord", columns: ["exerciseId"])
        }

        // v14 (FER-370): prescribed-diet plan + daily adherence. The plan is captured once
        // (noop.diet.v1, via the BYO-LLM / import path in StrandImport) and stored as an OPAQUE
        // JSON payload so WhoopStore needn't understand the nested meals/options; denormalized
        // columns (nombre, idioma, ciclo, createdAt) allow listing without decoding. Adherence
        // mirrors `journal`: one row per (deviceId, day, mealId), tri-state status. Additive only;
        // no existing row is touched.
        migrator.registerMigration("v14") { db in
            try db.create(table: "dietPlan") { t in
                t.column("id", .text).primaryKey()             // app-generated UUID
                t.column("deviceId", .text).notNull()          // source partition (consistent w/ schema)
                t.column("nombre", .text).notNull()
                t.column("idioma", .text).notNull()            // es | en (content language)
                t.column("ciclo", .text).notNull()             // diario
                t.column("payloadJSON", .text).notNull()       // canonical noop.diet.v1 document
                t.column("createdAt", .integer).notNull()      // unix seconds
            }
            try db.create(table: "dietAdherence") { t in
                t.column("deviceId", .text).notNull()
                t.column("day", .text).notNull()               // YYYY-MM-DD (local civil day)
                t.column("mealId", .text).notNull()            // references a DietPlan meal id
                t.column("status", .text).notNull()            // cumpli | sustitui | salte
                t.column("note", .text)
                t.primaryKey(["deviceId", "day", "mealId"])
            }
        }

        // v15 (FER-346): supersets. One nullable column on the v13 `routineExercise` table — same
        // value within a routine = one superset; NULL = a standalone exercise (every v13 row).
        // Append-only: a single ALTER ADD COLUMN, touching no prior migration and no other table.
        migrator.registerMigration("v15") { db in
            try db.alter(table: "routineExercise") { t in
                t.add(column: "supersetGroup", .integer)   // nullable; NULL = standalone exercise
            }
        }

        // v16 (FER-401): which equivalent option was eaten. One nullable column on the v14
        // `dietAdherence` table — the 0-based index into the plan meal's `opciones` array (stable
        // because the plan's payloadJSON is immutable while active); NULL = option not recorded (every
        // v14 row, and any sustitui/salte mark). Append-only ALTER ADD COLUMN, touching no prior
        // migration; does NOT change the apego % (DietAdherence.dayPercent still counts cumpli+sustitui).
        migrator.registerMigration("v16") { db in
            try db.alter(table: "dietAdherence") { t in
                t.add(column: "optionIndex", .integer)   // nullable; NULL = option not recorded
            }
        }

        // v17 (FER-492): per-set routine prescription. `routineSet` mirrors `setEntry`'s grain — one row
        // per planned set, so the plan and the performed log line up. Append-only: a new table + index,
        // touching no prior migration. Back-fill expands each existing `routineExercise` into MAX(targetSets,1)
        // 'work' rows carrying the single legacy reps/weight, so old routines open 1:1 with zero loss; the
        // legacy target* columns stay as derived compatibility fields. `kind` is written 'work' only here
        // (warm-ups stay as warmupPercents, expanded at runtime) but exists so materializing them later
        // needs no migration.
        migrator.registerMigration("v17") { db in
            try db.create(table: "routineSet") { t in
                t.column("id", .text).primaryKey()
                t.column("routineExerciseId", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("kind", .text).notNull()          // work | warmup (v17 writes only 'work')
                t.column("reps", .integer)
                t.column("weightKg", .double)
            }
            try db.create(index: "idx_routineSet_re_pos",
                          on: "routineSet", columns: ["routineExerciseId", "position"])
            // Recursive CTE expands targetSets (>=1) into N positions, carrying the single legacy
            // reps/weight to each. lower(hex(randomblob(16))) gives a stable per-row id.
            try db.execute(sql: """
                WITH RECURSIVE seq(re, pos, n, reps, w) AS (
                    SELECT id, 0, MAX(targetSets, 1), targetReps, targetWeightKg FROM routineExercise
                    UNION ALL
                    SELECT re, pos + 1, n, reps, w FROM seq WHERE pos + 1 < n
                )
                INSERT INTO routineSet (id, routineExerciseId, position, kind, reps, weightKg)
                SELECT lower(hex(randomblob(16))), re, pos, 'work', reps, w FROM seq
                """)
        }

        // v18 (FER-494): user-created folders for routines. Append-only — a new table plus a nullable
        // `folderId` on `routine`; touches no prior migration. Existing routines keep folderId NULL →
        // they fall into the UI's «Sin carpeta» section, zero loss. Deleting a folder NULLs its routines
        // (StrengthStore.deleteFolder), never deletes them, so there is no ON DELETE here. No index:
        // folders/routines are few and grouped in memory.
        migrator.registerMigration("v18") { db in
            try db.create(table: "routineFolder") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
            try db.alter(table: "routine") { t in
                t.add(column: "folderId", .text)   // nullable; NULL = no folder («Sin carpeta»)
            }
        }

        // v19 (FER-495): per-exercise HR rest target. Two columns on `routineExercise`; append-only,
        // touches no prior migration. The defaults (`restingMargin` / 0) reproduce FER-348 exactly, so
        // every existing heartRate routine keeps the resting+margin behavior with zero change on upgrade.
        migrator.registerMigration("v19") { db in
            try db.alter(table: "routineExercise") { t in
                t.add(column: "hrRestReference", .text).notNull().defaults(to: "restingMargin")
                t.add(column: "hrRestValue", .double).notNull().defaults(to: 0)
            }
        }

        // v20 (FER-511): stop storing the write-only `spo2Sample` stream and reclaim its space. The raw
        // red/ir ADC samples were never read on-device (the SpO₂ the UI shows comes from
        // dailyMetric.spo2Pct / Apple Health), so they were ~16% of the DB for nothing. Append-only:
        // this DELETEs the existing rows but KEEPS the (now-empty) table, so `Reads.spo2Samples` and
        // `storageStats` still compile and a downgraded reader sees an empty table, not a missing one.
        // New rows stop being written in `StreamStore.insert`. The one-time VACUUM that returns the
        // freed pages to the OS runs post-launch (AppModel.compactDatabaseAfterSpo2PurgeIfNeeded) —
        // VACUUM cannot run inside a migration transaction.
        migrator.registerMigration("v20") { db in
            try db.execute(sql: "DELETE FROM spo2Sample")
        }

        // v21 (FER-513): shrink the five 1 Hz sample tables ~60% with ZERO data loss by rebuilding them
        // as WITHOUT ROWID + an integer `deviceId` surrogate. A rowid table with a composite PK keeps a
        // second `sqlite_autoindex` copy of (deviceId, ts[, rrMs]) + rowid on EVERY row (~46% of the DB);
        // WITHOUT ROWID makes the PK the table itself (no autoindex), and the int surrogate replaces the
        // repeated "my-whoop" TEXT. `deviceId` is a SOURCE PARTITION, not hardware, so the mapping lives
        // in its own `deviceIdMap` (NOT `device`): writes/tests insert sample rows for ids that never have
        // a `device` row, so tying the surrogate to `device.rowid` would JOIN-drop them (data loss).
        //
        // Atomicity: the whole body runs in GRDB's single `.immediate` migration transaction — a crash
        // mid-way ROLLBACKs fully (grdb_migrations never records v21) and retries clean from v20. Each old
        // table is DROPped only after its rebuilt copy passed a row-count assert, in the SAME commit, so
        // there is never a persisted half-state. `synced` (dead since v5) is dropped from the rebuilt
        // tables. STRICT makes a downgraded (pre-v21) binary fail loudly instead of writing TEXT into the
        // INTEGER deviceId. Append-only: no prior migration is touched. spo2Sample/event/battery/stepSample
        // keep TEXT deviceId + rowid (empty / marginal — out of scope). The one-time VACUUM that returns the
        // freed pages runs post-launch (AppModel.compactDatabaseAfterRebuildIfNeeded) — VACUUM can't run in
        // a migration transaction.
        migrator.registerMigration("v21") { db in
            try db.execute(sql: """
                CREATE TABLE deviceIdMap (
                    deviceId TEXT PRIMARY KEY NOT NULL,
                    intId INTEGER NOT NULL UNIQUE
                )
                """)
            // Number the DISTINCT source partitions actually present across the five tables, densely and
            // deterministically. Today there is exactly one ("my-whoop"); the UNION handles N losslessly.
            try db.execute(sql: """
                INSERT OR IGNORE INTO deviceIdMap (deviceId, intId)
                SELECT d, ROW_NUMBER() OVER (ORDER BY d) FROM (
                    SELECT deviceId AS d FROM hrSample
                    UNION SELECT deviceId FROM rrInterval
                    UNION SELECT deviceId FROM skinTempSample
                    UNION SELECT deviceId FROM respSample
                    UNION SELECT deviceId FROM gravitySample
                )
                """)
            // Floor: guarantee the live strap partition maps even on a fresh install (all tables empty).
            try db.execute(sql: """
                INSERT OR IGNORE INTO deviceIdMap (deviceId, intId)
                VALUES ('my-whoop', (SELECT COALESCE(MAX(intId), 0) + 1 FROM deviceIdMap))
                """)

            // Rebuild one table: CREATE _new (STRICT, WITHOUT ROWID, int deviceId, no `synced`) →
            // INSERT…SELECT translating deviceId via the map → assert row counts match → DROP old → RENAME.
            func rebuild(_ table: String, columns: String, pk: String, dataCols: [String]) throws {
                let copyList = dataCols.joined(separator: ", ")
                let selectList = dataCols.map { "t.\($0)" }.joined(separator: ", ")
                try db.execute(sql: """
                    CREATE TABLE \(table)_new (
                        deviceId INTEGER NOT NULL, \(columns),
                        PRIMARY KEY (\(pk))
                    ) STRICT, WITHOUT ROWID
                    """)
                try db.execute(sql: """
                    INSERT INTO \(table)_new (deviceId, \(copyList))
                    SELECT m.intId, \(selectList)
                    FROM \(table) t JOIN deviceIdMap m ON m.deviceId = t.deviceId
                    """)
                let old = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
                let new = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)_new") ?? -1
                guard old == new else { throw MigrationError.rowCountMismatch(table: table, old: old, new: new) }
                try db.execute(sql: "DROP TABLE \(table)")
                try db.execute(sql: "ALTER TABLE \(table)_new RENAME TO \(table)")
            }

            try rebuild("hrSample", columns: "ts INTEGER NOT NULL, bpm INTEGER NOT NULL",
                        pk: "deviceId, ts", dataCols: ["ts", "bpm"])
            try rebuild("rrInterval", columns: "ts INTEGER NOT NULL, rrMs INTEGER NOT NULL",
                        pk: "deviceId, ts, rrMs", dataCols: ["ts", "rrMs"])
            try rebuild("skinTempSample", columns: "ts INTEGER NOT NULL, raw INTEGER NOT NULL",
                        pk: "deviceId, ts", dataCols: ["ts", "raw"])
            try rebuild("respSample", columns: "ts INTEGER NOT NULL, raw INTEGER NOT NULL",
                        pk: "deviceId, ts", dataCols: ["ts", "raw"])
            try rebuild("gravitySample",
                        columns: "ts INTEGER NOT NULL, x REAL NOT NULL, y REAL NOT NULL, z REAL NOT NULL",
                        pk: "deviceId, ts", dataCols: ["ts", "x", "y", "z"])
        }

        // FER-523: learned exercise aliases. When the user maps an imported exercise name to a catalog
        // exercise, we remember it (normalized name → exerciseId) so the next import of that name matches
        // on its own. PK on the normalized name = one mapping per name; re-mapping overwrites.
        migrator.registerMigration("v22") { db in
            try db.create(table: "learnedExerciseAlias") { t in
                t.column("name", .text).primaryKey()        // normalized imported name
                t.column("exerciseId", .text).notNull()     // catalog or custom exercise id
                t.column("ts", .integer).notNull()
            }
        }

        // v23 (FER-531): the weekly split — one row per weekday → routineId («La Semana» redesign).
        // Append-only: a brand-new table, touches no prior migration; existing routines/folders are
        // untouched and every user simply starts with an empty split (→ the planner's «no plan yet»
        // state). `weekday` (1…7, Calendar convention) is the PRIMARY KEY = at most one routine per day,
        // so assigning a day is an idempotent upsert. No FK to `routine`: deleting a routine clears its
        // schedule rows in the same transaction (StrengthStore.deleteRoutine), and a dangling routineId
        // derives to a rest day rather than crashing. No index — at most 7 rows.
        migrator.registerMigration("v23") { db in
            try db.create(table: "routineSchedule") { t in
                t.column("weekday", .integer).primaryKey()   // 1…7 (Calendar weekday); one routine per day
                t.column("routineId", .text).notNull()
            }
        }

        // v24 (FER-541): the user can override an exercise's measurement type — including a catalog
        // entry's (e.g. mark a "Plank" as time-based). The override is *user data*, so it lives here in
        // the store, NOT in the read-only bundled catalog. One row per exercise (`exerciseId` PRIMARY KEY
        // = at most one override; setting it is an idempotent upsert; reverting is a plain DELETE → back
        // to the catalog/custom default). `exerciseId` is the catalog slug or the custom uuid — the same
        // id every reader already uses. Append-only: a brand-new table, touches no prior migration.
        migrator.registerMigration("v24") { db in
            try db.create(table: "exerciseTypeOverride") { t in
                t.column("exerciseId", .text).primaryKey()   // catalog slug or custom uuid
                t.column("type", .text).notNull()            // weightReps | bodyweight | time | distance
                t.column("ts", .integer).notNull()
            }
        }

        // v25 (FER-712): body-clock phase for the "Tu reloj corporal" experimental surface. One
        // structured record per local civil day, holding CircadianEngine's cosinor phase estimate.
        // Written by the nightly IntelligenceEngine pass (the phase signal is the band's accelerometer
        // rest-activity rhythm). PK (deviceId, day) ⇒ recomputing a day is an idempotent upsert.
        // `confidence` is the raw PhaseConfidence string; WhoopStore keeps no dependency on
        // StrandAnalytics (the app layer translates). Append-only: brand-new table, touches no prior
        // migration.
        migrator.registerMigration("v25") { db in
            try db.create(table: "circadianPhase") { t in
                t.column("deviceId", .text).notNull()        // source partition (consistent w/ schema)
                t.column("day", .text).notNull()             // YYYY-MM-DD (local civil day)
                t.column("tempMinHour", .double).notNull()   // estimated body-temp minimum clock hour
                t.column("acrophaseHours", .double).notNull()// activity acrophase (peak), 0..<24
                t.column("offsetMinutes", .double).notNull() // CENTERED lean vs schedule (bias removed)
                t.column("confidence", .text).notNull()      // unreadable | wide | solid
                t.column("daysObserved", .integer).notNull() // days backing the fit → UI confidence
                t.column("bedtimeHour", .double)             // suggested sleep-window hour (nullable)
                t.column("wakeHour", .double)                // habitual wake used (nullable)
                t.column("computedAt", .integer).notNull()   // unix seconds
                t.primaryKey(["deviceId", "day"])            // ≤ 1 record/day ⇒ idempotent upsert
            }
        }

        // v26 (FER-715): per-set rest + persisted session energy. Append-only. Four nullable rest
        // columns on `routineSet` (NULL = inherit the exercise's rest at runtime), back-filled by
        // COPYING each routineExercise's rest onto ALL its existing sets (the FER-348 pattern: old
        // data keeps today's behavior bit-for-bit, zero loss). An orphan set (no parent exercise)
        // stays NULL and inherits at runtime rather than being lost. Plus nullable energyKcal/
        // energySource on `strengthSession` (NULL = a pre-v26 session — the UI shows no energy
        // rather than inventing one).
        migrator.registerMigration("v26") { db in
            try db.alter(table: "routineSet") { t in
                t.add(column: "restMode", .text)          // heartRate | fixed; NULL = inherit
                t.add(column: "restSeconds", .integer)
                t.add(column: "hrRestReference", .text)
                t.add(column: "hrRestValue", .double)
            }
            try db.execute(sql: """
                UPDATE routineSet
                   SET restMode = (SELECT re.restMode FROM routineExercise re
                                   WHERE re.id = routineSet.routineExerciseId),
                       restSeconds = (SELECT re.restSeconds FROM routineExercise re
                                      WHERE re.id = routineSet.routineExerciseId),
                       hrRestReference = (SELECT re.hrRestReference FROM routineExercise re
                                          WHERE re.id = routineSet.routineExerciseId),
                       hrRestValue = (SELECT re.hrRestValue FROM routineExercise re
                                      WHERE re.id = routineSet.routineExerciseId)
                 WHERE EXISTS (SELECT 1 FROM routineExercise re
                               WHERE re.id = routineSet.routineExerciseId)
                """)
            try db.alter(table: "strengthSession") { t in
                t.add(column: "energyKcal", .double)      // NULL = pre-v26 session
                t.add(column: "energySource", .text)      // 'band_calculated' | 'estimated'
            }
        }
        // v27 (FER-779): the catalog is now ExerciseDB. Custom exercises gain the two fields the new
        // `Exercise` model carries — `bodyParts` (coarse regions) and a remote `gifUrl`. Append-only;
        // the v13 `cues` column stays and is reused to store `instructions` (the field was renamed,
        // the column was not, so shipped migrations aren't edited). Existing custom rows get the
        // defaults (empty parts, no gif).
        migrator.registerMigration("v27") { db in
            // Idempotent adds (see `addColumnIfMissing`): a partial pre-release build could have already
            // grown these columns without recording v27, which would make a plain ALTER throw
            // "duplicate column" on every launch and wedge startup.
            try addColumnIfMissing(db, "bodyParts", on: "customExercise") {
                $0.add(column: "bodyParts", .text).notNull().defaults(to: "[]")   // JSON array
            }
            try addColumnIfMissing(db, "gifUrl", on: "customExercise") {
                $0.add(column: "gifUrl", .text)                                    // NULL = no media
            }
        }
        // v28 (FER-798): durable snapshot of the strength session IN PROGRESS, so a crash/kill of the
        // iPhone doesn't lose the workout — at relaunch the app rebuilds the live session (and the Apple
        // Watch's queued `.end` then finds it and saves the receipt). A singleton control table (0 or 1
        // row) holding a Codable JSON blob, written on start and on each durable edit, restored at launch,
        // deleted on save/discard. It is prunable control state, NOT a biometric stream — outside the
        // WITHOUT-ROWID rebuild and the sync bookkeeping.
        migrator.registerMigration("v28") { db in
            try db.create(table: "inProgressStrengthSession") { t in
                t.column("id", .text).primaryKey()
                t.column("snapshot", .text).notNull()   // JSON of StrengthSessionSnapshot
                t.column("updatedTs", .integer).notNull()
            }
        }
        // v29 (FER-A): per-exercise load progression. Four append-only columns on `routineExercise`,
        // all with defaults chosen so a pre-v29 routine reads back with progression OFF (enabled 0,
        // sessions 2, increment NULL = derive from plates, deload 'propose'). Idempotent adds so a DB
        // that already grew the columns locally (iterating this migration) is a no-op, not a crash.
        migrator.registerMigration("v29") { db in
            try addColumnIfMissing(db, "progressionEnabled", on: "routineExercise") {
                $0.add(column: "progressionEnabled", .integer).notNull().defaults(to: 0)
            }
            try addColumnIfMissing(db, "progressionSessions", on: "routineExercise") {
                $0.add(column: "progressionSessions", .integer).notNull().defaults(to: 2)
            }
            try addColumnIfMissing(db, "progressionIncrementKg", on: "routineExercise") {
                $0.add(column: "progressionIncrementKg", .double)   // NULL = derive from inventory
            }
            try addColumnIfMissing(db, "progressionDeload", on: "routineExercise") {
                $0.add(column: "progressionDeload", .text).notNull().defaults(to: "propose")
            }
        }
        // v30 (FER-D): the recovery gate is configurable per exercise (2c's "Recuperación baja" row).
        // Default 0 = defer an earned raise on a low-recovery day; 1 = raise anyway.
        migrator.registerMigration("v30") { db in
            try addColumnIfMissing(db, "progressionIgnoreRecovery", on: "routineExercise") {
                $0.add(column: "progressionIgnoreRecovery", .integer).notNull().defaults(to: 0)
            }
        }
        return migrator
    }

    /// Idempotent `ADD COLUMN`: runs `body` (which should add `column` to `table`) **only if the live
    /// schema lacks it**. A migration that re-runs against a DB that already grew the column — e.g. after
    /// iterating a migration locally and reinstalling over the same on-device DB — becomes a no-op instead
    /// of a "duplicate column" crash that wedges startup (FER-791). Use this for every migration ADD COLUMN.
    static func addColumnIfMissing(
        _ db: Database, _ column: String, on table: String,
        _ body: (TableAlteration) -> Void
    ) throws {
        guard try !db.columns(in: table).contains(where: { $0.name == column }) else { return }
        try db.alter(table: table, body: body)
    }
}
