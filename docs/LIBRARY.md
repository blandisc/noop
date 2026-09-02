# Cénit — Cross-Platform Swift Library Reference

Cénit is a standalone, fully **offline** health app on **Apple Health**. It syncs
HealthKit into on-device SQLite, can import Apple Health exports, and computes
recovery, strain, HRV, and sleep locally — no cloud, no account.

This document is the reference for the **reusable, cross-platform Swift
packages** that make that possible. They are designed to be vendored and reused
independently of the app itself.

> **Not affiliated with WHOOP.** Cénit contains no WHOOP proprietary code,
> firmware, or assets and works only with the user's own device and data.
> **Cénit is not a medical device.** Every derived metric (HR, HRV, recovery,
> strain, sleep, SpO₂, temperature) is an approximation and is not clinically
> validated.

## Credits

- **`groue/GRDB.swift`** — SQLite persistence used by `CenitStore`.

---

## Package overview

| Package | Purpose | Pure / portable? | UI deps | External deps |
|---|---|---|---|---|
| **CenitStore** | GRDB/SQLite persistence: migrations, streams, raw outbox, metric caches | ✅ Pure (server-free) | none | GRDB |
| **StrandAnalytics** | HRV / recovery / strain / sleep / correlation math | ✅ Pure, deterministic | none | (BiometricStreams, StrandModels types) |
| **StrandImport** | Apple Health (`export.xml`, streaming) importers | ✅ Pure Foundation/XML | none | ZIPFoundation |
| **CenitDesign** | SwiftUI design system (palette, components, charts) | SwiftUI only | SwiftUI | none |

These packages declare the same platforms — **iOS 16+ and macOS 13+** — and
build with **swift-tools-version 5.9**. The non-UI packages are platform-pure:
they never import `CoreBluetooth`, `UIKit`, or `AppKit`, so they run unchanged in
CLI tools, tests, and on any platform. `CenitDesign` is the only SwiftUI package;
it builds on both iOS and macOS, bridging through `UIColor`/`NSColor` only where
unavoidable, guarded with `#if canImport(UIKit)` / `#if canImport(AppKit)`.

### Dependency graph

```
BiometricStreams / StrandModels  (root vocabulary + shared models)
      │
      ├──────────────► CenitStore        (+ GRDB, StrandTraining)
      │                     │
      ▼                     ▼
StrandAnalytics ◄───────────┘            (depends on BiometricStreams + StrandModels)

StrandImport   ──► CenitStore, StrandTraining   (+ ZIPFoundation)

CenitDesign   (standalone — SwiftUI only, no internal deps)
```

The app target (`Cenit/`, built by `Cenit`) is the integration layer: it owns
HealthKit sync, wraps the pure packages together, and presents the UI. The pure
packages are platform-agnostic and reusable on their own.

---

## CenitStore

On-device persistence built on **GRDB/SQLite**. Stream tables are durable; raw
frames are a transient, compressed, prunable outbox. The store is an `actor`, so
its API is `async` and all `DatabaseQueue` work runs off the main thread on the
actor's serial executor.

**Sources:** `CenitStore.swift`, `Database.swift` (the migrator),
`StreamStore.swift`, `Reads.swift`, `RawOutbox.swift`, `Cursors.swift`,
`MetricsCache.swift`, `JournalWorkoutAppleCache.swift`, `MetricSeriesStore.swift`.

> **Note.** Schema version numbers and table inventories in this section may lag
> the live migrator — see [`DATA_MODEL.md`](DATA_MODEL.md) and
> `Packages/CenitStore/Sources/CenitStore/Database.swift` for ground truth.

### Depend on it

```swift
// Package.swift
dependencies: [
    .package(path: "../CenitStore"),
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "CenitStore", package: "CenitStore"),
    ]),
]
```

### Schema

The migrator (`CenitStore.makeMigrator()`) runs versioned migrations on open. The
store enables WAL journal mode, `synchronous = NORMAL`, a page cache, mmap, and a
busy timeout so two handles to the same file don't deadlock.

| Table | Purpose | Natural key |
|---|---|---|
| `device` | known devices (historical) | `id` |
| `hrSample`, `rrInterval`, `event`, `battery` | decoded stream tables | `(deviceId, ts[, …])` |
| `spo2Sample`, `skinTempSample`, `respSample`, `gravitySample` | biometric stream tables | `(deviceId, ts)` |
| `rawBatch` | zlib-compressed raw-frame outbox | `batchId` |
| `cursors` | named highwater/read cursors | `name` |
| `sleepSession`, `dailyMetric` | cached derived metrics | `(deviceId, startTs)` / `(deviceId, day)` |
| `journal`, `workout`, `appleDaily` | journal + workouts + Apple-Health daily | various |
| `metricSeries` | generic long-format (EAV) metric store | `(deviceId, day, key)` |

