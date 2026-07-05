# NOOP Analytics

On-device analytics for **NOOP** — a standalone, fully offline companion app for WHOOP straps (4.0 and 5.0). NOOP talks to *your own* strap over Bluetooth, stores everything locally in SQLite, and computes recovery, strain, HRV, and sleep on-device. There is no cloud and no account involved in any of the math described here.

> **Not affiliated with WHOOP.** NOOP interoperates with hardware and data you already own. The metrics below are **approximations** of common exercise-physiology and HRV methods, derived from published literature — they are **not** reproductions of any proprietary scoring model, and they are **not a medical device**. Nothing here is medical advice.

All analytics live in the cross-platform `StrandAnalytics` Swift package. Every entry point is a **pure, deterministic, DB-free** function over its inputs — no I/O, no global state, no network. Persistence and BLE are wired in elsewhere (`WhoopStore`, the app target). This makes the whole package straightforward to unit-test against fixed vectors.

- Package: `Packages/StrandAnalytics/Sources/StrandAnalytics/`
- Top-level index: `StrandAnalytics.swift` (`StrandAnalytics.version == "0.1.0"`)
- App layer: `Cenit/` (the shared SwiftUI app layer that builds the `Cenit` app target)

---

## What is actually wired into the app

The package contains more analytics than the app currently calls. This section is the honest map of **library-only** vs **live**, verified against the app sources.

| Engine | File | Status in the app |
|---|---|---|
| `HRVAnalyzer` | `HRVAnalyzer.swift` | **Library-only** as a type. The app computes RMSSD inline via `AppModel.rmssd(_:)` (same Task-Force formula) for the live stress nudge. |
| `RecoveryScorer` | `RecoveryScorer.swift` | **Live.** Runs inside `AnalyticsEngine.analyzeDay` via `Cenit/Data/IntelligenceEngine.swift`; computed recoveries are persisted under the `"<deviceId>-noop"` source and merged **under** any imported `recovery_score_pct` (imports always win). APPROXIMATE. |
| `AppleRecoveryEstimator` | `AppleRecoveryEstimator.swift` | **Live.** Surfaced read-time by `Repository.refresh` for **band-less** Apple nights only (FER-153): an ESTIMATED recovery from Apple SDNN vs the user's own Apple norm, labelled «estimado» + grade. Not persisted, no migration. APPROXIMATE. |
| `StrainScorer` | `StrainScorer.swift` | **Live.** Day strain is computed on-device for nights the strap offloaded; the imported `day_strain` column still wins for imported days. APPROXIMATE. |
| `SleepStager` | `SleepStager.swift` | **Live.** Stages each offloaded night inside `analyzeDay`; computed sessions are persisted under the `"-noop"` source, with imported sleeps taking precedence. APPROXIMATE. |
| `Baselines` | `Baselines.swift` | **Live.** Seeds the recovery baseline in `IntelligenceEngine.analyzeRecent` (two-pass cold-start). The fold is **strap-only**: Apple-only nights are excluded (`strapOnlyHistory`, FER-519) because their HRV is **SDNN**, not the band's **RMSSD** — different constructs with no published conversion (Shaffer & Ginsberg 2017). The only Apple→baseline bridge is the capped FER-60 prior, and (FER-634) only for **respiration** — breaths/min measured during sleep, the same metric across sources. Resting-HR is **not** seeded from Apple: the band reads it from the sleep nadir while Apple estimates it from awake sedentary samples (~10–13 bpm higher; Fenland Study, Gonzales et al. 2023), so it takes the same honest cold-start as HRV. The Apple HRV path is the separate `AppleRecoveryEstimator` (FER-153). The illness early-warning in `AppModel` still uses its own trailing-window baseline math inline (see below). |
| `WorkoutDetector` / `Calories` | `WorkoutDetector.swift` | **Live.** Runs inside `AnalyticsEngine.analyzeDay`; detected bouts are persisted as `workout` rows under the computed `"<deviceId>-noop"` source (sport `"detected"`), de-duplicated against imported WHOOP workouts. All intensity/calorie fields are APPROXIMATE. Not yet surfaced in the Workouts screen. |
| `AnalyticsEngine` | `AnalyticsEngine.swift` | **Live orchestrator.** `analyzeDay(...)` is called by `Cenit/Data/IntelligenceEngine.swift` — every 15 minutes while connected, and from the Intelligence screen — and its `DailyMetric`, sleep sessions and detected workouts are persisted under the `"-noop"` source. |
| `HRZones` | `HRZones.swift` | **Library-only** (display zone model). The app's live zone coaching computes `%HRmax` inline in `AppModel.coachZone(_:)`. |
| `CorrelationEngine` | `CorrelationEngine.swift` | **Live.** Used by `InsightsView`, `CompareView`, `MetricExplorerView`. |
| `BehaviorInsights` | `BehaviorInsights.swift` | **Live.** Used by `InsightsView` (`rank` + `sentence`). |
| `ComparisonEngine` | `ComparisonEngine.swift` | **Live.** Used by `MetricExplorerView`. |

**In short:** the *interactive data-interrogation* engines (correlation, behavior effects, period comparison) are wired into screens, and the *recompute-from-raw-streams* engines (recovery, strain, sleep staging, workout detection) run live too: `IntelligenceEngine` calls `analyzeDay` for every night the strap offloaded and persists the APPROXIMATE results under the `"-noop"` source, merged under any imported rows — a WHOOP export still wins wherever it covers a day. The live BLE app additionally runs four small inline analytics in `AppModel`: HR smoothing, RMSSD, HR-zone coaching, an illness/strain early-warning, and a resting-stress nudge.

---

## Live analytics in `AppModel`

Source: `Cenit/App/AppModel.swift`. These run against the live BLE stream and the daily history, on the main actor.

### 1. Heart-rate smoothing (`ingestHR`)

Every screen shows a **smoothed** bpm (`AppModel.bpm`), never the raw per-beat value (which swings with HRV). The smoother:

1. Prefers the strap's reported HR; falls back to `60000 / RR` (last R-R interval) if needed.
2. Clamps to a plausible `30…220` bpm range — rejects `0` and garbage spikes.
3. Keeps a ~10-second sliding window (max 40 samples) and **publishes the window median**.

```swift
hrWindow.append((now, inst))
hrWindow.removeAll { now.timeIntervalSince($0.t) > 10 }   // ~10 s window
if hrWindow.count > 40 { hrWindow.removeFirst(hrWindow.count - 40) }
let vals = hrWindow.map(\.v).sorted()
bpm = vals.isEmpty ? nil : Int(vals[vals.count / 2].rounded())
```

Median (not mean) is deliberate: it rejects single-beat outliers without lagging the signal.

### 2. RMSSD for the stress nudge (`rmssd` + `evaluateStress`)

The live RMSSD uses the classic Task-Force successive-difference formula over a rolling R-R buffer:

```swift
static func rmssd(_ rr: [Int]) -> Double {
    guard rr.count >= 2 else { return 0 }
    var sum = 0.0, n = 0
    for i in 1..<rr.count { let d = Double(rr[i] - rr[i - 1]); sum += d * d; n += 1 }
    return n > 0 ? (sum / Double(n)).squareRoot() : 0
}
```

`evaluateStress()` is an **experimental, off-by-default** resting-stress nudge:

- Only runs when `behavior.stressNudge` is on **and** the strap is bonded **and** worn.
- Filters R-R to plausible beats (`300 < rr < 2000` ms, i.e. 30–200 bpm), keeps the last 60, needs ≥ 20.
- Tracks a **slow HRV baseline** as an EWMA: `hrvBaseline = hrvBaseline * 0.98 + rmssd * 0.02`.
- Only fires when HR is in a **resting band** (`55…100` bpm — not a workout) and current RMSSD has dropped **below 60% of baseline**.
- Rate-limited to **once per 15 minutes** (`> 900` s). On fire it buzzes the strap once and logs "take a paced breath."

It is intentionally conservative so it rarely false-fires.

### 3. HR-zone haptic coaching (`coachZone`)

Watches the smoothed `bpm`, computes `%HRmax` from `profile.hrMax`, and buckets into 5 zones at `0.6 / 0.7 / 0.8 / 0.9` of max:

```swift
let pct = Double(hr) / maxHR
let zone = pct >= 0.9 ? 5 : pct >= 0.8 ? 4 : pct >= 0.7 ? 3 : pct >= 0.6 ? 2 : 1
```

On crossing **into zone 5** it buzzes three times ("ease off"); on dropping back **to zone ≤ 1** it buzzes once ("recovered"). Gated on `behavior.zoneCoaching`, bonded, worn, and a valid `hrMax`.

### 4. Illness / strain early-warning (`evaluateIllness`)

