# Contrato F−1 · Hoja de resumen → Liquid Glass

**Épico:** «Hoja de resumen → Liquid Glass» (plan v3, GO condicional round 2).
**Fase:** F−1 (papel — este documento). Es el contrato que gobierna F0…F6: la matriz de estados
sirve de criterios de aceptación para `/qa`, los props definen los componentes del DS, y las
decisiones por pieza acoplada (C3) quedan tomadas aquí.

**Regla de oro:** este contrato es fiel al CÓDIGO tal como está en la rama
`blandisc/inject-hoy-liquid-pulido` (2026-07-22). Donde el plan decía otra cosa, ganó el código
y la discrepancia está anotada en línea con `⚠️`.

Fuente de verdad actual de la hoja: `Cenit/Screens/MetricInfoSheet.swift` (1,303 líneas) +
`Cenit/Screens/MetricInfoCatalog.swift` (factories `MetricInfo`).

---

## 1 · Matriz estados × variantes

El ruteo de variantes vive en `summaryBranch` (`MetricInfoSheet.swift:170-182`), en este orden
de precedencia: recovery → vital-template → sleep rica → strain → clásica. Las condiciones:

| Variante | Condición de entrada | Cita |
|---|---|---|
| Recovery | `id == "recovery" && calibration == nil && displayValue != "—"` | `MetricInfoSheet.swift:377-379` |
| Vital-template | `usesLevels && id ∈ {hrv, rhr, spo2, skin_temp, steps, stress, resp_rate}` | `MetricInfoSheet.swift:395-396` |
| Sleep rica | `id == "sleep" && sleepDetail?.night != nil` | `MetricInfoSheet.swift:507` |
| Strain | `id == "strain" && displayValue != "—"` | `MetricInfoSheet.swift:477` |
| Clásica | todo lo demás (incluye heart_rate, submétricas de sueño, vo2max, recovery calibrando, y el *fallback* de las cuatro de arriba sin dato) | `MetricInfoSheet.swift:225-237` |

✅ **C2 confirmada en código:** SpO₂ **es** vital-template (está en `vitalTemplateIDs`
`MetricInfoSheet.swift:395` y lleva `levelsMetric: .bloodOxygen`,
`MetricInfoCatalog.swift:361`); heart_rate **es** clásica sin bandas + curva 24h
(`bands: []` `MetricInfoCatalog.swift:496`; curva `MetricInfoSheet.swift:244, 889-929`).
Son ramas distintas, no «comparten template».

### 1.1 Recovery

| Estado | Qué se ve | Cita |
|---|---|---|
| Con dato (scored) | Header rediseñado (Grotesk + ⓘ + punto «Calculated» `:322`), numeral 56 teñido por banda (verde ≥67 / ámbar 34-66 / rojo <34, `MetricInfoCatalog.swift:530-536`) + sufijo «/ 100» (`:369-371`) → `recoveryReading` (`:608-622`) → `recoveryZoneMeter` (5 zonas sobre 3 roles de color, `:629-659`) → headline tras ⓘ (`:382-390`) → `levelsBlock` (`:716-742`) → pie (método `:1168`, disclaimer, «Ver más en Tendencias» `:1186-1208`) | `MetricInfoSheet.swift:187-192` |
| Calibrando | `calibration != nil` (`MetricInfoCatalog.swift:512-525`, displayValue «2/4») → cae a **clásica**: headline + `calibrationCard` (barra de progreso «X of N nights», `MetricInfoSheet.swift:236, 1141-1163`). Sin niveles (la factory calibrando NO pone `levelsMetric`) | `MetricInfoCatalog.swift:513-525` |
| Sin dato «—» (score nil, sin calibración) | Tint neutral (`MetricInfoCatalog.swift:536, 542`); cae a clásica con `levelsBlock` (niveles fijos `.recovery` sin activa, `MetricInfoCatalog.swift:553`) | `MetricInfoSheet.swift:225-237` |
| Sin permiso Salud | **No aplica**: recovery no está en la lista `appleCapable` (`TodayView.swift:468`) — es calculado, nunca muestra `appleConnectLine` | `TodayView.swift:467-489` |

⚠️ **Sin entry point vivo** — solo `#Preview` (`MetricInfoSheet.swift:1279-1289`). Ver §2.

### 1.2 Vital-template (hrv · rhr · spo2 · skin_temp · steps · stress · resp_rate)