### Key public API

**Open / lifecycle**

```swift
public init(path: String) async throws          // open (creating) + migrate
public static func inMemory() async throws -> CenitStore   // tests
public static let schemaVersion: Int             // on CenitStoreInfo
```

**Write streams** (idempotent upsert by natural key; returns rows actually inserted)

```swift
public func upsertDevice(id: String, mac: String?, name: String?) async throws
@discardableResult
public func insert(_ streams: Streams, deviceId: String) async throws
    -> (hr: Int, rr: Int, events: Int, battery: Int,
        spo2: Int, skinTemp: Int, resp: Int, gravity: Int)
```

**Range reads** (each `(deviceId, from, to, limit)`, oldest-first)

```swift
public func hrSamples(...)  -> [HRSample]
public func rrIntervals(...) -> [RRInterval]
public func events(...)      -> [StreamEvent]
public func batterySamples(...) -> [BatterySample]
public func spo2Samples(...) / skinTempSamples(...) / respSamples(...) / gravitySamples(...)
public func latestHRSampleTs(deviceId:) async throws -> Int?
public func storageStats() async throws -> (decodedRows: Int, rawBatches: Int, rawBytes: Int)
```

**Raw outbox** (`RawOutbox.swift`) — frames packed and zlib-compressed via
Apple's Compression framework:

```swift
public func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws
public func rawFrames(batchId: String) async throws -> [[UInt8]]
public func pendingRawBatches(limit:) async throws -> [RawBatchMeta]
@discardableResult
public func pruneRaw(now:keepWindowSeconds:maxUnsyncedBytes:) async throws -> Int
```

**Caches & cursors** — `upsertSleepSessions`, `upsertDailyMetrics`,
`sleepSessions`, `dailyMetrics` (`MetricsCache.swift`); `upsertJournal`,
`upsertWorkouts`, `upsertAppleDaily` (`JournalWorkoutAppleCache.swift`);
`upsertMetricSeries`, `metricSeries`, `metricKeys`, `metricDays`
(`MetricSeriesStore.swift`); `setCursor` / `cursor` / `setHighwater` /
`highwater` (`Cursors.swift`). The cache row models — `DailyMetric`,
`CachedSleepSession`, `JournalEntry`, `WorkoutRow`, `AppleDaily`, `MetricPoint`
— are all public `Codable` structs.

### Minimal usage

```swift
import CenitStore

let store = try await CenitStore(path: "/path/to/noop.sqlite")
try await store.upsertDevice(id: "device-1", mac: nil, name: "Apple Watch")

// Persist stream rows (idempotent — safe to replay).
let counts = try await store.insert(streams, deviceId: "device-1")
print("inserted HR:", counts.hr)

// Read a day back out.
let hr = try await store.hrSamples(deviceId: "device-1",
                                   from: dayStart, to: dayEnd, limit: 100_000)
```

---

## StrandAnalytics

Pure, deterministic on-device analytics: HRV, recovery, strain, sleep staging,
workout detection, baselines, and statistical comparison/correlation. **No
database access** — every entry point is a pure function over its inputs (it
consumes `BiometricStreams` / `StrandModels` types and produces `CenitStore` cache
shapes, but performs no I/O). All derived values are explicitly **approximate**.

**Sources:** `HRVAnalyzer.swift`, `RecoveryScorer.swift`, `StrainScorer.swift`,
`HRZones.swift`, `Baselines.swift`, `SleepStager.swift`, `WorkoutDetector.swift`,
`AnalyticsEngine.swift` (orchestrator), `CorrelationEngine.swift`,
`ComparisonEngine.swift`, `BehaviorInsights.swift`.

### Depend on it

```swift
// Package.swift
dependencies: [
    .package(path: "../StrandAnalytics"),
],
targets: [
    .target(name: "MyTarget", dependencies: ["StrandAnalytics"]),
]
```

### Key public API

