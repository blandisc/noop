# Cénit — System Architecture

Cénit is a standalone, fully **offline** companion app for WHOOP straps (4.0, 5.0, and MG). It talks
directly to the strap over Bluetooth Low Energy, stores everything on-device in SQLite, and computes
recovery, strain, HRV, and sleep locally. There is no WHOOP cloud, no account —
the app interoperates with **your own device and your own data**. It can also import data you already
own: WHOOP CSV exports and Apple Health exports.

> **Not affiliated with WHOOP.** Cénit is an independent, interoperability project built on
> community reverse-engineering of the strap's Bluetooth protocol. It is **not a medical device**
> and produces **approximate** physiological estimates that must not be used for diagnosis or
> treatment. See [`DISCLAIMER.md`](../DISCLAIMER.md) and [`ATTRIBUTION.md`](../ATTRIBUTION.md).

---

## 1. The big picture

The system is a one-directional pipeline. Bytes arrive from the strap (or from an import file), get
decoded into typed rows, land durably in SQLite, are read back through a thin repository, are turned
into daily metrics by pure analytics functions, and finally render in SwiftUI. Nothing is ever sent
off-device.

```
                          ┌─────────────────────────────────────────────────────────┐
   WHOOP strap (4.0/5.0)  │                     Cénit (on-device)                     │
   ────────────────────   │                                                          │
        BLE GATT           │   CoreBluetooth          WhoopProtocol (pure decode)    │
   ┌──────────────┐  notify│  ┌────────────┐  bytes  ┌──────────────────────────┐    │
   │ custom svc   ├────────┼─▶│ BLEManager │────────▶│ Reassembler              │    │
   │ 6108…/fd4b…  │  write │  │ (CoreBT    │  frames │  → parseFrame            │    │
   │ HR 0x2A37    │◀───────┼──│  delegate) │         │  → extract[Historical]…  │    │
   │ batt 0x2A19  │  cmds  │  └─────┬──────┘         └────────────┬─────────────┘    │
   └──────────────┘        │        │                             │ Streams          │
                           │        │ complete frame              ▼                  │
                           │        ▼                  ┌──────────────────────┐      │
                           │  ┌───────────┐  live      │  WhoopStore (actor)  │      │
                           │  │FrameRouter│──events────▶│  GRDB / SQLite       │      │
                           │  │ LiveState │  HR/RR/UI  │  decoded streams +   │      │
                           │  └───────────┘            │  metric caches +     │      │
                           │        │                  │  raw outbox          │      │
                           │   live │ ┌─────────┐ hist └─────────┬────────────┘      │
                           │        └▶│Collector│ ┌──────────┐   │ reads             │
                           │          └─────────┘ │Backfiller│   ▼                   │
                           │   imports            └──────────┘ ┌────────────┐        │
   files ──────────────────┼─▶ StrandImport ──────────────────▶│ Repository │        │
   export.zip / *.csv      │   (CSV + Apple Health)            └─────┬──────┘        │
                           │                                         ▼               │
                           │                      StrandAnalytics ──▶ SwiftUI screens│
                           │                      (HRV/recovery/    (StrandDesign)   │
                           │                       strain/sleep)                     │
                           └─────────────────────────────────────────────────────────┘
```

The same `WhoopStore` SQLite file is the single convergence point for three independent producers:
the **live** BLE path, the **historical** BLE offload path, and the **import** path. All readers go
through `Repository`.

---

## 2. Repository layout

```
Cenit/                         App-layer (BLE/Collect/Data/Screens/System) compiled by the iOS target
├── App/                        App state (the iOS app scene lives in CenitApp/)
│   ├── AppModel.swift          @MainActor root state — owns BLE, Repository, profiles
│   └── ContentView.swift
├── BLE/                        CoreBluetooth + the live/decode seam
│   ├── BLEManager.swift        CBCentral/CBPeripheral delegate, scan→bond→stream
│   ├── FrameRouter.swift       pure decode→LiveState router (no CoreBluetooth)
│   ├── LiveState.swift         @MainActor observable connection/biometric snapshot
│   ├── Commands.swift          WhoopCommand enum (command bytes + frame builders)
│   ├── StandardHeartRate.swift 0x2A37 BLE-standard HR/RR parser (pure)
│   ├── BackfillPolicy.swift    rate-limiter for historical offload triggers
│   └── StuckStrapDetector.swift safety-net liveness watchdog
├── Collect/                    Persistence orchestration (BLE → store)
│   ├── Collector.swift         buffers live frames → decoded-first persistence
│   ├── Backfiller.swift        historical-offload state machine (safe-trim)
│   ├── ClockCorrelation.swift  device-epoch ↔ wall-clock correlation (pure)
│   ├── ClockPolicy.swift       when to (re)issue SET_CLOCK by drift (needs GET_CLOCK — moot on the 4.0)
│   ├── StorePaths.swift        on-disk SQLite location (App Support/OpenWhoop)
│   ├── PrunePolicy.swift       raw-outbox retention (24h / 50MB)
│   └── RawCaptureWindow.swift  bounded on-demand raw-capture window
├── Data/                       Read model + import glue
│   ├── Repository.swift        @MainActor read model over WhoopStore
│   ├── WhoopImporter.swift     CSV result → store rows
│   ├── AppleHealthImport.swift Apple Health result → store rows
│   ├── Profile.swift           user profile (age/sex/body/HRmax)
│   └── BehaviorStore.swift     toggles for automations/coaching
├── Screens/                    SwiftUI feature screens (Today, Live, Sleep, Trends…)
├── AI/                         opt-in BYO-key coach (`AICoach.swift`; off by default)
├── Media/                      opt-in exercise-media cache/download (off by default)
├── LiveActivity/               Live Activity / rest-timer presentation glue
├── Onboarding/                 first-run / restore / terms flows
└── System/                     app-layer helpers (ProjectInfo, Platform, StrapActions)

Packages/                       Cross-platform Swift packages (base `.iOS(.v16)` / `.macOS(.v13)`;
│                               StrandDesign is `.iOS(.v17)` / `.macOS(.v14)` + `.watchOS(.v10)`)
├── WhoopProtocol/              BLE frame parsing, CRC, command/event/packet decode
├── WhoopStore/                 GRDB/SQLite persistence (actor)
├── StrandTraining/             strength domain types + bundled exercise catalog (free-exercise-db, FER-923; pure, no DB)
├── StrandAnalytics/            HRV/recovery/strain/sleep/correlation math
├── StrandImport/               WHOOP CSV + Apple Health importers
└── StrandDesign/               SwiftUI design system (palette, components, charts)

CenitApp/                       iOS SwiftUI app shell (App/Health/System/Widgets/Resources)
CenitShared/                    code shared between the iOS app, its widgets, and (FER-740) the watch —
                                incl. the workout-mirroring contract (WorkoutMirrorMessage, RestActivitySnapshot)
CenitWidgets/                   iOS home / lock-screen widgets
CenitWatch/                     watchOS 10 companion app (single target, FER-740). Runs the real
                                HKWorkoutSession and mirrors it to the iPhone; no GRDB on the wrist.
                                Depends only on StrandDesign (project.yml + `import StrandDesign` only).

Tools/Backfill/                 CLI offload/replay tool
```

The app target is **`Cenit`** (Swift module `Cenit`, product `Cenit.app`): its shell (scene, HealthKit,
widgets, intents) lives in **`CenitApp/`**, and it compiles the app-layer under **`Cenit/`** (CoreBluetooth,
the live/decode seam, screens, data). The user-visible name stays **Cénit** (`CFBundleDisplayName`); the
visible rebrand to "Cénit" is tracked separately. The macOS app and its `Strand`/`StrandTests` targets were
retired (FER-143) and the dead `#if os(macOS)`/`AppKit` branches removed (FER-144); the app-layer unit tests
run as **`CenitUnitTests`** in the simulator. The packages keep their `Strand*`/`Whoop*` names. The
core/data/analytics packages declare `.iOS(.v16)`/`.macOS(.v13)`, guarding UI-framework calls behind
`#if canImport(UIKit)` / `#if canImport(AppKit)`. **`StrandTraining`** keeps that base (`.iOS(.v16)`/
`.macOS(.v13)`) and also declares **`.watchOS(.v10)`** (FER-740). **`StrandDesign` is higher:**
`.iOS(.v17)` / `.macOS(.v14)` / `.watchOS(.v10)` so the watch app can paint with the design tokens —
both are pure (Foundation-only / SwiftUI behind `#if canImport(UIKit|AppKit)`, with `#if os(iOS)`
guards on the two haptic/hover-scrub spots). `WhoopStore`/`WhoopProtocol`/`StrandAnalytics`/
`StrandImport` are **not** watchOS-bound: no DB, BLE, or analytics runs on the wrist.