| Estado | Qué se ve | Cita |
|---|---|---|
| Con dato | Header rediseñado + numeral Grotesk 56 + unidad (`:335-345`) + punto de origen (`vitalOriginDot :413-421`) → `vitalReading` (frase honesta por nivel activo, `:434-474`) → headline tras ⓘ → `levelsBlock` (explorador) → `vitalPatternBlock` «Tu patrón» SOLO hrv/rhr (`:482-501`; findings de `whatMovesItFindings`, `TodayView.swift:1991`, pasados en `:496`) → pie | `MetricInfoSheet.swift:196-201` |
| Sin dato «—» | Tint neutral por factory; `vitalReading` se oculta (`activeLevelKey` nil, `:425-429`); niveles fijos se dibujan sin fila activa; nota honesta por factory (HRV `MetricInfoCatalog.swift:158-160`, skin_temp `:381-383`) | `MetricInfoSheet.swift:434-441` |
| HRV sin base (niveles relativos, <1 noche válida) | `resolvedLevels` nil (`:764-775`, guard `nValid >= 1`) → `ChartWell.empty` con nota «Your levels come from your own baseline…» | `MetricInfoSheet.swift:737-741` |
| Sin permiso Salud (apple-connect) | Solo `{sleep, hrv, rhr, spo2, steps}` (`TodayView.swift:468`) y solo si `displayValue == "—"` → `appleConnectLine` en el pie (`:680-693`, montada en `:253-254`). skin_temp/stress/resp_rate NUNCA la muestran | `TodayView.swift:487` |
| Fuente Apple | `appleSource` resuelto por lectura en el caller (`TodayView.swift:472-486`) → punto «Apple Health» en el header (`:414-415`) + línea de fuente al pie (`:698-709`) | `MetricInfoSheet.swift:267` |
| Niveles cargando (serie async) | `levelsSeriesLoader` corre en `.task` (`:141-151`); mientras llega, los niveles FIJOS ya se resuelven (`:765`) → explorador con ventana vacía: nota «No readings in this range» (`MetricLevelsExplorer.swift:151`) y aviso `fellBack` (`:105-108`). Para HRV (relativo): `ChartWell.empty` hasta que la serie llegue | `MetricInfoSheet.swift:141-151` |

⚠️ **spo2 sin entry point vivo** (solo `#Preview :1261-1265`). Los otros seis abren desde Hoy (§2).
⚠️ **resp_rate tiene una entrada viva FUERA de Hoy**: el tile «Respiration» del Detalle de Sueño
(`SleepDetailScreen.swift:737-741`) — y ahí se abre SIN `levelsSeriesLoader` (solo `trendLoader`,
`:133-134`), así que rinde el explorador con ventana vacía. Estado real que el arnés debe cubrir.

### 1.3 Sleep

| Estado | Qué se ve | Cita |
|---|---|---|
| Rica (noche con etapas) | Header rediseñado SIN numeral (`:333`) → `sleepDobleDato` (horas \| regularidad /100, `:522-540`) → `sleepReading` (`:543-557`) → headline tras ⓘ → `sleepAnocheBlock` (SleepStageBar + reloj inicio→fin, `:561-578`) → `sleepActiveLaneLabel` (`:581-587`) → `levelsBlock` → `sleepParaEstaNoche` (`PaperSideBarBlock`, `:596-604`) → pie | `MetricInfoSheet.swift:206-214` |
| Regularidad pendiente | El segundo numeral lee «··» en tinta terciaria (el numeral nunca miente) | `MetricInfoSheet.swift:531-535` |
| **Cargando async el modelo** | El caller construye `SleepDetailModel` off-main al abrir (`TodayView.swift:364-373`, FER-953); mientras `sleepDetail` es nil → `isSleepSummary` false → cae a **clásica** con numeral único `instrumentoHero(46)` («7h 12m») + niveles. ⚠️ **El código NO tiene skeleton hoy**: el «skeleton async» de F5 es NUEVO, no paridad | `MetricInfoSheet.swift:505-507` |
| Sin noche / Apple sin etapas | Mismo fallback clásico de un numeral (deliberado) | `MetricInfoSheet.swift:505-507` |
| Sin dato «—» | Clásica, tint neutral | `MetricInfoCatalog.swift:129-137` |
| Sin permiso Salud | `appleConnectLine` (sleep ∈ appleCapable) | `TodayView.swift:468` |

### 1.4 Strain

| Estado | Qué se ve | Cita |
|---|---|---|
| Con dato (scored) | Header rediseñado + punto «Calculated» + sufijo «/ 21» (`:371`) → `vitalReading` (claves de nivel strain, `:467-471`) → headline tras ⓘ → `levelsBlock` | `MetricInfoSheet.swift:218-222` |
| Sin dato «—» | Clásica + niveles fijos `.strain`. Sin hint de Salud (no es appleCapable) | `MetricInfoCatalog.swift:100-106` |
| Detent por contenido | strain/heart_rate/trend/niveles miden su alto (`SheetContentHeightKey`) y fijan `.height(contentHeight)`; hojas cortas quedan en `.medium` | `MetricInfoSheet.swift:274-278` |

Nota: la curva intradía «hora a hora» se retiró en FER-1025 — el plan no la incluye y el código
tampoco la tiene. La tarjeta de Carga en Hoy abre `TrainingLoadSheet`, NO esta hoja
(`TodayView.swift:968-971`).

### 1.5 Clásica (fallback + submétricas de sueño + vo2max)

Cuerpo: headline tras ⓘ → (`usesLevels` → `levelsBlock` \| si no → `trendSection` 14d +
`bandsTable`) → `calibrationCard` si aplica → pie (`MetricInfoSheet.swift:225-248`).

