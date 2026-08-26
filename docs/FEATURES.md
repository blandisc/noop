# Cénit — Feature Guide

Cénit is a standalone, fully **offline** health app on **Apple Health** — **no account, no
cloud** — stores everything on-device in SQLite, imports your Apple Health (and optional historical
WHOOP CSV) exports, and computes recovery, strain, HRV and sleep locally. Direct WHOOP band
pairing was retired (FER-1003). Cénit is the iOS app (`Cenit`); its UI and data layer live under
`Cenit/`, on top of the cross-platform Swift packages.

> **Not affiliated with WHOOP.** Cénit is independent software for *your own* data. Historical
> "WHOOP" references name hardware the app once interoperated with, or import formats it can still
> read. **Cénit is not a medical device** — every metric (HR, HRV, recovery, strain, sleep, SpO₂,
> respiration, skin temperature) is an approximation, not a clinical reading, and must not be
> used to diagnose, treat or make health decisions.

Cénit is built on community reverse-engineering work, with thanks to:

| Project | Contribution |
| --- | --- |
| [`johnmiddleton12/my-whoop`](https://github.com/johnmiddleton12/my-whoop) | WHOOP 4.0 BLE protocol — framing, commands, decoding |
| [`b-nnett/goose`](https://github.com/b-nnett/goose) | WHOOP 5.0 / MG BLE protocol |
| [`groue/GRDB.swift`](https://github.com/groue/GRDB.swift) | On-device SQLite persistence |

---

## At a glance

Cénit is a **tab bar** app. Five tabs sit along the bottom — **Today**, **Trends**, **Live**
and **Sleep**, plus a **More** tab that opens a grouped list of every remaining screen
(*Insights*, *Body*, *Data*, *App*). The live connection state and battery % (bonded /
connecting / disconnected) surface inside the **Today** and **Live** screens, not in a global
chrome. The whole UI is dark, and a first-run wizard walks you through pairing.

Screens are grouped below by whether they need a connected strap:

| Needs a connected strap (live BLE) | Works from imported data alone |
| --- | --- |
| Live, Breathe (for haptics), Intervals (for haptics), Health Monitor (live HR), Automations (to act) | Control Center, Explore, Compare, Insights, Sleep, Trends, Workouts, Stress, Apple Health, Data Sources |

Most of Cénit works the moment you import an export. The strap adds the *live* layer — real-time
heart rate, haptic cues, and physical-input automations.

---

## Connection states

Throughout the app the strap reports one of three states:

- **Disconnected** — no strap found (critical / red dot).
- **Connecting** — found and connecting, finishing the secure pairing handshake (warning / amber).
- **Bonded** — paired and streaming; haptics and live HR are available (positive / green).

> WHOOP straps do **not** appear in *Settings → Bluetooth*. They advertise on a custom
> profile that only apps like Cénit can find — so there's nothing to pair in iOS Settings.

Commands that drive the strap motor (any wrist buzz) and the live realtime stream require a
**bonded** connection. Where a feature needs this, it is noted below and the button is disabled
until you bond.

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
  silent, and the **verdict word** fades in — borrowed from the same builder that says it on
  **Control Center**, so the two screens can never disagree. The landing has four branches
  (`OnboardingLanding.swift`, decided by what *landed* in the local database, never by the
  permission):
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

You can edit your **Profile** any time from **Settings**.

---

## Control Center

**Tab: Today · works from imported data; live connection status shows on this screen.**

The home dashboard (`TodayView.swift`, titled "Control Center"). A tight, gapless grid:

- **Health alert banner** — the illness early-warning banner appears here when triggered (see
  [Illness early-warning](#illness-early-warning)).
- **Today's Synthesis** — the signature **Recovery Ring** (HRV and resting HR underneath) beside
  a plain-English read-out ("Recovery is strong and sleep was consistent.") and a recovery state
  word (Depleted / Low / Steady / Primed / Peak).
- **Key Metrics** — a uniform tile grid, each with a 14-day sparkline: Recovery, Day Strain
  (of 21), Sleep (hours + efficiency), HRV, Resting HR, Blood Oxygen, Respiratory, Steps,
  Weight, Calories. WHOOP metrics come from the `strap` source; Steps/Weight/Calories/
  Respiratory pull from `apple-health`. Sparse series (e.g. weight) fall back to all history so
  a tile never shows empty when data exists.
- **Last Workouts** — up to six recent sessions as tiles (duration, date, avg HR, kcal).
- **Data Sources** — a footer showing whether WHOOP and Apple Health data are present, with day/
  session counts.

---

## Live

**Tab: Live · needs a bonded strap for HR; the hardware-test surface.**

`LiveView.swift` is the real-time heart-rate screen and the pairing/diagnostics surface:

- A large **smoothed heart rate** (BPM) — Cénit shows a spike-filtered median over a ~10 s
  window, not the raw per-beat value, so it's stable. Recent **R-R intervals** (ms) are listed
  beneath.
- **Status grid** — battery %, last decoded frame type, last decoded event.
- **Controls**:
  - **Scan & Connect / Re-scan** — start or restart BLE scanning.
  - **Buzz strap** — fire a test haptic buzz (requires a **bonded** connection).
  - **Disconnect** — drop the connection.
- A scrolling **BLE log** of frames, events and actions — useful for confirming the strap is
  streaming.

Opening Live starts the realtime HR stream and requests a fresh battery reading; leaving it
stops the realtime stream (the lightweight standard HR keeps recording).

---

## Breathe

**More › Body: Breathe · works visually without a strap; needs a bonded strap for haptic cues.**

`BreathingView.swift` — an **HRV haptic breathing biofeedback** trainer, and Cénit's flagship
novel feature. Because the strap both *measures* HRV (from R-R intervals) and *buzzes*, Cénit can
pace your breath with a felt cue and watch your HRV respond in real time.

- **Pick a pace**: Relax 4-6 (4 s inhale / 6 s exhale), Coherence 5.5 (equal ~5.5 breaths/min),
  or Box 4-4.
- **Start a session** — a soft orb expands on the inhale and contracts on the exhale, with your
  live BPM in its centre. With a strap bonded you feel **one pulse on the inhale, two on the
  exhale**, so you can breathe with your eyes closed. Without a strap it's visual-only ("Visual
  only" pill).
- **Live readouts**: heart rate, a rolling **HRV (RMSSD)** over the last ~30 beats, and the
  current pace.
- **Coherence estimate** — a normalized bar (RMSSD mapped 0–120 ms) with a band word (Building /
  Settling / Coherent / Deep calm). This is an estimate, not a clinical reading — trends across a
  session matter more than any single number.

A "Test buzz" button fires a single pulse (bonded only).

---

## Intervals

**More › Body: Intervals · works visually without a strap; needs a bonded strap for haptic cues.**

`IntervalTimerView.swift` — a **silent haptic HIIT interval timer**. Train hands-free: the strap
buzzes every transition so you never look at the screen.

- **Configure** Work seconds (5–600), Rest seconds (5–600) and Rounds (1–30).
- A big glanceable **stage face**: WORK / REST / DONE, the current round, a countdown ring, and a
  total-session progress bar (elapsed / planned).
- **Haptic cues** (bonded strap): a strong triple-buzz into each WORK block, a short single buzz
  into REST, a 3-2-1 tick on the last seconds of each phase, and a long 5-loop buzz when the
  session finishes.
- **Start / Pause / Restart** and **Reset**.

With no strap bonded it still works as a large visual timer (without haptics), prompting you to
bond on the Live screen.

---

## Explore (Metric Explorer)

**More › Insights: Explore · works from imported data.**

`MetricExplorerView.swift` — a catalog of every signal, one tap deep. The root is a grouped list
(by `MetricCatalog` category); a faint trailing dot marks metrics with no recorded data. Tapping a
metric opens its **detail dossier**:

- A **W / M / 3M / 6M / 1Y / ALL** range control.
- A hero **trend chart** with the latest value and "as of *date*".
- A uniform stat row: **Average, Min, Max, Latest, and Δ vs the previous equal-length window**
  (tinted by whether the change is the "good" direction for that metric).
- **What correlates** — a cross-catalog Pearson scan over the visible window (|r| ≥ 0.30,
  n ≥ 10), top 6, each with an r-bar.

Sparse metrics (weight, body fat) auto-widen the window when the selected range holds no points,
and flag that they did, so you always see real data instead of an empty state.

---

## Compare

**More › Insights: Compare · works from imported data.**

`CompareView.swift` — overlay **2–4 metrics** from the catalog and read how they move together:

- Pick metrics from a grouped menu; selected metrics show as removable colored chips.
- A **W / M / 3M / 6M / 1Y / ALL** range control.
- A **normalized overlay chart** — each line min–max scaled to 0–1 within the window so different
  units share an axis. Hovering shows a crosshair and a tooltip with every series' **real** value
  on the nearest day; the legend lists each series' true min–max range.
- **How They Move Together** — every selected pair gets a live **Pearson r** with a plain-English
  conclusion ("When weight rises, recovery tends to fall — a moderate negative link.").

Sparse series auto-widen so they still overlay against dense ones.

---

## Insights

**More › Insights: Insights · works from imported data (needs WHOOP journal answers for behaviour effects).**

`InsightsView.swift` — "interrogate what affects what", in two halves:

1. **Behaviour Effects** — splits your logged WHOOP **journal** answers (Alcohol, Caffeine, Late
   meal, Meditation…) into days each behaviour *was* vs *was not* logged, then compares a chosen
   outcome (Recovery / HRV / Sleep / RHR) between the two groups. Each effect card shows a
   plain-English sentence, the with/without means and group counts, a **SIGNIFICANT / EXPLORATORY**
   pill, and an effect size (**Cohen's d**) with a magnitude word. Tint is sign-aware: a behaviour
   that moves the outcome the "good" way reads positive/green, the "bad" way reads red. Without
   journal data, Cénit explains how to start logging.
2. **Metric Relationships** — a curated set of **Pearson** correlations: Sleep performance ↔
   Recovery, HRV ↔ Recovery, Resting HR ↔ Recovery, and Recovery → next-day recovery (1-day lag).
   Each is a one-line insight with r, a significance pill, an r-bar, and a strength/direction reading.

---

## Sleep

**Tab: Sleep · works from imported WHOOP data.**

`SleepView.swift` — last night, read in two seconds:

- **Stage breakdown hero** — a **hypnogram** (reconstructed from stage durations) or, if intervals
  can't be reconstructed, a proportional stacked stage bar. Footer shows REM / Deep / Light / Awake
  each as "Xh Ym · NN%", with time-in-bed, efficiency, and onset–wake times.
- **Night detail** — a uniform tile grid, each with a sparkline and a "vs typical" caption: Sleep
  Performance, Efficiency, Consistency, Hours vs Needed, Restorative (deep + REM share),
  Respiratory, and Sleep Debt (vs your personal sleep need, floored at 7.5 h).
- **Stages vs typical** — Deep / REM / Light as horizontal bars, last-night minutes with a marker
  at your personal mean, so highs and lows pop.
- **Asleep duration** — a trailing-30-night hours trend with avg / min / max.

If no sleep sessions are imported, Cénit points you to Data Sources.

---

## Trends

**Tab: Trends · works from imported WHOOP data.**

`TrendsView.swift` — the longitudinal view ("the thread of you over time"):

- A **W / M / 3M / 6M / 1Y / ALL** range control (default 3M).
- A hero **Recovery** chart with avg / peak / low / day-count.
- **Daily signals** — small multiples for **HRV**, **Resting HR** and **Day Strain**, each with
  mean / min / max.
- A **recovery year heat-strip** — a calendar of recovery scores across the past year (or all
  history on ALL), with a depleted→peaked legend.

Windows are taken relative to your latest recorded day and auto-widen on sparse data.

---

## Workouts

**More › Body: Workouts · works from imported WHOOP and Apple Health data.**

`WorkoutsView.swift` — the activity log, threaded together:

- A **7D / 30D / 90D / 1Y / All** range control (auto-picks the tightest range with ≥2 sessions).
- **Summary tiles** — Total Workouts, Total Time, Total Calories, Total Distance, Most Active sport.
- **Activity Breakdown** — per-sport cards (sessions, time, kcal, avg per session), sport-specific
  icons.
- **All Sessions** — a uniform table: date/time, sport, duration, avg HR, kcal, distance, and a
  **source badge** (WHOOP or Apple) per row.

---

## Health Monitor

**More › Body: Health · live HR needs a bonded strap; vitals come from imported WHOOP data.**

`HealthView.swift` — live vitals:

- **Live heart rate hero** — a streaming HR sparkline tinted by zone, with a zone pill, "% Max",
  your Max HR (from Settings) and a streaming/idle state. When the strap reports HR as 0, Cénit
  derives it from the latest R-R interval and notes "from R-R".
- **Vital Signs** — a tile grid from your most recent imported day: Respiratory Rate, Blood O₂,
  Resting HR, HRV and Skin Temp, each colored by whether it sits in a healthy range ("In range" /
  "Out of range").

With no live HR and no imported day, Cénit prompts you to connect or import.

---

## Stress

**More › Body: Stress · works from imported WHOOP data.**

`StressView.swift` — a clear, single-number **Stress Monitor** (0–3) with a LOW / MEDIUM / HIGH
band and one plain-English line on *why*:

- Today's value is your **recorded daily stress score** if one exists; otherwise Cénit **derives**
  it transparently — comparing today's resting HR and HRV to your own 30-day baseline (higher RHR
  and lower HRV both push stress up), combining two z-scores and squashing onto 0–3 with a logistic
  curve (0 calm · 1.5 baseline · 3 high).
- A semicircular **gauge** (its own blue → mint → amber ramp, deliberately not the recovery traffic
  light), the band, and an explanation tuned to your RHR/HRV shifts.
- **Today's markers** — the stress value (with sparkline), Resting HR and HRV vs baseline (tinted
  toward stress or recovery), and "Calm time" (share of recent days in the LOW band).
- A multi-range **trend** chart.
- A **"How this is computed"** card laying out the exact method and band legend.

---

## Apple Health

**More › Data: Apple Health · works from imported Apple Health data.**

`AppleHealthView.swift` — the per-source page for everything imported from the `apple-health`
source, read locally on your device:

- A **W / M / 3M / 6M / 1Y / ALL** range control.
- **Tiles**: Steps, Resting HR, HRV, VO₂ Max, Weight, Body Fat, Lean Mass, Asleep avg, Workouts.
- **Chart sections** — Heart & Vitals (resting HR, HRV, blood oxygen, respiratory rate), Activity
  & Energy (steps, active energy), Body Composition (weight, body fat, lean mass, BMI), and Sleep
  (asleep). Each chart has an avg / min / max / point-count footer.

Sparse weekly series (weight, body fat) auto-widen to all history so a short window is never empty;
a single reading is shown as a "Latest reading" value rather than an empty chart.

---

## Data Sources

**More › Data: Data Sources · the import hub. Everything stays on your device.**

`DataSourcesView.swift` — bring your history in once, then it's yours:

### WHOOP Export (CSV)
Import your full WHOOP history — recovery, strain, sleep, workouts — from a WHOOP data export
(`.zip` or unzipped folder). Works for WHOOP 4.0, 5.0 and MG. Get one from
*app.whoop.com → Data Management*. Cénit reports the records imported and the date span, and shows
how many days and sleeps are stored.

### Apple Health
Import an Apple Health export (`export.zip`) from *Health app → profile → Export All Health Data*.
Cénit **streams and aggregates** it locally — years of HR, HRV, sleep, SpO₂, steps, body
composition and more. Large exports take a minute or two.

### WHOOP Strap (Live BLE)
Shows whether the strap is bonded and streaming. Pairs directly over Bluetooth — no WHOOP app,
no cloud. Open **Live** to pair if it isn't connected.

All imports run on-device; nothing is uploaded. WHOOP data is stored under the `strap` source
and Apple Health under `apple-health`, so per-source pages and cross-source consensus stay distinct.

---

## Automations

**More › App: Automations · needs a bonded strap to act/buzz; settings save without one.**

`AutomationsView.swift` — turn the strap's physical inputs and live biometrics into on-device
strap actions and haptic coaching.

### Double-tap → action
Double-tap the strap to trigger an action. Pick one of:

| Action | What it does |
| --- | --- |
| Nothing | No action |
| Buzz back (confirm) | Fires a confirming wrist buzz |
| Mark a moment | Records a timestamped "moment" (with a confirming buzz) |

A **Test action** button runs it without the strap. Recent moments are listed and can be cleared.

### Haptic coaching
- **HR-zone coaching** — buzz when you hit your top zone (ease off) and again when you recover,
  using your max HR from Settings.
- **Resting stress nudge (experimental)** — a gentle buzz when your HRV drops while your heart
  rate is calm — a cue to take a paced breath. Conservative, rate-limited to **once every
  15 minutes**, off by default.

### Smart alarm
Wake to a wrist buzz. This arms the strap's **own firmware alarm**, so it still fires even if Cénit
is closed. Set your wake time — the strap buzzes at exactly that time. Cénit does not currently do
light-sleep early wake.

---

## Illness early-warning

Cénit watches for the classic early-illness/strain signature on-device. It compares your last ~2
days against a ~28-day baseline (ending 3 days ago) for resting HR, HRV, skin-temperature
deviation and respiration. When **two or more** anomalies appear — e.g. resting HR up ≥5 bpm,
HRV down ≥20%, skin temp up ≥0.6 °C, respiration up — a banner appears on **Control Center**:
*"Your body looks strained — … Consider taking it easy."*

On a banner transition from clear to raised, Cénit also posts a **system notification** (at most
once per local day) so the warning reaches you when the window is closed. The toggle lives in
**Automations → Illness early-warning** and is **opt-in** (off by default — enabling it triggers
the notification-permission prompt). Needs at least 14 days
of history. On-device and approximate — informational only, **not** a diagnosis.

---

## Settings

**More › App: Settings · always available.**

`SettingsView.swift`:

- **Profile** — age, sex, weight, height, and max heart rate (auto-estimated via Tanaka, or a
  manual override). These power your zones, calorie estimates and recovery baselines.
- **Strap** — connection status, battery, and Re-scan / Disconnect controls.
- **About** — version, the "all your data, none of the cloud" note, a **medical disclaimer**, and
  attribution to the community protocols Cénit is built on.

---

## Support

**More › App: Support · always available. Cénit is free and always will be.**

`SupportView.swift`:

- **Built on** — credit to the community reverse-engineering projects Cénit stands on.
- **Donate (optional)** — never a paywall; the whole app works without it. Copy-to-clipboard
  crypto addresses (Bitcoin, Cardano, Ethereum, XRP) for anyone who wants to chip in toward
  future work (Windows, the iOS port, new features). The app never asks again.
- A reminder: **not affiliated with WHOOP; interoperability software for your own device and
  data; not a medical device.**

---

## Privacy & data ownership

- **Offline by design.** Cénit talks to your strap directly over Bluetooth Low Energy — there is
  no server in the middle. No account, no sync, no cloud.
- **On-device storage.** All history (imported and live-captured) is stored locally in SQLite
  via GRDB.
- **Your data is yours.** Imports happen once and stay on your device; nothing is uploaded.