| Type | Entry points |
|---|---|
| `HRVAnalyzer` | `analyze(_:windowStart:windowEnd:)` and `analyze(rawRR:)` → `HRVResult` (RMSSD, SDNN, meanNN, pNN50). Range filter [300, 2000] ms + Malik 20%-local-median ectopic rejection; needs ≥ 20 clean beats. |
| `RecoveryScorer` | `restingHR(_:start:end:)`; `recovery(...)` → 0–100 (HRV-dominant z-score + logistic composite); `band(_:)` → `"red"`/`"yellow"`/`"green"`. |
| `StrainScorer` | `strain(_:maxHR:restingHR:method:sex:denominator:)` → 0–21 (Edwards/Banister TRIMP, log-mapped); `tanakaHRmax(age:)`, `estimateHRmax(_:age:)`, `trimpToStrain(_:)`. |
| `HRZones` | `zones(age:maxHROverride:)` → `HRZoneSet`; `timeInZone(_:zoneSet:)` → `TimeInZone`. |
| `Baselines` | `update(_:value:cfg:)` → `BaselineState` (Winsorized-EWMA personal baselines + `BaselineStatus`); standard `metricCfg` for HRV / resting HR / resp / skin temp. |
| `SleepStager` | `detectSleep(hr:rr:resp:gravity:)` → `[SleepSession]` (in-bed detection + approximate 4-class staging); `hypnogramMetrics(_:)` → `HypnogramMetrics`. |
| `WorkoutDetector` | `detect(hr:gravity:restingHR:maxHR:age:profile:)` → `[ExerciseSession]`; `Calories.estimateBoutCalories(...)`. |
| `AnalyticsEngine` | `analyzeDay(day:hr:rr:resp:gravity:profile:baselines:maxHROverride:)` → `DayResult` — the orchestrator that rolls everything into a `DailyMetric` + sleep/workout sessions. |
| `CorrelationEngine` | `pearson(_:)`, `alignByDay(_:_:)`, `lagged(x:y:lagDays:)` → `Correlation`. |
| `ComparisonEngine` | `stat(_:)` → `SeriesStat`; `compare(current:previous:)` / `monthOverMonth(...)` → `PeriodComparison`. |
| `BehaviorInsights` | `effect(behaviorDays:...)` → `BehaviorEffect`; `rank(...)`, `sentence(_:)`. |

`UserProfile` (`weightKg`, `heightCm`, `age`, `sex`) is the shared profile input.

### Minimal usage

```swift
import StrandAnalytics

// HRV over a night's R-R intervals.
let hrv = HRVAnalyzer.analyze(rrIntervals, windowStart: bedStart, windowEnd: wakeEnd)
print("RMSSD:", hrv.rmssd ?? .nan, "ms")

// Day strain from the full HR series.
let strain = StrainScorer.strain(hrSamples, maxHR: 190, restingHR: 50)  // 0…21

// Full-day rollup (sleep + recovery + strain + workouts) in one call.
let day = AnalyticsEngine.analyzeDay(
    day: "2026-06-07",
    hr: hrSamples, rr: rrIntervals, gravity: gravitySamples,
    profile: UserProfile(weightKg: 78, heightCm: 182, age: 34, sex: "male")
)
print("recovery:", day.recovery ?? .nan, "strain:", day.strain ?? .nan)
```

---

## StrandImport

Parser for the Apple Health export format a user can bring offline
(`export.zip` / `export.xml`, streamed so a multi-hundred-MB file never loads
fully into memory). This layer is **parsing only** — it produces normalized Swift
model arrays and an `ImportSummary` and does not touch the database, so the whole
package is unit-testable.

**Sources:** `ImportCoordinator.swift` (top-level + auto-detection),
`AppleHealthImporter.swift`, `AppleHealthAggregator.swift`, `ImportModels.swift`.

### Depend on it

```swift
// Package.swift
dependencies: [
    .package(path: "../StrandImport"),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: ["StrandImport"]),
]
```

### Key public API

```swift
public struct ImportCoordinator {
    public init(appleHealth: AppleHealthImporter = .init())

    public func importAppleHealth(from url: URL) throws -> AppleHealthImportResult
}
```

- **`AppleHealthImporter`** — `import(from:)` accepts a folder, `export.zip`, or
  `export.xml`; `importXML(at:)` / `importXML(data:)` stream-parse via
  `XMLParser`. `relevantTypes` lists the captured HealthKit types (HR, resting
  HR, HRV SDNN, SpO₂, body/wrist temperature, respiratory rate, energy, VO₂max,
  steps, sleep analysis, body composition). Returns `AppleHealthImportResult`
  (`samples`, `workouts`, `sleepIntervals`, `summary`).
