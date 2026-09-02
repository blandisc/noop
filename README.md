<p align="center">
  <img src="docs/assets/banner.svg" alt="Cénit — on-device health on Apple Health" width="860">
</p>

<h1 align="center">Cénit</h1>

<p align="center"><b>Your body. Your data. Your machine. Local-first, no cloud.</b></p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%2017+-0C8F62?style=flat-square">
  <img alt="On-device" src="https://img.shields.io/badge/on--device-only-0C8F62?style=flat-square">
  <img alt="Account free" src="https://img.shields.io/badge/account-free-0C8F62?style=flat-square">
  <img alt="Apple Health" src="https://img.shields.io/badge/source-Apple%20Health-6F6857?style=flat-square">
  <a href="LICENSE"><img alt="License: PolyForm Noncommercial 1.0.0" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-6F6857?style=flat-square"></a>
</p>

<p align="center">
  <a href="#download">⬇&nbsp;Download</a> ·
  <a href="#features">Features</a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a>
</p>

<p align="center"><sub>Cénit began life as <b>NOOP</b> — the name some paths and identifiers still carry.</sub></p>

---

## Download

Cénit is an iOS app — you build it from source:

| Platform | Build | Notes |
|---|---|---|
| **iOS** | Build from source — see [`docs/BUILD.md`](docs/BUILD.md) | App + Watch + widgets + HealthKit. **Not distributed as a download:** iOS has no anonymous install path — the App Store and TestFlight both require a real Apple Developer identity — so it's build-it-yourself in Xcode. |

See [`docs/BUILD.md`](docs/BUILD.md) for the full build instructions.

Everything runs **on your device**. There is no account and no Cénit server. Optional exceptions (off unless you turn them on): an **iCloud Drive backup** of the local database, and the **ExerciseDB** animation downloader in Settings.

---

Cénit is a standalone, fully **on-device** health app built on **Apple Health**.
It syncs HealthKit samples into a local SQLite database on your iPhone and
computes preparedness, strain, HRV, and sleep **locally**, with no account and
no required cloud. Historical band data from older installs is preserved in
SQLite but dormant (WHOOP BLE was retired in FER-1003).

> **Not affiliated with WHOOP.** Cénit is an independent project. It is not
> affiliated with, endorsed by, or connected to WHOOP, Inc. **Cénit is not a
> medical device**; every derived metric is an approximation, not clinical
> data. See [`DISCLAIMER.md`](DISCLAIMER.md).

---

## Contents