**Frozen identifiers from the NOOP legacy.** Bundle id `com.feriracheta.noop`, App Group
`group.com.feriracheta.noop` (entitlements / `project.yml`), on-disk folder `OpenWhoop/`
(`Cenit/Collect/StorePaths.swift`), and `noop.*` UserDefaults keys are load-bearing (data, pairing,
install). **Never rename them** — the visual rebrand to Cénit is complete, but these ids stay frozen
on purpose.

---

## 3. Package responsibilities and boundaries

Each package has a narrow contract. The dependency graph is acyclic and the leaf packages are
**platform-pure** (no CoreBluetooth, no UIKit/AppKit) so they run in CLI tools and tests:

```
StrandDesign        (no deps — pure SwiftUI)
StrandTraining      (no deps — pure domain types + bundled exercise catalog)

WhoopProtocol       (no deps)
   ▲
   │
WhoopStore ─────────▶ GRDB.swift + StrandTraining
   ▲
   │
StrandAnalytics ────▶ WhoopProtocol + WhoopStore   (NO StrandTraining dep: the strength engines —
                                                    MuscleFatigueMap FER-350, the 1RM estimator FER-346,
                                                    WeeklySplit FER-531 — take plain primitives the app
                                                    projects from StrandTraining types, keeping
                                                    StrandAnalytics decoupled)
StrandImport ───────▶ WhoopStore + StrandTraining + ZIPFoundation
```

| Package | Responsibility | Key types / functions | Notable boundary |
|---|---|---|---|
| **WhoopProtocol** | The reverse-engineering core: turn raw BLE bytes into typed rows. Framing, CRC, fragment reassembly, schema-driven field decode, stream extraction, historical-chunk classification. | `Reassembler`, `verifyFrame`, `parseFrame` → `ParsedFrame`, `extractStreams`, `extractHistoricalStreams`, `classifyHistoricalMeta`, `Streams`, `DeviceFamily`, `crc8`/`crc16Modbus`/`crc32` | **No CoreBluetooth.** Exposes GATT UUIDs as `String`; the app wraps them in `CBUUID`. |
| **WhoopStore** | Durable on-device persistence built on GRDB/SQLite. Migrations, decoded streams, metric caches, generic metric series, raw outbox, cursors. | `actor WhoopStore`, `makeMigrator()`, `insert(_:deviceId:)`, `dailyMetrics`, `sleepSessions`, `metricSeries`, `pruneRaw`, `ClockRef`, `RawBatchMeta` | An **`actor`** — all writes/reads run off the main thread on its serial executor. |
| **StrandAnalytics** | All physiological math, as pure functions over inputs. HRV, recovery, strain, sleep staging, workout detection, baselines, HR zones, correlation/comparison. | `AnalyticsEngine.analyzeDay(...)` → `DayResult`, `HRVAnalyzer`, `RecoveryScorer`, `StrainScorer`, `SleepStager`, `WorkoutDetector`, `Baselines`, `CorrelationEngine`, `DailyBriefEngine`, `WeeklySplit` (split → today's routine / day states / consistency streak, FER-531) | **Pure** — never touches the database. Produces `DailyMetric`/`CachedSleepSession` shapes for the store. |
| **StrandImport** | Parse data the user already owns: WHOOP CSV exports and Apple Health exports (`export.xml`, streaming). | `ImportCoordinator.detectAndImport`, `WhoopExportImporter`, `AppleHealthImporter`, `AppleHealthAggregator`, `SleepHKEncoder`/`SleepHKDecoder` | **Parsing only** — returns normalized model arrays; the app maps them into the store. |
| **StrandDesign** | The SwiftUI design system: palette, typography, motion, charts, components. | `StrandPalette`, `StrandCard`, `RecoveryRing`, `StrainGauge`, `Hypnogram`, `TrendChart`, `Sparkline`, `YearHeatStrip` | No data or protocol deps — pure presentation. |
| **StrandTraining** | Strength-tracker domain types + the bundled, read-only exercise catalog (**free-exercise-db**, 873 exercises with native slug ids; FER-923, was ExerciseDB OSS in FER-779). The value models WhoopStore persists and StrandAnalytics computes over. | `Exercise`, `ExerciseType`, `ExerciseCatalog`, `Routine`, `RoutineExercise` (with `supersetGroup`, FER-346), `RoutineSet` (per-set prescription, FER-492; optional per-set `RestConfig` override with exercise fallback, FER-715), `RoutineSchedule` (the weekly split, FER-531), `StrengthSession` (with persisted `energyKcal`/`EnergySource`, FER-715), `SetEntry`, `PersonalRecord` | **Pure** — Foundation only (no GRDB/UIKit). GRDB conformance lives in WhoopStore by extension. (FER-345) |

> **Exercise type override (FER-541).** The user can override an exercise's `ExerciseType` — including a catalog entry's (e.g. mark a "Plank" as time-based). The override is *user data*, so it lives in WhoopStore (`exerciseTypeOverride`, migration v24), **not** in the read-only bundled catalog. Precedence (user override > custom > catalog) is decided by the pure `ExerciseTypeResolver` and applied at a single resolver in `Cenit/Data/Repository+Strength.swift` (`resolvedExercise` / `allExercises`), which materializes the effective type into `Exercise.type`. Every downstream reader (guided session, builder, detail) sees the resolved type without bespoke logic; the catalog JSON is never mutated, so reverting is a plain delete.

> **Catalog adoption (FER-779 → FER-923).** The seed catalog is **free-exercise-db** (yuhonas — 873 real exercises, **The Unlicense / public domain**, native slug ids like `Barbell_Bench_Press_-_Medium_Grip`), baked offline by `Tools/bake-exercisedb/` into `exercises.json(.zlib)` (+ an `exercises.es.json(.zlib)` es-MX overlay, LLM-translated at bake). It **replaced ExerciseDB OSS** (~1500, non-commercial license + duplicates/junk) in FER-923: since Cénit ships its **own art** (FER-919), the base only needs clean data + a sane license, not media. free-exercise-db already uses Cénit's 17 canonical `MuscleAtlas` keys (identity, zero remap; `MuscleAtlas`/`MuscleVocabulary`/`MuscleFatigueMap` untouched); the bake derives `ExerciseType` from category/equipment/name and `bodyParts` from `primaryMuscles`. `Exercise.id` is the native slug, so media/data resolve **by id, without name matching**. The model carries `instructions`/`bodyParts`/`gifUrl`; custom exercises persist those via migration **v27**.
>
> **History remap (FER-923, migration v33).** Because the catalog source changed, the exercise ids changed too — and the user's saved history *does* reference them (`routineExercise`, `setEntry`, `personalRecord` [composite id `exerciseId:metric`], `learnedExerciseAlias`, `exerciseTypeOverride`, `progressionOptOut`). So FER-923 adds a **real history migration** (superseding FER-779's "no migration, fresh start" stance): v33 loads two baked maps from WhoopStore's bundle — `exercise-id-remap` (old ExerciseDB id → new slug, exact-name match) and `legacy-exercise-data` (old id → its record, for ids with no match) — and for every in-use id either **rewrites** the reference to the new slug, **materializes** a `customExercise` carrying the old id (no match), or leaves it (already a slug / user custom). Invariant: **zero orphaned history** (`MigrationTests.testV33Remap`). The bake also drops the old ExerciseDB stills (the new catalog ships no media; Cénit art lands per-id in FER-919) and rebuilds the import alias table (`build_aliases.py`) against the new names.

### Multi-generation protocol support

`WhoopProtocol` supports both strap generations through `DeviceFamily`:

- **`.whoop4`** — the original reverse-engineered protocol: `0xAA` SOF, `u16 LE` length, **CRC8**
  (poly `0x07`) header check, `CRC32` (zlib) payload trailer.
- **`.whoop5`** — the newer "puffin" transport: a format byte, **CRC16-Modbus** header check, and a
  set of packet types (e.g. `PUFFIN_COMMAND_RESPONSE` = 38, `PUFFIN_METADATA` = 56) that
  `canonicalTypeName(_:schema:)` aliases onto the 4.0 base names so they decode with the same logic.

`verifyFrame(_:family:)` and the `DeviceFamily` UUID/CLIENT_HELLO accessors are the single switch
points between generations; everything downstream of `parseFrame` is generation-agnostic.

---

## 4. The actor / concurrency model

Concurrency is deliberately split between two isolation domains plus a serial drain:

