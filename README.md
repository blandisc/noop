<p align="center">
  <img src="docs/assets/banner.svg" alt="Cénit — offline health on Apple Health" width="860">
</p>

<h1 align="center">Cénit</h1>

<p align="center"><b>Your body. Your data. Your iPhone. On-device, no cloud.</b></p>

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
| **iOS** | Build from source — see [`docs/BUILD.md`](docs/BUILD.md) | App + widgets + HealthKit. **Not distributed as a download:** iOS has no anonymous install path — the App Store and TestFlight both require a real Apple Developer identity — so it's build-it-yourself in Xcode. |

See [`docs/BUILD.md`](docs/BUILD.md) for the full build instructions.

Everything runs **on your device**. The built-in Coach answers locally, with no
network at all; the only thing that can ever leave your iPhone is the opt-in
exercise media downloader (off by default — see [Privacy](#privacy)).

---

Cénit is a standalone, fully **on-device** health app built on **Apple Health**.
It syncs HealthKit samples into a local SQLite database on your iPhone, can
import an Apple Health export, and computes recovery, strain, HRV, and sleep
**locally**, with no account and no cloud. Historical band data from older
installs is preserved in SQLite but dormant.

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
  uploaded anywhere.
- **Account-free and on-device.** Cénit never creates an account and never phones
  home. Health data stays in the app sandbox.
- **Bring your history.** Already have years of data in Apple Health? Sync it
  once and it's permanently on your machine. You can also import an Apple Health
  `export.xml` from **Settings → Data Sources**.
- **Transparent math.** Recovery, strain, HRV, and sleep are recomputed on-device
  from documented, citable methods (Task Force 1996 HRV, Karvonen %HRR, Edwards /
  Banister TRIMP, Tanaka HRmax, and so on). The algorithms are approximations of —
  not reproductions of — any proprietary model, and every analyzer file documents
  exactly what it does.

---

## Features

The app is organized into **five tabs**.

| Tab | What's there |
|---|---|
| **Today** | The home dashboard: a 24-hour dial with drivers, plus a grid of stat tiles (day strain, sleep, HRV, heart rate, resting HR, blood oxygen, steps, stress) each with a 14-day sparkline, recent workouts, and a data-sources footer. Pull down to sync Apple Health and recompute. |
| **Body** | Your biometrics in depth. A unified **metric-detail** surface with dedicated reads for recovery, strain, **sleep** (hypnogram, stage breakdown, efficiency, schedule regularity), stress, skin temperature, **fitness age**, plus HRV, resting HR, SpO₂, respiratory rate and steps — and long-range **trends** across all of them. Apple Health is the live source. |
| **Coach** | A single screen built as a loop — **Discover → Test → Act → Learn**. At the top, your **decision for today** (what to do) with recovery as the evidence. Below: **Ask your data** — free-text questions answered **on-device** (see [the Coach](#the-coach--ask-your-data-on-device)); **What works for you** — the habits most associated with your best recovery, as a causal registry; **Findings** — anomalies, trends and correlations the on-device engine surfaces; **Log your day** — a Yes/No journal that feeds your levers; and **N-of-1 experiments** — test one lever for 7 days and get an honest verdict (held up / didn't / not enough signal). |
| **Train** | Strength sessions (with Apple Watch mirror when available), **Breathe** (guided breathing with on-device HRV readouts), and **Intervals** (HIIT timer with glanceable UI). Live heart rate during strength can come from the Watch mirror (`watchBpm`). |
| **Settings** | Profile, preferences, and the in-app **What's new** changelog. A **More** area holds the power-user screens: **Metric Explorer** (interrogate any single metric over time), **Compare** (plot two metrics together), **Workouts** (detected sessions with strain + HR detail), **Data Sources** (Apple Health sync status plus one-tap import of an Apple Health export) and **Automations** (opt-in HealthKit write-back). |

There is also a first-run **onboarding wizard** that sets expectations
(independent/experimental, Apple Health, on-device only), Home-screen /
Lock-screen **widgets**, and an in-app **"What's new"** changelog shown after each
update.

### The Coach — "Ask your data", on-device

The Coach used to be a chat with an external LLM. It isn't anymore. **Ask your data** answers your free-text questions on-device, and the default path never touches the network:

- **On-device (Apple Intelligence).** On an iPhone with Apple Intelligence (iOS 26+), you type an open question — *"why did I wake up tired?"* — and your phone's own model answers, **with no network**. A deterministic engine (`CoachGrounding`, in `StrandAnalytics`) builds the answer from **your real numbers** and the model only **phrases it** — so it never invents one of your metrics. A guard rejects any answer that states a figure the engine didn't.
- **Essential mode.** On an iPhone without Apple Intelligence, you answer with pre-armed questions that use the same engine numbers — fully deterministic, still on-device.

See [`docs/PRIVACY_SECURITY.md`](docs/PRIVACY_SECURITY.md).

---

## Platform status

Cénit's logic lives in cross-platform Swift packages. The iOS app syncs
**Apple Health** and **scores recovery, strain and sleep on your own device**.

| Platform | Status |
|---|---|
| **iOS** | ✅ The app (`Cenit`, SwiftUI, **iOS 17+**) — app target + widgets + HealthKit. Syncs Apple Health and scores recovery / strain / sleep on-device. **Build-from-source only, not distributed:** iOS has no anonymous distribution path (App Store and TestFlight both require a real Apple Developer identity), which is fundamentally at odds with this project staying anonymous. |

Cénit is **iOS-only** today — earlier macOS and Android experiments have been
retired. The packages stay portable so a future port is technically possible;
none is in development right now.

### What to expect when you start

Cénit computes your scores on your own device, so like any recovery app it
needs a little data before everything fills in:

- **Apple Health sync** pulls samples when the app comes to the foreground
  (and on manual refresh).
- **Strain and sleep** appear once HealthKit has enough recent history.
- **Recovery** needs a few nights for the app to learn your personal baseline,
  then sharpens each night.
- **In a hurry?** Import an Apple Health `export.xml` in **Settings → Data
  Sources** and your full history fills in about a minute.

---

## Architecture

The repository is split into platform-pure Swift packages plus the iOS app target
(`Cenit`). All packages declare both `.iOS(.v16)` and `.macOS(.v13)` so the pure
logic builds and tests without an app;
framework-specific UI is guarded with `#if canImport(UIKit)` / `#if canImport(AppKit)`.

```
Cenit/                 SwiftUI app layer — App, Data, LiveActivity, Media, Onboarding, Screens, System
CenitApp/              iOS app shell — HealthKit, widgets, intents
CenitWidgets/          WidgetKit extension (Home / Lock-screen widget)
CenitShared/           code shared between the app and the widgets
Packages/
  BiometricStreams/     neutral vocabulary of biometric rows (pure, zero deps)
  CenitStore/           GRDB/SQLite persistence (versioned migrations)
  StrandAnalytics/      HRV / recovery / strain / sleep / correlation math + Coach grounding (pure, DB-free)
  StrandTraining/       strength domain (catalog, sets/reps, routines)
  StrandImport/         Apple Health importers
  StrandDesign/         SwiftUI design system (palette, components, charts)
Tools/                  developer scripts (localization, screen captures, design lint)
```

> The packages keep their original `Strand*` names from earlier eras; the app
> layer is `Cenit/` (display name **Cénit**).

### `CenitStore` — local SQLite via GRDB

Everything is stored on-device in SQLite (using
[GRDB.swift](https://github.com/groue/GRDB.swift)). The schema is a versioned
migrator (`Database.swift`, currently through **`v12`**). The decoded-stream
tables created in `v1`–`v3`:

```sql
CREATE TABLE hrSample      (deviceId TEXT, ts INTEGER, bpm INTEGER, PRIMARY KEY(deviceId, ts));
CREATE TABLE rrInterval    (deviceId TEXT, ts INTEGER, rrMs INTEGER, PRIMARY KEY(deviceId, ts, rrMs));
CREATE TABLE spo2Sample    (deviceId TEXT, ts INTEGER, red INTEGER, ir INTEGER, PRIMARY KEY(deviceId, ts));
CREATE TABLE skinTempSample(deviceId TEXT, ts INTEGER, raw INTEGER, PRIMARY KEY(deviceId, ts));
CREATE TABLE respSample    (deviceId TEXT, ts INTEGER, raw INTEGER, PRIMARY KEY(deviceId, ts));
```

Later migrations add server-derived metric caches (`sleepSession`, `dailyMetric`),
the journal and workout tables, a generic long-format `metricSeries` store (v9),
step counting (v10–v11), and the **N-of-1 `experiment`** table (v12).

### `StrandAnalytics` — transparent, on-device math

Pure, database-free analyzers. Each is documented and grounded in published
methods (and is explicitly an approximation, not a reproduction of any proprietary
model):

| File | Computes |
|---|---|
| `HRVAnalyzer.swift` | RMSSD + SDNN from R-R intervals (Task Force 1996), with range + Malik ectopic filtering. |
| `RecoveryScorer.swift` | A 0–100 recovery score: HRV-dominant z-score (on the log scale, lnRMSSD) + logistic composite vs personal baselines. |
| `StrainScorer.swift` | A 0–21 logarithmic strain scale from %HRR (Karvonen) and Edwards / Banister TRIMP. |
| `SleepStager.swift` | Sleep/wake detection + approximate 4-class staging from cardiorespiratory + gravity features. |
| `ReadinessEngine.swift` | The Today verdict — HRV vs baseline (Plews/Buchheit), RHR drift (Lamberts), respiratory-rate drift, load balance (ACWR, Gabbett) and monotony (Foster). |
| `CorrelationEngine.swift`, `BehaviorInsights.swift` | Pearson r / OLS / lagged correlations, with Student-t *p*-values and FDR correction; behavioral insights. |
| `CoachGrounding.swift`, `ExperimentVerdict.swift` | Deterministic grounding for the on-device Coach, and the N-of-1 experiment verdict. |

### `StrandImport` — bring your own history

- **Apple Health export** (`AppleHealthImporter.swift`): a **streaming** SAX parser
  (`XMLParser`) for `export.xml` (which can exceed 1 GB), with correlation-dedupe,
  unit normalization (e.g. SpO₂ fraction → %), and sleep-stage mapping.

### `StrandDesign` — the SwiftUI design system

Palette, typography, motion, and reusable components/charts — no external UI
dependencies. It carries **two languages**: the **«Instrumento diurno»** daytime
language (warm paper, one dominant number, color only in the datum) that is
canonical for new and redesigned screens, and the original **dark** system that
remaining legacy screens still use.

---

## Quickstart

**Requirements:** a recent Xcode and an iPhone on **iOS 17+** to install on. The
on-device Coach is built with Apple's **FoundationModels** framework, so building
it needs **Xcode 26** and it only runs on an iPhone with **iOS 26 + Apple
Intelligence**; on anything older the Coach compiles out and falls back to
"Essential mode". To explore without a full HealthKit history, import an Apple
Health export instead.

The Xcode project is generated from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# 1. Clone
git clone <your-fork-url> cenit
cd cenit

# 2. (Re)generate the Xcode project from project.yml
brew install xcodegen   # if you don't have it
xcodegen generate

# 3. Open in Xcode, then select the Cenit scheme and run on your iPhone.
```

Notes:

- Product, scheme and module are **Cenit**; the app's display name is **Cénit**.
  Set your own bundle id and signing team in `project.yml` before building to your
  device.
- Swift Package Manager resolves the only third-party dependencies automatically:
  **GRDB.swift** (SQLite) and **ZIPFoundation** (export unzip).
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
Apple Health (HealthKit) ──▶ HealthKitBridge ──────────┐
                                                       ▼
Apple Health export.xml ──▶ StrandImport ──▶ CenitStore (local SQLite)
                                                       │
                                                       ▼
                                         StrandAnalytics (recovery/strain/
                                         HRV/sleep, on-device)
                                                       │
                                                       ▼
                                         Cenit (SwiftUI) + StrandDesign
```

Every arrow stays on your machine.

---

## Privacy

**On-device by design.** Cénit has no server, no telemetry, and no account. Your
Health data, imports, and computed metrics live in a local SQLite database on your
device and never leave it.

The built-in Coach ("Ask your data") answers **on-device** — via Apple
Intelligence when available, or a deterministic engine otherwise — with **no
network**. There is exactly one network exception in the whole app, off by default:

- The **opt-in exercise media downloader** ("Descargar biblioteca de
  ejercicios" in Ajustes): off by default. If you turn it on, Cénit downloads
  exercise thumbnails and short video loops from the public ExerciseDB CDN and
  caches them on your iPhone forever, so they work offline afterward. Turning it
  off stops future downloads without deleting what's already cached; a
  separate "Borrar media descargada" button clears the cache.

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

**Cénit is not a medical device.** Heart rate, HRV, recovery, strain, sleep stages,
SpO₂, respiratory rate, and skin temperature are **approximations** computed from
published methods. They are not clinically validated and are not medical advice. Do
not use them to diagnose, treat, or make health decisions — consult a qualified
professional.

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
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the system map (pipeline, package boundaries, actor model, storage schema).
- [`docs/PRIVACY_SECURITY.md`](docs/PRIVACY_SECURITY.md) — exactly what stays on-device.
- [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) — repository layout, build/test, design-system rules.
- [`CHANGELOG.md`](CHANGELOG.md) — release history and what to expect (also shown in-app under **What's new**).
- [`DISCLAIMER.md`](DISCLAIMER.md) · [`ATTRIBUTION.md`](ATTRIBUTION.md) — trademark/medical notice and full credits.