This is the live, app-side version of the baseline-comparison idea. It recomputes whenever the daily history changes (`repo.$days`). It compares the **last ~2 days** against a **~28-day baseline ending 3 days ago** (so the recent window doesn't contaminate its own baseline):

```swift
let recent = Array(days.suffix(2))
let base   = Array(days.suffix(31).dropLast(3))   // ~28 days ending 3 days ago
```

It then flags anomalies by **z-score**: each signal fires when its recent mean sits **≥ 2σ** from the baseline mean *in the concerning direction*, where σ is the baseline's own robust dispersion (mean-absolute-deviation × 1.253, the same `E[|X−μ|] = σ·√(2/π) ≈ σ/1.253` convention as `RecoveryScorer`/`Baselines`; the math lives in the pure `IllnessWatch` type in `StrandAnalytics`). Anchoring to each user's own σ — instead of a fixed offset — makes the trigger comparable across people: a +5 bpm jump is several σ for a very stable user (a real signal) but sub-σ noise for a volatile one.

| Signal | Field(s) | Anomaly condition | Direction |
|---|---|---|---|
| Resting HR ↑ | `restingHr` | recent mean **≥ baseline + 2σ** | higher is worse |
| HRV ↓ | `avgHrv` | recent mean **≤ baseline − 2σ** | lower is worse |
| Skin temp ↑ | `skinTempDevC` | recent mean **≥ baseline + 2σ** | higher is worse |
| Respiration ↑ | `respRateBpm` | recent mean **≥ baseline + 2σ** | higher is worse |

σ is "not estimable" (no anomaly) for a flat or too-small baseline. Note the recent window is a **small sample** — 2 nights by design, but a single night if one is missing. A banner appears only when **two or more** anomalies fire together — the classic early-illness signature is *RHR up + HRV down + skin-temp up*. Requires `behavior.illnessWatch` on and at least 14 days of history. On-device only; the message is a plain-English summary like *"Your body looks strained — resting HR +6 bpm, HRV −22%. Consider taking it easy."*

---

## `HRVAnalyzer` — RMSSD / SDNN with cleaning

Source: `HRVAnalyzer.swift`. Reproduces the **Task Force (1996)** definitions over R-R / NN intervals (ms), with a deterministic cleaning pipeline.

### Formulas

```
RMSSD = sqrt( (1/(N-1)) · Σ (NN[i+1] − NN[i])² )    (Task Force 1996)
SDNN  = sample standard deviation of NN, ddof = 1     (Task Force 1996)
pNN50 = 100 · (count of |ΔNN| > 50 ms) / (N − 1)
```

`rmssdRaw(_:)` and `sdnnRaw(_:)` are the raw primitives (no filtering, return `nil` for fewer than 2 values).

### Cleaning pipeline (`cleanRR`)

1. **Range filter** — drop intervals outside `[rrMinMs, rrMaxMs] = [300, 2000]` ms (≈ 200 bpm to 30 bpm).
2. **Ectopic rejection (Malik-style)** — drop any beat deviating more than `ectopicThreshold = 0.20` (20%) from a **local median** over a centered window of `2·ectopicWindowRadius + 1 = 5` beats. Beats with too small a neighbourhood are kept.
3. **Sufficiency gate** — require at least `minBeats = 20` clean intervals before returning a trustworthy result; otherwise `HRVResult.empty(...)`.

> **Honest substitution.** The reference Python pipeline ran neurokit2's Kubios / Lipponen–Tarvainen (2019) artifact classifier, which isn't available on-device. NOOP substitutes the classical **Malik et al. (1989)** 20%-local-median rule — a simpler, fully deterministic approximation of the same intent (remove physiologically impossible beat-to-beat jumps before computing HRV). It does not model the missed/extra-beat insertion that Kubios does.

### API

```swift
HRVAnalyzer.analyze(_ rr: [RRInterval], windowStart: Int?, windowEnd: Int?) -> HRVResult
HRVAnalyzer.analyze(rawRR: [Double]) -> HRVResult
```

`HRVResult` carries `rmssd`, `sdnn`, `meanNN`, `pnn50`, plus `nInput` and `nClean` (counts before/after cleaning) for transparency.

---

## `RecoveryScorer` — transparent 0–100 recovery composite

Source: `RecoveryScorer.swift`. A **z-score + logistic** composite. It is explicitly **approximate** — HRV-dominant and baseline-normalized — and makes no claim to reproduce WHOOP's proprietary recovery model.

### Weighting

| Driver | Direction | Weight |
|---|---|---|
| HRV vs baseline | higher → better recovery | `wHRV = 0.60` (dominant) |
| Resting HR vs baseline | lower → better | `wRHR = 0.20` |
| Respiration vs baseline | lower → better | `wResp = 0.05` |
| Sleep performance | higher → better | `wSleep = 0.15` |
| Skin temperature vs baseline | lower → better | `wTemp = 0.10` (optional) |

Each metric is standardized to a **robust z-score** against the personal baseline (EWMA spread):

```
z = (value − mean) / (1.253 · spread)
```

The `1.253` converts an EWMA mean-absolute-deviation into an approximate Gaussian σ (`E[|X−μ|] = σ·√(2/π) ≈ σ/1.253`). For "lower is better" drivers (RHR, resp, skin temp) the z is inverted by swapping value and mean. The **skin-temperature term is optional** — it joins once its personal baseline is usable, and an elevated nightly temp (illness / overreaching) lowers recovery. The **sleep term is personalized** against the user's own efficiency baseline when available; until then it falls back to the fixed population center `(sleepPerf − 0.85) / 0.12`.

Missing terms are dropped and weights renormalized. The weighted-mean z is then **pulled toward neutral in proportion to the driver weight actually present** (missing-driver shrinkage, FER-698), so a single strong driver can't saturate the score as if the whole picture agreed:

```
z = weightedMeanZ · min(1, presentWeight / referenceCoverageWeight)
    referenceCoverageWeight = wHRV + wRHR + wSleep = 0.95   (the three primary drivers)
```

A read backed by the three primary drivers (HRV + RHR + sleep = `0.95`) counts as full coverage — the factor caps at `1.0`, so band scores are unchanged. `resp`/`skin-temp` are optional refinements, excluded from the reference so their absence never shrinks a band read. Below `0.95` (e.g. an Apple-Health estimate carrying HRV alone) the composite is shrunk toward `Z = 0` — the same James–Stein / empirical-Bayes spirit (Efron & Morris 1977) already applied per term via `Baselines.confidence(nValid)` for thin baselines, now applied along the coverage axis too. The shrunken z is squashed:

```
score = 100 / (1 + exp(−logisticK · (z − logisticZ0)))
        logisticK  = 1.6     (±2 z ≈ the full red–green band)
        logisticZ0 = −0.20   (anchors z = 0 → ~58 %)
```

The `58%` anchor matches WHOOP's self-reported member-average recovery (`populationMean = 58.0`) — a calibration anchor taken from WHOOP's own (self-selected) user base, not a peer-reviewed population norm.

### Cold-start

HRV is the dominant driver. If its baseline isn't usable yet (`BaselineState.usable == false`, i.e. fewer than `minNightsSeed` valid nights), `recovery(...)` returns `nil` — more honest than fabricating a number. Callers may fall back to `populationMean` but should flag it.

### Bands (`band(_:)`)

| Band | Range |
|---|---|
| red | `< 34` |
| yellow | `34 … 67` |
| green | `≥ 67` |

### Resting HR (`restingHR`)

"Lowest sustained HR" during the in-bed window = the **minimum of 5-minute non-overlapping bin means** of HR samples in `[start, end]`. This rejects single-beat dips while capturing the night's true floor.

### Estimated recovery from Apple Health (`AppleRecoveryEstimator`, FER-153)

Source: `AppleRecoveryEstimator.swift`. When a night did **not** come from the band, this scores an **estimated** recovery from Apple Health's HRV + sleep against the user's **own** Apple norm, so a band-less night reads a number instead of "—". It is **library code surfaced read-time** by the app: `Repository.refresh` maps each `apple-health` daily row into a `Night` and calls `estimate(...)` (`appleRecoveryEstimates`, band-less nights only — the band wins wherever it has the night). The result is a `[day: estimate]` side map; it is **NOT** folded into `days`/`displayDays` (those stay band-measured, so no recovery statistic over history mixes in an estimate) and surfaces for display on `repo.today` only. Nothing is persisted and there is no migration.

**The method (and why it's honest).** Apple exposes HRV as **SDNN**, not the **RMSSD** the band path uses. The estimator builds a **separate** SDNN baseline (plus optional RHR / respiration) from the user's own previous Apple nights and scores tonight's SDNN against it with the **same** `RecoveryScorer` z-score + logistic — **SDNN-vs-SDNN, never converted to RMSSD**. Because the log-domain z is relative and scale-invariant, the same *relative* deviation yields the same score regardless of the absolute ms scale, so "norma propia" carries no hidden cross-metric bias (proven by a scale-invariance test). Below `Baselines.minNightsSeed` Apple HRV nights the baseline isn't usable → no estimate (honest cold-start, "—").

**Construct caveat (do not let copy overclaim).** SDNN reflects **total** variability (sympathetic + parasympathetic); RMSSD reflects the **vagally-mediated** component (Shaffer & Ginsberg 2017, *Front Public Health* 5:258). Both are valid time-domain HRV measures (Task Force 1996, *Circulation* 93(5):1043–1065). Apple's SDNN is also ultra-short (~60 s) and aggregated across the whole day, not sleep-windowed — so this is an "autonomic state vs your own Apple norm" proxy, **not** the band's nocturnal-vagal recovery, and a "70" here is **not** interchangeable with a "70" from the band. It is therefore shown **labelled «estimado» with a lower confidence grade** (`ScoreConfidence`), with an explanation, on every surface (Today hero + Recovery detail). No clinical/diagnostic claim.

**Confidence** (`ScoreConfidence`, product-calibration knobs, not validated): high (≥ `minNightsTrust` Apple nights) · medium (≥ 7) · low (≥ seed); dropped one tier when overnight coverage is thin (`sleepMinutes < ~3 h`, a loose proxy since the SDNN is all-day). Pure + DB-free, like the rest of the package.

---

## `StrainScorer` — 0–21 logarithmic cardiovascular load

Source: `StrainScorer.swift`. An **independent** implementation of published exercise-physiology methods (WHOOP-*like*, not a reproduction).

### Pipeline

1. **Heart-Rate Reserve (Karvonen 1957):** `HRR = HRmax − RHR`.
2. **Per-sample intensity** as `%HRR = (HR − RHR) / HRR × 100`, clamped `[0, 100]`.
3. **TRIMP accumulation** over the window, by one of two methods:
   - **Edwards (1993) 5-zone summation (default):** each sample contributes its zone weight (`1…5` at the `50 / 60 / 70 / 80 / 90 %HRR` cut-offs) × duration.
   - **Banister (1991) exponential:** each sample contributes `duration × x × 0.64 × e^(b·x)`, where `x = %HRR/100` and `b = 1.92` (men) / `1.67` (women).
4. **Logarithmic compression** onto `[0, 21]`:

```
strain = 21 · ln(TRIMP + 1) / ln(D),    D = strainDenominator = 7201
```

`D = 7201` is calibrated so the Edwards daily ceiling — top zone weight 5 sustained for 24 h = `5 × 1440 = 7200` — maps to exactly `21.0` (`ln(7201)/ln(7201) = 1`).

### HRmax estimation (`estimateHRmax`)

- With ≥ `hrmaxMinSamples = 600` HR samples, use the observed `99.5th` percentile (`"observed"`), unless a Tanaka estimate is higher.
- **Tanaka (2001):** `HRmax = 208 − 0.7 × age` (gender-independent), used as the floor / fallback (`"tanaka"`).
- No data and no age → `(0, "unknown")`.

### Guards & gates

- Returns `nil` with fewer than `minReadings = 600` samples (≈ 10 min at 1 Hz) or when `HRmax ≤ RHR` (invalid HRR).
- Per-sample duration is inferred from the **median plausible spacing** between consecutive timestamps (gaps in `(0, 300) s`; shared with `HRZones.medianInterval`), falling back to `1 s`. Using the median rather than the first timestamp pair keeps an isolated early gap (strap reconnect at ~1 Hz) from inflating the duration applied to the whole day.

### Denominator calibration (`fitStrainDenominator`)

Given `(TRIMP, reference_strain)` pairs, fits `D` via a through-origin least-squares line in log-space: `ln(D) = 21 · Σx² / Σ(x·strain)`, `x = ln(TRIMP+1)`. Throws on fewer than 2 usable pairs.

---

## `RestReadiness` — between-sets rest by heart-rate recovery (HRR)

Source: `RestReadiness.swift`. Pure between-sets rule: "ready" = HR has returned to `restingHR + margin` (default 20 bpm over the user's personal resting HR). The dominant number is `bpmToReady = max(0, HR − target)` (variant C2: counts down to 0 → «Ready»). A floor (`minRestS`, default 20 s) blocks a premature «ready»; a ceiling (`maxRestS`, default 180 s) releases with no infinite wait; an honesty band (`bandBPM`, default 5) reports `almostReady` instead of faking beat-level precision. With no live HR (not worn / nil / no baseline) it falls back to a fixed timer — no invented HR or color, but the clock still releases at the ceiling.

Stateless: the caller (the guided session, FER-347, in `Cenit/`) owns the timer and passes plain values — live HR, wrist-wear, resting-HR baseline, seconds elapsed — so the package never imports CoreBluetooth/UIKit and never sees `LiveState`.

**Method:** heart-rate recovery — the bpm the HR falls after effort reflects parasympathetic reactivation (Cole 1999, NEJM 341:1351; Daanen 2012, IJSPP 7:251, HRR for monitoring training status). NOOP uses no absolute clinical thresholds: the target is the user's own resting HR. **APPROXIMATE** — a rest cue, not a medical verdict. (Distinct from the Heart-Rate *Reserve* the StrainScorer calls "HRR".)

---

## `SleepStager` — sleep/wake detection + approximate 4-class staging

Source: `SleepStager.swift`. Detects in-bed sessions from gravity/HR/RR/respiration and produces a 30-second hypnogram of `{wake, light, deep, rem}`.

> **Honest hedging.** These stages are **approximations**, not PSG-validated, not medical advice. The EEG-free 4-class ceiling is ~65–73% epoch agreement (Walch 2019). **Light/deep separation is the weakest link — deep-minute estimates are the least reliable output.**

### Stage 0 — gravity-stillness sleep/wake spine (`detectSleep`)

- Per-record movement proxy = L2 magnitude of the gravity-vector change vs the previous record (`gravityDeltas`).
- A sample is "still" if its delta < `gravityStillThresholdG = 0.01 g`. A rolling window (`stillWindowMin = 15` min) calls its center "sleep" when ≥ `stillFraction = 0.70` of samples are still.
- Contiguous runs are built, breaking on a class change or a data gap > `maxGapMin = 20` min; runs shorter than `mergeMin = 15` min are absorbed into neighbours.
- A run must exceed `minSleepMin = 60` min to count, and is **HR-confirmed**: mean HR over the run must be ≤ `hrSleepBaselineMult = 1.05 ×` the day's median HR (skipped when fewer than 30 HR samples — gravity is trusted alone).
- A citable **te Lindert 30 s Cole–Kripke** index (`SI = 0.001 · Σ wᵢ·Aᵢ`, sleep iff `SI < 1`, weights `[106, 54, 58, 76, 230, 74, 67]`) is computed per epoch as a cross-check and to find onset / final-wake.

### Stage 1 — per-epoch cardiorespiratory features

Over a rolling 5-minute window per 30 s epoch:

- mean HR;
- **Walch difference-of-Gaussians HR variability** (`σ1 = 120 s` minus `σ2 = 600 s`, reflect-padded convolution; NaNs linearly interpolated);
- **RMSSD / SDNN** from range-filtered R-R (`HRVAnalyzer.rmssdRaw` / `sdnnRaw`);
- **respiration rate + RRV** from the raw 1 Hz resp channel via a simple peak detector (detrend → local-maxima peaks ≥ 2 s apart → breath intervals 1.5–12 s → rate = `60 / median interval`, RRV = std of intervals).

> Frequency-domain HRV (HF, LF/HF) is **omitted** — there is no neurokit2/scipy on-device — so the parasympathetic-tone signal is **RMSSD only**. The respiration peak-finder is a faithful port (the reference derived these "robustly ourselves" too, without neurokit).

### Stage 2 — percentile-band classifier (`classifyOne`)

Reference distributions are taken over the session's **sleep-period** epochs (Cole–Kripke = sleep). A motion fraction and the per-epoch features are compared against session-relative percentiles:

| Class | Rule |
|---|---|
| **wake** | sustained motion (`moveFrac ≥ 0.15`) **and** activated cardiac (high HR or high DoG-HR variability), or no HR to vet the motion |
| **deep** | still (`moveFrac ≤ 0.10`) **and** high parasympathetic tone (RMSSD ≥ 70th pct) **and** low HR (≤ 25th pct) **and** regular respiration |
| **rem** | still body **and** activated cardiac **and** irregular respiration (RRV ≥ 65th pct); a fallback requires both cardiac signals when respiration is unavailable |
| **light** | everything else (the default) |

### Stage 3 — smoothing + physiology re-imposition

- 5-epoch **median smoothing** of the label sequence (`smoothLabels`).
- **No REM in the first 15 min** after onset (`reimposePhysiology` → demote to light).
- **No deep after the first third** of the night (deep is biased early) → demote to light.
- Pre-onset and post-final-wake epochs are forced to `wake`.

Consecutive same-stage epochs are merged into `StageSegment`s tiling `[start, end]`.

### Outputs

- `SleepSession` — `start`, `end`, `efficiency` (AASM `asleep / in-bed`, where `asleep = in-bed − wake`), `stages`, per-session `restingHR` (lowest 5-min rolling-mean HR) and `avgHRV` (**median** RMSSD over 5-min tumbling windows, each window ectopic-rejected, and **wake windows excluded** via the hypnogram — a steadier, sleep-only parasympathetic read).
- `hypnogramMetrics(_:)` — AASM-style roll-up: TIB / TST / SPT / SOL / REM latency / WASO / efficiency / disturbances, plus deep/REM/light minutes and percentages.

---

## `SleepRegularityIndex` — sleep-timing regularity (SRI)

Source: `SleepRegularityIndex.swift` (FER-214). The **Sleep Regularity Index** (Phillips et al. 2017, *Sci Rep* 7:3216) scores how repeatable your sleep TIMING is, independent of duration or quality: the probability of being in the same state (asleep vs awake) at two instants exactly 24 h apart, averaged over the window and rescaled `SRI = (2·P − 1)·100` (100 = a perfectly repeated schedule; 0 = chance; negatives clamped to 0). Windred et al. 2024 (*Sleep* 47(1):zsad253, DOI 10.1093/sleep/zsad253) found the SRI predicts all-cause mortality **above** sleep duration — which is why `VitalityEngine`'s regularity hazard prefers it to the `1 − CV` duration proxy it ships with.

NOOP records only during sleep sessions (a night wearable, not 24/7 actigraphy), so the index compares consecutive nights over a **±12 h coverage window** around each night's onset rather than a continuous round-the-clock timeline: daytime reads as awake on both days (a match), and a missing night drops out of the 24 h pairing instead of reading as an all-awake day. Coverage gate: fewer than `minNights` (7) → `nil`, and the orchestration falls back to the duration proxy.

**Comparability caveat (FER-657).** When `VitalityEngine` scores this SRI against the population **median 60** from **Cribb et al. 2023** (24/7 accelerometry, UK Biobank), the two are not measured on the same timeline: Cribb's SRI sees the full round-the-clock day, ours sees only the ±12 h windows around recorded nights. A window-restricted SRI tends to read **higher** than a full 24/7 SRI (it excludes daytime irregularity and counts near-certain daytime awake-awake matches), so comparing it against 60 is if anything **optimistic** — biased toward "regular", i.e. conservative in the direction that would *age* you. The Vitality regularity factor keeps its 0.450 slope rather than widening the band: it is already a soft input (a real SRI only when coverage exists, else the `1 − CV` duration proxy), and the bias does not over-penalize. See `VitalityEngine.contributions` (correction #5).

**What counts as a night — the "main night" gate (FER-298).** Both schedule-regularity engines — the SRI here (`fromSessions`) and the mid-sleep SD (`SleepRegularity.compute`) — score the *main* sleep period, so a **nap is excluded**: a short daytime sleep sits ~11 h from the nocturnal mid-sleep (near anti-phase on the 24 h circle), and counted as a "night" it would tank the SRI / explode the SD (13 steady nights + one 2 h nap → SD 126.9 min, score 0). Criterion: a session counts only if it lasts at least **3 h** (`SleepMainNight.minDurationMinutes`); shorter sleeps are naps and never enter the read. The threshold is a product-calibration boundary (it cleanly separates a typical nap ≤ ~2 h from a main sleep), not a clinical claim. Applied at the **session** level — not inside `compute(asleepIntervals:)`, which receives sub-night hypnogram spans that are legitimately short.

The per-night asleep timeline comes from the **already-persisted hypnogram** — the `stagesJSON` segments for on-device nights (every non-`wake` segment), via `AnalyticsEngine.decodeStages` — or, for imported / Apple-Health nights that store only stage totals, the session's whole `[start, end]` span (a coarser timeline that captures bed/wake-time regularity but not intra-night wakes). APPROXIMATE; no clinical claim.

---

## `SleepRegularity` — mid-sleep timing SD (circular)

Source: `SleepRegularity.swift` (FER-218). Live in `SleepDetailScreen`. A second, complementary take on sleep-timing regularity to the SRI above: instead of the epoch-to-epoch overlap probability, it reports the **standard deviation of the mid-sleep point** (the midpoint between onset and wake) over a rolling window of nights. Lower SD = a steadier schedule. It also reports the **weekend shift** (social jetlag): the shortest-arc gap between the typical weekend and weekday mid-sleep.

Mid-sleep is treated as a point on the 24 h **clock circle** and reduced with **circular statistics**, so a 23:30 and a 00:30 mid-sleep average to ~midnight rather than ~11:30 — the midnight wrap is built into the math, not patched with an origin. Each clock minute `m` becomes an angle `θ = 2π·m/1440`; with mean resultant length `R = |mean(e^{iθ})|`, the circular SD is `√(−2·ln R)` scaled back to minutes by `1440/2π` (a degenerate `R≈0` is clamped to the 12 h cap). The weekend median uses a wrap-aware circular median (the candidate minimizing summed shortest-arc distance).

The SD in minutes is the load-bearing, literature-anchored figure; the **0–100 score is presentation only** — a bounded, linear remap of the SD anchored so SD ≈ 0 → ~100 and SD ≥ `worstMidSleepSwingMinutes` (120, a product-calibration knob) → ~0. Gates: `nil` below `minNights` (7); flagged `preliminary` until `stableNights` (14); the rolling window is the most recent `windowNights` (14).

**Sampling limit — main nights only (FER-298).** A nap sits ~11 h from the nocturnal mid-sleep (near anti-phase on the circle) and would wreck the SD, so only sessions lasting ≥ 3 h (`SleepMainNight.qualifies`) feed the read; naps are excluded. The 3 h boundary is a product-calibration threshold, not a clinical claim — so the SD reflects schedule, not nap noise.

APPROXIMATE; no clinical claim. References: **Roenneberg et al. 2006** (mid-sleep point & social jetlag, *Chronobiology International* 23(1–2)); **Mardia & Jupp 2000** (*Directional Statistics* — circular mean/SD); supporting outcome links **Huang & Redline 2019** (*Diabetes Care* 42) and **Windred et al. 2024** (*Sleep* 47(1)).

---

## `Baselines` — personal rolling baselines

Source: `Baselines.swift`. Per-metric personal baselines that `RecoveryScorer` consumes. Two interchangeable paths produce the same `BaselineState` shape.

### 1. Winsorized EWMA (production model — `update` / `foldHistory`)

A robust, recency-weighted center with an EWMA-of-absolute-deviation spread tracker:

- **Half-life → smoothing factor:** `λ = 1 − 0.5^(1/halfLife)`. Center half-life 14 nights; spread half-life 21 (slower).
- **Sanity gate:** values outside `[minVal, maxVal]` (per-metric) → skip-and-hold.
- **Hard outlier rejection:** once seeded, a value > `hardOutlierK = 5 ×` spread away is seen but not folded.
- **Winsor clamp:** fold only within `± winsorK = 3 ×` spread of the current baseline, so a single big night can't yank the center; the **spread** uses the unclamped deviation so real change is still tracked.

```swift
let clamped = max(lo, min(hi, value))                       // ±3·spread
let newBaseline = lb * clamped + (1 - lb) * state.baseline
let newSpread   = max(cfg.floorSpread, ls * abs(value - newBaseline) + (1 - ls) * state.spread)
```

### 2. Trailing-window mean/SD (`rollingMeanSD`)

The simple, maximally auditable path: plain mean and sample SD (ddof = 1) over the trailing N (default 30) valid nights, with the σ floor applied and converted back into abs-dev space (`÷ 1.253`) so `deviation()` recovers the intended Gaussian σ unchanged.

### Log-domain baseline for HRV (`logDomain`)

Nightly HRV (RMSSD) is **~log-normal**, so HRV is baselined and z-scored on **`ln(RMSSD)`**, not raw ms (Plews et al. 2013, who monitor **lnRMSSD**; RMSSD itself per Task Force 1996). A `MetricCfg.logDomain` flag drives this — set only for `hrv`. Everything happens in "center space" (`ln(value)` for HRV, the raw value for every other metric), so the Winsor/EWMA/trailing math above is unchanged; only the space differs:

- **Center** — the stored `baseline` is the **geometric mean** (back in ms, so display is untouched), not the arithmetic mean. On a log-symmetric series the geometric mean is the true center; the arithmetic mean sits above it.
- **Spread** — kept in **ln units**; `deviation()` and the ±σ band (`Baselines.normalRange`) read `state.logDomain` to z-score on `ln(value)` and to make the normal-range band **multiplicative** (`exp(lnBaseline ± k·σ)`), so it stays positive and asymmetric in ms.
- **Plausibility gate** — `minVal`/`maxVal` stay the ms bounds, applied *before* the log transform.
- **Why it matters** — a raw-ms baseline biases the center **up** and underweights low nights (a −1σ_ln night scored z ≈ −0.89 instead of −1.0). Since HRV weighs `0.60` in `RecoveryScorer`, that bias propagated into both Recovery and Readiness. Measured on 58 real nights: center bias **+1.9 %**, recovery shifted **−1.4 pts** on average (median |Δ| ≈ 1.8, max ≈ 9.5 pts on the lowest nights — exactly where the linear z under-reacted).

### Status lifecycle (`BaselineStatus`)

| Status | Condition |
|---|---|
| `calibrating` | fewer than `minNightsSeed = 4` valid nights (no score yet) |
| `provisional` | `4 … 13` valid nights (usable, higher uncertainty) |
| `trusted` | ≥ `minNightsTrust = 14` valid nights |
| `stale` | usable but no update for > `staleDays = 14` nights |

### Per-metric config (`metricCfg`)

| Metric | min | max | floor spread | center / spread half-life |
|---|---|---|---|---|
| `hrv` | 5 | 250 | 0.08 (ln units, **log-domain**) | 14 / 21 |
| `resting_hr` | 30 | 120 | 2.0 | 14 / 21 |
| `resp` | 4 | 40 | 0.5 | 14 / 21 |
| `skin_temp` | 20 | 42 | 0.3 | 14 / 21 |

### Deviation

`deviation(_:state:)` returns a robust z-score, a signed physical-units delta, a fractional ratio (`value/baseline − 1`), and an `inNormalRange` flag (`|z| ≤ 1`). For a log-domain baseline (HRV) the z is taken on `ln(value)` vs `ln(baseline)`; `delta` and `ratio` stay in ms.

---

## `WorkoutDetector` + `Calories` — retroactive workout detection

Source: `WorkoutDetector.swift`. Finds workouts in the stored 1 Hz HR + gravity streams (no manual logging).

A workout is a **sustained window** (≥ `minExerciseMin = 5` min) where **both** gates hold per sample:

- **Elevated HR** — above `RHR + hrMarginBPM (15 bpm)`. RHR defaults to the day's 10th-percentile HR.
- **Sustained motion** — gravity-derived intensity (10-second trailing mean) above `motionThreshold = 0.20`.

Active samples are grouped into runs (merging gaps < `mergeGapS = 150 s`), then qualified by intensity: ≥ `minIntensityZ2Plus = 0.50` of the bout in Edwards zone 2+. Per bout it reports avg/peak HR, duration, Edwards zone-time %, mean `%HRR`, strain (via `StrainScorer`), and calories.

### Calories (`Calories.estimateBoutCalories`)

Per-second blend of **Keytel (2005)** active expenditure and **revised Harris–Benedict** BMR (resting), with sex-specific coefficients (`male` / `female` / `nonbinary`). Below a `RHR + 0.30 × HRR` threshold the resting rate is used; above it, the HR-driven active rate. Returns `(kcal, kJ)`. **Approximate** — not laboratory calorimetry.

### Strength sessions (`Calories.estimateStrengthEnergy`)

A guided strength session uses `Calories.estimateStrengthEnergy`, which prefers heart rate when the session captured it (FER-399): with ≥2 strap HR samples it uses the **Keytel (2005)** HR model (`estimateBoutCalories`, the same as detected bouts); without usable HR it falls back to a **MET** estimate (`estimateStrengthCalories`): `kcal = MET × bodyMassKg × hours`, with MET from the **Compendium of Physical Activities (Ainsworth et al. 2011)** — resistance training ≈ 3.5 MET (8–15 reps, varied resistance), the moderate value since a no-HR session doesn't measure effort. Body mass falls back to 70 kg when unknown; duration is clamped to [0, 6 h]. The captured HR also yields the session's `avgHr` + `strain` (`StrainScorer`). **Approximate** — not laboratory calorimetry.

---

## `FitnessAgeEngine` — on-device "Fitness Age" (Nes/HUNT)

Source: `FitnessAgeEngine.swift`. A pure, **independent** implementation of the **Nes et al. 2011** HUNT non-exercise VO₂max model (waist-circumference variant), inverted into a **"Fitness Age"**. It is a *fitness comparison, never a biological or clinical age*. **Live** — orchestrated from `CuerpoView` (`FitnessAgeEngine.snapshot`) with its own detail view (FER-141, done).

### The model

- **VO₂max (ml/kg/min), Nes 2011 waist variant** — coefficients from the primary Nes 2011 (PMID 21502897); a secondary "verbatim reproduction" ([PMC7428991](https://pmc.ncbi.nlm.nih.gov/articles/PMC7428991/)) could not be verified, so the primary source alone anchors them (FER-657). SEE ≈ 5.70 (men) / 5.14 (women):

```
men:    100.27  − 0.296·age + 0.226·PA − 0.369·waist − 0.155·RHRseated
women:   74.736 − 0.247·age + 0.198·PA − 0.259·waist − 0.114·RHRseated
```

- **PA-index (0–15)** — the HUNT1 PA-Q (Kurtze 2008): `frequency(0–5) × intensity(1–3) × duration(0.10–1.0)`, reconstructed from weekly signals since NOOP has no questionnaire.
- **Fitness Age** — invert the *same* Nes equation against a reference-fit peer: `FA = age + (rhrC·(RHR − RHRref) − paiC·(PA − PAref)) / ageC`. The waist term appears in both the user's estimate and the reference curve, so it **cancels** — the headline needs no body measurement, and an average-fitness person maps to their own chronological age by construction.

### NOOP domain-transfer corrections (FER-122)

The Nes model was calibrated on HUNT questionnaire inputs; NOOP feeds it wearable signals from a different domain. Three documented corrections (each verified by a test), after an expert review of the model's assumptions:

1. **Resting-HR domain.** Nes/CERG use **seated** resting HR ("sit 10 min, count your pulse"); WHOOP reports **nocturnal** RHR, ≈7 bpm lower (nocturnal dip; [Dial 2025](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12367097/) confirms WHOOP tracks nocturnal RHR accurately vs ECG — the gap is the *domain*, not the device). Feeding nocturnal RHR against a seated reference would read everyone ≈0.52 yr/bpm × 7 ≈ **3.7 yr too young**. Fix: the engine's RHR contract is **nocturnal throughout**; `restingHRReference = 58` (the validated seated anchor 65 minus the 7-bpm dip); the absolute VO₂max converts nocturnal → seated-equivalent internally. The Fitness Age uses `(RHR − RHRref)` with both terms nocturnal, so the dip cancels and the delta is unbiased.
2. **Activity scale.** `physicalActivityIndexFromStrain` is recalibrated to **this repo's 0–21 strain scale** (the upstream engine assumed 0–100, where a real workout would read as sedentary here). The strain→PA-index bridge is an **unvalidated heuristic** in any scale, so activity is a *soft* input: resting HR drives the headline, and sparse activity coverage caps confidence at `.estimate`.
3. **Uncertainty band.** The per-reading Nes SEE (≈5.70 ml/kg/min over the ~0.3/yr age slope ≈ **±19 yr**) is far wider than the displayed ±5. The ±5 band is defensible **only for the age delta** (the shared structural SEE of the same model cancels between user and reference); it does **not** apply to the absolute VO₂max, which is presented as a coarse estimate.

### Readiness & honesty

`assessReadiness` returns `.ready` / `.estimate` / `.notReady` from profile completeness + 7-day coverage. RHR (the validated driver) gates confidence: `.ready` needs a well-covered RHR week; sparse activity never promotes to `.ready`. Body metrics (height/weight/waist) only power the separate VO₂max and never block the headline. References: **Nes 2011** (Med Sci Sports Exerc 43(11):2024-30), **Kurtze 2008** (HUNT1 PA-Q), **Dial 2025** (nocturnal RHR validation).

---

## `VitalityEngine` — on-device "Vitality" score + "Body Age" (WHOOP Age / Healthspan method)

Source: `VitalityEngine.swift`. A pure, **independent** implementation of the published method behind WHOOP's "Healthspan / WHOOP Age": map each wearable input to its **all-cause-mortality hazard ratio** vs a population reference, sum the log-hazards with an overlap correction, and convert the combined hazard to **years of aging** via the Gompertz mortality-rate doubling time (~8 yr). Returns both a **Vitality** score (0–100) and a **Body Age** (years). It is a *wellness comparison, never a biological or clinical age*. **Live** — orchestrated from `CuerpoView` (`VitalityEngine.compute` → `BodyAgeSheet`) (FER-145, done).

**Differentiation from Fitness Age:** Fitness Age (above) is cardiorespiratory only (Nes/HUNT). Body Age is a **whole-body** composite that adds sleep duration, sleep regularity, HRV and steps; the two deliberately share the RHR/VO₂max signal, and the presentation layer keeps them distinct.

### The model

- **Factors** — each a signed log-hazard vs a reference (positive = ages you): resting HR, VO₂max vs the age/sex-expected value, sleep duration, sleep regularity, HRV (RMSSD), daily steps. `compute` returns nil until ≥ `minFactors` (3) are present (honesty gate).
- **Combine** — `Δage = (Σ lnHR · shrink) / (ln2 / 8)`; `bodyAge = age + Δage` (clamped [20, 90]); `vitality = clamp(50 + (age − bodyAge)·2.5, 0, 100)`. `contributions` exposes the per-factor breakdown that drives the "what's moving this" UI.

### NOOP corrections (FER-124)

An expert review against current primary literature found the upstream coefficients portable but **not verbatim**. Six documented corrections (each verified by a test):

1. **Resting-HR domain [= FER-122].** Re-anchored from the seated 65 to the **nocturnal** domain by reusing `FitnessAgeEngine.restingHRReference` (58) — one shared constant across both engines. Slope kept (≈+10%/10 bpm; Zhang 2016 / Aune 2017).
2. **Sleep duration — asymmetric.** Optimum 7.0 h (±0.5 neutral); short arm 0.060, long arm 0.120 (Yin 2017; Cappuccio 2010), replacing the symmetric 0.110 that over-penalized short sleep.
3. **Overlap shrink — factor-count-dependent.** `1/(1+0.35·(n−1))` instead of a fixed 0.75, which over-counted correlated signals and unfairly cut users with few inputs (e.g. steps only, no strap).
4. **HRV — attenuated.** Weight 0.160 → 0.110, in log form (`ln(norm/rmssd)`, Hillebrand 2013) — the HRs come from clinical short-term ECG, not nocturnal PPG, and the daytime-calibrated norm table already makes the factor conservative. Carries a mandatory non-clinical domain caveat. *Citation scope (FER-657):* Hillebrand 2013 (*Europace* 15(5):742–749) is a **first-cardiovascular-event** dose-response, **not** all-cause mortality — we borrow only its log-linear shape; the all-cause direction rests on **Jarczok 2022 / Dekker-ARIC 2000**.
5. **Sleep regularity — reference.** Slope kept; the SRI p5-vs-median all-cause-mortality HR 1.53 (95% CI 1.41–1.66) and the population median SRI ≈60 (→0.60 on an SRI/100 scale) are from **Cribb 2023** (*eLife* 12:RP88359). Windred 2024 is the "regularity predicts mortality more strongly than duration" result — its cohort median runs higher (~81), so it is *not* the source of the 0.60 reference. Upstream ref 0.75 → 0.60 so the average user is neutral. The orchestration (FER-145, `CuerpoView.computeSleepRegularity` → `SleepRegularityIndex.fromSessions`) passes a **real SRI/100**; the engine's `sleepConsistency` (1 − CV of durations) remains only as a cold-start fallback.
6. **Steps — age-aware threshold.** Reference `age ≥ 60 ? 7000 : 8500` (Paluch 2022); per-1,000 weight 0.064 and the 11k protection cap kept (conservative vs Jayedi 2022).

Kept **verbatim** (well-centered, documented): VO₂max 0.130/MET (Kodama 2009 / Singh 2025; estimated ≈ measured); Gompertz MRDT 8 yr (within the human 7.7–9.9 range, a global ±~15% scale). The full per-coefficient review with primary sources is logged on the FER-124 issue. References: **Zhang 2016 / Aune 2017** (RHR), **Kodama 2009 / Singh 2025** (VO₂max), **Yin 2017 / Cappuccio 2010** (sleep), **Cribb 2023 / Windred 2024** (regularity), **Jarczok 2022 / Hillebrand 2013** (HRV), **Paluch 2022 / Jayedi 2022** (steps).

---

## `ReadinessEngine` — morning readiness verdict

Source: `ReadinessEngine.swift`. Live in `TodayView` (the verdict hero). A pure, deterministic synthesis of a handful of established sports-science signals from the daily-metrics history into one readiness `Level` (`primed` / `balanced` / `strained` / `rundown` / `insufficient`) plus the drivers behind it. Each signal is a flag (`good` / `neutral` / `watch` / `bad`):

- **HRV / resting-HR** — z-scores against the robust EWMA personal baseline `RecoveryScorer` also consumes (shrunk toward neutral on thin baselines). An HRV drop / RHR rise flags autonomic fatigue / overtraining (Plews et al. 2013; Buchheit 2014). **Respiratory rate** uses a plain trailing-window Gaussian z (mean / sample-SD over the recent baseline window) and **skin-temperature** uses fixed °C deviation thresholds (≈ +0.4 / +0.8 °C) rather than a baseline z — a rise in either is an early illness marker. (`RecoveryScorer.recovery()` *does* route all four through the EWMA baseline, so the score and this verdict can differ slightly for resp / skin-temp.)
- **Training Stress Balance (ACWR)** — acute (7-day) ÷ chronic (28-day) workload, banded `<0.8 / 0.8–1.3 / 1.3–1.5 / ≥1.5`. Computed on a **linearized** TRIMP-like load (inverting `StrainScorer`'s log map) so a spike reads as a spike, not flattened. Needs ≥ `minChronic` (14) days of strain. **The signal copy is purely descriptive of where your acute load sits vs your chronic** ("acute above chronic", "acute well above chronic") — no injury-risk imperative (FER-657): **Impellizzeri et al. 2020** (*Br J Sports Med* 54:1451–1462) show the ACWR does **not** predict injury, so NOOP states the load relationship, not a risk verdict.
- **Training monotony** — week-long mean ÷ SD of strain; high monotony (low day-to-day variety) is associated with higher strain/illness (Foster 1998).

A short night (< 6 h) flags the morning read **low-confidence** (a short night suppresses HRV / lifts RHR regardless of true recovery). A separate, testable `BridgeKind` reconciles a high recovery score against a cautious verdict (the classic "you woke up recovered, but your training load is the thing to watch" divergence), reusing `RecoveryScorer.bandYellowMax` as the "recovery high" threshold.

**Honest note — the ACWR is coupled.** The acute window is a subset of the chronic window (acute ⊂ chronic), faithful to the original Gabbett formulation; this is the "coupled" ACWR whose statistical properties (spurious correlation, ratio artefacts) were critiqued by **Lolli et al. 2019** — an uncoupled ACWR (acute vs the *preceding* chronic block) avoids the shared term. NOOP keeps the coupled form deliberately (it matches the published bands users may know), and the readout is an association, not a clinical risk model. APPROXIMATE. References: **Gabbett 2016** (*Br J Sports Med* 50:273–280, ACWR); **Foster 1998** (*Med Sci Sports Exerc* 30(7), monotony); **Lolli et al. 2019** (*Br J Sports Med* 53(15):921–922, PMID 29101104, mathematical-coupling critique); **Plews et al. 2013**, **Buchheit 2014** (HRV/RHR).

---

## `RecoveryForecast` — one-day-ahead recovery projection

Source: `RecoveryForecast.swift` (FER-188). Live in two places: `RecoveryDetailScreen` (the "Mañana, si descansas igual: ~X" block) and the post-session strength summary's recovery-cost block (FER-442, the "Mañana, si descansas bien, deberías rondar ~X%" line). Answers a narrow question — *given how recovery has been trending and assuming you rest about the same, roughly where does tomorrow land?* — as a **trend projection with a range**, never a guarantee.

It projects the **recovery composite directly** rather than forecasting HRV and RHR separately and recomposing them: recovery is already the HRV-dominant composite, so its day-to-day series *is* the autoregressive trend of those drivers, de-noised and already on the 0–100 scale. The model is a **damped level + slope**:

- `level` = mean of the last `levelDays` (7) valid days
- `slope` = OLS slope of recovery vs day index over the trailing `window` (21 days), then `step = slope · 0.5`, clamped to ±8 pts/day (short noisy daily series over-extrapolate)
- `debt` = a gentle, bounded downward drag from standing sleep debt (a **product heuristic**, not a peer-reviewed coefficient — "si descansas igual" means you won't repay it tomorrow)
- `strain` = an **optional**, bounded downward drag from an acute session done *today* whose cost hasn't yet landed in the recovery series (FER-442). A harder session delays post-exercise parasympathetic reactivation, so tomorrow sits a little below the trend alone (**direction** per Stanley, Peake & Buckley 2013 — see citation below; **magnitude** is a product-calibration knob, capped at 8 pts to stay inside the engine's ±8 one-day envelope). Off (0) unless the caller passes a session strain — the strength cost block does, the Recovery-detail trend does not.
- `estimate = clamp(level + step − debt − strain, 0…100)`; `range = estimate ± max(5, 1.15·σ)` — deliberately wide, because the band is the honesty

**Honest gate:** returns `nil` below `minDays` (14, ≈ two weeks of baseline); the caller then **hides** the block rather than inventing a number. The window/damping/cap/band/debt/strain-drag constants are product-calibration knobs, not validated quantities. APPROXIMATE. References: **De Sabbata & Simonini 2025** (*J Healthcare Informatics Research*, PMC12037944) — for univariate short-term wearable forecasting, "refining model complexity offers minimal benefit" and a random-walk baseline "remains competitive, if not superior", which is exactly why this is a damped level+slope model and not something heavier (the paper's scope is short-term, cited accordingly); **Stanley, Peake & Buckley 2013** (*Sports Medicine* 43(12):1259–1277) — post-exercise cardiac parasympathetic reactivation is delayed by higher training load, the grounded *direction* (not magnitude) of the optional acute session-strain drag.

---

## `RecoveryChange` — «qué cambió vs ayer» day-over-day attribution

Source: `RecoveryChange.swift` (FER-642). **Live.** Surfaced in the unified «qué mueve tu recuperación» experience (Recovery summary + detail). Answers a narrow question — *how did the recovery score move since yesterday, and which one or two signals moved with it?* — as a **day-over-day change read-out**, never a causal explanation.

It is the companion to `RecoveryImpact`. Where `RecoveryImpact` decomposes **today's LEVEL** (each present signal's share of today's composite z vs your personal base — an *exact, additive* decomposition of the score), this engine decomposes the **CHANGE**:

- `deltaScore = todayScore − yesterdayScore`, over the **displayed** scores. This part is **exact** — the engine invents no score, so the headline always equals «today shown − yesterday shown», rounded to whole points.
- **Movers** — for each signal present in *both* days' impacts, the day-over-day move in its own oriented contribution to the composite (`contribution = orientedZ × weight`, taken as a difference of two `RecoveryImpact` results). Ranked by `|Δcontribution|` descending; the top **1–2** are shown. The move is oriented so «+» always means «moved the way that helps recovery», driving the ▲/▼ glyph and the «mejoró/empeoró» word. Sleep is scored on **efficiency %** (the quantity the sleep term reads), not duration, so the «ayer → hoy» read-out matches what actually moved the score. Different units (ms vs bpm vs %) never compete on raw magnitude — they compete in the score's own contribution currency.

> **Honest caveat — the mover ranking is a co-movement attribution heuristic, not an exact Δscore decomposition.** Ranking signals by their change-in-contribution surfaces *which signal moved alongside the score* between the two days; it is **not** an exact algebraic split of `deltaScore` into per-signal parts (the composite is a renormalized weighted mean squashed through a logistic, so the day-over-day Δscore is not the plain sum of per-signal Δcontributions). Contrast `RecoveryImpact`, which *is* an exact additive decomposition of a single day's level. The copy therefore says «cambió» / «subió» / «bajó», **never** «causó» — a signal that moved with the score is described, not a cause of it.

**Gates & purity.** «vs ayer» means literally the previous **calendar** day: `compute` returns `nil` (and the whole block hides) when yesterday's band row, either day's displayed score, or either day's `RecoveryImpact` is missing — it never invents a change or reaches past yesterday. Both impacts are computed **band-only** (the same whole-row Apple-day drop `RecoveryImpact` uses, FER-519 / FER-629), so a day-over-day story never mixes an Apple-only night into a band day. Signals whose contribution didn't actually move (`|Δcontribution| ≤ 1e-9`) are dropped. Pure and deterministic — no store, no clock, no state. APPROXIMATE; no clinical claim.

---

## Interactive engines (wired into screens)

These are the **live** data-interrogation engines, used by `InsightsView`, `CompareView`, and `MetricExplorerView`.

### `CorrelationEngine`

Source: `CorrelationEngine.swift`. Pearson r, OLS regression, and an approximate two-sided p-value between two daily series.

```
r         = Σ(x−x̄)(y−ȳ) / sqrt( Σ(x−x̄)² · Σ(y−ȳ)² )
slope     = Σ(x−x̄)(y−ȳ) / Σ(x−x̄)²          (OLS, y on x)
intercept = ȳ − slope·x̄
t         = r · sqrt( (n−2) / (1−r²) )
p         = 2·Iₓ(df/2, ½),  x = df/(df+t²)  (exact two-sided Student-t tail, df = n−2)
```

- Returns `nil` for fewer than 3 pairs or zero variance in either variable.
- The tail is the **exact** two-sided Student-t p-value via the regularised incomplete beta `Iₓ(df/2, ½)` (continued-fraction evaluation, Lentz's method; *Numerical Recipes* §6.4), df = n−2 — fully deterministic, no special-function tables. (FER-299 replaced the earlier normal approximation, which **understated** p for small n because the true Student-t tails are heavier.)
- `alignByDay(...)` inner-joins two `yyyy-MM-dd`-keyed series; `lagged(x:y:lagDays:)` shifts y forward by `lagDays` (UTC day arithmetic) to probe directional/delayed effects — e.g. *today's strain vs tomorrow's recovery*.

### `BehaviorInsights`

Source: `BehaviorInsights.swift`. The headline "does this behavior move an outcome?" feature. Splits days where a behavior was logged (e.g. *Alcohol*, *Late meal*, *Meditation*) from days it was not, and compares an outcome metric between the groups.

For each behavior/outcome it reports group means, signed `delta`, `pctChange`, **Cohen's d** (pooled SD), and a **Welch t-test** p-value (unequal variances, Welch–Satterthwaite df, exact Student-t tail via the regularised incomplete beta):

```
sp = sqrt( ((n1−1)·s1² + (n2−1)·s2²) / (n1+n2−2) )     d = (m1 − m2) / sp
t  = (m1 − m2) / sqrt(s1²/n1 + s2²/n2)
```

- `significant` requires `p < 0.05` **and** `min(nWith, nWithout) ≥ 5` (guards against spurious "significance" from a handful of days).
- `rank(...)` orders effects by `|d|` descending, significant first.
- `sentence(_:)` renders plain English, e.g. *"On days you logged 'Alcohol', Recovery was 12% lower (avg 61 vs 69, n=140 vs 498)."*

**Eligible-day restriction (FER-385).** `effect(… , eligibleDays:)` takes an optional universe of days the behavior is even *measured* on. For journal behaviors it stays `nil` — absence of a log means "didn't do it", so every day is eligible. For **diet adherence** it's the set of days that carry a `diet-adherence` point: a day with no record is *unknown*, not non-adherent, and falls into **neither** group. The binary behavior is *"I followed my diet"* = days with `diet-adherence ≥ 80%` (`DietAdherence.adherentDayThreshold`; 80% is borrowed *by analogy* from the medication-adherence PDC/MPR convention — Karve 2009 — not a validated diet cutoff, so it's a NOOP product convention). `InsightEngine.Inputs.eligibleDaysByBehavior` threads the per-behavior universe in; the **N-of-1 experiment deliberately does NOT restrict** (its "without" group is the full baseline — restricting a 7-day window would starve it below the `minGroup` floor).

### `ComparisonEngine`

Source: `ComparisonEngine.swift`. Period-over-period comparison of one daily metric.

- `stat(_:)` → `SeriesStat`: mean, median, min, max, sample SD (ddof = 1), n, and least-squares slope-per-day (OLS against the 0-based index).
- `compare(current:previous:)` → `PeriodComparison`: signed `delta` on the means, `pctChange` (nil when the previous mean is 0/empty), and a coarse `direction` (`-1/0/+1`).
- `monthOverMonth(byDay:referenceDay:)` splits a `yyyy-MM-dd` series on the `yyyy-MM` prefix (locale/timezone-free) into the reference month vs the immediately preceding calendar month.

---

## The library orchestrator: `AnalyticsEngine`

Source: `AnalyticsEngine.swift`. A pure function that ties the recompute engines together for one day. **Implemented and tested, but not yet wired into the import/store pipeline** — the importers currently copy WHOOP's own per-day recovery/strain/sleep numbers from your export.

`analyzeDay(day:hr:rr:resp:gravity:profile:baselines:maxHROverride:)` runs, in order:

1. `SleepStager.detectSleep` → keep sessions whose `end` falls on `day` (UTC) — a night ending that morning.
2. Daily sleep aggregates (in-bed-weighted efficiency; deep/REM/light minutes; disturbances) via `hypnogramMetrics`.
3. Daily resting HR = lowest per-session resting HR; daily avg HRV = in-bed-weighted mean of per-session HRV.
4. `RecoveryScorer.recovery(...)` with the personal HRV/RHR/resp/skin-temp baselines and a personal (own-baseline) sleep-efficiency term.
5. `StrainScorer.strain(...)` over the full day's HR window (Tanaka HRmax from age unless overridden).
6. `WorkoutDetector.detect(...)`.

It assembles a `DailyMetric` (the `WhoopStore` cache shape) plus rich `SleepSession`s and `CachedSleepSession` cache rows. Every derived value is **approximate** by construction.

---

## `ActivityCostEngine` — per-sport recovery association

Source: `ActivityCostEngine.swift`. A pure, DB-free engine that describes, **per sport**, how far your next-morning Charge (recovery) tends to sit *below* your rest-day baseline after a session, and roughly how long it tends to take to climb back. **Live.** Surfaced in `ActivityRecoverySheet` (presented from `CuerpoView`), evaluated in `Repository` via `ActivityCostEngine.evaluate` (FER-139). The Kotlin/Android mirror is tracked in FER-140.

Given `activityDaysBySport` (per sport, the set of `yyyy-MM-dd` day keys it was tagged on) and `recoveryByDay` (daily Charge 0–100), for each sport S:

```
restDays       = days with a Charge value that are NEITHER tagged with any sport NOR inside any
                 tagged day's forward window D+1…D+7   (your "untouched" days)
baselineCenter = median(Charge over restDays)                        (shared across all sports)
nextMorningCenter = median(Charge[D+1] over tagged days D that have a D+1 value)
delta          = baselineCenter − nextMorningCenter        (positive → mornings sit below baseline)
daysToBaseline = smallest k∈1…7 with median(Charge[D+k]) ≥ baselineCenter − 3      (.solid only)
```

- **Excluding the post-effect window from the baseline** is the key bit of hygiene: the mornings *after* a session are exactly the days the gap suppresses, so counting them as "rest" would contaminate the baseline with the very thing being measured.
- It is plain descriptive statistics over aligned day keys — in the spirit of HRV-/recovery-guided training monitoring (Plews et al. 2013; Task Force 1996 for the HRV that backs Charge). Nothing is learned.

### Expert-review adjustments (FER-123)

The engine was ported from upstream NoopApp/noop **after an expert review of the method**, which found several upstream thresholds sat below the measurement-noise floor. Five adjustments were applied (each covered by a test), deliberately breaking byte-parity with the upstream oracle:

| Lever | Upstream | NOOP | Why |
|---|---|---|---|
| Center | arithmetic mean | **median** | a single off night shouldn't dominate a thin sample (matches the robust-center house style of `Baselines`) |
| `minSessions` | 4 | **6** | at n≈4 the standard error of the center (~5 pts for SD≈10) is the same order as the gap itself — mostly noise |
| `barelyMovesPoints` | 1.0 | **3.0** | day-to-day Charge test-retest is ~±5–7 pts; a 1–2 pt "effect" is noise |
| `daysToBaseline` | always | **`.solid` only** | the most fragile output (composite trajectory over different day subsets per horizon, `tol`=3 near the noise floor) |
| Narrative | "cost you" | **association** | framed as correlation, not a causal cost (see below) |

Kept as-is: `solidSessions = 8`, `maxLookahead = 7` days (recovery from a single bout is largely done in 24–72 h, with DOMS/eccentric damage trailing to ~5–7 days), `tolerance = 3` pts.

### This is association, not a causal "cost"

The narrative (`sentence()`) and these docs frame the gap as an **association over your own history**, never a cause. Three confounders make the causal reading wrong:

- **Regression to the mean** — you tend to train on days you wake up feeling good (high Charge), so the next morning drifts back down regardless of the session.
- **Non-random rest days** — you rest when tired / sick / travelling, so "untouched" days are not a clean counterfactual for "what your Charge would have been without the session".
- **Day-of-week & overlapping sessions** — a sport done mostly on weekends conflates the sport with weekend behaviour; two sports on the same day both inherit that D+1 morning.

A sport with fewer than `minSessions` next-morning pairs is **omitted entirely** (too thin to say anything honest); 6–7 pairs → `.building`, ≥ 8 → `.solid`. Results rank by `|delta|` descending, `.solid` before `.building`, then sport name — fully deterministic.

---

## Data flow summary

```
WHOOP strap (BLE) ─┐
                   ├─► WhoopProtocol (frame decode) ─► WhoopStore (SQLite, 1 Hz streams)
WHOOP CSV export ──┤                                         │
Apple Health XML ──┘                                         │
                                                             ▼
   importers copy per-day recovery / strain / sleep ──► DailyMetric (metrics cache)
                                                             │
                          ┌──────────────────────────────────┤
                          ▼                                   ▼
   AnalyticsEngine.analyzeDay (recompute path,        Repository.days ─► TodayView,
   library-only today: HRV/recovery/strain/sleep      InsightsView (CorrelationEngine,
   from raw streams)                                   BehaviorInsights), CompareView,
                                                       MetricExplorerView (ComparisonEngine)

   live BLE stream ─► AppModel: HR smoothing · RMSSD · zone coaching ·
                       illness early-warning · resting-stress nudge
```

---

## `CyclePhaseEngine` — menstrual-cycle phase awareness (FER-672)

Estimates the **current** cycle phase (follicular-lean vs luteal-lean) from the nightly skin-temperature
deviation NOOP already stores (`DailyMetric.skinTempDevC`). Pure, DB-free, computed on the fly — no new
decode, no persistence, no migration. Opt-in and off by default; surfaced only in the Experiments sheet.

### Method

A robust **luteal index** z over the trailing window: `z = 0.75·zTemp + 0.25·zRHR`, each term z-scored
against the window's own median (centre) and robust σ (`IllnessWatch.robustSigma`, the repo's `× 1.253`
mean-absolute-deviation convention). Skin temp is the dominant driver; resting HR corroborates. **HRV is
NOT a term in the index** (decision H1): a DROP is luteal-ward, but for the RMSSD NOOP measures the
effect is inconsistent, so HRV can only *raise confidence one notch* when it agrees with the temp+RHR
lean — it never votes on the phase. A ≥42-night gate (`.learning` below it), a robust-σ noise floor and a
minimum |z| guard the `.noClearPattern` state; confidence scales with |z| and night count.

### Evidence (each an approximate, documented driver — not a reproduction of any algorithm)

- **Skin temp ↑ in luteal (dominant).** Maijala et al. 2019, *BMC Women's Health* 19
  (doi:10.1186/s12905-019-0844-9): nightly skin temp **+0.30 °C** (SD 0.12), p<0.001. Gombert-Labedens
  et al. 2024, *J Biol Rhythms* 39(4):331–350 (doi:10.1177/07487304241247893): post-ovulatory thermal
  shift detectable in **~85 %** of cycles with a wearable.
- **Resting HR ↑ in luteal (corroboration).** Shilaih et al. 2017, *Sci Rep* 7
  (doi:10.1038/s41598-017-01433-9): sleeping pulse **+1.8 bpm** (mid-luteal vs fertile), +3.8 vs menses.
- **HRV ↓ in luteal (weak, mixed — confidence only).** Real on average (Schmalenberger et al. 2019
  systematic review, PMID 31726666; 2020 *J Clin Med* 9(3):617, doi:10.3390/jcm9030617), but for RMSSD
  specifically inconsistent/null: Yazar & Yazıcı 2016, *Med Princ Pract* 25(4)
  (doi:10.1159/000444322): rMSSD 38±12 → 41±27 ms, **n.s.** This is why HRV is reinforcement, not a term.

### Honesty

The weights (0.75/0.25) and the ≥42-night gate are **product-calibration knobs, NOT derived from any
publication** (decision H2) — they encode the evidence hierarchy (temp ≫ RHR), nothing more, and are
pinned by `CyclePhaseEngineTests.testCalibrationConstantsPinned`. The estimate is **retrospective**: the
temperature shift confirms a phase 1–3 days *after* it changes, so the copy never implies real-time
detection (H3). Wellness / self-knowledge only — never fertility, ovulation, contraception, a period
date, or any clinical claim.

---

## Conventions & honesty notes

- **Approximate by design.** Recovery, strain, sleep stages, workout intensity, and calories are transparent approximations of published methods — not reproductions of any proprietary algorithm. Each engine's source header states exactly where it approximates (e.g. Malik instead of Kubios; RMSSD-only parasympathetic tone).
- **Deterministic.** No randomness, no wall-clock dependence inside the math, no DB/network access. Same inputs → same outputs, which makes the package unit-testable against fixed vectors.
- **Robust statistics.** z-scores use EWMA mean-absolute-deviation (`× 1.253` to a Gaussian σ); resting HR uses 5-minute bin minima; HR display uses windowed medians — all chosen to resist single-sample outliers.
- **Cold-start honesty.** When a baseline isn't trustworthy yet, the recovery scorer returns `nil` rather than a fabricated number.
- **Not a medical device.** None of this is diagnostic or medical advice. The illness early-warning is a wellness nudge from your own baselines, not a clinical screen.
- **Not affiliated with WHOOP.** NOOP interoperates with hardware and exports you already own, entirely on-device. Protocol decoding builds on community reverse-engineering of the WHOOP 4.0 (project *my-whoop*, `johnmiddleton12/my-whoop`) and WHOOP 5.0 (project *goose*, `b-nnett/goose`) protocols.