| Component | Isolation | Why |
|---|---|---|
| `WhoopStore` | **`actor`** | GRDB's `DatabaseQueue` calls block; the actor moves that blocking off the main thread onto its own serial executor. `DatabaseQueue` (not `DatabasePool`) is kept on purpose — the actor provides serialization. |
| `AppModel`, `LiveState`, `Repository`, `BLEManager`, `FrameRouter`, `Collector`, `Backfiller` | **`@MainActor`** | These observe/mutate published UI state. CoreBluetooth's central is created on `queue: .main`, so delegate callbacks already arrive on the main actor — no hopping needed to update `LiveState`. |
| Historical frame drain | **serial Task queue** | `BLEManager.routeBackfillFrame` appends frames synchronously (delegate order) and a single drain `Task` awaits `Backfiller.ingest` one frame at a time, so `HISTORY_START → data → HISTORY_END` chunk assembly can never be reordered. |

The key invariant: **frames are buffered synchronously in delegate-callback order**, and only the
slow work (decode + `await store.insert`) crosses out of the main actor. `Collector.flush()` and
`Backfiller.finishChunk()` both *snapshot-and-clear* their buffer before the first `await`, so
concurrent ingests accumulate cleanly into the next batch.

Two refinements keep that main-actor work small (FER-183). **Each inbound frame is parsed once** in
the BLE delegate loop — the single `ParsedFrame` is reused by the live `FrameRouter`, the GET_CLOCK
read, the clock-correlation and the live-gesture gate, instead of re-parsing the same bytes 2–3×.
And `Collector.flush()` runs its CPU-pure decode (`parseFrame` + `extractStreams`) in a
**`Task.detached`**, off the main actor, before the `await store.insert`; `Streams`/`ParsedFrame`
are `Sendable`, so the result crosses back safely. This is sound because `WhoopProtocol`'s schema is
now loaded **once into immutable shared state** (`CompiledProtocol.shared`, a `static let`) instead
of lazily mutated globals — so `parseFrame` is race-free even when first called concurrently from the
main actor and a detached task.

> **In flight (FER-173):** the BLE delegate itself still runs on the main actor (the central is
> created on `queue: .main`), which is why the `CBCentralManagerDelegate`/`CBPeripheralDelegate`
> conformances still carry a "crosses into main actor-isolated code" warning. Moving the central onto
> a dedicated serial `DispatchQueue` and the delegate off the main actor — so BLE I/O no longer
> competes with SwiftUI for the main thread — is tracked separately and must be verified on real
> hardware.

Two SQLite handles are open simultaneously — one inside `BLEManager`'s `Collector`/`Backfiller`, one
inside `Repository`. This is safe because `WhoopStore` enables **WAL journal mode** and a **5-second
busy timeout** (`PRAGMA journal_mode = WAL`, `config.busyMode = .timeout(5)`), so the writer and the
reader never deadlock on contention.

---

## 5. Live path vs. historical path

The two BLE data paths diverge at one branch in `BLEManager.peripheral(_:didUpdateValueFor:)`. After
the `Reassembler` yields a complete frame, `FrameRouter.handle(frame:)` always runs (it drives the
live UI state), and then:

```swift
if backfilling {
    if BLEManager.isOffloadFrame(frame) {   // types 47/48/49/50 only
        armBackfillTimeout()
        routeBackfillFrame(frame)           // serial drain → Backfiller
    }                                       // live type-40/43 flood is dropped during offload
} else {
    collector?.ingest(frame)                // live → Collector
}
```

### Live path (real-time)

1. **CoreBluetooth notify** on the data/cmd/event characteristics, or on standard HR `0x2A37`.
2. **`Reassembler.feed`** accumulates BLE fragments into complete `0xAA…CRC32` frames.
3. **`FrameRouter.handle`** runs `parseFrame`, rejects bad-CRC frames, and updates `LiveState`
   (`heartRate`, `rr`, `lastEvent`, `worn`, …). `EVENT` packets fire physical-input hooks
   (double-tap, wrist on/off) and a rate-limited catch-up sync trigger.
4. **`Collector.ingest`** buffers the frame. Once a `ClockRef` exists (from `GET_CLOCK`
   correlation), it flushes on cadence (`maxFrames: 64` or `maxInterval: 30s`):
   `parseFrame → extractStreams(clockRef) → store.insert` (**decoded first, durable**) →
   optionally `enqueueRawBatch` (raw, transient).
5. Standard `0x2A37` HR/RR is recorded **continuously and independently** via
   `Collector.ingestStandardHR` — it carries a wall-clock timestamp so it needs no clock
   correlation and keeps recording regardless of which screen is open.

Live `REALTIME_DATA` (type 40) timestamps are a **device monotonic epoch**; `extractStreams` maps
them to wall time with the linear `(device, wall)` offset captured at connect by
`ClockCorrelation`/`GET_CLOCK`.

### Historical path (offload / backfill)

The strap holds a ~14-day on-device biometric store. Cénit re-offloads it the way the official client
syncs — once per connect and then every `backfillIntervalSeconds` (900s) while connected+bonded — so
the periodic **type-47 historical offload is the primary metric source**, not the live stream.

1. `requestSync(_:)` gates every kick on connection state **and** `BackfillPolicy` (the rate
   limiter, persisted across relaunch) — except the `.drain` trigger, which bypasses the limiter on
   purpose (see step 5). On a go it calls `beginBackfill()`, which sends
   `SEND_HISTORICAL_DATA` and arms **two** timers: an *idle watchdog* (`backfillIdleTimeoutSeconds`,
   60s, re-armed on every offload frame) and an *absolute session cap*
   (`backfillAbsoluteTimeoutSeconds`, 300s, armed **once**, never re-armed by frames).
2. The strap streams `HISTORY_START → type-47 records → HISTORY_END (acked) … → HISTORY_COMPLETE` —
   except some WHOOP 4.0 firmware (e.g. FW 1.542.0.0) **never sends `HISTORY_COMPLETE`** (FER-201), so
   completion can't rely on that frame alone (see step 4).
3. `Backfiller.ingest` is a state machine driven by `classifyHistoricalMeta`. On each `HISTORY_END`
   it commits one chunk with a strict **local safe-trim invariant**:

   ```
   decode chunk  →  await store.insert (decoded durable)
                 →  await store.enqueueRawBatch (only if research toggle on)
                 →  await store.setCursor("strap_trim", …)
                 →  ackTrim (.withResponse confirmed ack to strap)
   ```

   A chunk is forgotten by the strap **only after** decoded data is locally durable and the ack is
   link-layer confirmed. If the idle watchdog fires (strap went silent) — or the absolute cap fires
   (strap keeps streaming offload frames but never signals `HISTORY_COMPLETE`, the WHOOP 4.0 wedge in
   FER-152/FER-174) — the session tears down, nothing in-flight is acked, and the durable `strap_trim`
   cursor lets the next session resume exactly where it left off. The absolute cap is the ultimate
   backstop that guarantees the "Sincronizando…" pill can never pin forever.
4. **Completion is positive, not just a timeout (FER-201).** A session ends as **success** two ways:
   the strap's own `HISTORY_COMPLETE`, or — for firmware that never sends it — `CaughtUpDetector`
   (`WhoopProtocol`, sibling of `RtcHealthPolicy`) judging the backlog drained from a sustained run of
   small `HISTORY_END` chunks (the offload has shrunk to the live ~1 Hz drip). `Backfiller` feeds it the
   per-END type-47 count **after** the safe-trim ack, flips `isBackfilling`/`didCatchUp`, and
   `BLEManager.afterBackfillIngest` tears down with `reason: "caught-up"` → `.completed` (stamps
   `lastSyncedAt`, green receipt). Completing on the heuristic is self-healing for *recorded* data: the
   durable `strap_trim` cursor + periodic re-sync drain any remainder next tick, so safe-trim loses nothing
   the band actually banked.

   **RTC-lost guard (FER-93).** A power-reset WHOOP 4.0 loses its volatile RTC and stops persisting biometry
   to flash, narrating `CONSOLE_LOGS` (type-50) with zero type-47 instead — so there's a real on-band gap no
   re-sync can fill (that night was never recorded; the safety net is the Apple-Health backfill, FER-153).
   `RtcHealthPolicy` (`WhoopProtocol`, sibling of `CaughtUpDetector`) judges this from the session's frame
   tallies (no `GET_CLOCK`, which this firmware never answers). When it reads "lost", `BLEManager`: (a) does
   **not** stamp a successful sync even on a clean `caught-up`/`HISTORY_COMPLETE` close — a
   narrating-not-saving END is excluded from `CaughtUpDetector`, so the offload can't complete "green"; and
   (b) re-asserts `SET_CLOCK` + the `SET_CONFIG` data-stream burst at the **start** of the next session
   (never mid-offload, which would stop the strap streaming), throttled per connect by `ClockReassertPolicy`
   (`WhoopProtocol`) so a never-latching band can't loop. Success is read the only way this firmware allows:
   type-47 flowing again.