- **`AppleHealthAggregator`** — `daily(samples:)`, `sleepDaily(...)`,
  `aggregate(_:)` roll samples into per-civil-day `AppleDailyAggregate`s;
  `metricPoints(_:)` projects them into `(day, key, value)` triples ready for
  `CenitStore.upsertMetricSeries`.

Models include `HealthSample`, `HealthWorkout`, `SleepStageInterval`,
`SleepStage`, `ImportSummary`, and the `ImportError` enum.

### Minimal usage

```swift
import StrandImport

let coordinator = ImportCoordinator()
let result = try coordinator.importAppleHealth(from: fileURL)
let daily = AppleHealthAggregator.aggregate(result)
let points = AppleHealthAggregator.metricPoints(daily)   // → upsertMetricSeries
print("Apple daily rows:", daily.count)
```

---

## CenitDesign

The SwiftUI design system — the only UI package. Palette, type scale, motion
presets, and the signature data components (Hypnogram, trend/sparkline charts,
year heat strip, cards, status pills). Builds on **both iOS and macOS**; it
imports only `SwiftUI` and bridges to `UIColor`/`NSColor` for color-component
extraction under `#if canImport(UIKit)` / `#if canImport(AppKit)`.

**Sources:** `Palette.swift`, `Typography.swift`, `Motion.swift`, plus the
component views `Hypnogram.swift`, `TrendChart.swift`, `Sparkline.swift`,
`YearHeatStrip.swift`, `StatePill.swift`, `Components.swift` — the full
rol → símbolo → archivo index is generated into
[CATALOGO.md](design-system/CATALOGO.md).

### Depend on it

```swift
// Package.swift  (no internal Cénit deps — standalone)
dependencies: [
    .package(path: "../CenitDesign"),
],
targets: [
    .target(name: "MyAppUI", dependencies: ["CenitDesign"]),
]
```

### Key public API

**Tokens**

- `StrandPalette` — every semantic color token: surfaces
  (`surfaceBase`/`surfaceRaised`/`surfaceOverlay`/`surfaceInset`), `hairline`,
  text (`textPrimary`/`textSecondary`/`textTertiary`), `accent`, the recovery
  gradient stops (`recoveryStops`), and recovery/strain color sampling. A
  `Color(hex:)` initializer supports `RRGGBB` / `RRGGBBAA`.
- `StrandFont` — the full type scale with tabular digits: `display(_:)`,
  `title1`/`title2`, `headline`, `body`, `subhead`, `caption`, `footnote`,
  `overline`, `mono(_:weight:)`, `number(_:weight:)`.
- `StrandMotion` — spring/animation presets: `interactive`, `gentle`, `hero`,
  `drawIn`, `breathe`, `pulse`, `fade`, and the `durationFast`/`durationStandard`/
  `durationSlow` constants.

**Components** (all public `View`s)

| View | Role |
|---|---|
| `Hypnogram` | sleep-stage timeline |
| `TrendChart`, `Sparkline` | line/area charts |
| `YearHeatStrip` | year-at-a-glance heat strip |
| `liquidGlass(_:)` | card/pill/dock surface (the dark-legacy card primitives were retired in FER-444) — see [CATALOGO.md](design-system/CATALOGO.md) |
| `StatePill`, `ConnectionDot`, `SourceBadge` | status chips / source labels |
| `StatTile`, `SegmentedPillControl` | layout primitives |

Full index (rol → símbolo → archivo → cuándo usarlo → cuándo no): see
[CATALOGO.md](design-system/CATALOGO.md).

### Minimal usage

```swift
import SwiftUI
import CenitDesign

struct TodayHeader: View {
    let score: Double
    let theme: InstrumentoTheme
    var body: some View {
        VStack(spacing: 16) {
            StatTile(label: "Recuperación", value: "\(Int(score))", unit: "%", theme: theme)
            Text("Today")
                .font(StrandFont.overline)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .padding()
        .background(StrandPalette.surfaceBase)
    }
}
```

---

## Reuse notes

- **Pick only what you need.** `CenitStore` adds GRDB; `StrandImport` adds
  ZIPFoundation; `StrandAnalytics` is pure over stream/model types and does no I/O.
  A headless tool can analyze stored samples with no SwiftUI involved at all.
- **Determinism.** The analytics packages are pure and deterministic — the same
  inputs always yield byte-identical outputs, which is what makes their
  golden-fixture tests possible and what makes them safe to run fully offline on
  the user's own data.
