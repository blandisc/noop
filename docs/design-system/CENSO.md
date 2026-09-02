# CENSO.md — censo de 8 dimensiones

> Regenerable: `cd Tools/DesignCensus && swift run design-census --repo ../.. --roles roles.yaml --labels labels/composicion-etiquetado.json --out ../../docs/design-system/CENSO.md`
>
> **Commit**: `17ba6c45d2d9` · **fecha del commit**: 2026-09-01T16:36:29-06:00 · **archivos .swift escaneados**: 209
>
> Este archivo distingue **[MEDIDO]** (contado por el AST de swift-syntax, reproducible) de **[ETIQUETADO]** (`roles.yaml` y `labels/composicion-etiquetado.json`, mantenidos a mano por un agente — el AST no ve roles). Etiquetado por: subagent-general-purpose-independent-labeler-2026-08-31 — declarado distinto del autor del detector (swift-syntax visitor) en el propio archivo de labels.
>
> **No gatea nada.** Es un reporte de solo lectura (FER-266); aplicar cualquier veredicto es trabajo de `/migracion`.

## Resumen ejecutivo

| Dimensión | Hits [MEDIDO] |
|---|---|
| color | 73 |
| spacing | 713 |
| radio_elevacion | 116 |
| tipografia_dynamictype | 54 |
| movimiento | 65 |
| interaccion_haptica | 2 |
| iconografia | 65 |
| composicion | 0 |

## 1. Colador de evasiones [MEDIDO]

APIs que evaden el regex de `Tools/check-design-drift.py` (multi-línea, nombre distinto, `token ± n`) pero que el AST sí ve:

| API / patrón | conteo | archivos distintos |
|---|---|---|
| `evasion:.frame(height:)-decorativo` | 146 | 42 |
| `evasion:.frame(width:)-decorativo` | 109 | 38 |
| `evasion:Color.clear` | 63 | 27 |
| `evasion:clipShape(RoundedRectangle)` | 12 | 8 |
| `evasion:.offset` | 10 | 7 |
| `evasion:Color.white` | 4 | 2 |
| `evasion:.foregroundStyle(.white)-fuera-de-token` | 2 | 2 |
| `evasion:Color.black` | 2 | 2 |
| `evasion:EdgeInsets(literal)` | 2 | 2 |
| `evasion:.foregroundStyle(.primary)-fuera-de-token` | 1 | 1 |
| `evasion:.foregroundStyle(.secondary)-fuera-de-token` | 1 | 1 |

## 2. Censo de `token-exempt` por taxonomía [ETIQUETADO por heurística sobre texto a mano]

Taxonomía: `dato` · `sistema` · `falta-pieza` · `optico` · `paridad` · `unico`. Clasificación automática por palabras clave sobre la razón que el autor original ya escribió a mano — no reinterpreta intención, bucketiza.

| Categoría | conteo |
|---|---|
| unico | 58 |
| dato | 34 |
| sistema | 26 |
| falta-pieza | 24 |
| optico | 13 |
| paridad | 4 |

**Total exempts vivos en el árbol**: 159

### Top archivos por exempts

| Archivo | exempts |
|---|---|
| `CenitWidgets/RestLiveActivity.swift` | 24 |
| `Cenit/Screens/ExerciseDetailScreen.swift` | 13 |
| `Cenit/Screens/MetricDetailScreen.swift` | 13 |
| `Cenit/Screens/TrainingBodyScreen.swift` | 11 |
| `Cenit/Screens/WorkoutHistoryScreen.swift` | 10 |
| `Cenit/Screens/BreathingView.swift` | 7 |
| `Cenit/Screens/DataSourcesView.swift` | 6 |
| `Cenit/Screens/Hoja/RoutineSheetLiveTarjeta.swift` | 6 |
| `Cenit/Screens/LiveStrengthSheet.swift` | 6 |
| `Cenit/Screens/WorkoutImportView.swift` | 6 |
| `Cenit/Screens/AjustesView.swift` | 4 |
| `Cenit/Screens/Hoy/HoyModosHost.swift` | 4 |
| `Cenit/Screens/MetricDetailSupport.swift` | 4 |
| `Cenit/Screens/ReceiptPrinterScreen.swift` | 4 |
| `Cenit/Screens/SleepDetailScreen.swift` | 4 |