5. **Auto-continue until drained (FER-287, ground-truth gate FER-480).** One session hands over only a
   few-hundred-frame batch, so a night's ~19,400-frame backlog (1 Hz × hours, phone disconnected) would
   otherwise need *dozens* of manual "Sync" taps — only `.manual` skips the rate-limiter. When a session
   closes **cleanly** (`HISTORY_COMPLETE` or caught-up) and **ground truth says backlog remains** — the
   strap's `GET_DATA_RANGE` newest banked record is still ahead of our persisted frontier (max HR ts) by
   more than `behindGapSeconds`, **or** the session persisted real sensor rows (the #451 stale-epoch
   fallback) — **and** the `strap_trim` cursor advanced this session (anti-spin), `BLEManager` immediately
   re-fires another session via the `.drain` trigger — skipping the limiter — and repeats until the strap
   is **caught up** (not ahead, or `CaughtUpDetector`) or the `maxChain` cap. `DrainContinuationPolicy`
   (`WhoopProtocol`, sibling of `CaughtUpDetector`) is the pure decision — FER-480 replaced its original
   frame-count heuristic with this ground-truth signal, retiring the unanchored `largeSessionFrames`
   guess; a non-clean close (idle timeout / session cap) **never** chains, so an unhealthy link falls
   back to the rate-limited path. The frontier is read async (via the Collector) after the session, so the
   decision runs in the post-session `Task`; a `state.draining` latch bridges that hop so the «Descargando
   la noche…» hero (FER-286) stays steady between chained sessions. Each chained session re-arms its own
   watchdog + 300 s cap, so the backstops are unchanged. `.drain` re-uses `SEND_HISTORICAL_DATA` (no new
   outbound bytes) and never touches `strap_trim`, so it changes only *when* the next session fires, never
   data integrity.

Type-47 records carry their **own real-unix timestamps**, so the historical path does *not* depend on
`GET_CLOCK`; if the clock correlation hasn't landed yet, `Backfiller` falls back to an identity
`ClockRef` and the offset math becomes a no-op.

### Why they differ

| Aspect | Live path | Historical path |
|---|---|---|
| Producer | `Collector` | `Backfiller` |
| Trigger | Continuous notify | `SEND_HISTORICAL_DATA`, rate-limited |
| Frame types | 40/43 (REALTIME) + 0x2A37 | 47/48/49/50 (HISTORICAL/EVENT/META/LOGS) |
| Timestamp source | Device epoch → wall via `ClockRef` | Real unix in the record |
| Durability unit | Cadence flush (64 frames / 30s) | One `HISTORY_END` chunk, trim-acked |
| Decode fn | `extractStreams` | `extractHistoricalStreams` |
| Role | Live HR/UI + opt-in detail | **Primary** metric source |

### Watch-mirrored strength sessions (FER-740, F1.1 of the Apple Watch epic FER-391)

A guided strength session can run as an **`HKWorkoutSession` mirrored from the Apple Watch** (iOS 17 /
watchOS 10 workout mirroring). The wrist (`CenitWatch/`) runs the real `HKWorkoutSession` and mirrors it
to the iPhone; there is **no GRDB on the watch**. State crosses the pairing over two channels: HealthKit's
mirror payload (`sendToRemoteWorkoutSession`, best-effort — rest windows via the reused
`RestActivitySnapshot`, pulse) and `WatchConnectivity` (`WCSession`, guaranteed + acked — the control
messages: start / end / "watch saved" / "watch won't save"). The single contract is `WorkoutMirrorMessage`
in `CenitShared`; the iPhone half is `WorkoutMirroringBridge` (`CenitApp/Health/`), wired into `AppModel`.

The iPhone stays the **single source of truth**: it persists the session to `WhoopStore` before any
HealthKit/watch step (decoded-first, unchanged). The **one-`HKWorkout` invariant** is held by the
deterministic shared key `HKMetadataKeyExternalUUID = "noop:strength:<sessionId>"`: whichever device writes,
the write is idempotent (delete-by-key then save). The iPhone omits its own `saveStrengthWorkoutIfEnabled`
**only** on a positive `watchDidSaveWorkout` ack (`WorkoutSaveGate`); otherwise it saves, so a missing/absent
watch is regression-free. Heart rate for the iPhone's own strain still comes from the WHOOP strap over BLE
**on the iPhone** — the watch is a control + display surface in F1.1, and adopting its physiology into the
recovery/strain engine is Phase 2.

The in-progress session is **durable across a crash/kill of the iPhone** (FER-798): a Codable
`StrengthSessionSnapshot` (defined in `StrandTraining`) is written to `WhoopStore`'s singleton
`inProgressStrengthSession` table on start and on each durable edit (debounced; immediate on rest
start/end), and restored in the launch `analysisTask` — so the Apple Watch's queued `.end` finds a live
session and saves the receipt instead of dropping the workout. The snapshot is deleted on save/discard.
The `HKWorkout` mirror is **not** rebuilt from the snapshot — HealthKit re-delivers the `mirroredSession`
when the process relaunches; the one-`HKWorkout` invariant is resolved at end time (`WorkoutSaveGate` +
the deterministic `externalUUID`), never from persisted state. When no session is recoverable, a hook
(`onNoRecoverableStrengthSession`) lets a caller close any orphaned Live Activity (FER-806).

### Session Live Activity + the app→widget media channel (FER-721 / FER-789 / FER-806)

FER-806 generalizes this from a **rest-only** Activity to one that lives the **whole session**: it is born
when the strength session starts (the `strengthSession` `didSet` → reconcile already produces a snapshot)
and persists through the active set, rest and pause until the receipt is up, then ends. `computeRestSnapshot`
became `computeSessionSnapshot`, gated on a pure `AppModel.sessionPhase(for:)` (`paused` → `.paused`;
`resting` → `.resting`; else `.active`) that returns `nil` (no session / receipt up) so the Activity ends.
The contract grew four Optional/defaulted fields (`sessionPhase`, `sessionStartedAt` = the effective active
anchor excluding paused time, `setsDone`/`setsTotal`); a pre-FER-806 Activity decodes them `nil` and the view
falls back to the rest layout. The lock-screen actions gained `resume` (leave «En pausa»), and `completeSet`
now applies in the active phase too (the «Completar» button). Crucially, the launch-time `endOrphans()` is no
longer unconditional — it would kill a legitimate card before crash-recovery restores its session; instead
FER-798's `onNoRecoverableStrengthSession` hook ends the orphan **only** when no session is recoverable (a
recoverable one is restored first and its reconcile adopts the running Activity). `staleDate` is
`restEndsAt + margin` in a rest but a rolling 1 h window in the active/paused phases (renewed per update; on
app death it expires → the card paints its `context.isStale` «Abre Cénit para continuar» state). The Apple
Watch mirror keeps FER-721's **rest-only** semantics (it only receives `pushRest` while genuinely resting),
so the wrist never shows a phantom countdown mid-set.

The same `RestActivitySnapshot` (`CenitShared`) drives the **session Live Activity** on the lock screen /
Dynamic Island (`RestActivityController`, `Cenit/LiveActivity/`) → `RestActivityAttributes.ContentState`
(`CenitWidgets/Shared/`, ActivityKit-gated). Lock-screen buttons fire `LiveActivityIntent`s
(`RestActivityIntents`) that don't apply anything inline — they **enqueue** onto a durable inbox in the
shared App Group `group.com.feriracheta.noop` (`RestActivityBridge`: `UserDefaults(suiteName:)` + a Darwin
notification), and the app drains it into `AppModel.applyRestAction` → the live `StrengthSessionModel`; the
normal reconcile loop reflects the result back onto the Activity. FER-789's four actions map to existing
model methods — **Completar ≠ Saltar**: `completeSet` logs the upcoming set (`registerCurrentSet`) and rests
again, `skip` only cuts the timer; `±30` is `extendRest` (−30 floored at now); `finishWorkout` registers the
last set and ends the session. The `ContentState`/`RestActivitySnapshot` contract is **additive and
Optional** so an Activity started under an older app decodes unchanged (missing keys → nil).