| Estado | Qué se ve | Cita |
|---|---|---|
| Trend 14d con datos | `TrendChart` 140pt con bandas sombreadas si el metric es «banded» (`bandedTrend`, set `{sleep, stress, spo2, rhr, steps}`, `:1056-1093`); `rangeReadoutLine` «{banda} · X of N days/nights» arriba (`:869-882`) | `MetricInfoSheet.swift:984-1036` |
| Trend cargando | `ChartWell(theme).loading(height: 140)` | `MetricInfoSheet.swift:1030-1031` |
| Trend vacío | `ChartWell.empty` «No data for the last 14 days.» | `MetricInfoSheet.swift:1032-1033` |
| Tabla de bandas | Filas con punto/etiqueta/rango + conteo por banda cuando el trend cargó (`bandSummary`, `:832-846`); fila activa con wash del hue | `MetricInfoSheet.swift:786-825` |
| Header clásico | Overline + ⓘ (no rediseñado), numeral `instrumentoHero(46)` | `MetricInfoSheet.swift:324-330, 347-354` |

Entradas vivas de la clásica: los 6 tiles del Detalle de Sueño
(`SleepDetailScreen.swift:735-751` → `.sheet :133-134`): sleepPerformance, sleepEfficiency,
sleepRestorative, sleepLatency, sleepAwakenings (+ respiratory, que es vital-template).

### 1.6 heart_rate (clásica + curva 24h)

| Estado | Qué se ve | Cita |
|---|---|---|
| Con curva (>1 punto) | Título/subtítulo + último bpm → `TrendChart` 260pt con scrub → pie min/prom/max (`hrFooter`, `:933-955`) | `MetricInfoSheet.swift:889-923` |
| Cargando | `ChartWell.loading(height: 200)` | `MetricInfoSheet.swift:924-925` |
| Sin lecturas hoy | `ChartWell.empty` «No readings yet today.» | `MetricInfoSheet.swift:926-928` |
| Header | Clásico (overline) — heart_rate NO está en el header rediseñado | `MetricInfoSheet.swift:366` |

⚠️ **heart_rate está huérfana**: ningún `metricDetail = .heartRate(...)` existe. El
`heartRateCurveLoader` está cableado en `TodayView.swift:492` pero es inalcanzable; la única
referencia viva a la factory es como copy del detalle rico (`MetricDetailSpec.swift:193`).

### 1.7 SpO₂ (vital-template + niveles `.bloodOxygen`)

Todos los estados de §1.2 aplican (con `appleConnectHint` posible: spo2 ∈ appleCapable). La
serie de niveles existe en el caller (`levelsSeriesLoader` cubre "spo2",
`TodayView.swift:1897-1910`) — solo falta quién la abra.

---

## 2 · Entry points reales

### Hoy (TodayView) — la única superficie viva

Presentación: `.sheet(item: $metricDetail, onDismiss: …)` (`TodayView.swift:360-362`) →
`metricSheet(for:)` (`:467-499`), que resuelve `appleConnectHint`, `appleSource` POR LECTURA
(`:472-486`), y cablea `heartRateCurveLoader`/`trendLoader`/`levelsSeriesLoader`
(`:1871-1927`)/`whatMovesIt` (`:1991`)/`sleepDetail` (modelo async, `:364-373`)/`onSeeMore`
(`:511-573`).

| Entrada | ids → variante | Cita |
|---|---|---|
| Tile Liquid (`openLiquidMetric`) | `sleep, hrv, rhr, strain, steps, skintemp, resp, stress` | `TodayView.swift:1039-1061` |
| Orbe (`openLiquidSenal`) | `autonomico` → **NO abre esta hoja** (abre `showAutonomicDetail`, `:1068`); `sueno` → hoja sleep; `termico` → hoja skin_temp | `TodayView.swift:1065-1077` |
| Héroe (`onTapHero`) | `.autonomic` → detalle autonómico; `.sleep` → hoja sleep | `TodayView.swift:973-981` |
| Superficie clásica (solo `noSources`, `:676-691`) | héroe sueño (`:1166`) + filas sleep/hrv/rhr/strain/steps/skin_temp/resp/stress (`:1461-1539`) | `TodayView.swift:1461-1539` |

**No cableados desde Hoy (C5 ✓): `spo2`, `heart_rate`, `recovery`.** Peor aún que lo que el
plan asumía: **no tienen NINGÚN entry point vivo en toda la app** (recovery abre su detalle
rico `RecoveryDetailScreen` desde Cuerpo; spo2 y heart_rate solo existen como `#Preview` /
copy del detalle). Para F1-F5 su verificación es arnés + `#Preview`; si F6 quiere exponerlas
necesita wiring NUEVO → decisión de dueño (§dudas).

### Cuerpo — el dead path (C1 ✓)

- `@State private var metricInfo: MetricInfo? = nil` — `CuerpoView.swift:190`
- `.sheet(item: $metricInfo) { info in metricSheet(for: info) }` — `CuerpoView.swift:337`
- builder `metricSheet(for:)` — `CuerpoView.swift:1228-1238`

`metricInfo` **nunca se asigna** (verificado por grep: cero escrituras). Los vitales de Cuerpo
abren `MetricDetailScreen` (detalle rico). Además el builder muerto es más pobre que el de Hoy
(sin `onSeeMore`, sin niveles, sin `whatMovesIt`, sin `sleepDetail`). **F6 = borrar estas tres
piezas en Cuerpo**; `MetricDetailScreen` queda FUERA del épico.

### SleepDetailScreen — entrada viva que el plan NO contempló

