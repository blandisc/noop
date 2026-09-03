# Cénit — On-Device Data Model

Cénit is a standalone, fully offline health app on **Apple Health**. It stores HealthKit syncs,
file imports, and on-device computed metrics in a single local SQLite database. Older installs may
still carry dormant historical band-era partitions in the same DB. This document describes that
on-device database: every table, its columns, natural keys, indexes, and the migration history that
produced the current schema.

> **Scope note.** Cénit is **not affiliated with, endorsed by, or connected to WHOOP**, and it is
> **not a medical device** — none of the stored values are intended for diagnosis or treatment.

---

## Where the database lives

The persistence layer is the `CenitStore` Swift package
(`Packages/CenitStore`), built on [GRDB](https://github.com/groue/GRDB.swift) over SQLite. Like
every package in the repo, it declares both platforms — `.iOS(.v16)` and `.macOS(.v13)`
(`Packages/CenitStore/Package.swift`) — and is UI-framework agnostic, so the same schema and
storage code back the `Cenit` app from a single cross-platform core.

The app target opens the database at a fixed, per-user location
(`Cenit/Data/StorePaths.swift`):

```
<Application Support>/OpenWhoop/whoop.sqlite
```

```swift
// Cenit/Data/StorePaths.swift
static func defaultDatabasePath() throws -> String {
    let fm = FileManager.default
    let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                          appropriateFor: nil, create: true)
        .appendingPathComponent("OpenWhoop", isDirectory: true)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("whoop.sqlite").path
}
```

On iOS that resolves inside the app's sandbox, to
`<app sandbox>/Library/Application Support/OpenWhoop/whoop.sqlite`. Tests use an in-memory database via
`CenitStore.inMemory()`.

### Connection configuration

`CenitStore.init(path:)` (`Packages/CenitStore/Sources/CenitStore/CenitStore.swift`) opens a
single `DatabaseQueue` and applies these PRAGMAs before any query runs:

| PRAGMA | Value | Why |
| --- | --- | --- |
| `journal_mode` | `WAL` | Concurrent readers (pool) and the actor-serialized writer can read/write without deadlocking. |
| `synchronous` | `NORMAL` | Durable pairing with WAL — only an OS crash or power loss can lose the last transaction. |
| `cache_size` | `-16000` | ~16 MB page cache for multi-thousand-row import/backfill writes. |
| `mmap_size` | `268435456` | 256 MB memory-mapped I/O. |
| `temp_store` | `MEMORY` | In-memory temp tables. |
| `busyMode` | `.timeout(5)` | 5-second busy timeout under write contention. |

`CenitStore` is an `actor`: all GRDB calls run on the actor's serial executor (off the main
thread) through the `syncRead` / `syncWrite` helpers. The reported schema version is
`CenitStoreInfo.schemaVersion = 16`.

---

## Schema at a glance

The schema falls into four groups:

| Group | Tables | Origin |
| --- | --- | --- |
| **Device registry** | `device` | Dormant/historical registry from the retired band era |
| **Decoded streams** (durable) | `hrSample`, `rrInterval`, `event`, `battery`, `spo2Sample`, `skinTempSample`, `respSample`, `gravitySample` | Dormant/historical sample tables (band era and/or HealthKit-derived) |
| **Raw outbox** (transient) | `rawBatch` | Dormant/historical compressed frames from the retired band era, prunable |
| **Bookkeeping** | `cursors` | Highwater / read cursors |
| **Metric caches** | `sleepSession`, `dailyMetric`, `journal`, `workout`, `appleDaily`, `metricSeries` | Derived metrics + CSV / Apple-Health imports |
| **Experiments** *(v12)* | `experiment` | N-of-1 experiments (FER-307) |
| **Strength tracker** *(v13, +v15, +v17, +v26)* | `customExercise`, `routine`, `routineExercise`, `routineSet`, `strengthSession`, `setEntry`, `personalRecord` | User-authored routines/sessions/sets/PRs — relational, UUID PKs. `routineExercise.supersetGroup` (v15) groups exercises into supersets. `routineSet` (v17) holds the per-set prescription; each set carries an optional rest override (v26, NULL = inherit the exercise). `strengthSession.energyKcal`/`energySource` (v26) persist the session's energy + its origin. The seed exercise catalog is a bundled resource in `StrandTraining`, not in SQLite. (FER-345/346/492/715) |
| **Diet** *(v14, +v16)* | `dietPlan`, `dietAdherence` | Prescribed diet plan (`noop.diet.v1`, captured via import) + daily per-meal adherence — apego tracking. `dietAdherence.optionIndex` (v16) records which equivalent option was eaten (FER-370/401) |