The widget extension can't read the app-local `MediaCache` (`applicationSupportDirectory`), so FER-789 opens
a **one-way app→widget media channel** through the App Group: `RestThumbnailProvider` (app) copies the active
exercise's already-cached thumbnail into `group…/RestThumb/<name>.jpg` at each rest, and the widget resolves
it via the shared `RestThumbnailStore` (same path constant, compiled into both targets). The snapshot carries
the file **name only, never image bytes** (kept small — ActivityKit serializes it on every update); the file
is a single slot, overwritten per rest and cleared when the rest/session ends and at launch. The
**"no thumbnail" state is first-class** (exercise media is opt-in, §"Network exceptions") — the card omits the
circle, never a placeholder. No network is introduced; the provider only copies a file the opt-in media
download already fetched.

---

## 6. The BLE connection lifecycle

`BLEManager` is the only CoreBluetooth surface. The connection handshake runs **exactly once per
connection** (guarded by `connectHandshakeDone`, because `didWriteValueFor` re-fires on every
confirmed write):

```
scan(customService) ─▶ didDiscover ─▶ connect ─▶ didDiscoverServices
   ─▶ discover characteristics ─▶ BOND (one confirmed GET_BATTERY_LEVEL write to …0002)
   ─▶ subscribe notify on cmd/event/data + 0x2A37 + 0x2A19
   ─▶ didWriteValueFor (bond ack) ─┬─ HELLO → SET_CLOCK → GET_CLOCK
                                   ├─ stop type-43 realtime flood, GET_DATA_RANGE
                                   ├─ requestSync(.connect)  (deferred ~1.5s)
                                   ├─ startBackfillTimer()   (re-offload every 900s)
                                   └─ startKeepAlive()       (re-arm realtime, poll battery, watchdog)
```

Supporting machinery, all on the main run loop:

- **Keep-alive (30s):** re-arms the realtime stream if wanted, polls battery, and — if **no
  notification has arrived for >120s** — bounces the link; the auto-rescan on disconnect re-bonds and
  resumes streaming.
- **Stuck-strap watchdog:** after each offload, `StuckStrapDetector` compares the strap's newest
  record (`GET_DATA_RANGE`) against Cénit's data frontier (`latestHRSampleTs`). Strap-ahead **and**
  frontier-frozen ⇒ a reboot hint banner; off-wrist / caught-up is *not* flagged.
- **Auto-reconnect:** an unintentional disconnect flushes the `Collector` and rescans after 3s.

`LiveState` is the published bridge: `BLEManager` and `FrameRouter` write it; SwiftUI observes it.
The app shell isolates the ~1 Hz HR/frame churn into a small status view so the rest of the
UI doesn't re-render on every beat.

---

## 7. Storage model (WhoopStore / SQLite)

GRDB drives a migrator (the migrator currently reaches `v35`; see `Database.swift` — the source of
truth is the migration list, not a constant). The schema groups into four
concerns:

**Durable decoded streams** — natural key `(deviceId, ts)`, one row per sample:
`hrSample`, `rrInterval`, `event`, `battery`, plus the type-47 biometrics `spo2Sample`,
`skinTempSample`, `respSample`, `gravitySample`.
- The five 1 Hz tables (`hrSample`, `rrInterval`, `skinTempSample`, `respSample`, `gravitySample`)
  are **`WITHOUT ROWID` + `STRICT`** with an **integer `deviceId` surrogate** as of **v21 (FER-513)**.
  A rowid table with a composite PK keeps a second `sqlite_autoindex` copy of the key + rowid on every
  row (~46% of the DB); `WITHOUT ROWID` makes the natural PK *be* the table (no autoindex), and the int
  surrogate replaces the repeated `"my-whoop"` TEXT — together ~−60% on these tables, zero data loss.
  The dead `synced` column (v5) is dropped from these five. `event`/`battery`/`stepSample`/`spo2Sample`
  keep TEXT `deviceId` + rowid (marginal / empty — out of scope). `spo2Sample` is decoded but no longer
  written (**v20, FER-511**) and its rows were purged; it survives empty for downgrade-safe reads.