`.sheet(item: $metricInfo)` (`SleepDetailScreen.swift:133-134`) desde los tiles «Tonight's
metrics» (`:735-751`): 5 submétricas clásicas + respiración (vital-template). D5 las declara
FUERA del épico, pero **son instancias de `MetricInfoSheet`**: el F6 del plan («se borra el
código Instrumento de MetricInfoSheet») es imposible tal cual sin decidir qué pasa aquí
(§dudas abiertas, D1).

---

## 3 · Props por componente Liquid

**Contrato de props (D3):** todo dato llega RESUELTO y todo string llega YA LOCALIZADO
(`String`, jamás `LocalizedStringKey` — mismo contrato que `LiquidMetricTile`/`LiquidHoyModel`
y que `ZoneMeter.Segment.label` hoy). Sin loaders, sin `InstrumentoTheme`, sin acceso a repo.
Los closures de formato síncronos y puros (p. ej. formatear el punto bajo el dedo en el scrub)
SÍ se permiten — son función, no loader. Los componentes viven en
`Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/`.

### F1 — cascarón

```swift
// Fondo + velo + detents; el grip lo pone el sistema (presentationDragIndicator).
// Reusa LiquidSheetFondo (YA acuñado) como presentationBackground.
public struct LiquidMetricSheet<Content: View>: View {
    public let tono: Color                 // hue de la métrica (tiñe el fondo al 4 %)
    public let detent: LiquidSheetDetent   // .medio | .porContenido (paridad :274-278)
    @ViewBuilder public let content: () -> Content
}

public struct LiquidSheetHeader: View {
    public struct Props {
        public let icono: LiquidIcon.Glyph?    // gota SF 24 (nil = recovery, sin glifo)
        public let titulo: String              // «HRV» ya localizado
        public let tono: Color                 // hue de la métrica (LiquidColor.*)
        public let numeral: String?            // «66» / «7h 12m» / «2/4» / «—»; nil = sleep rica
        public let unidad: String?             // «ms» — LiquidType.numeralHojaUnidad
        public let sufijo: String?             // «/ 100» · «/ 21» (paridad :369-373)
        public let numeralTono: Color          // resuelto por el caller (banda/neutral/hue)
        public let origen: LiquidOrigen?       // .medido | .calculado → LiquidOrigenDot
        public let origenEtiqueta: String?     // «Apple Health» / «Calculado» ya localizado
        public let explicacion: String         // headline; el ⓘ (estado interno) la pliega/despliega
        public let a11yLabel: String
    }
}
```

### F2 — lectura, zonas, patrón

```swift
public struct LiquidReadingLine: View {      // recoveryReading / vitalReading / sleepReading
    public let texto: String                 // frase ya localizada (catálogo de :443-474)
}

public struct LiquidZoneMeter: View {        // reemplaza ZoneMeter en la hoja (§4)
    public struct Segmento {
        public let peso: Double              // span de la zona (paridad :633-639)
        public let color: Color              // LiquidColor.positivo/atencion/negativo
        public let activa: Bool
        public let etiqueta: String          // «ALTO» ya localizado y uppercased
    }
    public let segmentos: [Segmento]
    public let fraccion: Double?             // nil = sin tick (sin lectura)
}

public struct LiquidPatternBlock: View {     // «Tu patrón» y «Para esta noche» (una sola pieza)
    public let overline: String              // ya localizado
    public let lineas: [String]              // frases resueltas (findings ya en texto)
    public let tono: Color                   // barra lateral
}
```

### F3a — host de niveles (capa app, `Cenit/`, SIN UI nueva)

```swift
// Extrae de MetricInfoSheet el wiring puro: @State range + serie parseada una vez
// (:70-73, :141-151) + resolvedLevels con caché (:744-784, incl. el fold HRV con
// Baselines.normalRange) + MetricWindowMath.make. Tests de paridad numérica
// obligatorios: mismos niveles/conteos/ventana que hoy, bit a bit.
@Observable final class MetricLevelsHostModel { … }   // en Cenit/Screens/ o Cenit/Data/
```

### F3b — explorador Liquid (piel; interacción intacta, I1-I3)

```swift
public struct LiquidRangeSelector: View {    // I3: RECTANGULAR (LiquidChart.selectorRadio = 12)
    public let opciones: [String]            // «S M 3M 6M 1A TODO» ya localizadas
    @Binding public var seleccion: Int       // índice — el app mapea a ExploreRange (tipo app)
}

public struct LiquidGraficaNiveles: View {   // consume LiquidChart.* (ya acuñados)
    public struct Banda { public let lo, hi: Double?; public let color: Color; public let activa: Bool }
    public let puntos: [(fecha: Date, valor: Double)]   // ventana YA cortada por el host
    public let bandas: [Banda]                          // I1: washes 8/16/3 (LiquidChart)
    public let dominio: ClosedRange<Double>
    public let ticksY: [(valor: Double, etiqueta: String)]  // etiquetas YA formateadas
    public let tono: Color
    public let puntoHoy: (fecha: Date, valor: Double)?      // joya endpoint; anillo hueco si exploras otro nivel
    public let hoyAnillo: Bool                              // paridad markedPointHollow (:145)
    public let formatoScrub: (Double, Date) -> String       // «56 ms · mar 14» — puro, síncrono
    public let estadoVacio: String                          // «Sin lecturas en este rango» localizado
    public let a11yLabel: String
}

public struct LiquidLevelRow: View {         // fila tocable de la lista de niveles
    public let etiqueta: String              // «En tu base»
    public let rango: String                 // «49–71» ya formateado
    public let conteo: String                // «12 días» ya formateado (BandSummaryCopy en el app)
    public let esHoy: Bool                   // anillo hueco (paridad :231-237)
    public let activa: Bool
    public let tono: Color
    public let onTap: () -> Void
}
```

