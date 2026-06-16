# Strand / NOOP — Design System

> **Dark-only, instrument-grade.** Every screen reads like a precision instrument:
> calm dark-green-black surfaces, tabular numerics that never reflow, physiological
> motion (breathe / pulse / flow — no cartoon bounce), and a locked component set
> that guarantees a uniform look.

> **Two languages, one package.** The system above is the **legacy** one — dark, and
> what every *shipped* screen still uses. A second language, **«Instrumento diurno»**
> (light, warm paper, one dominant number) is being built for the redesign and lives
> *alongside* it, not replacing it — see [§8](#8-instrumento-diurno--the-daytime-language-fer-131).

- **Source of truth:** the `StrandDesign` Swift package — `Packages/StrandDesign/Sources/StrandDesign/`
- **Package version:** `0.1.0` (`StrandDesign.version`)
- **Token entry points:** `StrandPalette` (color), `StrandFont` (type), `StrandMotion` (motion), `NoopMetrics` (spacing/sizing)
- **Machine-readable tokens:** [`tokens/design-tokens.json`](tokens/design-tokens.json) (W3C Design Tokens format)
- **Assets:** [`assets/`](assets/) — app icons + brand marks

> ⚠️ This document is **generated from code**. The Swift package is canonical — if a
> value here disagrees with `Palette.swift` / `Typography.swift` / `Motion.swift` /
> `Components.swift`, the code wins. Hex values are exact per design spec §9.1; do not substitute.

---

## 1. Foundations

### 1.1 Color — surfaces

Dark green-black stack. Layer surfaces from `base` (the canvas) up to `overlay` (sheets/popovers).

| Token | Hex | Use |
|---|---|---|
| `surface.base` | `#060A08` | App background — near-black, faint green |
| `surface.raised` | `#0D1512` | Cards |
| `surface.overlay` | `#121D18` | Popovers / sheets |
| `surface.inset` | `#0A100D` | Wells / chart insets |
| `hairline` | `#1B2620` | 1px border (default) |
| `hairlineStrong` | `#27362E` | 1px border on hover / emphasis |
| `glow.ambient` | `#1B2A3A` | Soft ambient glow behind hero elements |

### 1.2 Color — text

| Token | Hex | Use |
|---|---|---|
| `text.primary` | `#F4F7F5` | Values, titles |
| `text.secondary` | `#8B9690` | Supporting copy, labels |
| `text.tertiary` | `#6F7A74` | Overlines, captions, axis |

`opacity.disabled = 0.45` — shared dim value for disabled sections (don't invent your own).

### 1.3 Color — accent (chrome, **not** data)

The accent is for UI chrome (selection, focus, links), **never** to encode a metric — data is colored by the recovery/strain/zone scales below.

| Token | Hex |
|---|---|
| `accent` | `#18C98B` (health green) |
| `accent.hover` | `#2FE0A0` |
| `accent.muted` | `#10271F` (selected-row tint) |
| `focusRing` | `#18C98B` |

### 1.4 Color — status

Status colors are reserved and **never reused as recovery colors**.

| Token | Hex |
|---|---|
| `status.positive` | `#18C98B` |
| `status.warning` | `#F5A623` |
| `status.critical` | `#FF4F73` |

### 1.5 Color — per-metric accents

For Apple-Health-style bars and metric tiles.

| Token | Hex | Use |
|---|---|---|
| `metric.cyan` | `#2FC7FF` | Apple Health bars |
| `metric.purple` | `#A879FF` | HRV / strain-style data |
| `metric.amber` | `#F5A623` | Calories / moderate |
| `metric.rose` | `#FF4F73` | Risk / high strain / low recovery |

### 1.6 Data scales — gradients

**Recovery** — a traffic-light scale (low red → high green). Sample any score `0…100`
with `StrandPalette.recoveryColor(score)`.

| Stop | Position | Hex | State word |
|---|---|---|---|
| `recovery.s000` | 0.00 | `#FF4F73` | DEPLETED (`<25`) |
| `recovery.s030` | 0.30 | `#F5A623` | LOW (`<50`) |
| `recovery.s055` | 0.55 | `#E8C24B` | MODERATE (`<70`) |
| `recovery.s078` | 0.78 | `#18C98B` | PRIMED (`<88`) |
| `recovery.s100` | 1.00 | `#2FE6A8` | PEAK (`≥88`) |

> State words come from `StrandPalette.recoveryState(score)` and are localized against
> the host app's string catalog (`Bundle.main`) — the package ships no strings of its own.

**Strain** — ember → magenta (output / heat). Sample any value on the `0…21` WHOOP
scale with `StrandPalette.strainColor(strain)`.

| Stop | Position | Hex |
|---|---|---|
| `strain.s000` | 0.00 | `#E8B04B` (ember / warm gold) |
| `strain.s033` | 0.33 | `#E8743B` (orange) |
| `strain.s066` | 0.66 | `#E0476B` (rose-red) |
| `strain.s100` | 1.00 | `#C13AC1` (magenta) |

### 1.7 Sleep stages & HR zones

**Sleep** (`StrandPalette.sleepStageColor(stage)`):

| Stage | Hex |
|---|---|
| Awake | `#E0476B` (rose) |
| Light | `#5C6FB1` (periwinkle) |
| Deep | `#2C3A7A` (deep indigo) |
| REM | `#5BE0C7` (mint, glows) |

**HR zones** (`StrandPalette.hrZoneColor(1…5)`):

| Zone | Hex |
|---|---|
| Z1 | `#4FA9C9` |
| Z2 | `#5BD3A0` |
| Z3 | `#E8C24B` |
| Z4 | `#E8743B` |
| Z5 | `#E0476B` |

---

## 2. Typography (`StrandFont`)

SF Pro — **Display ≥ 20pt, Text < 20pt**. Every numeric style uses **tabular /
monospaced digits** so live values don't reflow. SF Mono for raw/log views.

| Style | Size | Weight | Notes |
|---|---|---|---|
| `display(_:)` | 64–80 (default 72) | Semibold | Recovery ring number. Tabular digits. |
| `title1` | 28 | Bold | |
| `title2` | 22 | Semibold | Section titles |
| `headline` | 17 | Semibold | |
| `body` | 15 | Regular | |
| `subhead` | 13 | Regular | |
| `caption` | 12 | Regular | |
| `footnote` | 11 | Regular | |
| `overline` | 11 | Semibold | ALL-CAPS, **+0.8 tracking** |
| `mono` | 13 | Regular | SF Mono — raw / log |
| `bodyNumber` | 15 | Regular | Tabular digits |
| `captionNumber` | 12 | Medium | Tabular digits (sparklines, chips) |

Helpers:
- `StrandFont.number(size, weight:)` — arbitrary tabular-digit numeric.
- `StrandFont.mono(size, weight:)` — arbitrary mono.
- `Text(...).strandOverline()` — applies overline style (ALL-CAPS, semibold, +0.8 tracking, secondary text).

---

## 3. Spacing & sizing (`NoopMetrics`)

The **one** spacing scale. Every screen composes from these — fixed dimensions are
what guarantee the uniform, instrument-grade look. Do not invent ad-hoc values.

| Token | Value | Use |
|---|---|---|
| `cardRadius` | 16 | Card corner radius (`.continuous`) |
| `cardPadding` | 16 | Default card padding |
| `gap` | 12 | Gap between cards |
| `sectionGap` | 28 | Gap between sections |
| `screenPadding` | 24 | Screen edge padding |
| `tileHeight` | 104 | **Every** metric tile is this tall |
| `chartHeight` | 220 | Default chart body height |

---

## 4. Motion (`StrandMotion`)

Physiological motion — **breathe / pulse / flow, no cartoon bounce.**

**Spring presets:**

| Preset | Params | Use |
|---|---|---|
| `interactive` | response 0.28, damping 0.82, blend 0.1 | Direct manipulation — hover, press, sidebar slide |
| `gentle` | response 0.5, damping 0.8 | House style for value changes — ring draw-in, gauges |
| `hero` | response 0.85, damping 0.85 | Hero transitions — first ring materialize |

**Durations:** `fast` 0.18s · `standard` 0.30s · `slow` 0.9s · `breathPeriod` 3.2s

**Curves:**
- `drawIn` — `easeOut(0.9s)` for ring/gauge draw-in on value change.
- `breathe` — `easeInOut(3.2s).repeatForever(autoreverses:)` for ambient glow/pulse.
- `pulse` — `easeOut(0.6s)` single heartbeat ripple.
- `fade` — `easeInOut(0.30s)`.

---

## 5. Components

> Every screen composes **only** these. Fixed dimensions + one spacing scale guarantee
> the uniform look. Don't invent ad-hoc cards.

### 5.1 Surfaces & layout

| Component | Purpose | Key API |
|---|---|---|
| `NoopCard` / `StrandCard` | The one card surface — `surface.raised` fill, `cardRadius`, hairline border, hover lift (shadow + border → `hairlineStrong`) | `padding:`, `cornerRadius:`, `@ViewBuilder content` |
| `StrandCardHover` | Hover-lift `ViewModifier` (shadow-md + translateY(-1px) + border emphasis) for any card-like surface | `cornerRadius:` |
| `SectionHeader` | Section title with optional overline + trailing text | `(_ title, overline:, trailing:)` |

### 5.2 Metric & content cards

| Component | Purpose | Key API |
|---|---|---|
| `StatTile` | Uniform fixed-height (104pt) metric tile: overline label, big tabular value, optional sparkline, caption + delta | `label:`, `value:`, `caption:`, `accent:`, `delta:`, `deltaColor:`, `sparkline:`, `sparkColor:` |
| `ChartCard` | Uniform chart container: header (overline + subtitle + trailing) → fixed chart body → optional divided footer | `title:`, `subtitle:`, `trailing:`, `height:`, `@ViewBuilder chart`, `@ViewBuilder footer` |
| `ChartFooter` | Row of small "LABEL / value" stats for `ChartCard` | `[(LocalizedStringKey, String)]` |
| `InsightCard` | Category overline + large colored status word + supporting detail | `category:`, `status:`, `detail:`, `statusColor:` |

### 5.3 Controls & chrome

| Component | Purpose | Key API |
|---|---|---|
| `SegmentedPillControl` | The **one** segmented pill control (range pickers everywhere) — accent capsule on selection | `(_ items, selection:, label:)` |
| `SourceBadge` | Tiny uppercase tinted capsule badge (data source) | `(_ text, tint:)` |
| `StatePill` | Status pill: tone color + optional dot + optional breathing pulse | `(_ title, tone:, showsDot:, pulsing:)` |
| `ConnectionDot` | Tiny status dot with optional breathing halo (connection / live state) | `tone:`, `pulsing:`, `size:` |

`StrandTone`: `neutral` (text.secondary) · `accent` · `positive` · `warning` · `critical`.

### 5.4 Signature visualizations

| Component | Purpose | Key API / notes |
|---|---|---|
| `RecoveryRing` | **THE** signature component. 240° open gauge (gap at bottom, 150°→390°), thick rounded stroke filled to `score/100`, draws in with `gentle` spring, soft outer bloom scaled by score, leading bead, center read-out + state word | `score:` (0–100), `supporting:`, `diameter:` (240), `lineWidth:` (16), `showsLabel:`, `showsHover:`, `valueFormat:`. Tip color = `recoveryColor(score)` |
| `RecoveryArc` | The reusable open-gauge `Shape` powering the ring | `startAngle:`, `spanDegrees:`, `fraction:`, `lineWidth:` |
| `StrainGauge` | Strain analogue of the ring, using the strain ramp (0…21) | `strain:`, `supporting:`, `diameter:`, `lineWidth:`, `showsLabel:`, `showsHover:`, `valueFormat:` |
| `Sparkline` | Tiny inline trend line (Today / live-HR tile): optional area fill, head dot, hover read-out | `values:`, `gradient:`, `range:`, `lineWidth:`, `showsArea:`, `showsHead:`, `showsHover:`, `valueFormat:`, `indexLabel:` |
| `TrendChart` | Full trend line over `[TrendPoint]` (date, value): gradient stroke, optional area, hover crosshair + tooltip | `points:`, `gradient:`, `valueRange:`, `showsArea:`, `height:`, `showsHover:`, `valueFormat:`, `dateFormat:` |
| `Hypnogram` | Sleep-stage bands over `[SleepInterval]` (stage, start/end secs), stage axis, hover | `intervals:`, `height:`, `showsStageAxis:`, `showsHover:`, `nightStart:` |
| `YearHeatStrip` | GitHub-style year grid of `[RecoveryDay]` (date, score?), recovery-tinted cells, month labels, hover ring + tooltip | `days:`, `cellSize:`, `spacing:`, `showsMonthLabels:`, `showsHover:`, `valueFormat:` |
| `StatePill` / `ConnectionDot` | (see §5.3) | |

### 5.5 Chart hover toolkit (`ChartHover.swift`)

Reusable across every visualization so hover reads identically everywhere:

- `ChartTooltip` — dark read-out card (bold value line + secondary label/date line).
- `ChartTooltipPlacement` — positions a tooltip near an anchor, flipping/clamping to stay inside the container.
- `ChartHoverMath` — nearest-datum lookup from a hover location.
- Crosshair rule (thin vertical `hairlineStrong` line) + highlighted-point dot, shared by `TrendChart` / `Sparkline`.

---

## 6. Assets

See [`assets/`](assets/) (and its [README](assets/README.md)):

- `assets/app-icon/` — full macOS icon set (`16…512 @1x/@2x`) + iOS marketing `icon_1024.png`.
- `assets/brand/` — `logo.svg`, `banner.svg`.

---

## 7. Usage notes

- **Dark-only.** All previews force `.preferredColorScheme(.dark)`. There is no light theme.
- **Data colors come from scales, chrome comes from `accent`.** Never tint a metric with `accent`; never reuse a status color as a recovery color.
- **Numerics are tabular.** Any live value uses a `*Number` font or `StrandFont.number(...)` so digits don't shift.
- **Compose from the locked set.** New cards = `NoopCard` + the components above, not bespoke surfaces.
- **Regenerating tokens:** this doc and [`tokens/design-tokens.json`](tokens/design-tokens.json) are derived from the Swift package; re-derive them when `Palette` / `Typography` / `Motion` / `Components` change.

---

## 8. «Instrumento diurno» — the daytime language (FER-131)

The redesign language. It reads like a precision instrument printed on **warm paper**:
light mode, **one dominant number**, **color only in the datum**, hierarchy by space.
It lives **alongside** the dark system (§1–§7) — no shipped screen changes in FER-131.

> **Source of truth:** `Instrumento.swift` (theme + type) and `InstrumentoStates.swift`
> (scaffold + states) in the `StrandDesign` package. Renderable proof of every state:
> `InstrumentoSnapshotTests` (`swift test --filter InstrumentoSnapshotTests` → `/tmp/noop-fer131/`).

### 8.1 Why a `struct`, not static tokens

The roles are an **instance** (`InstrumentoTheme`), not statics like `StrandPalette`,
on purpose: the by-the-hour theme engine (**FER-132**) produces dawn/day/dusk/night
variants by interpolating these same roles. `.base` is the neutral **daytime anchor**.
Inject with `.instrumentoTheme(_:)`; read with `@Environment(\.instrumentoTheme)`. Every
screen reads it from the environment, so recoloring by the hour is free.

### 8.2 Color roles — `.base` (daytime anchor)

Warm paper surfaces, warm-gray ink, saturated hue reserved for the measured value.
Every pair clears **WCAG AA** (large-text 3:1 for the data numerals, normal 4.5:1 for ink).

| Role | Hex | On paper | Use |
|---|---|---|---|
| `paper` | `#F4F1E8` | — | App canvas — warm bone (never pure white) |
| `surface` | `#FBF9F2` | — | A *sparingly*-used raised surface; never nested |
| `hairline` / `hairlineStrong` | `#E6E0D2` / `#D8D0BD` | — | Faint warm rule / on emphasis |
| `ink` | `#221D16` | 14.8:1 | Primary text & the hero numeral |
| `inkSecondary` | `#5C5648` | 6.5:1 | Supporting copy, labels |
| `inkTertiary` | `#6F6857` | 4.9:1 | Overlines, captions, axis |
| `dataRecovery` | `#0C8F62` | 3.6:1¹ | Recovery / "good" datum |
| `dataStrain` | `#C4631F` | 3.6:1¹ | Strain / "output" datum |
| `dataSleep` | `#5D5A9E` | 5.4:1 | Sleep trend hue (per-metric chart) — FER-147 |
| `dataHrv` | `#2E7D6B` | 4.4:1 | HRV trend hue — FER-147 |
| `dataHeart` | `#B85068` | 4.2:1 | Heart-rate trend hue (HR & resting HR) — FER-147 |
| `dataSpO2` | `#3B6FA0` | 4.7:1 | Blood-oxygen trend hue — FER-147 |
| `dataSteps` | `#4C8998` | 3.5:1 | Steps trend hue — FER-147 |
| `verdict` | `#0C8F62` | 3.6:1¹ | The day's verdict accent (positive green) |
| `warning` | `#9C5E10` | 4.6:1 | Caution / "strained" |
| `critical` | `#BC3A34` | 4.9:1 | Depleted / error — contained brick red |

¹ Data accents carry color **only on a large numeral** (≥24pt), where AA-large is 3:1.
They are never used on label-size or body text.

### 8.3 Type voice (`InstrumentoType`)

Reuses SF Pro tabular digits (`StrandFont`); adds only the two opinionated moves:

- **The protagonist numeral** — `Text(...).instrumentoHero(size)` = tabular hero font +
  size-aware **negative tracking** (~-1.6pt at 72), so a big figure reads as one machined
  object, not loose digits. Color it with a *data* role; everything else stays ink.
- **A moderate overline** — `Text(...).instrumentoOverline()` = medium weight (not semibold),
  gentler `0.6` tracking, uppercased. Loud enough to label, quiet enough not to compete.

### 8.4 Hierarchy rules

Not tokens — how the tokens are allowed to combine. `/qa` checks screens against them.

1. **One dominant element.** Each screen has a single hero (usually the recovery/strain
   numeral). Nothing else matches its size/weight.
2. **Color only in the datum.** Saturated hue appears on a *measured value*, never on
   chrome, labels, decorative icons, or backgrounds.
3. **Hierarchy by space, not boxes.** Group with whitespace + hairlines. No card-in-card;
   `surface` is the exception, used sparingly and never nested.
4. **Moderate overline.** Labels are quiet (tertiary ink). They orient; they don't announce.

### 8.5 Components & states

| Component | Purpose | Key API |
|---|---|---|
| `ScreenScaffold` | The base shell — warm-paper canvas, screen padding, optional quiet header (overline + one title). Doesn't scroll; a screen wraps its own `ScrollView`. | `title:`, `overline:`, `@ViewBuilder content` |
| `LoadingStateView` | Calm loading — three ink dots that breathe (no spinner, no color), optional line. Renders cleanly in `ImageRenderer`. | `(_ message:)` |
| `EmptyStateView` | Empty — optional glyph, one title, supporting line, optional quiet action. All ink (no datum → no color). | `systemImage:`, `title:`, `message:`, `actionTitle:`, `action:` |
| `ErrorStateView` | Error — same shape; glyph carries the one allowed color (`critical`), because an error is a genuine alert. Optional retry. | `title:`, `message:`, `retryTitle:`, `retry:` |
| `QuietButton` | Sober action — ink label on a hairline-bordered surface. No color: chrome stays quiet. | `(_ title:, action:)` |

> **Data-state family is out of scope for FER-131.** "No recent data / N days unsynced",
> partial 14-day trends, and gaps in charts are *data* states (of a chart or metric, not a
> whole screen). They get their own requirement, designed with real data in front of them.
