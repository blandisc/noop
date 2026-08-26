# Strand / Cénit — Design System

> **One language: «Instrumento diurno».** Every screen reads like a precision instrument on warm
> day paper: one dominant number, **meaningful color (the value and each signal's identity)**, hierarchy by space (not boxes),
> tabular numerics that never reflow, and physiological motion (breathe / pulse / flow — no cartoon
> bounce). The canonical surface / text / role tokens live in **[§8](#8-instrumento-diurno--the-daytime-language-fer-131)**.

> **The dark legacy system was retired (FER-430).** Cénit used to ship a dark, instrument-grade
> language alongside Instrumento; it has been removed. What remains in §1 below is the shared,
> language-agnostic data (recovery / strain / sleep / HR-zone / status / metric scales) + the chrome accent.

- **Source of truth:** the `StrandDesign` Swift package — `Packages/StrandDesign/Sources/StrandDesign/`
- **Package version:** `0.1.0` (`StrandDesign.version`)
- **Token entry points:** `StrandPalette` (color), `StrandFont` (type), `StrandMotion` (motion), `CenitMetrics` (spacing/sizing), `StrandElevation` (shadow), `StrandLayer` (z-index), `StrandIcon` (icons)
- **Machine-readable tokens:** [`tokens/design-tokens.json`](tokens/design-tokens.json) (W3C Design Tokens format)
- **Assets:** [`assets/`](assets/) — app icons + brand marks
- **Voz y contenido:** [`LENGUAJE.md`](LENGUAJE.md) — cómo suena el sistema: tono, escritura es-MX, microcopy y glosario canónico (compañero de este doc)
- **«Liquid Glass v1» (rediseño 2026-07):** [`LIQUID-GLASS.md`](LIQUID-GLASS.md) — la evolución del ADN para pantallas rediseñadas: tokens `Liquid*` (color/tipo/espacio/radios), 4 recetas de vidrio, contrato de motion (`LiquidMotion`) y los 7 componentes + la pantalla Hoy de referencia (`LiquidHoyScreen`), todo en `Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/`
- **Guías compañeras:** [`ACCESIBILIDAD.md`](ACCESIBILIDAD.md) (contraste, Dynamic Type, VoiceOver, reduce-motion, 44pt) · [`I18N.md`](I18N.md) (locales, plurales, formato) · [`ICONOGRAFIA.md`](ICONOGRAFIA.md) (catálogo `StrandIcon`, glifos, naming)

> ⚠️ This document is **generated from code**. The Swift package is canonical — if a
> value here disagrees with `Palette.swift` / `Typography.swift` / `Motion.swift` /
> `Components.swift`, the code wins. Hex values are exact per design spec §9.1; do not substitute.

---

## 1. Foundations

### 1.1 Color — surfaces & text

Surfaces and text are **«Instrumento diurno»** (warm paper + ink) — see **[§8](#8-instrumento-diurno--the-daytime-language-fer-131)** for the canonical roles (`paper`, `surface`, `hairline`, `hairlineStrong`, `ink`, `inkSecondary`, `inkTertiary`). The dark `surface.*` / `text.*` / `glow` tokens were **retired in FER-430**.

`opacity.disabled = 0.45` — shared dim value for disabled sections (don't invent your own).

### 1.3 Color — accent (chrome, **not** data)

The accent is for UI chrome (selection, focus, links), **never** to encode a metric — data is colored by the recovery/strain/zone scales below.

| Token | Hex |
|---|---|
| `accent` | `#18C98B` (health green) |
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
| REM | `#3E9E8C` (muted teal — calmer than the old `#5BE0C7` mint, FER-234) |

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

## 3. Spacing & sizing (`CenitMetrics`)

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
| `interactive` | response 0.28, damping 0.82, blend 0.1 | Direct manipulation — press, drag, tab/sheet transitions |
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
| `Sparkline` | Tiny inline trend line (Today / live-HR tile): optional area fill, head dot, hover read-out, optional **reference band** (p25–p75 typical range, in ink — FER-155) | `values:`, `gradient:`, `range:`, `referenceBand:`, `bandColor:`, `lineWidth:`, `showsArea:`, `showsHead:`, `showsHover:`, `valueFormat:`, `indexLabel:` |
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
- `ReferenceRange` (pure helper) computes the p25–p75 "typical range" band a `Sparkline` draws behind its line (FER-155); the band is ink (`bandColor`, default `hairlineStrong`), never a data hue — the line's gradient still carries the metric.

---

## 6. Assets

See [`assets/`](assets/) (and its [README](assets/README.md)):

- `assets/app-icon/` — the iOS app icon (`icon_1024.png`); the older `16…512 @1x/@2x` PNGs are retired macOS leftovers (see the assets [README](assets/README.md)).
- `assets/brand/` — `logo.svg`, `banner.svg`.

---

## 7. Usage notes

- **Dark-only.** All previews force `.preferredColorScheme(.dark)`. There is no light theme.
- **Data colors come from scales, chrome comes from `accent`.** Never tint a metric with `accent`; never reuse a status color as a recovery color.
- **Numerics are tabular.** Any live value uses a `*Number` font or `StrandFont.number(...)` so digits don't shift.
- **Compose from the locked set.** New cards = `NoopCard` + the components above, not bespoke surfaces.
- **Regenerating tokens:** this doc and [`tokens/design-tokens.json`](tokens/design-tokens.json) are derived from the Swift package; re-derive them when `Palette` / `Typography` / `Motion` / `Components` change. The «Instrumento» color blocks (§8.2 + `color.instrumento`) are emitted from `Instrumento.swift` by `swift run StrandDesignTokens` (run it in `Packages/StrandDesign`); CI fails if they drift (FER-131 handoff · 01).

---

## 8. «Instrumento diurno» — the daytime language (FER-131)

The redesign language. It reads like a precision instrument printed on **warm paper**:
light mode, **one dominant number**, **meaningful color (value + signal identity)**, hierarchy by space.
It lives **alongside** the dark system (§1–§7) — no shipped screen changes in FER-131.

> **2026-08 · Tendencias salió del inventario Instrumento (épico FER-97).** Toda la pestaña
> Tendencias — su aterrizaje (`CuerpoView`, FER-100), las gemelas, el detalle de vital, Sueño,
> Comparar/Explorador, longevidad y «Fuentes de datos»/«Apple Health» — migró a **Liquid Glass**
> (§ LIQUID-GLASS.md). «Instrumento diurno» sigue siendo canónico para lo que aún es papel:
> **Entrenar** (WorkoutsView / WorkoutHistoryScreen / RestEditor), **Ajustes**, **Bucle**, **Dieta**.
> Los componentes de papel compartidos (`HeroInvertido`, `TileSurface`, `BarraAncla`, `SeccionBloque`,
> `PieMetodo`, `GraficaRangos`, …) NO se borraron: los detalles migrados los conservan como
> *rollback* deliberado y Entrenar todavía es su consumidor vivo. Su retiro espera a que Entrenar
> migre (FER-106 lo dejó documentado; borrado diferido).

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
Data accents carry color **only on a large numeral** (≥24pt, where AA-large is 3:1); a datum or
delta on **<24pt** text uses `positiveText` / `negativeText` instead (FER-131 · 02). The «On paper»
column is the WCAG contrast against `paper`. The by-the-hour engine (FER-132) re-derives every data
hue against the live paper so this 3:1 floor holds at every hour (FER-131 handoff · 08).

> ⚠️ The table below is **generated from `Instrumento.swift`** by `swift run StrandDesignTokens`
> (FER-131 handoff · 01). Do not edit it by hand — change the token in code and re-run the generator;
> CI fails if the committed table or `tokens/design-tokens.json` drifts from code.

<!-- GENERATED:INSTRUMENTO-COLORS:START -->
| Role | Hex | On paper | Use |
|---|---|---|---|
| `paper` | `#F4F1E8` | — | canvas — warm bone paper (never pure white) |
| `surface` | `#FBF9F2` | — | a sparingly-used raised surface; never nested |
| `hairline` | `#E6E0D2` | — | faint warm 1px rule |
| `hairlineStrong` | `#D8D0BD` | — | rule on emphasis |
| `paperHi` | `#F9F8F3` | — | paper-gradient highlight — lighter pool toward top-centre (derived from paper) |
| `paperLo` | `#EDE8DD` | — | paper-gradient rim — deeper warm edge (derived from paper) |
| `ink` | `#221D16` | 14.8:1 | primary text & the hero numeral |
| `inkSecondary` | `#5C5648` | 6.5:1 | supporting copy & labels |
| `inkTertiary` | `#6F6857` | 4.9:1 | overlines, captions, axis |
| `inkDim` | `#AFAA9D` | — | no-data cells — the «—» + its glyph; intentionally low-contrast, NOT AA text (derived from inkTertiary→paper) |
| `dataRecovery` | `#0C8F62` | 3.6:1 | recovery datum — color on the numeral (AA-large, ≥24pt) |
| `dataStrain` | `#C4631F` | 3.6:1 | strain datum — color on the numeral (AA-large, ≥24pt) |
| `dataSleep` | `#5D5A9E` | 5.4:1 | sleep trend hue (FER-147) |
| `dataHrv` | `#147C8C` | 4.3:1 | HRV trend hue — cyan, distinct from the verdict green (FER-206) |
| `dataHeart` | `#B85068` | 4.2:1 | heart-rate trend hue, shared by HR & resting HR (FER-147) |
| `dataSpO2` | `#3B6FA0` | 4.7:1 | blood-oxygen trend hue (FER-147) |
| `dataSteps` | `#4C8998` | 3.5:1 | steps trend hue (FER-147) |
| `verdict` | `#0C8F62` | 3.6:1 | day verdict accent — positive green |
| `warning` | `#9C5E10` | 4.6:1 | caution / strained |
| `critical` | `#BC3A34` | 4.9:1 | depleted / error — contained brick red |
| `positiveText` | `#00774B` | 5.0:1 | positive delta on <24pt text — darkened verdict to clear text-AA (FER-131 · 02) |
| `negativeText` | `#BC3A34` | 4.9:1 | negative delta on <24pt text (= critical) (FER-131 · 02) |
| `inkMuted` | `#AFAA9D` | — | quietest chrome — inactive tabs, unlit marks; intentionally NOT AA text (FER-708) |
| `patternBlock` | `#EFEAE0` | — | «patrón/conexión» block background (FER-708) |
| `rangeBand` | `#EDE8DB` | — | personal-range band behind a trend line (FER-708) |
| `rangeMidline` | `#C9C2AF` | — | dotted personal-median line inside the range band (FER-708) |
| `dataSun` | `#D79567` | — | day/sun arc on the dial seal — context, not a datum (FER-708) |
| `ctaAccent` | `#2FE6A8` | — | accent on the ink CTA bar — only ever on ink, never on paper (FER-708) |
| `moderate` | `#E8C24B` | — | «moderado» lane fill (FER-708) |
| `dataSleepDeep` | `#3F3C78` | — | deep-sleep stage fill (FER-708) |
| `dataSleepLight` | `#8E8BC4` | — | light-sleep stage fill (FER-708) |
| `originBand` | `#0C8F62` | — | data-origin dot — strap/band (= dataRecovery) (FER-708) |
| `originApple` | `#3B6FA0` | — | data-origin dot — Apple Salud (= dataSpO2) (FER-708) |
| `originComputed` | `#AFAA9D` | — | data-origin dot — computed on-device (= inkMuted) (FER-708) |
<!-- GENERATED:INSTRUMENTO-COLORS:END -->

### 8.3 Type voice (`InstrumentoType`)

> **Evolución 2026-07:** para pantallas nuevas o rediseñadas la voz canónica es la de §8.7
> (Space Grotesk). Esta sección describe la voz que las pantallas aún no migradas conservan.

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
2. **Color carries meaning, not decoration.** Saturated hue marks a *measured value* **or a
   *signal's identity*** — each metric keeps its own tone (indigo sleep, rosa resting HR, verde
   load, …) on its number, its label, or its mark. It never fills backgrounds, boxes, or
   chrome, and it stays restrained: the page is still ink on warm paper, not a field of color.
   *(Evolución Fer 2026-08: la regla anterior, «color solo en el dato», prohibía teñir
   rótulos/íconos; se retira. El color de identidad de cada señal también habla —como en los
   rótulos del héroe y las filas del acta de Hoy—, con la misma contención. El único acento que
   sigue reservado es el del **veredicto/estado**: verde/ámbar/rojo hablan de juicio, no de
   identidad, y no se mezclan con el hue de la señal en el mismo elemento.)*
3. **Hierarchy by space, not boxes.** Group with whitespace + hairlines. No card-in-card;
   `surface` is the exception, used sparingly and never nested.
4. **Moderate overline.** Labels are quiet (tertiary ink). They orient; they don't announce.

**«Decoración» depende del contexto — y por eso la regla 2 puede dar resultados opuestos en dos
pantallas sin que ninguna esté mal** (decisión Fer 2026-07-19). El caso que fijó el criterio: el
numeral de serie va en **tinta pelona** al editar una rutina (`RoutineEditorScreen.numeralRing`) y con
**anillo ámbar** en la sesión activa (`LiveStrengthSheet.badge`). Las dos citaban la regla 2 y llegaban
a lo contrario. La lectura correcta es que el color «vive en el significado» (el dato o la identidad de
la señal), y **qué cuenta como el dato cambia con el momento**: planeando el martes en el sillón, «cuál
serie es» no urge y el anillo sería
cromo; con la barra en la mano, «cuál voy» es el dato más urgente de la pantalla y el anillo deja de
ser adorno.

Cuando dos pantallas diverjan por esta razón, **escríbelo en el código de las dos** (nota gemela con el
porqué). Una divergencia deliberada sin documentar es indistinguible de un copy-paste desfasado, y la
siguiente auditoría de duplicación la va a «corregir».

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

### 8.6 Daytime specifics — flat surfaces, touch scrub, tinted text (FER-131 handoff)

The «Instrumento diurno» language differs from the legacy dark system in four ways that the
shared components handle automatically once a subtree is themed with `.instrumentoTheme(_:)` /
`.instrumentoThemeByHour()` (which also sets `\.instrumentoFlat = true`):

- **Flat, no glow (03).** Glow / bloom (the additive plus-lighter halos on chart dots, the REM
  band, the connection dot; the heavy black tooltip shadow) are black-screen effects that muddy
  a glyph on warm paper. On paper they're dropped: the highlight reads as a flat, enlarged
  **paper-fill + colored-ring** scrub handle, the sparkline head is a solid dot, the tooltip
  keeps only a quiet separation shadow. Motion keeps only the physical springs + `breathe`.
- **Hour-derived data hues (08).** The by-the-hour engine darkens every data hue against the live
  paper (`InstrumentoTheme.contrastSafeDataHues()`, the `positiveText` OKLab technique generalized)
  so each holds the **3:1** numeral floor at every minute — never hand-tuned per anchor.
- **Tinted text <24pt (02).** A datum or delta below 24pt uses `positiveText` / `negativeText`
  (the 4.5:1+ text-tier tokens), never a saturated data hue; the ≥24pt hero numeral keeps the hue.
- **Touch, not hover (10).** Charts respond to a finger **press-drag scrub** (`DragGesture`, snap to
  nearest datum, tooltip follows the finger, **selection haptic** on each datum change via
  `ChartHaptics`). Controls (`SegmentedPillControl`, `QuietButton`) and the scrub plot meet the
  **44pt** touch minimum. The toolkit's public API carries no "hover" term (it's `showsScrub`,
  `ChartScrubMath`, `ChartScrub.swift`).

### 8.7 Voz evolucionada — handoff «Hoy» 2026-07 (FER-707/708)

El rediseño integral de «Hoy» (épico FER-707, decisiones del dueño 2026-07-05) evoluciona la
voz del lenguaje diurno. **Canónica para pantallas nuevas o rediseñadas**; las pantallas aún
no migradas conservan la voz de §8.3 hasta que les toque.

- **Space Grotesk** (400/500/600/700, OFL, empaquetada en `StrandDesign/Resources`, registrada
  vía CoreText) toma numerales, títulos de hoja, overlines, labels de carril, pestañas y
  botones. El cuerpo de texto y el microcopy siguen en SF. Numerales SIEMPRE tabulares.
  Tokens: `InstrumentoType.grotesk*` (`groteskHero` 124/700/ls −6 · `groteskSheetNumeral`
  56/700/ls −2 · `groteskVerdict` 20/700 · `groteskSheetTitle` 12/700/ls 2.4 MAYÚS ·
  `groteskOverline` 9–10/600/ls 2 MAYÚS · `groteskTileValue` 21/700 · `groteskTab` 11/700/ls 2
  · `groteskLane` 12/700/ls 1.8).
- **Overlines de pantalla evolucionada, en exclusiva Grotesk:** toda pantalla ya migrada a esta voz usa
  `Text(...).groteskOverline()` (10/600, tracking 2, ALL-CAPS) para sus overlines. `InstrumentoType.overline` /
  `.instrumentoOverline()` (§8.3) queda reservado a pantallas del sistema base «Instrumento diurno» aún sin
  migrar a esta voz evolucionada. `StrandFont.overline` / `.strandOverline()` es legacy §9.2: ninguna pantalla
  nueva lo usa.
- **La serif se retira** (supersede FER-564): `StrandFont.serifVerdict` queda deprecada; los
  veredictos migran a `groteskVerdict`. La fuente Instrument Serif sale del bundle al cerrar
  FER-710.
- **Color bajo 24pt, relajado a conciencia:** en las pantallas rediseñadas el color del dato
  puede aparecer en labels de grupo (9pt) y valores de tile (21pt) **cuando el texto ES el
  datum o su etiqueta directa** — es identidad de señal, no chrome. Sigue vigente: valence
  (positivo/negativo) en texto chico usa `positiveText`/`negativeText` (piso 4.5:1); el chrome
  nunca lleva hue; `inkMuted`/`inkDim` jamás para copy que deba leerse.
- **Sin em dashes (—) en el copy de pantallas rediseñadas** — usar coma, dos puntos o «·».
  Regla por pantalla, no barrido global (decisión del dueño): el copy existente migra cuando
  su pantalla se rediseña.
- **Tokens nuevos de color** (§8.2, generados): `inkMuted`, `patternBlock`, `rangeBand`,
  `rangeMidline`, `dataSun`, `ctaAccent`, `moderate`, `dataSleepDeep`, `dataSleepLight`, y los
  puntos de origen del dato `originBand`/`originApple`/`originComputed` (alias de roles
  existentes: origen y hue de métrica no pueden divergir). El verde profundo de delta favorable
  del handoff (`#00774B`) es exactamente `positiveText`: no hay rol nuevo.
- **El dial 24h** deja de ser pieza central de «Hoy»: sobrevive como **sello de header**
  (34 px, mini dial con arco de día `dataSun`, banda de sueño y punto «ahora») y como spinner
  del pull-to-refresh (FER-709). En **F3 (FER-711)** el `DiurnalDial` grande se **retiró del
  paquete**: su geometría compartida vive ahora en `DialGeometry.swift` (`SleepWindow` +
  `DialGeometry`, lo único que `DialSeal` necesita); el view y sus tests se borraron.
- **Excepciones aprobadas de la sesión de fuerza (canvas 2026-07, dueño):** (a) el pill
  **«+ Serie»** lleva fill `dataStrain` — única CTA con hue de dato como fondo; vive DENTRO del
  recibo y ancla la familia ember de la carga (handoff Entrenar), no se replica en otros CTAs;
  (b) los **chips troquel** de Descanso/Nota llevan su hue SOLO en el icono (reloj ember, lápiz
  teal — propuesta B aprobada): el único color del chip es ese glifo; el valor va en tinta.
  Ambas son excepciones nombradas a la regla 2 (§8.4) —hue como FONDO/CTA, que la regla sigue
  reservando aunque ya permita el color de identidad en marcas y rótulos—, como `keyCap`.
- **Excepción del AZUL del vigía (FER-22, dueño):** en «El Ecosistema» de Hoy, los dos vigías
  (temperatura y respiración) hablan en `LiquidColor.azul` —orbe, estela, mirada y su dato— para
  que se lean como UNA familia: «lo que vigila». Es una excepción CONSCIENTE al mapeo 1:1 de
  tonos de dato: `azul` es el hue 1:1 de *respiración* como métrica, así que en la misma pantalla
  conviven el tile RESPIRACIÓN azul y dos vigías azules (uno de ellos es temperatura, cuyo tile
  es ámbar). Se acepta porque en el héroe el vigía es un ROL (vigilar), no la métrica: el azul
  agrupa el rol, no colisiona con el dato. No se acuñó un token nuevo (evita proliferar la
  paleta); si un día el rol necesita voz propia, ahí sí un `azulVigia`.
- **Aprendizajes del canvas de la sesión de fuerza (2026-07, ley para pantallas nuevas):**
  1. **Los números vivos RUEDAN.** Todo numeral que cambia solo en pantalla (relojes, contadores,
     countdown) lleva `contentTransition(.numericText())` — los dígitos ruedan, nunca parpadean;
     un anillo/barra de progreso drena CONTINUO (lineal 1 s), no a brincos por tick.
  2. **Todo selector es RECTANGULAR y su thumb llena el segmento.** `SegmentedPillControl`
     (rectangular global), `PresetPill` (thumb de tinta) y los toggles del foco comparten una
     sola gramática; las cápsulas quedan reservadas a acciones, nunca a selección.
  3. **Chips «troquel» = `troquelChip`** (papel hundido + `chipRadius` + `hairlineStrong`) —
     componente, no receta que se copia.
  4. **El visual puede pedir menos de 44 pt; el toque NUNCA.** El área táctil se completa con
     `contentShape` extendido / frame externo (pasos ± del foco, «×» de cierre) — así el numeral
     manda sin sacrificar dedo.
  5. **Los relojes le hablan a VoiceOver por HITOS, no por ticks:** `.updatesFrequently` +
     valores cuantizados (60/30/15 s, «casi listo») en toda superficie con countdown.
  6. **Elementos que deben alinearse viven en UN solo árbol de layout.** El riel (hilo + bolita +
     nacimiento) ancla al thumbnail/tarjeta, jamás a fondos de celda: los marcos de `List` derivan
     y esa deriva costó 10 rondas (r7–r18: la sesión terminó en `ScrollView`+`VStack`).
  7. **Cápsulas hermanas = altura FIJA compartida**, no padding vertical: dos fuentes distintas
     (SF vs Grotesk) con el mismo padding rinden cápsulas de tamaños distintos.

#### 8.7.1 Estados de «Hoy» + banners (FER-711)

- **El numeral nunca miente.** El héroe usa `··` calibrando, `—` sin datos/en espera, y `~N`
  cuando la recuperación es un estimado de Apple (`isRecoveryEstimated`). El color del numeral es
  el semáforo: color de nivel = lectura lista; tinta/`—` = en espera. Los estados que la app
  distingue hoy (primer uso, calibrando 1–4, base Apple preliminar, sin datos, parcial estimado)
  se mapean 1:1 al `HeroState`. Los estados del mock que exigen detección nueva —anomalía
  multi-señal, corte de noche (~22:00) y madrugada (0–6)— se difieren a issues propios (FER-736,
  FER-737): F3 NO inventa detección.
- **Banner de estado (`TodayBanner`).** Tarjeta estándar reutilizable montada bajo el header, sobre
  el día normal: punto de estado (7 px), título 13/600 en `ink`, subtítulo 11.5 en `inkTertiary`,
  CTA opcional 11/600 grotesk en color. Se dibuja SOLO el de mayor prioridad, desde señales que ya
  existen: **batería crítica** (`critical`), ~~**banda desconectada de día**~~ (*retirado*, FER-1003 —
  la app ya no empareja banda; no apaga el BPM del header por desconexión) y **línea base envejecida**
  (`warning`). Los banners que exigen
  detección/matemática nueva —siesta (re-score del numeral), zona horaria (exención de regularidad)
  y permisos parciales de Apple— se difieren (FER-734/735/738); la tarjeta ya soporta su forma.
- **Reglas × banners.** La gráfica de las cinco reglas SIEMPRE cuadra con el numeral: Σ marcas
  encendidas == el numeral (invariante de `RecoveryRules`, con test `testNumeralEqualsVisibleSumAcrossStates`).
  Los banners que F3 envía son presentacionales y no tocan esa descomposición, así que el invariante
  se conserva en todos los estados con numeral.

### 8.8 «El Tablero» — evolución DNA de Hoy (FER-28)

El rediseño de la mitad inferior de Hoy formaliza dos evoluciones del ADN, ambas acotadas a la
pantalla Hoy (el resto del sistema no cambia). Misma disciplina que la excepción del vigía (FER-24):
excepciones **conscientes y nombradas**, no una relajación general.

- **Hoy estrenó la evolución de la regla 2 (§8.4).** Aquí se probó primero que el color puede
  vivir en más de una capa; la regla 2 ya lo generalizó a todo el sistema. En «El Tablero» el
  color vive en tres capas, no en una:
  1. **Los valores** de cada métrica van teñidos con su tono 1:1 (`indigo` sueño, `rosa` FC,
     `verde` carga, `ámbar` temp/esfuerzo, `teal` pasos, `cian` VFC, `azul` resp) — el dato manda,
     y su color lo ancla a su casa.
  2. **El ambiente** (la *plasta*, `LiquidPlasta`) es MONOCROMO del veredicto — una sola familia de
     clima a la vez (verde/ámbar/rojo/neutro), a luminancia casi constante.
  3. **Los filos** (`LiquidAuroraEdge`) llevan, insinuados, los tonos de LOS DATOS de su módulo.
  La regla 2 (§8.4) ya permite el color de identidad en todo el sistema; lo que sigue siendo
  propio de Hoy es la COMPOSICIÓN de tres capas (dato + plasta del veredicto + filos), porque su
  trabajo es que un vistazo lea a la vez el veredicto (fondo) y de dónde sale (datos teñidos).

- **Doctrina sin-scroll de Hoy.** Con Dynamic Type por defecto, Hoy entera cabe SIN scroll en un
  iPhone estándar (header + héroe + 4 módulos + dock). Para lograrlo sin tocar el arte del héroe
  («El Ecosistema», FER-13), el héroe tiene una presentación **compacta** (`LiquidEcosistema.compacto`):
  recorta el aire superior del lienzo y acerca el veredicto al orbe — exactamente la proporción que
  ya mostraba el mock aprobado. Los módulos ABRAZAN su contenido (sin piso de altura fijo), así un
  módulo de una línea (LO QUE ACOMPAÑA) no ocupa lo mismo que uno de tres. Con tallas **AX** vuelve
  el scroll y los módulos apilan **1 dato por fila** (excepción honesta, como lo hace Apple).

- **El dial-sello se aplana.** Sobre el suelo casi blanco nuevo (`fondoAlto/Bajo` = `#FEFEFD/#F3F4F2`),
  el dial de 24 h deja la lente de vidrio pesada y las 24 marcas por un anillo fino + los arcos de
  dato (noche índigo, día oro) + una aguja a la hora actual. El dato son los arcos; el chrome calla.

Tokens/componentes nuevos y su spec cerrada viven en `LIQUID-GLASS.md` (§ El Tablero).

### 8.9 Hojas de detalle de métrica (sheets) — FER-29

Las 9 hojas de detalle de Hoy se reconstruyen sobre **una plantilla + 6 contratos** (familia
única; Sueño añade piezas en un slot, no un fork). Spec cerrada — papel opaco en tarjetas
internas, contratos C1–C6, plantilla y componentes — en
[`LIQUID-GLASS.md` §11](LIQUID-GLASS.md#11-hojas-de-detalle-de-métrica-sheets--fer-29).

Reglas de superficie (reafirmación):

- **Héroe idéntico para las 9:** valor + unidad + frase de nivel + **sello de la ventana**;
  **sin doble-dato** en el héroe.
  - El sello dice A QUÉ VENTANA pertenece el numeral: «HOY · 3 AGO» en la semana,
    «MEDIA · 30 DÍAS» en los rangos largos. Sin él, un numeral que cambia al mover el
    selector sería un número sin dueño.
  - **La regla es «la fecha no cambia con el scrub», no «no hay fecha»** (FER-33). Esta línea
    decía «sin fecha» y contradecía a los tres prototipos canónicos, que sí la pintan; lo que
    el dueño decidió fue que el héroe y su fecha son ESTÁTICOS frente al scrub. El rango sí
    los mueve; el scrub no.
- **El héroe sigue la ventana del selector:** en la semana es el dato de hoy; en los rangos
  largos es la **media** de la ventana visible, y la frase de nivel, el titular de la gráfica
  y la fila activa de la escalera siguen ese mismo valor.
- **Color con significado** (el dato y la identidad de la señal) + plasta monocroma del tono de la métrica (no cajas teñidas).
- **Papel opaco** en tarjetas internas (tabla de bandas, pie, Regularidad…):
  `.liquidGlass(.superficieSolida)` / `.pastillaSolida`. El vidrio real queda en la hoja
  (`LiquidSheetFondo`), el dock y el orbe.