### F4 — template clásico

```swift
public struct LiquidTrendChart: View {       // trend 14d (misma gramática que LiquidGraficaNiveles)
    public let titulo: String                // «Últimos 14 días»
    public let readout: (etiqueta: String, tono: Color, frase: String)?  // «{banda} · X de N…»
    public let puntos: [(Date, Double)]
    public let bandas: [LiquidGraficaNiveles.Banda]
    public let dominio: ClosedRange<Double>
    public let ticksY: [(Double, String)]
    public let tono: Color
    public let formatoScrub: (Double, Date) -> String
    public let estado: LiquidChartEstado     // .datos | .cargando | .vacio(String)
}

public struct LiquidBandsTable: View {
    public struct Fila { public let etiqueta, rango: String; public let conteo: String?; public let activa: Bool }
    public let filas: [Fila]
    public let tono: Color
}

public struct LiquidCurvaFC: View {          // curva 24h de heart_rate
    public let titulo: String                // «Pulsaciones por minuto»
    public let subtitulo: String             // «Promedio de 5 min · desde medianoche»
    public let ultimo: String?               // «72 bpm»
    public let puntos: [(Date, Double)]
    public let dominio: ClosedRange<Double>  // hrRange ya calculado (paridad :967-972)
    public let stats: (min: String, prom: String, max: String)?  // ya formateados
    public let formatoScrub: (Double, Date) -> String
    public let estado: LiquidChartEstado
}

public struct LiquidCalibracionCard: View {
    public let titulo: String                // «Calibrando tu base»
    public let leyenda: String               // «2 de 4 noches» ya localizado
    public let hechas: Int
    public let necesarias: Int
    public let tono: Color
}
```

### F5 — sueño (4 piezas + skeleton)

```swift
public struct LiquidDobleDato: View {
    public let principal: (valor: String, etiqueta: String)   // («7:12», «horas dormido»)
    public let secundario: (valor: String, etiqueta: String)  // («84» o «··», «regularidad»)
    public let tono: Color
}

public struct LiquidStageBar: View {         // reemplaza SleepStageBar en la hoja (§4)
    public struct Etapa { public let minutos: Double; public let color: Color
                          public let etiqueta: String; public let duracion: String } // «1:31» resuelto
    public let etapas: [Etapa]
    public let overline: String              // «Anoche»
    public let ventana: String               // «23:38 → 7:04» ya formateado
}

public struct LiquidLaneLabel: View {        // lane activa sobre el selector
    public let texto: String                 // «ÓPTIMO · ANOCHE» ya compuesto
    public let tono: Color
}

// «Para esta noche» reusa LiquidPatternBlock (F2).

public struct LiquidSheetSkeleton: View { }  // NUEVO (no existe hoy, ver §1.3): placeholder
                                             // redacted mientras buildDetached entrega el modelo
```

### Pie / método / Ver más

```swift
public struct LiquidMetodo: View {           // plegable (estado interno, como Metodo)
    public let titulo: String                // «Cómo se calcula»
    public let prosa: String
    public let cita: String?
}

public struct LiquidSheetPie: View {
    public let nota: String?                 // note del catálogo
    public let disclaimer: String?
    public let fuente: String?               // «Apple Health» (línea + glifo corazón)
    public let conectaSalud: String?         // línea apple-connect; nil = oculta
    public let verMas: (titulo: String, estilo: VerMasEstilo, action: () -> Void)?
    public enum VerMasEstilo { case tendencias   // botón full-width con borde (paridad :1187-1208)
                               case detalle }    // pastilla trailing (paridad :1209-1230)
}
```

---

## 4 · Decisión por pieza acoplada (C3)

C3 confirmada: las tres piezas acoplan `InstrumentoTheme`/`InstrumentoType` y NO se reutilizan
tal cual.