- The surrogate map is **`deviceIdMap(deviceId TEXT PK, intId INTEGER UNIQUE)`** — distinct from
  `device` (hardware): writes/tests insert sample rows for source partitions that never have a `device`
  row, so binding the surrogate to `device.rowid` would JOIN-drop them. `WhoopStore` translates at the
  actor boundary via a `[String: Int64]` cache (`resolvedDeviceId`), so the public read/write API still
  takes `deviceId: String`. The write path creates the mapping on demand (never throws on an unknown id
  → the Backfiller, which acks+trims history even when `insert` fails, can't lose acked data).

**Metric caches** — the rolled-up shapes the screens read:
- `dailyMetric` — one row per `(deviceId, day)`: `recovery`, `strain`, sleep stage minutes,
  `restingHr`, `avgHrv`, `spo2Pct`, `skinTempDevC`, `respRateBpm`, `exerciseCount`.
- `sleepSession` — one row per `(deviceId, startTs)` with `efficiency`, `restingHr`, `avgHrv`, and
  a JSON `stagesJSON` hypnogram.
- `journal`, `workout`, `appleDaily` — imported journal answers, workouts (WHOOP + Apple Health),
  and Apple-Health daily aggregates.
- `experiment` (v12, FER-307) — one row per N-of-1 experiment, natural key `id` (UUID): the lever
  (`behavior` × `outcome`), `startDay`/`windowDays`, `status` (running/completed/canceled), and the
  verdict columns filled on completion. Additive only; one experiment runs at a time (app-enforced),
  but the table keeps the full history.
- `dietPlan` / `dietAdherence` (v14, +v16, FER-370/401) — a prescribed diet plan stored as an opaque
  `noop.diet.v1` JSON `payloadJSON` (PK `id`, + denormalized `nombre`/`idioma`/`ciclo`/`createdAt`),
  and per-meal daily adherence keyed `(deviceId, day, mealId)` with a tri-state `status`
  (cumpli/sustitui/salte) plus a nullable `optionIndex` (v16, FER-401) recording WHICH equivalent
  `opciones` index was eaten — registro only, it does not change the apego %. WhoopStore never decodes
  the plan (that's `StrandImport.DietPlan`); the apego % (FER-372) is computed from `dietAdherence`
  against the active plan's meal count. Mirrors `journal`.
- `inProgressStrengthSession` (v28, FER-798) — a singleton control table (0 or 1 row, PK `id`) holding a
  Codable `StrengthSessionSnapshot` as an opaque JSON blob: the guided strength session in progress, so a
  crash/kill of the iPhone doesn't lose the workout (written on start + each durable edit, restored at
  launch, deleted on save/discard). Ephemeral control state — prunable, outside the `WITHOUT ROWID`
  rebuild and the sync bookkeeping.
- `progressionOptOut` (v31, FER-835) — one row per `(sessionId, exerciseId)` when the user tapped
  «Volver a X» in that session: the load-progression classifier treats the session as neither hit nor
  miss. Written atomically inside `saveSession` (delete-first, so a re-save is idempotent), cleaned by
  `deleteSession`, surfaced by `workSetHistory` via LEFT JOIN, consumed as
  `ProgressionMath.PastSession.optedOut`.

**Generic metric series** — `metricSeries(deviceId, day, key, value REAL)`: a tall, long-format
table so *any* scalar metric from *any* source can be queried/compared uniformly (the substrate for
the Metric Explorer and correlations), indexed by `(deviceId, key, day)`. The nightly frequency-domain
HRV powers (`hrv_lf` / `hrv_hf` / `hrv_totalpower`, ms², FER-702) persist here under the `-noop`
computed source — an additive scalar cache with no schema change, alongside `steps_est` and the stress
aggregates. FER-868 added the daily motion derivatives under the same `-noop` source: `motion_intensity`
(the civil day's gravity motion volume, `StepsEstimateEngine.dayMotionIntensity` — the steps-estimate
input) and `act_h00`…`act_h23` (the per-local-hour motion profile feeding `CircadianEngine`'s cosinor;
a row exists iff the hour had samples, even at 0.0 — absent hour = no row, preserving the pooled-bins
semantics). Persisting them means the engine reads each day's raw `gravitySample` rows ONCE when the
day's data changes, instead of re-reading 60+14 days of gravity every 15-minute pass — and the derived
motion history survives both an app relaunch and a raw-stream safe-trim.

**Circadian phase** — `circadianPhase(deviceId, day, tempMinHour, acrophaseHours, offsetMinutes,
confidence, daysObserved, bedtimeHour, wakeHour, computedAt)`, PK `(deviceId, day)`: one structured
record per local civil day holding `CircadianEngine`'s cosinor phase estimate for the «Tu reloj
corporal» surface (FER-712). Written by the nightly `IntelligenceEngine` pass (gated to WHOOP bands —
the phase signal is the accelerometer rest-activity rhythm). A dedicated table, not `metricSeries`,
because the record is multi-field including an enum confidence. `confidence` is stored as the raw
`PhaseConfidence` string; `WhoopStore` keeps no dependency on `StrandAnalytics`.

**Raw outbox** — `rawBatch`: the compressed, **transient, prunable** record of original frames,
captured only when the research toggle is on. Decoded data is always committed *before* raw is queued,
so pruning raw (`PrunePolicy`: 24h window / 50MB cap) can never lose a metric. `cursors` holds durable
watermarks such as `strap_trim`.

`deviceId` is the per-source partition key. The app uses `"my-whoop"` for the strap and
`"apple-health"` for imported Apple Health, so per-source pages and cross-source "consensus" views
read the same tables filtered by source. On the five v21 `WITHOUT ROWID` sample tables the stored
`deviceId` is the integer surrogate from `deviceIdMap`; everywhere else it is still the TEXT partition
key. A one-time VACUUM after the v21 rebuild (and after the v20 spo2 purge) returns the freed pages to
the OS — each runs once per install, gated by a `cursors` flag (`rebuildVacuumV1Done` / `spo2VacuumV1Done`),
off the launch path; `auto_vacuum=INCREMENTAL` (FER-511) keeps later deletes reclaimable.

### Day-key convention (local civil day)

`dailyMetric.day` (and the additive-totals window behind it) is the device's **local civil day** in
**every** source — on-device computed (`my-whoop-noop`), Apple Health (`apple-health`), and imported
WHOOP (`my-whoop`, already local-of-cycle). The local day is derived by shifting the instant by the
device's UTC offset and formatting in UTC — the pure `AnalyticsEngine.dayString(_:tzOffsetSeconds:)` /
`localMidnight(_:tzOffsetSeconds:)` (offset passed explicitly so the math stays testable), the same
trick `WhoopImporter` uses with `tzOffsetMin`. Consumers pick "today" by the matching local key
(`Repository.localDayKey`); `IntelligenceEngine` sums steps/calories over `[localMidnight, +24h)`.
This is what makes the evening's strain/steps/HRV/sleep count for the correct day in a UTC− zone
instead of rolling into a "future-in-local" row (FER-226; consumer shielding in FER-224 / FER-228).

This **supersedes the UTC choice of FER-32** (which dated Apple Health by UTC to avoid duplicate rows
on time-zone travel). The cross-zone duplicate is now handled by last-writer-wins on the `(deviceId,
day)` PK — at most one defined seam on a travel day, never a silent duplicate. On update, a one-time,
flag-gated re-bucket (`cursors.dayKeyV2Done`, no schema change) re-groups the bounded recent window
from the still-stored raw streams / Apple Health onto the local day and prunes the spurious
future-in-local rows; days whose raw was already pruned keep their date (accepted seam, no data loss).

---

## 8. Imports (StrandImport)

Imports converge on the *same* store as the BLE paths, so history lights up instantly:

```
URL (export.zip / *.csv / export.xml / folder)
  └─▶ ImportCoordinator.detectKind  → .whoopExport | .appleHealth
        ├─ WhoopExportImporter   → cycles/sleeps/workouts/journal  → WhoopImporter      → store rows
        └─ AppleHealthImporter   → streamed export.xml (aggregated) → AppleHealthImport  → store rows
```

`StrandImport` is **parse-only**; the app's `WhoopImporter`/`AppleHealthImport` glue maps the
normalized results into `dailyMetric`, `sleepSession`, `workout`, `appleDaily`, and `metricSeries`
rows, then calls `Repository.refresh()`. Apple Health's `export.xml` is parsed with a streaming
reader so multi-hundred-MB files don't blow up memory.

The prescribed-diet path is a third producer on the same parse-only principle: `DietPlanImporter`
validates a `noop.diet.v1` payload — from the BYO-LLM "copy prompt" flow, a future on-device parse,
or manual entry — into a `DietPlan`, which the app maps to a `dietPlan` row (FER-370). The user
brings the JSON in, so Cénit still makes no network call.

Apple-Health sleep STAGES are the live-sync counterpart of the import path (FER-486): `HealthKitBridge`
reads `sleepAnalysis` category samples, and the pure `SleepHKDecoder` (`StrandImport`, the inverse of
`SleepHKEncoder`) groups them into one `CachedSleepSession` per night — gap-based, 1 h threshold —
mapping Apple's deep/REM/core/awake onto the `[{start,end,stage}]` `stagesJSON` the hypnogram already
reads, stored under `deviceId="apple-health"`. So a night that came from Apple (Combined-without-band,
or Apple-Health-only) draws the same per-epoch hypnogram as a strap night. The read-model merge
(`Repository.sleepSessions` → `mergeSleepSessions`) gates Apple sleep on `usesAppleHealth` and lets the
band win per night by interval overlap. No migration — the `sleepSession` table already partitions by
`deviceId`.

The **recovery** counterpart for a band-less night is an **estimate computed read-time** (FER-153), not a
stored value: `Repository.refresh` runs `AppleRecoveryEstimator` over the `apple-health` daily rows
(`appleRecoveryEstimates`, band-less nights only — the band wins wherever it has the night). The estimate is
**deliberately kept out of
`days`/`displayDays`** (`appleRecoveryEstimates` returns a `[day: estimate]` map on `DashboardData`, it is
NOT folded into the merge) — so **every recovery statistic over history stays band-measured**: the recovery
baseline, the rest-day baseline (`activityCosts`), the Coach's correlations/forecast (`InsightEngine`), the
strain↔recovery driver (`WhatMovesStrainEngine`), the metric-explorer/compare sweeps, the AI-coach average —
none can mix in an estimate, with no per-consumer carve-outs to maintain. The estimate surfaces for display
on **`repo.today` only** (a single-day override: today's row gets the estimate when the band didn't cover the
night), which is what the ring, the verdict and the recovery-detail hero read. `isEstimated` /
`recoveryConfidence` are derived from the same map; no column, no migration.

---

## 9. Analytics (StrandAnalytics)

`AnalyticsEngine.analyzeDay(...)` is a pure function: given a day's raw streams (`hr`, `rr`, `resp`,
`gravity`), a `UserProfile`, and personal `ProfileBaselines`, it runs the analyzers and returns a
`DayResult`:

- **`SleepStager`** detects in-bed sessions and stages them (deep/REM/light), producing per-session
  efficiency, resting HR, average HRV, and a hypnogram.
- **`HRVFreqDomain`** (FER-669) computes frequency-domain HRV (LF/HF/total power, ms²) from an R-R
  series via the Lomb-Scargle periodogram (Lomb 1976; Scargle 1982) on the uneven tachogram — no
  resampling — span-gated per Task Force (1996). **Additive**: feeds no recovery/strain/sleep output.
  Surfaced in the HRV detail (FER-702): `analyzeDay` computes the nightly `Bands` over the SAME in-bed
  session R-R as `avgHrv` (coherent by construction), the app persists the three powers to
  `metricSeries` under `-noop`, and `HRVSpectralBaseline` labels each band vs "your normal" by reusing
  `Baselines.foldHistory(logDomain:)` + z-score (log-normal HRV powers, Plews 2013) — no new estimator.
- **`RecoveryScorer`** normalizes nightly HRV/RHR (and a sleep-performance proxy) against baselines
  into a `0–100` score.
- **Baseline recalibration (FER-677).** `ProfileStore.baselineEpoch` (a `YYYY-MM-DD` local day-key in
  UserDefaults, with one level of undo via `previousBaselineEpoch`) cuts every nightly baseline fold:
  `Baselines.foldHistory(_:epoch:cfg:)` drops nights with `day < epoch` before the replay (delegating to
  the value-only fold, so all its invariants hold). `IntelligenceEngine` applies it to all five baselines
  (HRV/RHR/resp/temp/efficiency) and pass-1, and `AppleRecoveryEstimator.estimate(nights:epoch:)` applies
  it to the estimated path — so recovery re-anchors from the epoch on both the strap and Apple sides. It is
  a user setting, not derived data: **no GRDB schema**. `nil`/`""` epoch = no cut (byte-identical to before).