All timestamp columns named `ts`, `startTs`, `endTs`, `capturedAt`, etc. are **unix seconds**
(integers). Day-keyed cache tables use a `day` text column in `YYYY-MM-DD` form and compare it
lexicographically.

---

## Migration history

Migrations are registered in `Packages/CenitStore/Sources/CenitStore/Database.swift`
(`makeMigrator()`) and run in order on every open.

| Version | What it adds |
| --- | --- |
| **v1** | Core tables: `device`, the four original decoded streams (`hrSample`, `rrInterval`, `event`, `battery`), and the raw outbox `rawBatch`. |
| **v2** | `cursors` key/value table for highwater bookkeeping. |
| **v3** | Type-47 biometric streams: `spo2Sample`, `skinTempSample`, `respSample`, `gravitySample`. |
| **v4** | Local metric caches: `sleepSession` (one row per session) and `dailyMetric` (one row per calendar day). |
| **v5** | Adds a `synced` integer column (default `0`) to all eight decoded-stream tables. **Vestigial** — see below. |
| **v6** | Adds nullable `charging` boolean to `battery` for the dense BATTERY_LEVEL series. |
| **v7** | Adds in-sleep signal aggregates to `dailyMetric`: `spo2Pct`, `skinTempDevC`, `respRateBpm` (all nullable). |
| **v8** | Adds `journal`, `workout`, and `appleDaily` (Apple-Health daily aggregates). |
| **v9** | Adds the generic long-format `metricSeries` table and its `(deviceId, key, day)` index. |
| **v10** | Adds `stepSample` (WHOOP5 step-motion counter persistence). |
| **v11** | Adds nullable `steps` + `activeKcalEst` to `dailyMetric` (on-device daily step total + calorie estimate). |
| **v12** | Adds the `experiment` table (N-of-1 experiments, FER-307). |
| **v13** | Strength tracker (FER-345): `customExercise`, `routine`, `routineExercise`, `strengthSession`, `setEntry`, `personalRecord` + their indexes. Relational, UUID-string PKs; array fields (muscles, cues, warm-up percents) are JSON text columns. Append-only. |
| **v14** | Diet (FER-370): `dietPlan` (prescribed plan as an opaque `noop.diet.v1` JSON payload + denormalized columns, PK `id`) and `dietAdherence` (per-meal daily status, PK `(deviceId, day, mealId)`). Append-only. |
| **v15** | Supersets (FER-346): adds nullable `supersetGroup` (INTEGER) to `routineExercise` — same value within a routine = one superset; NULL = standalone. Append-only `ALTER ADD COLUMN`. |
| **v16** | Diet option (FER-401): adds nullable `optionIndex` (INTEGER) to `dietAdherence` — the 0-based index into the plan meal's `opciones` array (which equivalent was eaten); NULL = not recorded. Registro only — does not change the apego %. Append-only `ALTER ADD COLUMN`. |
| **v17–v25** | *(not yet documented row-by-row — this table has a gap; v17 created `routineSet`, later migrations covered routine folders, HR-rest references, the weekly split, exercise-type overrides, DB compaction, and the circadian-phase table.)* |
| **v26** | Per-set rest + persisted session energy (FER-715): four nullable rest columns on `routineSet` (`restMode`/`restSeconds`/`hrRestReference`/`hrRestValue`; NULL = inherit the exercise's rest at runtime), back-filled by copying each `routineExercise`'s rest onto ALL its sets (old data keeps today's behavior). Plus nullable `energyKcal`/`energySource` on `strengthSession` (NULL = a pre-v26 session). Append-only. |
| **v42** | Ola 1 · FER-324 (one schema PR for five pieces). `strengthSession`: `strainSource` TEXT (`hr`\|`rpe`), `sessionRpe` REAL, `sessionRpeSource` TEXT (`answered`\|`prefill`), `trimpPerAU` REAL, `source` TEXT (`strong`\|`hevy`\|`cenit`), `title` TEXT, `programWeek` INTEGER, `deload` INTEGER — all NULL on old rows. `routineExercise.progressionUseRPE` INTEGER NOT NULL DEFAULT 0. `routineSet.mode` / `setEntry.mode` TEXT (`standard`\|`amrap`\|`drop`, NULL = standard). Every ADD COLUMN via `addColumnIfMissing`. Append-only. |
| **v43** | Ola 1 · FER-324: table `program` (singleton, PK `id = 'active'`): `name`, `weeks`, `startTs`, `deloadRule`, `endMode`, `templateId`, `createdTs`. `ifNotExists`. Append-only. |
| _v27–v41_ | _Documented in `Database.swift` comments; the table entries here are pending (FER-337)._ |

### The vestigial `synced` column

Migration v5 added a per-row `synced` integer (`NOT NULL DEFAULT 0`) to each of the eight
decoded-stream tables. It dates from a since-removed server-upload feature. **Cénit is fully
offline: nothing writes or reads `synced`.** The insert path explicitly never sets it
(`StreamStore.swift`), and no read query references it. The column is left in place only to avoid
a `DROP COLUMN` migration over potentially millions of existing rows. Treat it as dead schema.

---

## Device registry

### `device` *(v1)*

One row per device the app has ever recorded data for (historical — no device pairs today). Natural key is the device `id`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT | **Primary key.** Stable device identifier. |
| `mac` | TEXT | BLE MAC address (nullable). |
| `name` | TEXT | Advertised/device name (nullable). |
| `firstSeen` | INTEGER | Unix seconds, set on first insert. |
| `lastSeen` | INTEGER | Unix seconds, bumped on every upsert. |

`upsertDevice(id:mac:name:)` (`StreamStore.swift`) inserts or, on `id` conflict, updates `mac`,
`name`, and `lastSeen` (it does not touch `firstSeen`). Every other table references the device via
a `deviceId` text column, scoping all data per device.

---

## Decoded streams (durable record)

These eight tables were historically populated by the (now-removed) band-decode path and remain
for schema continuity; they may also hold HealthKit-derived samples. Writes go through
`CenitStore.insert(_ streams:deviceId:)` (`StreamStore.swift`). The in-memory shapes are the
`BiometricStreams` stream structs (`Packages/BiometricStreams/Sources/BiometricStreams/Streams.swift`):
`HRSample`, `RRInterval`, `StreamEvent`, `BatterySample`, `SpO2Sample`, `SkinTempSample`,
`RespSample`, `GravitySample`, aggregated into `Streams`.

All inserts are **idempotent by natural key** — they use `ON CONFLICT(...) DO NOTHING`, so
replaying overlapping samples never duplicates rows. `insert(...)` returns the count of rows
*actually* inserted per stream. Range reads live in `Reads.swift` and follow a uniform shape:
`WHERE deviceId = ? AND ts >= ? AND ts <= ? ORDER BY ts ASC LIMIT ?`.

> The biometric stream structs carry a constant `unit` field (`"raw_adc"` / `"g"`) for JSON
> parity with golden fixtures, but `unit` is **not** a database column — only the numeric fields
> below are persisted.

### `hrSample` *(v1)* — heart rate

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Wall-clock unix seconds. Part of PK. |
| `bpm` | INTEGER NOT NULL | Beats per minute. |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts)`. HR is taken only from `REALTIME_DATA` (type 40) frames.
`latestHRSampleTs(deviceId:)` returns `MAX(ts)` here — the biometric "data frontier" used by the
stuck-strap watchdog.

### `rrInterval` *(v1)* — R-R intervals (HRV source)

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Wall-clock unix seconds. Part of PK. |
| `rrMs` | INTEGER NOT NULL | Beat-to-beat interval, milliseconds. Part of PK. |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts, rrMs)` — `rrMs` is in the key because multiple R-R intervals can
share a single `REALTIME_DATA` timestamp. Reads order by `ts ASC, rrMs ASC`.

### `event` *(v1)* — strap events

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Real RTC unix seconds (never offset). Part of PK. |
| `kind` | TEXT NOT NULL | Event name (e.g. `BATTERY_LEVEL(3)`). Part of PK. |
| `payloadJSON` | TEXT NOT NULL | Decoded payload as JSON. |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts, kind)`. `payloadJSON` is serialized with `JSONEncoder`'s
`.sortedKeys` so the same payload is byte-identical every time — important for the natural-key
dedupe. Reads decode it back into `[String: ParsedValue]` with a shared, reused decoder.

### `battery` *(v1, +charging in v6)*

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Event RTC for BATTERY_LEVEL events, else `wallClockRef`. Part of PK. |
| `soc` | DOUBLE | State of charge (%), nullable. |
| `mv` | INTEGER | Millivolts, nullable. |
| `charging` | BOOLEAN | *(v6)* Nullable — only the dense BATTERY_LEVEL event series reports it; the command-response path leaves it `NULL`. |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts)`. (Note: `batterySamples(...)` reads back only `ts, soc, mv`.)