| Pieza | Acople real | Decisión | Justificación (una línea) |
|---|---|---|---|
| `ZoneMeter` (`Packages/StrandDesign/Sources/StrandDesign/ZoneMeter.swift:17-102`) | `theme.ink` (tick), `theme.inkTertiary` (labels), `InstrumentoType.grotesk(8)` | **Variante Liquid nueva** (`LiquidZoneMeter`, rebuild ligero copiando la geometría de pesos `:56-61`) | La geometría son ~30 líneas triviales; parametrizar el tema ensuciaría el componente papel que Instrumento sigue usando. |
| `SleepStageBar` (`Packages/StrandDesign/Sources/StrandDesign/SleepStageBar.swift:14-82`) | `theme` en init, `InstrumentoType.grotesk(9)` en la leyenda | **Variante Liquid nueva** (`LiquidStageBar`) | Misma razón; además la variante Liquid absorbe overline + ventana horaria (hoy montadas fuera, `MetricInfoSheet.swift:563-575`) y recibe duraciones ya formateadas. |
| Chart del explorador (`TrendChart.swift:147-762` vía `MetricTrendChart` vía `MetricLevelsExplorer.swift:129-153`) | Fuentes `StrandFont` hardcodeadas en ejes/tooltip; colores inyectables pero tooltip/haptics Instrumento | **Re-vestir, no rediseñar ni rebuild total**: `LiquidGraficaNiveles` nueva en el DS que REUSA las piezas de interacción ya públicas — `scrubGesture` (`TrendChart.swift:642`), `CrosshairRule` (`ChartScrub.swift:172`, con alfa `LiquidChart.scrubReglaAlfa`) y el anillo del punto (paridad `HighlightDot` flat, `ChartScrub.swift:201`) — y pinta con `LiquidChart.*` | La interacción es la parte cara y los invariantes I1-I3 la congelan; `TrendChart` no puede re-skinearse in place porque lo comparten N pantallas papel. |

**Invariantes del dueño, mapeados a código y a tokens ya acuñados:**
- **I1 (glow/luminosidad del seleccionado):** banda activa iluminada — hoy `bandLayer` activa
  al 0.16 (`TrendChart.swift:586-604`) y `GraficaRangos` con washes 8/16/3; los tokens F0
  eligieron la paridad `GraficaRangos` (`LiquidChart.bandaReposoAlfa/bandaActivaAlfa/bandaApagadaAlfa`,
  `LiquidChartTokens.swift:29-36`). ⚠️ Nota: la hoja ACTUAL dibuja con `TrendChart` (activa 0.16,
  resto sin wash) — F3b adopta los valores `LiquidChart` (más ricos), documentado aquí para que
  `/qa` no lo marque como regresión de paridad.
- **I2 (scrubber vertical):** regla vertical + anillo + chip — `CrosshairRule` punteada
  (`ChartScrub.swift:183-193`) + `HighlightDot` plano (anillo sobre papel, `:201-220`) +
  tooltip; tokens `LiquidChart.scrubRegla*/scrubAnillo*/scrubChip*` (`LiquidChartTokens.swift:38-51`).
- **I3 (selector RECTANGULAR):** `SegmentedPillControl` es «ALWAYS the rounded-RECT look»
  desde 2026-07-15 (`Components.swift:108-111`); token `LiquidChart.selectorRadio = LiquidRadius.control`
  (12, «NUNCA cápsula», `LiquidChartTokens.swift:53-59`). La propuesta original de «pastillas»
  en F3b queda corregida.

---

## 5 · Tokens a acuñar en F0

⚠️ **Discrepancia mayor plan-vs-código (a favor):** F0 ya está PARCIALMENTE ENTREGADO en esta
misma rama (`blandisc/inject-hoy-liquid-pulido`, commit `aeadc0df`), pendiente de PR/merge:

**Ya acuñados (verificados en código, con `#Preview`):**

| Token | Valor | Cita |
|---|---|---|
| `LiquidType.numeralHoja` | Grotesk **34** tabular, `relativeTo: .largeTitle` | `LiquidType.swift:43` |
| `LiquidType.numeralHojaUnidad` | system 13 | `LiquidType.swift:45` |
| `LiquidSheetFondo` (receta vidrio/hoja) | degradado `fondoAlto→fondoBajo` + suspiro del tono al 4 %, para `presentationBackground`; grip del sistema | `LiquidGlassRecipes.swift:196-221` |
| `LiquidChart.lineaAncho / lineaSecundariaAncho` | 1.6 / 1.2 | `LiquidChartTokens.swift:19-21` |
| `LiquidChart.gridAlfa` | 0.10 | `LiquidChartTokens.swift:23` |
| `LiquidChart.endpointRadio / endpointBorde` (joya) | 2.8 / 1.2 | `LiquidChartTokens.swift:25-27` |
| `LiquidChart.bandaReposoAlfa / bandaActivaAlfa / bandaApagadaAlfa` (I1) | 0.08 / 0.16 / 0.03 | `LiquidChartTokens.swift:32-36` |
| `LiquidChart.scrubReglaAlfa / scrubReglaAncho / scrubAnilloDiametro / scrubAnilloBorde / scrubChipAlto / scrubChipFuente` (I2) | 0.35 / 1 / 10 / 2.5 / 16 / groteskNumber 9.5 sb | `LiquidChartTokens.swift:40-51` |
| `LiquidChart.selectorRadio / selectorAlto` (I3) | `LiquidRadius.control` (12) / 28 | `LiquidChartTokens.swift:57-59` |

⚠️ El plan D2 hablaba de un numeral «dato héroe de hoja» tipo 56; F0 decidió **34 tabular +
unidad 13**. El contrato adopta la decisión de F0 (el código gana).