- [Why Cénit](#why-cénit)
- [Features](#features)
- [Platform status](#platform-status)
- [Architecture](#architecture)
- [Quickstart](#quickstart)
- [How your data flows](#how-your-data-flows)
- [Privacy](#privacy)
- [Attribution](#attribution)
- [Disclaimer](#disclaimer)
- [License](#license)
- [Docs](#docs)

---

## Why Cénit

Your biometrics are yours. Cénit is built on that premise:

- **Own your data.** Cénit reads from **Apple Health** (and optional file imports)
  and writes everything to a local SQLite database on your iPhone. Nothing is
  uploaded unless you opt into backup or exercise media.
- **Account-free and on-device.** Cénit never creates an account and never phones
  home. Health data stays in the app sandbox.
- **Bring your history.** Already have years of data in Apple Health? Sync it
  once and it's permanently on your machine. You can also import an Apple Health
  `export.xml` from **Ajustes → Fuentes de datos**.
- **Transparent math.** Strain, HRV, sleep, and the daily preparedness verdict
  are recomputed on-device from documented, citable methods (Task Force 1996 HRV,
  Karvonen %HRR, Edwards / Banister TRIMP, Tanaka HRmax, and so on). The
  algorithms are approximations of — not reproductions of — any proprietary
  model, and every analyzer file documents exactly what it does.

---

## Features

The live shell is **four tabs** (`RootTabView` / `TabRouter`):

| Tab | What's there |
|---|---|
| **Hoy** | Home. An ecosystem hero (orb, moons, guardian) with a **Preparedness** verdict, then a three-shelf matrix: decide your day (sleep, resting HR), watch (temperature / respiration), and context (load, HRV / stress, steps). Pull down to sync Apple Health. **En vivo** is not a tab — it opens as a cover from Hoy. |
| **Tendencias** | Longer-range body. Period chips (W / M / 3M / 6M / 1Y / ALL). Hero is the **Preparedness** word, not a 0–100 recovery score (that scorer is retired from the UI). Modules: rest & load, training load (ACWR), vitals, activity, longevity (fitness age, VO₂max). Compare + see-all at the bottom. |
| **Entrenar** | Today's routine hero with **Empezar** and shortcuts (quick strength, intervals, 20 min mobility, 3 min breathe), plus a mosaic: week, dose, hills, body map, marks + volume, consistency, history. Strength opens a full-screen **Hoja** (`RoutineSheet` live): log weight/reps, rest, focus mode; save writes `strengthSession` + sets locally (discarded if you logged no sets). Apple Watch mirroring is optional. |
| **Ajustes** | Profile (age / sex / weight / height / HRmax), units, data sources + backup, recovery recalibration, opt-in ExerciseDB animations, illness watch, morning notice, workout reminder, FA history, display/sound/rest alerts, experimental metrics, cycle phase, About. |

There is also a first-run **onboarding wizard**, Home-screen / Lock-screen
**widgets**, and an in-app **"What's new"** changelog.

**Retired from the live shell (still in git history):** a fifth **Coach / Patrones** tab (archived FER-240) and WHOOP BLE pairing (retired FER-1003). Do not treat those as current product.

---

## Platform status

Cénit's logic lives in Swift packages. The iOS app syncs **Apple Health** and
scores preparedness, strain, and sleep **on your own device**.

| Platform | Status |
|---|---|
| **iOS** | ✅ The app (`Cenit`, SwiftUI, **iOS 17+**) — app target + Watch + widgets + HealthKit. Syncs Apple Health and scores preparedness / strain / sleep on-device. **Build-from-source only, not distributed.** |

Cénit is **iOS-only** today — earlier macOS and Android experiments have been
retired. The packages stay portable so a future port is technically possible;
none is in development right now.

### What to expect when you start

- **Apple Health sync** pulls samples when the app comes to the foreground
  (and on pull-to-refresh). HealthKit authorization is requested from the empty
  Hoy state, not silently at launch.
- **Strain and sleep** appear once HealthKit has enough recent history.
- **Preparedness** needs a few nights to learn your baseline, then updates
  each night.
- **In a hurry?** Import an Apple Health `export.xml` in **Ajustes → Fuentes de
  datos** and your full history fills in about a minute.

On the **Simulator**, HealthKit is unavailable; screenshot fixtures fill the UI.

---

## Architecture

The repository is split into platform-pure Swift packages plus the iOS app target
(`Cenit`). All packages declare both `.iOS(.v16)` and `.macOS(.v13)` so the pure
logic builds and tests without an app;
framework-specific UI is guarded with `#if canImport(UIKit)` / `#if canImport(AppKit)`.

```
Cenit/                 SwiftUI app layer — AppModel, Repository, Screens
CenitApp/              iOS app shell — HealthKitBridge, RootTabView, widgets, intents
CenitWatch/            watchOS companion (optional HR mirroring)
CenitWidgets/          WidgetKit extension (Home / Lock-screen widget)
CenitShared/           code shared between the app and the widgets
Packages/
  BiometricStreams/     neutral vocabulary of biometric rows (pure, zero deps)
  CenitStore/           GRDB/SQLite persistence (versioned migrations, currently through v41)
  StrandAnalytics/      HRV / preparedness / strain / sleep math (pure, DB-free)
  StrandTraining/       strength domain (catalog, sets/reps, routines)
  StrandImport/         Apple Health importers
  CenitDesign/         SwiftUI design system
  StrandModels/         shared models
Tools/                  developer scripts (localization, screen captures, design lint)
```

> The packages keep their original `Strand*` names from earlier eras; the app
> layer is `Cenit/` (display name **Cénit**).

### `CenitStore` — local SQLite via GRDB

Everything is stored on-device in SQLite (using
[GRDB.swift](https://github.com/groue/GRDB.swift)). The schema is a versioned
migrator in `Packages/CenitStore` (`Database.swift`, currently through **`v41`**).
Live HealthKit rows land under `deviceId = "apple-health"`. An older `"strap"`
partition from the WHOOP era is **dormant**, not deleted — `SourceModeStore` is
pinned to `.appleHealthOnly`.

### `StrandAnalytics` — transparent, on-device math

Pure, database-free analyzers. Each is documented and grounded in published
methods (and is explicitly an approximation, not a reproduction of any proprietary
model). The live UI verdict is **Preparedness** (categorical), not a 0–100
recovery score.

| File | Computes |
|---|---|
| `HRVAnalyzer.swift` | RMSSD + SDNN from R-R intervals (Task Force 1996), with range + Malik ectopic filtering. |
| `Preparedness.swift` / `ReadinessEngine.swift` | The Hoy / Tendencias verdict — HRV vs baseline, RHR drift, load balance (ACWR), and related signals. |
| `StrainScorer.swift` | A logarithmic strain scale from %HRR (Karvonen) and Edwards / Banister TRIMP. |
| `NocturnalHRV.swift` | Night RMSSD from Apple Health heartbeat series. |
| `FitnessAgeEngine.swift` / `VitalityEngine.swift` | Longevity-facing reads (fitness age, VO₂max, etc.). |

A legacy `RecoveryScorer` (0–100) still exists in the package; it is **not**
what the production tabs show.

### `StrandImport` — bring your own history

- **Apple Health export** (`AppleHealthImporter.swift`): a **streaming** SAX parser
  (`XMLParser`) for `export.xml` (which can exceed 1 GB), with correlation-dedupe,
  unit normalization (e.g. SpO₂ fraction → %), and sleep-stage mapping.

### `CenitDesign` — the SwiftUI design system

Palette, typography, motion, and reusable components/charts — no external UI
dependencies.

---

## Quickstart

**Requirements:** a recent Xcode and an iPhone on **iOS 17+**. To explore without
a full HealthKit history, import an Apple Health export instead.

The Xcode project is generated from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Canonical checkout on the
author's machine is `~/code/noop`.

```bash
# 1. Clone
git clone https://github.com/blandisc/noop.git cenit
cd cenit
git checkout iOS

# 2. (Re)generate the Xcode project from project.yml
brew install xcodegen   # if you don't have it
xcodegen generate

# 3. Open in Xcode, then select the Cenit scheme and run on your iPhone.
```

Notes:

- Product, scheme and module are **Cenit**; the app's display name is **Cénit**.
  Set your own bundle id and signing team in `project.yml` before building to your
  device.
- Default branch is **`iOS`**.
- Swift Package Manager resolves the only third-party dependencies automatically:
  **GRDB.swift** (SQLite) and **ZIPFoundation** (export unzip).
- A 16 GB Mac should cap parallel simulator work (`-jobs 4`); see `CLAUDE.md`.
- Run the tests from Xcode (the app's test target + each package's test target),
  or per-package with `swift test` inside `Packages/<Name>/`.

To explore without an Xcode project, the packages build on their own:

```bash
cd Packages/StrandAnalytics && swift build && swift test
```

See [`docs/BUILD.md`](docs/BUILD.md) for the full build guide.

---

## How your data flows

```
Apple Health (HealthKit) ──▶ HealthKitBridge.sync (.foreground)
                                      │
                                      ▼
                         CenitStore GRDB (deviceId "apple-health")
                                      │
                                      ▼
                         Repository.refresh → Preparedness
                                      │
                                      ▼
                    Hoy / Tendencias / Entrenar / Ajustes
```

File imports (`export.xml`) join the same SQLite store via `StrandImport`.
The `"strap"` partition is excluded at read time. Optional Watch HR during a
strength session writes `strengthHrSample`. Optional iCloud Drive backup and
ExerciseDB CDN downloads are the only network paths, both opt-in.

---

## Privacy

**On-device by design.** Cénit has no server, no telemetry, and no account. Your
Health data, imports, and computed metrics live in a local SQLite database on your
device.

Network exceptions, both **off unless you opt in**:

- **iCloud Drive backup** of the local database (`autoBackup` in the iOS app).
- **ExerciseDB media** ("Descargar biblioteca de ejercicios" in Ajustes):
  downloads exercise thumbnails and short video loops from the public ExerciseDB
  CDN and caches them on your iPhone. Turning it off stops future downloads;
  a separate clear-cache control deletes what's already stored.

See [`docs/PRIVACY_SECURITY.md`](docs/PRIVACY_SECURITY.md).

---

## Attribution

With thanks:

- **`groue/GRDB.swift`** — SQLite persistence.
- **`weichsel/ZIPFoundation`** — export unzipping.

Cénit contains no WHOOP proprietary code, firmware, logos, or assets, and performs
no DRM circumvention. Full detail in [`ATTRIBUTION.md`](ATTRIBUTION.md).

---

## Disclaimer

Cénit is an independent, unofficial, non-commercial project. It is **not
affiliated with, endorsed by, or connected to WHOOP, Inc.**

**Cénit is not a medical device.** Heart rate, HRV, preparedness, strain, sleep
stages, SpO₂, respiratory rate, and skin temperature are **approximations**
computed from published methods. They are not clinically validated and are not
medical advice. Do not use them to diagnose, treat, or make health decisions —
consult a qualified professional.

Provided **as-is**, with **no warranty**, for **personal and educational use**. You
use it at your own risk. Read the full notice in [`DISCLAIMER.md`](DISCLAIMER.md).

---

## License

Cénit is **source-available** under the [PolyForm Noncommercial License 1.0.0](LICENSE):
**free for personal and other non-commercial use** — read it, run it, fork it, and
contribute. Commercial use is not granted by this license. (PolyForm Noncommercial is
a proper software license with patent terms; it is deliberately *not* an OSI
"open-source" licence, because that would permit the commercial use this project's
non-commercial nature rules out.)

The license covers Cénit's own original code and docs. Protocol facts (frame layouts,
command numbers, byte offsets) are uncopyrightable and free to reuse; bundled
dependencies keep their own licenses (GRDB.swift and ZIPFoundation are MIT — see
[`NOTICE`](NOTICE)). By opening a pull request you agree your contribution is licensed
under the same terms — see [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).

---

## Docs

- [`docs/BUILD.md`](docs/BUILD.md) — full build & install guide.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the system map (pipeline, package boundaries, storage schema).
- [`docs/PRIVACY_SECURITY.md`](docs/PRIVACY_SECURITY.md) — exactly what stays on-device.
- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — repository layout, build/test, design-system rules.
- [`CHANGELOG.md`](CHANGELOG.md) — release history and what to expect (also shown in-app under **What's new**).
- [`DISCLAIMER.md`](DISCLAIMER.md) · [`ATTRIBUTION.md`](ATTRIBUTION.md) — trademark/medical notice and full credits.