### Type-47 biometric streams *(v3)*

These four mirror the original streams (per-row natural key `(deviceId, ts)`, `DO NOTHING`
inserts, identical range-read shape).

#### `spo2Sample` — pulse oximetry raw ADC

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Unix seconds. Part of PK. |
| `red` | INTEGER NOT NULL | Red LED raw ADC. |
| `ir` | INTEGER NOT NULL | IR LED raw ADC. |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts)`.

#### `skinTempSample` — skin temperature raw ADC

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Unix seconds. Part of PK. |
| `raw` | INTEGER NOT NULL | Raw ADC reading. |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts)`.

#### `respSample` — respiration raw ADC

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Unix seconds. Part of PK. |
| `raw` | INTEGER NOT NULL | Raw ADC reading. |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts)`.

#### `gravitySample` — accelerometer / gravity vector

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `ts` | INTEGER NOT NULL | Unix seconds. Part of PK. |
| `x` | DOUBLE NOT NULL | Gravity vector X (g). |
| `y` | DOUBLE NOT NULL | Gravity vector Y (g). |
| `z` | DOUBLE NOT NULL | Gravity vector Z (g). |
| `synced` | INTEGER NOT NULL DEFAULT 0 | *(v5, vestigial)* |

**Primary key:** `(deviceId, ts)`.

---

## Raw outbox (transient, prunable)

### `rawBatch` *(v1)*

The raw outbox stores the strap's original BLE frames — compressed and batched — so the exact
bytes survive even for frames Cénit can't yet fully decode. Whereas the decoded streams are durable,
raw batches are **transient and prunable**. Implementation in `RawOutbox.swift`.

| Column | Type | Notes |
| --- | --- | --- |
| `batchId` | TEXT | **Primary key.** |
| `deviceId` | TEXT NOT NULL | Owning strap. |
| `capturedAt` | INTEGER NOT NULL | Unix seconds the batch was captured; pending reads order by this. |
| `deviceClockRef` | INTEGER NOT NULL | Strap-clock reference for the wall-clock offset. |
| `wallClockRef` | INTEGER NOT NULL | Wall-clock reference, unix seconds. |
| `startTs` | INTEGER NOT NULL | First frame timestamp in the batch. |
| `endTs` | INTEGER NOT NULL | Last frame timestamp in the batch. |
| `frameCount` | INTEGER NOT NULL | Number of frames packed. |
| `byteSize` | INTEGER NOT NULL | Size used for `storageStats()` totals. |
| `framesBlob` | BLOB NOT NULL | zlib-compressed packed frames (length-prefixed). |
| `syncedAt` | INTEGER | Unix seconds; `NULL` until marked. |

**Primary key:** `batchId`. Frames are packed as `[count u32 LE]{[len u32 LE][bytes]}×count`,
then zlib-compressed with a 4-byte uncompressed-length prefix.

**Pruning policy** (`pruneRaw(now:keepWindowSeconds:maxUnsyncedBytes:)`): only batches with a
non-null `syncedAt` older than `now - keepWindowSeconds` are deleted — safe because the decoded
streams persist separately. Unsynced raw is **never** dropped (it is the sole copy of the strap's
not-yet-decoded bytes after a chunk is trimmed). `maxUnsyncedBytes` is accepted for call-site
compatibility but intentionally unused.

---

## Bookkeeping

### `cursors` *(v2)*

A simple key/value table for incremental-processing highwater marks (`Cursors.swift`).

| Column | Type | Notes |
| --- | --- | --- |
| `name` | TEXT | **Primary key.** |
| `value` | INTEGER | Stored cursor value (typically a timestamp). |

Helpers namespace the `name`: `highwater:<stream>` (upload/forward-only highwater) and
`read:<stream>` (pull cursor). The distinct prefixes keep the two cursor families from colliding
for the same stream.

---

## Metric caches

These tables hold **derived metrics and imported aggregates** rather than raw measurements.
Recovery / strain / HRV / sleep math is computed locally by the `StrandAnalytics` package, and
CSV / Apple-Health data arrives through `StrandImport`. Every cache table follows the same
contract: a `Codable` struct, an idempotent `ON CONFLICT(...) DO UPDATE` upsert keyed by its
natural key (latest value wins), and range-read accessors that run off-main.

### `sleepSession` *(v4)*

One row per sleep session (`MetricsCache.swift`, `struct CachedSleepSession`).

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `startTs` | INTEGER NOT NULL | Session start, unix seconds. Part of PK. |
| `endTs` | INTEGER NOT NULL | Session end, unix seconds. |
| `efficiency` | DOUBLE | Sleep efficiency, nullable. |
| `restingHr` | INTEGER | Resting HR, nullable. |
| `avgHrv` | DOUBLE | Average HRV, nullable. |
| `stagesJSON` | TEXT | Verbatim JSON array of stage segments (`[{start,end,stage}]`), nullable — stored as a string so the cache stays schema-agnostic about staging shape. |

**Primary key:** `(deviceId, startTs)`. Read by `startTs` range, oldest first.

### `dailyMetric` *(v4, +v7 columns)*

One row per calendar day (`MetricsCache.swift`, `struct DailyMetric`). This is the central
per-day rollup behind the dashboard. **Natural key `(deviceId, day)`** where `day` is
`YYYY-MM-DD`. All metric columns are nullable.

| Column | Type | Migration | Notes |
| --- | --- | --- | --- |
| `deviceId` | TEXT NOT NULL | v4 | Part of PK. |
| `day` | TEXT NOT NULL | v4 | `YYYY-MM-DD`. Part of PK. |
| `totalSleepMin` | DOUBLE | v4 | Total sleep, minutes. |
| `efficiency` | DOUBLE | v4 | Sleep efficiency. |
| `deepMin` | DOUBLE | v4 | Deep sleep, minutes. |
| `remMin` | DOUBLE | v4 | REM sleep, minutes. |
| `lightMin` | DOUBLE | v4 | Light sleep, minutes. |
| `disturbances` | INTEGER | v4 | Disturbance count. |
| `restingHr` | INTEGER | v4 | Resting heart rate. |
| `avgHrv` | DOUBLE | v4 | Average HRV. |
| `recovery` | DOUBLE | v4 | Recovery score. |
| `strain` | DOUBLE | v4 | Day strain. |
| `exerciseCount` | INTEGER | v4 | Number of exercises. |
| `spo2Pct` | DOUBLE | v7 | Mean SpO2 (%) during sleep. |
| `skinTempDevC` | DOUBLE | v7 | Skin-temperature deviation (°C) from baseline. |
| `respRateBpm` | DOUBLE | v7 | Mean respiration rate (breaths/min) during sleep. |

**Primary key:** `(deviceId, day)`. Read by lexicographic `day` range, oldest first. The
`DailyMetric` struct's `init` defaults the three v7 fields to `nil` so older callers stay
source-compatible.

### `journal` *(v8)*

One user-answered daily prompt (`JournalWorkoutAppleCache.swift`, `struct JournalEntry`).

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `day` | TEXT NOT NULL | `YYYY-MM-DD`. Part of PK. |
| `question` | TEXT NOT NULL | Prompt text. Part of PK. |
| `answeredYes` | INTEGER NOT NULL | `0`/`1`, mapped to/from `Bool`. |
| `notes` | TEXT | Free-text note, nullable. |

**Primary key:** `(deviceId, day, question)`. Read by `day` range, ordered `day ASC, question
ASC`.

### `workout` *(v8)*

One workout (`JournalWorkoutAppleCache.swift`, `struct WorkoutRow`). All metric columns nullable.

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `startTs` | INTEGER NOT NULL | Start, unix seconds. Part of PK. |
| `endTs` | INTEGER NOT NULL | End, unix seconds. |
| `sport` | TEXT NOT NULL | Sport/activity name. Part of PK. |
| `source` | TEXT NOT NULL | Origin of the row (e.g. import source). |
| `durationS` | DOUBLE | Duration, seconds. |
| `energyKcal` | DOUBLE | Energy, kcal. |
| `avgHr` | INTEGER | Average HR. |
| `maxHr` | INTEGER | Max HR. |
| `strain` | DOUBLE | Workout strain. |
| `distanceM` | DOUBLE | Distance, meters. |
| `zonesJSON` | TEXT | Verbatim JSON of HR-zone percentages — stored as a string so the cache stays schema-agnostic about zone shape. |
| `notes` | TEXT | Free-text note. |

**Primary key:** `(deviceId, startTs, sport)`. Read by `startTs` range, oldest first.

### `appleDaily` *(v8)*

Apple-Health-specific daily aggregates (`JournalWorkoutAppleCache.swift`, `struct AppleDaily`),
imported from an Apple Health `export.xml`. All metric columns nullable.

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `day` | TEXT NOT NULL | `YYYY-MM-DD`. Part of PK. |
| `steps` | INTEGER | Step count. |
| `activeKcal` | DOUBLE | Active energy, kcal. |
| `basalKcal` | DOUBLE | Basal energy, kcal. |
| `vo2max` | DOUBLE | VO₂max estimate. |
| `avgHr` | INTEGER | Average HR. |
| `maxHr` | INTEGER | Max HR. |
| `walkingHr` | INTEGER | Walking HR average. |
| `weightKg` | DOUBLE | Body weight, kilograms. |

**Primary key:** `(deviceId, day)`. Read by lexicographic `day` range, oldest first.

### `metricSeries` *(v9)*

A generic **long-format / EAV** metric store (`MetricSeriesStore.swift`, `struct MetricPoint`).
Where the tables above use a wide column-per-metric layout, this is the tall counterpart: one row
per `(deviceId, day, key)` with a single REAL `value`. Any scalar metric — server-derived,
Apple-Health, journal-encoded, etc. — can be projected into this one table and read back uniformly
by key, which is the substrate for a metric explorer that lists and compares metrics without
knowing each source's schema.

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `day` | TEXT NOT NULL | `YYYY-MM-DD`. Part of PK. |
| `key` | TEXT NOT NULL | Metric identifier (e.g. `"restingHr"`, `"steps"`, `"recovery"`). Part of PK. |
| `value` | DOUBLE NOT NULL | The scalar value. |

**Primary key:** `(deviceId, day, key)`.

**Index** — `idx_metricSeries_device_key_day` on `(deviceId, key, day)`. The primary key orders by
`day` before `key`, so it can't efficiently serve per-metric range reads (`metricSeries(key:from:
to:)`) or `metricDays(key:)`, which scan `(deviceId, key)` and then walk days. This index makes
those reads index-only. Accessors: `upsertMetricSeries(...)`, `metricSeries(...)`,
`metricKeys(...)` (distinct keys for a device), and `metricDays(...)` (`MIN`/`MAX` day per key).

---

## Index summary

| Index | Table | Columns | Purpose |
| --- | --- | --- | --- |
| *(implicit PK)* | every table above | (its natural key) | Dedupe + primary lookup. |
| `idx_metricSeries_device_key_day` | `metricSeries` | `deviceId, key, day` | Index-only per-metric range reads. |

Every other table relies on its primary-key index; the decoded-stream and date-range reads are all
served by the `(deviceId, ts)` / `(deviceId, day)` / `(deviceId, startTs)` primary keys.

---

## Provenance

Persistence is `CenitStore`; the local recovery / strain / HRV / sleep math is `StrandAnalytics`;
and the Apple Health importers are `StrandImport`.

> **Reminder.** Cénit is not affiliated with WHOOP and is not a medical device. All stored data is
> the user's own, kept entirely on the user's device.