**Existentes que se REUTILIZAN (no acuñar):** `LiquidRadius.hoja` (28) / `.tarjeta` (18) /
`.control` (12) / `.pastilla` (`LiquidLayout.swift:42-51`); `LiquidSpace.s050…s1400`
(`LiquidLayout.swift:8-27`); `LiquidColor.tinta900/700/500`, `papel*/fondo*`, `vidrio*`
(especular/bordes/streak/lente/pastilla/superficie), semánticos `positivo/atencion/negativo/
atencionTexto` y hues de métrica `indigo/cian/rosa/ambar/teal/azul/oro` (`LiquidColor.swift`);
recetas `.liquidGlass(.superficie/.pastilla/.pastillaElevada/.lente)` + `LiquidVeil`
(`LiquidGlassRecipes.swift:16-64, 155-194`); `LiquidMotion.sheet/sheetDuration/entrada/
entradaStagger/selector/press/lift` (`LiquidMotion.swift`); `LiquidType.titulo/kicker/micro/
microEstado/label/caption/cuerpo/datoMenor/valorL/unidad` (`LiquidType.swift`); átomos
`LiquidIconDrop`, `LiquidOrigen` (.medido/.calculado) + `LiquidOrigenDot`, `LiquidDeltaCaption`
(`LiquidAtoms.swift`); `LiquidElevation.e0…e3` (`LiquidLayout.swift:72-99`).

**Restante de F0 (criterio de cierre):** ningún token bloqueante pendiente. Candidatos menores
que F1/F4 pueden acuñar si duelen inline: altos de gráfica (260 curva FC / 140 trend / 168
explorador — hoy números inline en `MetricInfoSheet.swift:920, 1001, y MetricLevelsExplorer.swift:137`)
y el alto del skeleton de F5.

---

## 6 · Criterios de aceptación por fase

**Gates transversales (aplican a TODA fase):**
- [ ] `cd Packages/StrandDesign && swift build && swift test` verde.
- [ ] C4: el flag `liquidSheet` nace `false` y NO se voltea en ningún PR antes de F6 (mismo
  patrón que `liquidDemo`, `TodayView.swift:936` — que hoy está en `true` por la sesión
  /inject viva: el cutover de F6 debe verificar AMBOS flags).
- [ ] C5: cada variante/estado nuevo se agrega a `LiquidSheetEstadosRenderTests`
  (`Packages/StrandDesign/Tests/StrandDesignTests/`, mismo patrón que
  `LiquidHoyEstadosRenderTests`: macOS `ImageRenderer`, `\.liquidMotionDisabled = true`,
  PNG por estado a `/tmp/noop-liquid/`, `swift test --filter LiquidSheetEstadosRenderTests`).
- [ ] design-lint verde; ningún hex/fuente/espaciado inline nuevo fuera de tokens.
- [ ] Carriles (D6): F0, F3a/F3b, F5, F6 = PESADO con `/qa` independiente usando ESTA matriz
  (§1) como criterios; F1/F2/F4 = ligero (flag + preview).

**F0 · Tokens (pesado — parcialmente entregado, commit `aeadc0df`)**
- [ ] PR con `LiquidChartTokens.swift`, `numeralHoja(+Unidad)` y `LiquidSheetFondo` mergeado a `iOS`.
- [ ] Cada token con `#Preview` que lo ejercita (ya existen: `LiquidChartTokens.swift:63-118`,
  `LiquidType.swift:152`, preview de recetas `LiquidGlassRecipes.swift:255`).
- [ ] `/qa`: los valores I1-I3 del preview coinciden con §4 de este contrato.

**F1 · Cascarón (ligero)**
- [ ] `LiquidMetricSheet` + `LiquidSheetHeader` + `LiquidSheetPie` skeleton compilan en el DS
  sin `InstrumentoTheme` ni `LocalizedStringKey` (grep en CI del arnés: cero ocurrencias en
  `LiquidGlass/`).
- [ ] Detents con paridad: `.medium` hojas cortas; `.height(contenido)` para strain/heart_rate/
  trend/niveles (`MetricInfoSheet.swift:274-278`).
- [ ] Header reproduce los 4 orígenes (Calculated / Apple Health / medido / sin origen) y el ⓘ
  pliega la explicación.
- [ ] Hoy sigue abriendo la hoja Instrumento INTACTA (flag en false). ⌘R del dueño (hito).
- [ ] Estados de F1 en el arnés (header por variante × con/sin dato).

**F2 · Lectura + zonas + patrón (ligero)**
- [ ] `LiquidReadingLine`, `LiquidZoneMeter`, `LiquidPatternBlock` con `#Preview` por estado.
- [ ] `LiquidZoneMeter`: pesos proporcionales (25/25/20/18/12 en recovery), tick en
  `fraccion`, sin tick con `fraccion == nil` — paridad `ZoneMeter :56-81`.
- [ ] Las frases vienen del MISMO catálogo de copy (`vitalReadingText :443-474`,
  `recoveryReadingText :615-622`, `sleepReadingText :549-557`) — cero copy nuevo sin `/pm`.
- [ ] Arnés: recovery scored (3 bandas de tint), vital con dato, vital sin dato (línea oculta).

**F3a · Host de niveles (pesado)**
- [ ] `MetricLevelsHostModel` en el app SIN UI nueva; la hoja Instrumento sigue idéntica.
- [ ] Tests de paridad numérica: niveles resueltos (incl. HRV `Baselines.normalRange` con
  guard `nValid >= 1`, `MetricInfoSheet.swift:764-775`), conteos por nivel, ventana
  (`MetricWindowMath.make`) y caché (`resolvedLevelsKey :748-750`) — iguales bit a bit a los
  actuales, con serie sintética fija.