- **`AppleRecoveryEstimator`** (FER-153) scores an **estimated** recovery for a night that did not come
  from the band, from Apple Health's **SDNN** against the user's **own** Apple SDNN baseline — SDNN-vs-SDNN,
  **never converted to RMSSD** — reusing the same `RecoveryScorer` model. A separate baseline, never mixed
  with the strap's RMSSD; SDNN is a different construct (total vs vagal variability) and ultra-short/all-day,
  so the result is labelled «estimado» with a `ScoreConfidence` grade, never equated to a band recovery
  (Task Force 1996; Shaffer & Ginsberg 2017). Pure + DB-free; surfaced read-time (see §8), not persisted.
- **`CyclePhaseEngine`** (FER-672) estimates the current menstrual-cycle phase (follicular-lean vs
  luteal-lean) from the nightly `skinTempDevC` Cénit already persists (+ resting HR corroboration; HRV as
  conditional confidence only, decision H1). Robust z-index over the trailing window (median centre,
  IllnessWatch robust σ), ≥42-night gate, states `.learning` / `.noClearPattern` / `.estimated`. Pure,
  DB-free, **on-the-fly — no persistence, no migration, no new decode**. Opt-in, surfaced only in the
  Experiments sheet (Ajustes), off by default. Wellness / self-knowledge only, retrospective (temp
  confirms a phase with 1–3-day lag), never fertility/ovulation/contraception/diagnosis. Weights + gate
  are product-calibration knobs, not validated; see docs/ANALYTICS.md for citations.
- **`SourceLens`** (FER-623 / FER-631, formerly `HrvSourceLens`) keeps a baseline pure by source, with two
  lenses over one row classification (`appleDays` is app knowledge passed in; the package stays pure).
  `maskHrv(_:keep:appleDays:)` nils only `avgHrv` on the rows of the other source — the FER-623 path: the
  verdict scores HRV against the band (RMSSD) baseline only, the brief adds an **estimated** SDNN bullet on
  a band-less day, and `StressModel` z-scores each reading against the baseline of its own source.
  `maskForBaseline(_:keep:appleDays:)` (FER-631) nils **every cross-source column** — `avgHrv`,
  `restingHr`, `respRateBpm`, `deepMin`/`remMin`/`lightMin` — for band-anchored consumers (FER-632+): no
  band↔Apple metric is interchangeable without correction (RMSSD≠SDNN — Task Force 1996, Shaffer &
  Ginsberg 2017 — plus measured RHR/resp/stage offsets, FER-629). It is the column-level equivalent of
  `IntelligenceEngine.strapOnlyHistory` (whole-row drop): under the skip-and-hold folds both yield the
  same single-source baseline (pinned by test). The **z-score is the common currency** across sources;
  raw ms are never compared between them. `keep: .band, appleDays: []` is the identity for both lenses
  (a strap-only user is unchanged).
- **`StrainScorer`** integrates the day's HR window into a `0–21` cardiovascular load (Tanaka HRmax
  from age unless overridden).
- **`WorkoutDetector`** segments exercise bouts from HR + motion.
- **`Baselines`**, **`HRZones`**, **`CorrelationEngine`**, **`ComparisonEngine`**, and
  **`BehaviorInsights`** supply rolling baselines, zone math, and cross-metric/behaviour insights.
- **`SleepRegularity`** (FER-218) scores schedule consistency from a rolling window of nights: the
  circular standard deviation of the mid-sleep point (Wittmann et al. 2006; Mardia & Jupp 2000) plus the
  weekend "social-jetlag" shift. Pure + DB-free like the rest; the app feeds it onset/wake out of
  `repo.sleeps`. The SD (minutes) is the validated figure; the 0–100 score is presentation only.
- **`RecoveryForecast`** (FER-188) projects tomorrow's recovery one day ahead from the recent
  recovery series — a damped level+slope trend plus a bounded sleep-debt drag and an optional
  acute session-strain drag (FER-442, for the post-session "tomorrow ~X%" line in the strength
  summary; direction per Stanley 2013) — returning an `estimate` with a deliberately wide
  confidence range, or `nil` below ~two weeks of base (the UI then hides the block). A trend
  projection, never a guarantee; simple by design per the short-term autoregressive-forecasting
  evidence (De Sabbata & Simonini, *J Healthc Inform Res* 2025). Pure + DB-free; the app feeds it
  the recovery column out of `repo.days` (two consumers: the Recovery detail and the strength
  summary cost block).
- **`InsightEngine`** (FER-290) is the single orchestrator behind the redesigned Coach ("el Bucle"):
  it takes data already read from the store (`DailyMetric`, logged behaviours, sleep sessions) and
  runs a catalog of detectors — each a thin wrapper over one of the engines above (`BehaviorInsights`,
  `CorrelationEngine`, `Baselines`, `ComparisonEngine`, `RecoveryForecast`, `SleepRegularityIndex`,
  `ActivityCostEngine`, `ReadinessEngine`, `FitnessAgeEngine`, plus a sleep-debt aggregate) — and
  returns ranked `Insight`s with es-MX templates. It **re-implements no math**; its only new logic is
  statistical hygiene: every inferential detector feeds ONE Benjamini-Hochberg family
  (`MultipleComparisons`) so a finding is "significant" only when its FDR-adjusted q-value clears α
  alongside per-side sample and effect-size floors. A synthetic suite proves planted effects are
  recovered and pure noise is not (family-wise false-positive rate held near α). The LLM step
  (issue E) only rewrites the templates — it never produces a figure. Pure + DB-free. The behaviour
  family accepts a per-behaviour *eligible universe* (`Inputs.eligibleDaysByBehavior`, FER-385) so a
  source whose absence means "unknown" rather than "didn't happen" — diet adherence — only contrasts
  the days it was actually tracked; journal behaviours pass none and keep absence = "without".

- **`ExperimentVerdict`** (FER-307) is the N-of-1 "Prueba" engine behind the redesigned Coach: it
  judges whether a candidate lever (a logged behaviour × an outcome) *reproduced* prospectively over
  an experiment window. It re-implements no math — it delegates to `BehaviorInsights.effect` (Welch +
  pooled Cohen's d + the `minGroup` floor), comparing the window's adherent days (derived from the
  existing journal) against the user's baseline, and classifies a `Verdict` (`sustained` /
  `notSustained` / `insufficient`). A `sustained` verdict promotes the lever candidate→proven, which
  `InsightEngine.promoteProven` then projects onto the engine's output (the engine stays stateless;
  "proven" lives in the `experiment` table, not on the `Insight`). Pure + DB-free.

- **`TrajectorySimulator`** (FER-311) is the goal simulator's projector: it extends a goal metric's
  daily series over an N-day horizon as two paths — "como vas" (the trend) and "si cambias X" (the trend
  plus a proven lever's measured effect) — inside a confidence band that grows with √h. The trend is a
  **damped** level+slope (Gardner–McKenzie 1985) so long horizons plateau instead of extrapolating in a
  straight line; it reuses `RecoveryForecast.olsSlope`/`sampleSD` and is **metric-agnostic** (the app
  passes the focus series, generous `bounds`, and a *signed* `leverDelta`, so a higher-is-better metric
  and a lower-is-better one like resting HR share one projector with no special case). Returns `nil`
  below ~two weeks of base (the screen hides the chart). It never projects performance, only the
  measurable signal. Pure + DB-free.
- **`StressEngine`** (FER-376) is the intraday autonomic-activation ("stress") engine: a `0–3` curve
  for the current day from beat-to-beat RR, normalized against a **personal waking reference** (robust
  percentile RMSSD anchors over the recent ~7 days of *waking* buckets — high RMSSD = calm = 0, low =
  activated = 3, clamped). It reimplements no HRV math — it delegates per window to `HRVAnalyzer`
  (RMSSD, Task Force 1996; Malik 1989 cleaning). Unlike the daily `StressModel` it is **relative to the
  person's own waking day** (the daily resting/sleep baseline would read "maxed out all day"); noisy or
  active windows (HR-reserve gate, analogous to Firstbeat excluding activity) and excluded spans
  (sleep/movement) return `nil` ("no reading"), and a short history yields no reference (cold start),
  never a min-max fallback. The reference is computed **on the fly** from the already-stored
  `rrInterval` rows (no new migration, mirroring how the strain curve recomputes from `hrSample`);
  persisting a summary for performance and cross-day patterns is deferred to FER-378. Pure + DB-free.

Because the engine never touches the database, the same code runs over live-collected streams,
backfilled streams, or imported data interchangeably. **All derived values are approximate.**

---

## 10. Presentation (the app + StrandDesign)

The `Cenit` app shell (under `CenitApp/App/`) builds a single `AppModel`, injects it plus
`LiveState`, `Repository`, `ProfileStore`, `BehaviorStore`, and `GoalStore` (the Bucle's goal — a single
metric+date preference in `UserDefaults`, not a DB table, FER-311) into the environment, and presents the
shared screens under `Cenit/Screens/` (Today, Live, Breathe, Intervals, Compare, Sleep, Trends,
Workouts, Health, Apple Health, Data Sources, Automations, Settings, Support).
The home / lock-screen widgets live in `CenitWidgets/`.

Screens bind to `Repository`'s published `days`/`sleeps` caches (refreshed on data change, not on the
~1 Hz stream). The launch refresh runs in **two passes**: a ~90-day *first-paint* pass that publishes
immediately (`loaded == true`, `fullyLoaded == false`) so Today renders without waiting for the full
history, then a full pass whose merge work runs **off the main actor** (`Repository.assembleDashboard`,
nonisolated) and publishes the identical final dashboard (`fullyLoaded == true`). A monotonic
generation counter makes the most recently started refresh the only one that may publish, and a
first-paint pass can never overwrite a fully loaded dashboard (`Repository.shouldPublish`). **Rule:**
anything that *persists* a value derived from `repo.days` — `IntelligenceEngine.analyzeRecent`
baselines, `Repository.closeDueExperiment`, the restore offer — must gate on `repo.fullyLoaded`;
pure display readers may see the short window transiently and self-correct on the full publish.