### Clusters ×3 de `falta-pieza` (regla anti-excepción del épico §5)

- **8×** — pieza propuesta: _sin token exacto (horizontal/chip handoff)_
  - `Cenit/Screens/Hoja/RoutineSheetLiveLogic.swift:703` — sin token exacto (horizontal/chip handoff)
  - `Cenit/Screens/LiveStrengthSheets.swift:421` — sin token exacto (horizontal/chip handoff)
  - `Cenit/Screens/WorkoutHistoryScreen.swift:1943` — sin token exacto (horizontal/chip handoff)
  - `Cenit/Screens/WorkoutHistoryScreen.swift:1948` — sin token exacto (horizontal/chip handoff)
  - `Cenit/Screens/WorkoutImportView.swift:320` — sin token exacto (horizontal/chip handoff)
- **4×** — pieza propuesta: _sin token exacto (edge ≠ rowVPad)_
  - `Cenit/Screens/TrainingBodyScreen.swift:293` — sin token exacto (edge ≠ rowVPad)
  - `Cenit/Screens/TrainingBodyScreen.swift:579` — sin token exacto (edge ≠ rowVPad)
  - `Cenit/Screens/WorkoutHistoryScreen.swift:393` — sin token exacto (edge ≠ rowVPad)
  - `Cenit/Screens/WorkoutImportView.swift:345` — sin token exacto (edge ≠ rowVPad)

## 3. Colisiones de rol y veredicto del árbitro [ETIQUETADO + MEDIDO]

Regla: canónico = Liquid Glass · El Eje en su contexto (`roles.yaml`); si Liquid no define el rol, el más frecuente entre pantallas ya migradas; empate → dueño con preview. **Estos veredictos viven aquí; aplicarlos es trabajo de `/migracion`.**

Contexto asignado por heurística de ruta (`Watch` → watch_oled, `Liquid` en el path → mosaico, resto → sobrio) — es una aproximación declarada, no una verdad medida.

| Dimensión | Contexto | Valores en disputa | Canónico propuesto | Razonamiento |
|---|---|---|---|---|
| radius | sobrio | 0, 0.5, 1, 1.1, 1.2, 1.5, 1.6, 1.9, 2, 2.4, 2.5, 3, 4, 42 | 1 | Ningún valor de este grupo tiene rol en roles.yaml — candidato a `falta-pieza` o a colisión real; requiere veredicto del dueño. |
| radius | watch_oled | 1, 4 | 1 | Ningún valor de este grupo tiene rol en roles.yaml — candidato a `falta-pieza` o a colisión real; requiere veredicto del dueño. |
| spacing | sobrio | -10, -8, -2, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20, 22, 24, 28, 32, 34, 36, 40, 46, 48, 68 | 1 | roles.yaml ya nombra 13 de 31 valores; 18 sin rol compiten por el mismo sitio — candidatos a colisión. |

## 4. Detector de composición (fondo+radio+sombra) — solo reporte [MEDIDO + ETIQUETADO]

**Nunca promovido a gate** (anti-alcance del épico). Candidatos detectados: 307.

- n etiquetado = 120
- Precision = 0.45 (Wilson 95%: 0.35–0.57), tp=35 fp=42
- Recall = 0.58 (Wilson 95%: 0.46–0.70), fn=25

⚠️ **Sesgo de muestreo conocido**: el set etiquetado se tomó de los propios candidatos que el detector produjo (no de un barrido independiente del árbol), así que `fn` solo puede venir de un candidato detectado y luego descartado en el conteo — el recall de esta corrida NO mide qué fracción de composiciones REALES en todo el repo el detector se perdió, sólo qué tan bien re-encuentra su propia lista. Un recall verdadero necesitaría una muestra etiquetada por barrido ciego del árbol, independiente del detector — pendiente, fuera del alcance de esta primera corrida.