- [ ] La política «quién tira el día parcial» se conserva vía `MetricDetailSpec.accumulatesToday`
  (`TodayView.swift:1920-1924`).
- [ ] `/qa` independiente PASS.

**F3b · Explorador Liquid (pesado)**
- [ ] `LiquidRangeSelector` + `LiquidGraficaNiveles` + `LiquidLevelRow` consumen SOLO
  `LiquidChart.*`/`LiquidColor.*`/`LiquidType.*`.
- [ ] I1: banda activa 0.16, reposo 0.08, apagadas 0.03 — verificado en render del arnés.
- [ ] I2: regla vertical + anillo 10/2.5 + chip en scrub — gesto idéntico
  (`scrubGesture`/snap/haptic reusados, no reimplementados).
- [ ] I3: selector rectangular radio 12, NUNCA cápsula.
- [ ] Tocar un nivel resalta su banda y re-lee la frase; re-tocar limpia; hoy conserva anillo
  hueco (paridad `MetricLevelsExplorer :53-55, 194-237`).
- [ ] Estados: con dato · sin lectura hoy · ventana vacía (`fellBack`) · HRV sin base — al arnés.
- [ ] ⌘R del dueño (hito visible). `/qa` PASS.

**F4 · Template clásico (ligero)**
- [ ] `LiquidTrendChart` (3 estados: datos/cargando/vacío), `LiquidBandsTable` (conteos
  opcionales + fila activa), `LiquidCurvaFC` (3 estados + min/prom/max), `LiquidCalibracionCard`.
- [ ] El readout «{banda} · X de N días/noches» vive UNA vez, arriba de la tabla (paridad
  FER-469/471, `MetricInfoSheet.swift:852-882`).
- [ ] heart_rate y spo2 renderizan en arnés/#Preview aunque no tengan entry point vivo (C5).

**F5 · Sueño (pesado)**
- [ ] `LiquidDobleDato` (incl. «··» de regularidad), `LiquidStageBar` (rampa de opacidad
  indigo deep→REM→light + awake en tinta, paridad `:570-575`), `LiquidLaneLabel`,
  «Para esta noche» vía `LiquidPatternBlock`, `LiquidSheetSkeleton`.
- [ ] El skeleton async es NUEVO comportamiento (hoy cae al layout clásico, §1.3): el arnés
  cubre skeleton → rica y skeleton → fallback clásico (sin noche).
- [ ] Los 4 estados de sueño (rica / cargando / sin-noche / sin dato) al arnés. `/qa` PASS.
- [ ] ⌘R del dueño (hito visible).

**F6 · Cutover atómico (pesado)**
- [ ] Hoy: `metricSheet(for:)` presenta la hoja Liquid para TODAS las variantes cableadas; el
  flag `liquidSheet` desaparece (no queda flag muerto).
- [ ] Cuerpo: se borra el dead path completo (`CuerpoView.swift:190, 337, 1228-1238`).
- [ ] Resolución de la duda D1 (abajo) implementada para `SleepDetailScreen.swift:133-134`.
- [ ] Se borra el código Instrumento de la hoja que quedó huérfano (D7: solo tras cutover
  verde) — incluyendo `ZoneMeter`/`SleepStageBar` SI ya nadie los usa (verificar por grep, no
  por suposición).
- [ ] `/qa` PASS con §1 como checklist por variante × estado; captura por variante; CHANGELOG;
  `/simplify`; PR con label `ci-app` (toca `Cenit/**`).
- [ ] `xcodegen generate` + build de app verde tras esperar `pgrep swift-frontend`.

---

## Dudas abiertas — requieren decisión del dueño

1. **SleepDetailScreen usa `MetricInfoSheet` (6 tiles vivos)** y el plan la excluye (D5) pero
   ordena borrar la hoja Instrumento en F6. Opciones: (a) F6 también cambia esa `.sheet` a la
   hoja Liquid (las 5 submétricas son variante clásica — «gratis» con F4); (b) conservar una
   `MetricInfoSheet` recortada solo-clásica para ese uso (contradice D7). **Recomendación: (a).**
2. **spo2 / heart_rate / recovery no tienen NINGÚN entry point vivo** (ni en Hoy ni en ningún
   lado; §1.6-1.7, §2). ¿F6 les cablea entrada (¿tile/orbe nuevo? — alcance nuevo, pasa por
   `/pm`) o quedan como variantes construidas verificables solo por arnés/#Preview (C5)?
   **Recomendación: solo arnés en este épico; wiring en un issue aparte.**
3. **Copy legado «Band · last night» / «Band»** en el punto de origen del header
   (`MetricInfoSheet.swift:416-419`): en el mundo Apple-only sin banda ese rótulo miente.
   ¿La hoja Liquid lo reemplaza en F1 (p. ej. «Medido · anoche») o se copia tal cual por
   paridad? **Recomendación: reemplazar en F1, con `/pm` para el copy.**
4. Menor: los washes de banda del explorador cambian de los de `TrendChart` (0.16 activa,
   resto sin wash) a los de `LiquidChart` (8/16/3, paridad `GraficaRangos`) — ya adoptado en
   §4; solo se lista para que el dueño lo vea en el primer ⌘R de F3b.
