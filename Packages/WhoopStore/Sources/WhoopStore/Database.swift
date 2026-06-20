import Foundation
import GRDB

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
        return migrator
    }
}