Etiquetado por: subagent-general-purpose-independent-labeler-2026-08-31 — declarado distinto del autor del detector (swift-syntax visitor) en el propio archivo de labels.

<details><summary>Candidatos (primeros 30)</summary>

- `Cenit/App/AppMap.swift:38` — `VStack(spacing: 10) {             TodayView()                 .environmentObject(model.repo)                 .environ...`
- `Cenit/App/AppMap.swift:39` — `TodayView()                 .environmentObject(model.repo)                 .environment(model)                 .envir...`
- `Cenit/App/AppMapSerieActiva.swift:26` — `Group {             if model.strengthSession != nil {                 // FER-167 ronda 2 (R23, QA O3): La Hoja viva s...`
- `Cenit/App/AppMapSerieActiva.swift:30` — `RoutineSheet(origin: .today(routineId: model.strengthSession?.routineId), mode: .live)                     .environme...`
- `Cenit/Screens/ActivityRecoverySheet.swift:198` — `Text(confidence == .solid ? String(localized: "solid") : String(localized: "building"))             .font(LiquidType....`
- `Cenit/Screens/AppleHealthView.swift:680` — `Text(String(localized: "No readings recorded."))             .font(LiquidType.cuerpo)             .foregroundStyle(Li...`
- `Cenit/Screens/CuerpoView.swift:687` — `Button {             trainingLoadItem = TrainingLoadItem(model: load ?? TrainingLoadModel(acwr: nil, series: []))    ...`
- `Cenit/Screens/CuerpoView.swift:690` — `liquidModulo(index: 1, tones: [LiquidColor.ambar, LiquidColor.ambarClaro],                         period: 52, revers...`
- `Cenit/Screens/CuerpoView.swift:692` — `VStack(alignment: .leading, spacing: LiquidSpace.s250) {                     moduleTitle("Training load")            ...`
- `Cenit/Screens/CuerpoView.swift:694` — `HStack(spacing: LiquidSpace.s400) {                         VStack(alignment: .leading, spacing: 3) {                ...`
- `Cenit/Screens/CuerpoView.swift:710` — `ZStack(alignment: .center) {                                 Capsule().fill(LiquidColor.tinta10)                     ...`
- `Cenit/Screens/CuerpoView.swift:711` — `Capsule().fill(LiquidColor.tinta10)                                     .frame(width: 104, height: 3)`
- `Cenit/Screens/CuerpoView.swift:903` — `Capsule().fill(LiquidColor.tinta10)                 .frame(width: 132, height: 6)                 .overlay(alignment:...`
- `Cenit/Screens/CuerpoView.swift:906` — `Capsule().fill(LiquidColor.tinta500)                         .frame(width: 132 * CGFloat(calibrating) / CGFloat(Self....`
- `Cenit/Screens/CuerpoView.swift:1170` — `Button { darkSheet = .screen(.dataSources) } label: {                 HStack(spacing: LiquidSpace.s200) {            ...`
- `Cenit/Screens/CuerpoView.swift:1171` — `HStack(spacing: LiquidSpace.s200) {                     LiquidIcon(.corazon, size: 17, color: LiquidColor.azul)      ...`
- `Cenit/Screens/CuerpoView.swift:1683` — `content             .padding(.horizontal, LiquidSpace.s550)             .padding(.vertical, LiquidSpace.s400)        ...`
- `Cenit/Screens/CyclePhaseView.swift:362` — `GeometryReader { geo in             ZStack(alignment: .leading) {                 Capsule().fill(LiquidColor.tinta10)...`
- `Cenit/Screens/CyclePhaseView.swift:363` — `ZStack(alignment: .leading) {                 Capsule().fill(LiquidColor.tinta10)                 Capsule().fill(Liqu...`
- `Cenit/Screens/CyclePhaseView.swift:364` — `Capsule().fill(LiquidColor.tinta10)`
- `Cenit/Screens/CyclePhaseView.swift:365` — `Capsule().fill(LiquidColor.verdePrimario)                     .frame(width: max(0, min(1, fraction)) * geo.size.width)`
- `Cenit/Screens/DataSourcesView.swift:608` — `VStack(alignment: .leading, spacing: LiquidSpace.s200) {             Text(coverageSummaryString(withData: withDataCou...`
- `Cenit/Screens/DataSourcesView.swift:612` — `LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LiquidSpace.s100), count: 6),                     ...`
- `Cenit/Screens/DataSourcesView.swift:614` — `ForEach(Array(days30.enumerated()), id: \.offset) { _, day in                     Group {                         if ...`
- `Cenit/Screens/DataSourcesView.swift:615` — `Group {                         if withData.contains(day) {                             RoundedRectangle(cornerRadius...`
- `Cenit/Screens/DataSourcesView.swift:617` — `RoundedRectangle(cornerRadius: 4).fill(LiquidColor.azul)`
- `Cenit/Screens/DataSourcesView.swift:619` — `RoundedRectangle(cornerRadius: 4)  // token-exempt: geometría de dato                                 .fill(LiquidCol...`
- `Cenit/Screens/DataSourcesView.swift:653` — `HStack(spacing: LiquidSpace.s125) {             // Swatch geometry: `LiquidCalendario90.radioSwatch`/`.swatchLado` ar...`
- `Cenit/Screens/DataSourcesView.swift:656` — `RoundedRectangle(cornerRadius: 2, style: .continuous)  // token-exempt: paridad LiquidCalendario90.radioSwatch (no pú...`
- `Cenit/Screens/Entrenar/EntrenarHubCuerpo.swift:45` — `Canvas { context, _ in             let ink = GraphicsContext.Shading.color(LiquidColor.tinta700)             // Cabez...`

