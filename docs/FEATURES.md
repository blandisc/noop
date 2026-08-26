# Cénit — Feature Guide

Cénit is a standalone, fully **offline** health app on **Apple Health** — **no account, no
cloud** — that stores everything on-device in SQLite, imports your Apple Health export, and
computes readiness (preparedness), strain, HRV and sleep locally on your iPhone. There is no
wearable to pair: Cénit reads the samples your **Apple Watch** already saves to Apple Health.
Direct WHOOP band pairing and the live Bluetooth layer were retired (FER-1003). Cénit is the iOS
app (`Cenit`); its UI and data layer live under `Cenit/`, on top of the cross-platform Swift
packages.

> **Not affiliated with WHOOP.** Cénit is independent software for *your own* data. Historical
> "WHOOP" references name hardware the app once interoperated with; a legacy WHOOP-sourced data
> partition still on your device is shown as **"On-device"**, never as a band. **Cénit is not a
> medical device** — every metric (HR, HRV, readiness, strain, sleep, SpO₂, respiration, skin
> temperature) is an approximation, not a clinical reading, and must not be used to diagnose,
> treat or make health decisions.

Cénit stores its history on-device with [`groue/GRDB.swift`](https://github.com/groue/GRDB.swift)
(SQLite). Earlier versions interoperated with WHOOP hardware directly over Bluetooth — that path
is **retired** (FER-1003), but the reverse-engineering work it stood on deserves the credit:

| Project | Contribution |
| --- | --- |
| [`groue/GRDB.swift`](https://github.com/groue/GRDB.swift) | On-device SQLite persistence (still in use) |
| [`johnmiddleton12/my-whoop`](https://github.com/johnmiddleton12/my-whoop) | WHOOP 4.0 BLE protocol (retired band era) |
| [`b-nnett/goose`](https://github.com/b-nnett/goose) | WHOOP 5.0 / MG BLE protocol (retired band era) |

---

## At a glance

Cénit is a **four-tab** app, all of it warm-paper **«Instrumento diurno»** (one dominant number,
color only on the datum, hierarchy by space). The tabs are **Hoy** (Today), **Tendencias** (your
body over time), **Entrenar** (Train), and **Ajustes** (Settings):

| Tab | What it is |
| --- | --- |
| **Hoy** | The verdict home — today's readiness word and the SEÑALES grid. |
| **Tendencias** | Your body over time — the trend of every signal, plus sleep, stress, vitals, body composition and longevity. |
| **Entrenar** | The training planner — plan, routines, a guided live strength session, plus Breathe and Intervals. |
| **Ajustes** | Profile, units, data & backup, illness watch, reminders, support. |

There is **no live-connection chrome, no battery indicator, no "pairing" state** anywhere:
everything is computed from Apple Health samples and on-device math. The one place a live heart
rate appears is *inside a guided strength session*, mirrored from a paired **Apple Watch** — not a
band. Most of Cénit works the moment you connect (or import) Apple Health; a few surfaces sharpen
over your first couple of weeks and always say so while they calibrate.

Every metric is an approximation computed locally. Nothing is uploaded.

---

## Hoy — Today

**Tab: Hoy · the verdict home. Works from Apple Health data, computed on-device.**

`TodayView.swift` (with the `Cenit/Screens/Hoy/` builders) is the home screen — «El Ecosistema».
A header with the short date and the **24-hour dial seal** (no live BPM), then, when you have data:

- **The verdict hero** — the orb, with **one dominant word** — today's *Preparedness* reading
  (**In range**, **Go light today**, or **Recover**, and **Getting to know you** while the baseline
  calibrates) — and a plain-language clause. Color lands only on the datum. Tapping "how I got here"
  opens the **verdict acta** — the same word and math the onboarding and Entrenar show, so no two
  screens can disagree.
- **Training load** — a strip with your ACWR band (recent vs. your usual) when there's enough
  recorded strain.
- **SEÑALES** — a uniform tile grid, each with a sparkline: **Sleep, HRV, Resting HR, Day strain,
  Steps, Skin temp, Respiration, Stress**. Resting HR is your **nocturnal** rate, measured by your
  Apple Watch during sleep and read through Apple Health. Tapping a tile opens its metric sheet
  (14-day curve, bands, level table); "Ver más" escalates to the rich detail screen.
- **Manuals & guardian** — «¿Qué decide tu día?» and «Tu contexto» explain the reading; the
  **guardian sheet** shows the sentinel pair (skin temp + respiration) and why it only votes when
  both drift together.

**Data** — everything comes from Apple Health plus on-device computation (`repo.todayPreparedness`,
the measured `DailyMetric` rows, on-device step estimation when Apple has no count). No network,
no account, no server.

**Empty state** — with no data and no Health permission, the **orb sleeps**: "Connect Apple Health
and it will start beating with your nights," a **Connect Apple Health** button (opening Data
Sources), and "Everything stays on your iPhone. No account, no cloud." The button connects Apple
Health — there is nothing to scan.

The **illness early-warning** banner also appears here when triggered (see below).

---

## Tendencias — your body over time

**Tab: Tendencias · works from Apple Health data, computed on-device.**

The second tab is labeled **Tendencias** and shows `CuerpoView.swift` — your body over time, on
warm paper. A **W / M / 3M / 6M / 1Y / ALL** range control re-windows every sparkline and the
hero's "vs your average" delta at once. Top to bottom:

- **Preparación hero** — no 0–100 recovery score (that died with the band): the **verdict word**
  for today, tinted, with its clause; or a calibration bar ("N/4", "Calibrating your baseline") on
  a young baseline. Tapping opens the **Preparación detail** ("your 30 mornings": today's word as
  anchor, a mosaic of 30 mornings, how often each of the three signals drifted, and the method).
- **Rest & load** — Sleep (minutes), Day strain / Day load, and Stress (0–3), each a tappable
  sparkline column.
- **Training load** — the ACWR band in a word (Low / Optimal / High) with the ratio and a
  mini-trend; "—" and a calibration note under ~2 weeks of recorded strain.
- **Your body** — a card that opens the **muscle map** (`TrainingBodyScreen`): per-muscle load
  crossed with your recovery.
- **Vitals** — a grid of **HRV, Resting HR, Blood Oxygen, Heart Rate** (intraday average),
  **Respiratory** and **Skin temp**, each tappable to its detail screen.
- **Activity** — Steps and Workouts (7d), plus "how you wake after each sport" (a per-sport
  recovery ranking).
- **Longevity** — **Physical age** (Nes/HUNT 2011, from resting HR + activity), **Body age**
  (VitalityEngine over 28 nights), and **VO₂ Max** (your Apple Watch's latest reading). All labeled
  "Estimate", all with non-clinical disclaimers.
- **Footer** — **Compare** and **See all metrics** (Explore).

Detail screens reachable from here:

- **Sleep detail** (`SleepDetailScreen.swift`) — a hypnogram of last night, last-night-vs-typical
  bars, per-night metric tiles, the week's sleep debt, a 90-night calendar, and the method. From
  Apple Health sleep sessions + on-device nightly metrics.
- **Stress detail** (`StressDetailScreen.swift`) — a single-number Stress Monitor (0–3, its own
  color ramp, never the recovery traffic light), what moves it (resting HR + HRV vs your baseline),
  your patterns, history, a 90-day calendar, and the method.
- **Skin temp detail** (`SkinTempDetailScreen.swift`) — signed deviation vs your rolling nightly
  baseline (Apple Watch wrist temperature), a warm/cool streak, bands, history, and (behind the
  experimental toggle) nightly thermal stability.
- **Physical age / Body age** (`FitnessAgeDetailView.swift`, `BodyAgeSheet.swift`) — the longevity
  estimates, what moves each, and honest "not enough signals yet" states.
- **Compare** (`CompareView.swift`) — overlay 2–4 metrics on a normalized axis and read every
  pair's **Pearson r** ("Association, not cause"). Sparse series auto-widen.
- **Explore** (`MetricExplorerView.swift`) — the whole signal catalog, one tap deep: latest value,
  a trend with a range control, and **"What correlates"** (Pearson scan, |r| ≥ 0.30, n ≥ 10).
- **Workouts** (`WorkoutsView.swift`) — the activity log: totals, weekly volume, by-sport, and a
  session list → detail. "Each session is a workout from Apple Health, an on-device capture, or a
  manual entry."
- **Apple Health** (`AppleHealthView.swift`) — the per-source viewer for everything read from the
  `apple-health` source, with tiles and chart sections (Heart & Vitals, Activity & Energy, Body
  Composition, Sleep).

Every value reads from the merged on-device dashboard (`repo.displayDays`); sparse series auto-widen
so a short window is never empty. The only wearable the copy ever names is the **Apple Watch**.

---

## Entrenar — Train

**Tab: Entrenar · the training planner. Fully offline; no account, no network.**

`EntrenarView.swift` is a **planner** on warm paper. Its data comes from the on-device store
(SQLite/GRDB), the exercise catalog and strength rules of `StrandTraining`/`StrandAnalytics`, and
the same day-verdict Hoy uses. Top to bottom:

- **The verdict thread** — the first line talks about your *body*, not the plan; tapping it opens
  the same verdict acta Hoy serves (never switches tabs).
- **The hero, by day** — a **routine day** shows the routine name, its muscles, "~50 min · 6
  exercises · 18 sets", and today's earned progression ("Hoy subes…" / "Hoy mantienes… la subida
  espera"), with one solid green **Empezar** that starts the guided session in a tap; a **rest day**
  shows "Descanso" and a single **Movilidad · 20 min** door; a **live session** wins over both, with
  an "En curso · N min" ticker and **Continuar** / **Terminar sesión**.
- **"Otra forma ›"** — four fixed doors that never read the verdict: **Rápido** (an empty strength
  session), **Intervalos**, **Movilidad**, **Respira**.
- **Tu semana** — a Mon→Sun token strip (done / today / planned / rest), a row per other routine,
  and the way into **Tu Plan**, **Nueva rutina**, and **Crear plan**.
- **Músculos cargados** — a one-line recovery estimate (or, on a rest day, the full per-muscle
  module), from `MuscleFatigueMap` over 84 days. Tapping opens the muscle map.
- **Bitácora** — the last completed sessions ("Mié 12 · Tirón A", marks, "44 min · 4 880 kg",
  effort "/21" when the Apple Watch gave HR), and **Historial y progreso ›**.

First-run (no split) shows "Arma tu semana", template chips, "Import your plan from your AI ›", and
a **Crear mi plan** CTA.

**Create a plan — three paths** (`CrearPlanScreen.swift`, FER-137). One door, three rows, all
offline: **Templates** (copying a group copies its routines *and* fills the free days of the week in
order, never overwriting an assigned day), **From scratch** (New routine → the library create-flow),
and **Import from your AI** (`WorkoutImportView.swift`) — Cénit hands you a prompt, you run it in
*your own* LLM, and you bring back a `noop.workout.v1` file that becomes real routines. **Cénit never
calls the network** — you run the LLM step yourself.

**Tu Plan** (`WeeklyPlanEditorView.swift`) — one surface: assign a routine or rest to each day (top),
weekly volume by muscle group, and every routine in a flat list (create / import / templates /
library / folders). `WeekEditorSheet.swift` is the quick way to rotate one day through the routines
already in the split.

**Routine editor** (`RoutineEditorScreen.swift`, FER-839) — one editor for viewing, editing, and
starting: the screen *is* the routine (Notes-style autosave, a "Guardado"/Undo banner; edits lock
while a session is live). On today's routine it evaluates progression per slot (history + your plate
inventory + the verdict). **Rest editor** (`RestEditorScreen.swift`) handles all five real rest
shapes (fixed, resting-margin, peak-drop, fixed-BPM, HR reference); **progression setup**
(`ProgressionSetupScreen.swift`) sets a rep floor/ceiling and a load step from your plate math.

**Exercise library & detail** (`ExerciseLibraryScreen.swift`, `ExerciseDetailScreen.swift`) — browse
the on-device catalog (search + filter by muscle/equipment), or multi-select into a routine. A
detail shows which muscles an exercise loads and your estimated-1RM trend; "Create exercise" adds
your own.

**The guided live strength session** (`LiveStrengthSheet.swift`, `StrengthSessionModel.swift`) — the
big piece. It presents as a **full-screen cover** owned by `AppModel`, so minimizing it (‹) or
switching tabs never loses it; a **floating pill** re-opens it from any tab. It runs 100% offline and
without HealthKit — logging strength is manual.

- **Set → rest → done.** The active exercise row is edited inline with Cénit's **own keypad**
  (`SessionKeypad.swift`): a 3-column grid whose "Next" key is the confirm affordance and carries the
  only accent. Marking a set done logs it; the **rest** appears as an inline countdown card. Rest and
  finish **haptics come from the iPhone** (`AppModel.buzz` — which explicitly replaces the retired
  strap motor).
- **The receipt.** When you finish, a receipt renders in place; the full-screen thermal print is
  `ReceiptPrinterScreen.swift`, and `SavedTicketsScreen.swift` is the grid of saved mini-receipts.
  `ShareCardView.swift` renders the shareable card.
- **Effort/HR only if present.** A session records HR and an effort score only when it carries
  **Apple Watch** heart rate; without it, those blocks are omitted (never invented as zero).

**History** — **Mis entrenamientos** (`WorkoutHistoryScreen.swift`) lists completed sessions →
**detail** (`WorkoutDetailScreen.swift`, honest hero: effort → avg HR → duration); **ManualWorkoutSheet**
adds a workout you tracked elsewhere.

**Breathe & Intervals** (hub tools):

- **Respira** (`BreathingView.swift`) — a paced-breathing trainer: a visual orb plus an **iPhone
  haptic cue** (one pulse on the inhale, two on the exhale). The live HRV/RMSSD readout and the
  coherence card were **retired with the band** (FER-1003) — solo breathing has no live R-R source.
- **Intervalos** (`IntervalTimerView.swift`) — a silent **haptic HIIT timer**: the phone buzzes each
  transition (WORK / REST / DONE, countdown ring, session progress), so you can train without looking.

---

## Ajustes — Settings

**Tab: Ajustes · always available.**

`AjustesView.swift` opens directly (no "More" drawer, no dark legacy Settings). Warm paper, sheet
navigation. A privacy chip up top ("On this iPhone · no account · no cloud"), then:

- **Profile** — Age, Sex, Weight, Height (wheel/segmented editors, unit-aware), and **Max heart
  rate** (Automatic = Tanaka, 208 − 0.7·age, or a Manual override). These drive your zones and
  workout-burn estimates.
- **App** — **Units & format** (Metric/Imperial, temperature °C/°F; display only, storage is SI).
- **Data** — **Data & sources** (→ Data Sources) and **Recalibrate recovery** (re-anchor your
  baseline from today; reversible, with Undo).
- **Salud** — the **illness watch** toggle (`behavior.illnessWatch`, off by default; see below).
- **Morning notice** (`AjustesAvisoMatutino.swift`) — a reminder (not a delivery: the app doesn't
  wake itself; the reading computes when you open it) to read yourself in the morning, at a time you
  set. Asks notification permission on enable; won't fake being on if iOS denied it.
- **Training reminder** (`AjustesRecordatorioEntreno.swift`) — same pattern, on your training days
  (read straight from your weekly split).
- **AFib History** (`AjustesHistorialFA.swift`) — an *informed door* to Apple's AFib History,
  shown only while your Apple Watch isn't yet giving dense beat-to-beat series. It presents both
  faces evenly — what it tunes (night HRV as a 0.5 co-vote) and what it costs (Apple requires
  confirming an AFib diagnosis; not for under-22s; turns off real-time irregular-rhythm alerts) —
  and never recommends or diagnoses.
- **During a session** — three off-by-default toggles: keep the screen on, a sound when a timed rest
  ends, and a rest-is-up notification.
- **Experimental** — experimental metrics (nightly vagal reserve, thermal stability, nocturnal
  respiration, post-session recovery) and **Download the exercise library** — the **one** opt-in
  exception to Cénit's zero-network rule (off by default; downloads exercise animations from a CDN,
  exposing your IP to that service; with a "Delete downloaded media" button).
- **More** — **About & support** (→ Support).

---

## Data Sources

**More › Ajustes › Data & sources · the import hub. Everything stays on your device.**

`DataSourcesView.swift` — bring your history in once, then it's yours. It is **Apple Health only**;
there is no WHOOP CSV import and no live-Bluetooth "strap" section (both retired). Sections:

- **Import** — **Apple Health Export**: import an `export.zip` (from *Health app → profile → Export
  All Health Data*). Cénit streams and aggregates years of HR, HRV, sleep, SpO₂, steps and body
  composition **locally**, showing record counts and a summary.
- **Apple Health** (live sync) — connect and keep a **two-way sync**: per-stage progress, a coverage
  summary (days + span), a per-metric "what landed" list, and write-back permissions. Two opt-in
  toggles (off by default): **Save workouts to Apple Health** (your strength sessions as workouts +
  an estimated active-energy ring) and **Record on Apple Watch** (only if a watch is paired — real
  HR/calories on the watch).
- **Coverage** — a diagnostic 30-day grid with a legend: **On-device**, **Apple Health only**, **No
  data**, plus a per-source day-count rollup.
- **Backup** — **Export / Import** a single backup file (Import replaces device data and relaunches),
  and an optional **Automatic iCloud backup** to a folder you choose (Back up now / Restore / Turn
  off).

All imports run on-device; nothing is uploaded.

---

## Illness early-warning

Cénit watches for the classic early-illness/strain signature on-device (`IllnessSignalEngine`). It
compares your last ~2 days against a ~28-night baseline (ending 3 days ago) across **resting HR,
HRV, skin-temperature deviation and respiration** — all within-source Apple Health z-scores — behind
a **≥2-signal corroboration gate**, with explicit suppression of confounders (alcohol, hard/late
training, sauna, already-ill, read from your journal). When it raises, a banner appears on **Hoy**:
*"Your body looks strained: … Consider taking it easy,"* naming the concrete signals.

On a clear→raised transition, Cénit also posts a **system notification** (at most once per local
day). The toggle lives in **Ajustes → Salud** and is **opt-in** (off by default — enabling it asks
notification permission). Needs at least 14 nights of baseline. On-device and approximate —
informational only, **not** a diagnosis.

---

## First-run onboarding

The onboarding wizard (`OnboardingWizard.swift`, with `OnboardingActo*.swift` siblings) appears
on first launch and runs once (tracked by the `noop.onboarded` preference, an `@AppStorage` flag).
It is **not** a form wizard and there is no band to pair: it's a single scene that transforms
**seven times over one continuous particle field**, built entirely on **Apple Health** — no
Bluetooth, no strap, no radar. The canvas fills with *your* evidence (density comes from how much
real history landed, never from how long you wait), and color arrives once, as a revelation, when
your verdict tints the field. There is **no global progress indicator, no generic Skip, and no
cross-launch resume** — most acts carry a **Back** control, but the reveal does not, and quitting
before you finish restarts at act 1.

- **Act 1 · Promesa** — the pitch: "all your data, none of the cloud", with a one-line privacy
  promise you can check on the spot (turn on airplane mode). One button: **Empezar**.
- **Act 2 · Permiso** — the single gate of the whole app, and it *is* the weight diagram. It
  requests Apple Health access and, in the same breath, shows how the engine weighs your six
  signals: three votes — the **autonomic axis** (resting HR + night HRV), **sleep**, and the
  **sentinel** (skin temperature + respiration, which counts only when *both* drift the same day)
  — plus one signal that does **not** vote (daytime HRV, shown without color). A pinned **Conectar**
  button, an **Ahora no** off-ramp, and a note that a partial grant is indistinguishable from a
  denied one (HealthKit never reveals read permission).
- **Acts 3–4 · Conexión → Lectura** — one screen that transforms with no cut. First it **reads
  your last 180 days** of Apple Health: a rolling day counter, the current stage named and tinted
  (15 stages), a **2.5 s floor** (reading 180 days can't look like a blink) and a **20 s ceiling**
  (after which a real "enter anyway" exit appears); a failed sync offers **Reintentar**. Then the
  field converges, densifies to the evidence that actually exists, **tints with the verdict**, falls
  silent, and the **verdict word** fades in — borrowed from the same builder that says it on **Hoy**,
  so the two screens can never disagree. The landing has four branches (`OnboardingLanding.swift`,
  decided by what *landed* in the local database, never by the permission):
  - **lectura** — there's a word, with a confidence line ("8 of 14 nights") and a history line; an
    ⓘ points to the Acta.
  - **calibrando** — resting HR arrived but the baseline is young: no word, an honest count
    ("night N of 4").
  - **sinRitmoEnReposo** — signals arrived but *zero* resting HR: the hard ceiling. Without it
    there is no verdict, ever, so the flow doesn't promise one — it offers what works without a
    watch and a door back to Apple Health.
  - **sinDatos** — not a single row (denied read or empty Health, indistinguishable): open Health,
    retry, or enter anyway.
- **Act 5 · Acta** — what the word is made of. The field decomposes into three wells, one per axis,
  as you watch. It states plainly there is **no 0–100 score**, lists the four verdict words with
  their glosses and the three votes, and — inside the axis that leads — shows the actual weights
  (resting HR **1.0**, the spine; night HRV **0.5**, its companion), what doesn't weigh (daytime
  HRV, steps), and what it compares you against.
- **Act 6 · Perfil** — the four data points the engine needs from *you*: **age, sex, weight,
  height**, auto-filled from Apple Health where possible, each field showing its provenance ("From
  Apple Health" / "You set this" / "I set this"). Age alone drives your HR zones (Tanaka,
  208 − 0.7·age); sex, weight and height tune workout burn. The derived **max HR** updates live as
  you edit, and anything you change wins over the autofill. This is the **last common stop of every
  branch** — you pass through it whichever way you arrived.
- **Act 7 · Ciclo** — the close: "and with that, what?" The field circulates between the two
  centers the tab dock shows. It translates each verdict word into what it means for the day,
  renders the **real** tab dock (not a drawing), and — only where a reading can actually exist —
  offers the optional morning-reading notice. No confetti: tomorrow's word might be "take it easy".

**Salida ("Ahora no")** — the off-ramp from Permiso. Not a dead end: it names what you lose, what
still works, and leaves both doors open (reconsider and grant, or enter anyway). It never reappears
on its own.

You can edit your **Profile** any time from **Ajustes**.

---

## App-level gates & notices

Around the four tabs, a few whole-app surfaces:

- **Terms gate** (`TermsGateView.swift`, `Terms.swift`) — a clickwrap over *everything* (before
  onboarding), re-shown if the terms materially change (`currentVersion` "2.0"). The four points you
  accept: Cénit reads from Apple Health on your device (**no separate hardware pairing required**);
  it's offline and local (no account, server or telemetry); it's general wellness, not a medical
  device; and there's no warranty.
- **What's New** (`WhatsNewView.swift`) — the in-app changelog, shown automatically after an update
  and reachable from Ajustes: a "What to expect" section, then each release.
- **Restore offer** (`ContentView.swift`, FER-116) — shortly after onboarding, *only* if Apple
  Health is authorized but no data landed, Cénit offers to restore from a **backup file you exported
  yourself** (it has no cloud of its own). "Choose a backup file…" / "Not now".
- **Store failure** (`StoreFailureView.swift`) — if the local database can't open (a wedged
  migration or a corrupt file), an honest full-screen paper state with **Retry** and **Restore from
  backup…**, never an eternally empty dashboard.

---

## Support

**More › Ajustes › About & support · Cénit is free.**

`SupportView.swift` — thinned to essentials: Cénit's identity and version, a short mission ("A health
app built on Apple Health. Everything stays on this device… an independent, experimental project"),
and a single footer disclaimer: **"Not a medical device."**

---

## Privacy & data ownership

- **Offline by design.** Cénit reads the samples your **Apple Watch** and iPhone already save to
  **Apple Health**, on your device. No account, no sync, no cloud, no telemetry, no server — and no
  wearable to pair.
- **On-device storage.** All history (imported and computed) is stored locally in SQLite via GRDB.
- **Your data is yours.** Imports happen once and stay on your device; backups are files *you*
  export (with an optional iCloud folder *you* choose). Nothing is uploaded.
- **One opt-in network exception.** Downloading the exercise-animation library (Ajustes →
  Experimental) is off by default; enabling it fetches media from a CDN and exposes your IP to that
  service. Every other part of Cénit makes zero network calls.