`IntelligenceEngine.analyzeRecent` — the ~15-minute scoring loop — is **incremental per day and
off-main** (FER-868). Each pass takes ONE `WhoopStore.streamDayCounts` snapshot (COUNT(\*) per local
civil day per raw stream; sound because the stream writers only `INSERT … ON CONFLICT DO NOTHING`,
never UPDATE — a backfill that fills a gap moves the COUNT even when it doesn't move MAX(ts), and a
safe-trim lowers it) and compares each night's window signature (`AnalysisScheduler`, pure, in
`StrandAnalytics`) against an **in-memory** cache: clean nights replay their cached pass-1
`NightResult` with zero store reads; only dirty nights (plus today, always) pay the 8 stream reads +
`analyzeDay`. Pass 2 — the baseline seed + `recomputeRecovery` — still runs over ALL nights
unchanged, so the published scores are identical to a full pass; the upserts also still write the
full window (the detected-workout prune deletes-and-reinserts it). The cache is not persisted: a
relaunch costs one full first pass, and `force` / any context change (profile, tz, mode, baseline
epoch) resets it. The heavy body is a `nonisolated static runAnalysis(_:cache:store:)` run on a
`.utility` detached task — same pattern as `Repository.assembleDashboard` — with all repo-derived
inputs snapshotted contiguously on the main actor before the hop (FER-177/519); `analyzeRecent`
itself stays a thin `@MainActor` wrapper (guards → snapshot → hop → publish). The daily motion
derivatives it persists (`motion_intensity`, `act_hNN`) are described in §7 "Generic metric series".

Screens render with `StrandDesign` components — `RecoveryRing`, `StrainGauge`, `Hypnogram`,
`TrendChart`, `TrajectoryChart` (the goal simulator's two-path + confidence-band plot), `Sparkline`,
`YearHeatStrip` — over the `StrandPalette` tokens. `AppModel` also hosts
the opt-in, on-device behaviours (HR smoothing, illness/strain early-warning, stress nudges, HR-zone
haptic coaching, double-tap actions, wrist-wear automation, smart alarm) — all default-off and all
computed locally.

### Network exceptions (opt-in, off by default)

Cénit is offline by construction (§11.1) with exactly **two** deliberate, user-controlled exceptions,
both living in `Cenit/` (never in `Packages/`, which stays 100% offline so `swift test` over packages
is hermetic in CI):

- **AI Coach** (`Cenit/AI/AICoach.swift`) — bring-your-own-key LLM chat; nothing leaves the device
  until the user pastes their own provider key and asks a question.
- **Exercise media** (`Cenit/Media/`, FER-722/786) — opt-in thumb/video-loop cache from ExerciseDB,
  gated by `noop.exerciseMediaEnabled` (default off). `MediaDownloadCoordinator` is the single point
  where the toggle is read; both its entry points (`bulkDownloadThumbsIfNeeded`, `loopIfNeeded(for:)`)
  guard on `isEnabled` before touching `URLSession`, so toggle-off is zero requests by construction,
  not by convention. Media downloads once per exercise into
  `Application Support/OpenWhoop/MediaCache/{thumbs,videos}/` — presence of the file on disk **is** the
  "downloaded" record, no GRDB table — and stays there (offline-readable) until the user taps "Borrar
  media descargada"; turning the toggle off stops future downloads but never deletes the cache. Since
  FER-786 the download is a **plain GET of each exercise's baked `gifUrl`** (native ExerciseDB id, from
  the FER-779 catalog) off the public CDN `static.exercisedb.dev` — **no runtime name lookup, no API
  key** (the old `ExerciseDBClient`/RapidAPI path and its `EDBApiKey` were retired). An exercise with
  no `gifUrl` is a miss → the YouTube hand-off fallback stays.

### The «Instrumento diurno» theme (single warm day paper)

`StrandDesign` carries a second, light-mode visual language («Instrumento diurno», warm paper) whose
`InstrumentoTheme` role struct is injected through the `\.instrumentoTheme` Environment key. Screens
anchor it to the single day paper, `InstrumentoTheme.base`, via `.instrumentoTheme(.base)` (which also
sets `\.instrumentoFlat`, so shared chart components drop the legacy dark-system glow on paper). The
theme does **not** change with the clock.

FER-132 originally varied the theme by the device clock — a 60-second `InstrumentoThemeDriver`
interpolating all seventeen roles between dawn/day/dusk/night anchors in the perceptual **OKLab** space,
overridden app-wide by `View.instrumentoThemeByHour(solar:)`. **FER-398 retired that engine:** the owner
found the dimmed night parchment (`#A39C8F`) read as "the brightness dropped" rather than warmth, and
the design research placed time-of-day colour in *content*, not chrome (and Apple's convention is a
stable, user-controlled appearance). The app is now a single warm light paper at every hour, on every
screen — far less machinery (no anchors, no per-minute interpolation, no timer).

What survives in `InstrumentoThemeEngine.swift` is load-bearing for the parts that still encode the day:
`InstrumentoThemeEngine.localHour(of:calendar:)` and the injected `SolarWindow` feed the «Hoy»
`DiurnalDial` (its now-dot, day arc and sleep band still track the real clock — time as *datum*, not
tint), and the pure **OKLab** colour math (Ottosson 2020) backs the paper gradient
(`paperHi`/`paperLo`/`inkDim`), `DiurnalDial.dayGold`, `ReferenceRange`, and the AA-repairing
`positiveText`/`negativeText` (the base anchor's hues clear WCAG AA on its paper; pinned in
`InstrumentoThemeEngineTests` / `FitnessAgeContrastTests`). **Package purity:** sunrise/sunset
(`StrandAnalytics.SolarClock`, FER-133) is consumed by **injection** of a plain `SolarWindow` value,
never imported — `StrandDesign` remains the dependency-free leaf of the package graph, 100% offline
(`Date`/`Calendar` only).

---

## 11. Design principles, restated

1. **Offline by construction.** There is no network client anywhere in the data path. The strap, the
   SQLite file, and the UI are the whole system. Two narrow, user-controlled exceptions exist outside
   the data path — AI Coach and exercise media (FER-722) — both bring-your-own-key/off-by-default and
   documented in §10.
2. **Decoded-first durability.** Metrics are committed before raw is queued; the raw outbox is a
   prunable convenience, never the source of truth.
3. **Resumable safe-trim.** The strap forgets historical data only after Cénit has it durably and has
   confirmed the ack; a durable cursor makes every offload resumable.
4. **Pure cores, thin shell.** `WhoopProtocol`, `WhoopStore`, `StrandAnalytics`, and `StrandImport`
   are platform-pure and testable in isolation; the app target is the only CoreBluetooth/SwiftUI
   surface.
5. **Interoperability, not impersonation.** Cénit reads your strap and your exports for your own use.
   It is independent of WHOOP and is not a medical device.

---

## Attribution

Cénit's BLE protocol work builds on community reverse-engineering of the WHOOP straps:

- **johnmiddleton12/my-whoop** — WHOOP 4.0 protocol.
- **b-nnett/goose** — WHOOP 5.0 protocol.

See [`ATTRIBUTION.md`](../ATTRIBUTION.md) for full credits and [`DISCLAIMER.md`](../DISCLAIMER.md) for
the non-affiliation and not-a-medical-device notice.