</details>

## 5. Deuda por generación visual, por target [MEDIDO por símbolo]

Clasificado por qué símbolos importa cada archivo (`Liquid*` vs `Instrumento*`) — no por fecha ni autor. Un archivo sin ninguno de los dos símbolos queda `indeterminada` (probable candidato: no usa CenitDesign en absoluto, o usa solo tipos neutros como `Color`/`Font` del sistema).

| Target | Liquid (vigente) | Instrumento (absorbida, en migración) | Indeterminada |
|---|---|---|---|
| Cenit | 89 | 7 | 82 |
| CenitApp | 2 | 0 | 7 |
| CenitShared | 0 | 0 | 3 |
| CenitWatch | 1 | 2 | 5 |
| CenitWidgets | 0 | 3 | 8 |

## 6. Iconografía — vocabulario de SF Symbols literales [MEDIDO]

Usos de `Image(systemName: "…")` fuera de un token de icono — cada nombre distinto es un candidato a `CenitIcon` si se repite.

| Símbolo | usos |
|---|---|
| `checkmark` | 8 |
| `heart.fill` | 7 |
| `exclamationmark.triangle` | 5 |
| `ellipsis` | 4 |
| `arrow.up.left.and.arrow.down.right` | 2 |
| `chevron.left` | 2 |
| `clock.arrow.circlepath` | 2 |
| `doc.plaintext` | 2 |
| `pause.fill` | 2 |
| `play.rectangle` | 2 |
| `plus` | 2 |
| `trash` | 2 |
| `xmark` | 2 |
| `applewatch` | 1 |
| `arrow.clockwise` | 1 |
| `arrow.counterclockwise` | 1 |
| `arrow.down` | 1 |
| `arrow.left.arrow.right` | 1 |
| `arrow.up.forward.app` | 1 |
| `arrow.uturn.backward` | 1 |

## Acta de la sesión de vocabulario del dueño

_Pendiente — FER-268. Este espacio se llena a mano tras la revisión única del dueño (épico §5, principio 5); el censo no la sustituye._
