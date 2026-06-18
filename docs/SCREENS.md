# NOOP iOS — Inventario de Pantallas

**Fuente de verdad textual** del mapa de pantallas. La representación visual vive en [`docs/screen-map.html`](screen-map.html).

## 🗺️ Mapa visual interactivo

[`docs/screen-map.html`](screen-map.html) es un mapa tipo flow de Figma con **screenshots reales** de cada pantalla (marcos de iPhone + conectores de navegación).

**Para abrirlo:** doble clic en `docs/screen-map.html` (o `open docs/screen-map.html`). No necesita servidor — las imágenes cargan por ruta relativa. Hazle bookmark en el navegador la primera vez para tenerlo a un clic.

**Para regenerar las capturas** (`docs/fixtures/*.png`) cuando cambies una pantalla — un solo comando (necesita Xcode + simulador iOS):

```bash
./Tools/update-screen-map.sh                 # iPhone 17 Pro Max por defecto
./Tools/update-screen-map.sh "iPhone 16"     # otro simulador
```

Corre el UI test `NOOPScreenshotTests`, copia las PNGs al repo y sube la fecha del toolbar. Luego commitea los cambios en `docs/`.

**Recordatorio automático:** hay un git hook (`.githooks/pre-commit`) que avisa si commiteas un `*View.swift` sin actualizar el mapa. Habilítalo una vez (en `~/code/noop`; los worktrees lo heredan):

```bash
git config core.hooksPath .githooks
```

**Regla de mantenimiento:** si tu PR modifica un `*View.swift`, actualiza la sección correspondiente aquí y en el array `SCREENS` de `screen-map.html` (la fecha del toolbar la sube el script). Mismo PR, no opcional.

---

## Estructura de navegación global

```
Tab shell (FER-182) → 5 pestañas: Hoy · Cuerpo · Coach · Entrenar · Ajustes
  Hoy      → TodayView
  Cuerpo   → CuerpoView (landing curado de la capa «historia», FER-186)
  Coach    → hub-lista → IntelligenceView · InsightsView · CoachView
  Entrenar → hub-lista → «Iniciar en vivo» (LiveWorkoutHubRow) · BreathingView · IntervalTimerView
  Ajustes  → SettingsView + sección «Más» → MetricExplorerView · CompareView ·
             WorkoutsView · AppleHealthView · DataSourcesView · AutomationsView · SupportView
             (Sueño · Health · Stress se mudaron a «Cuerpo» como métricas — FER-186)
SettingsView → WhatsNewView (sheet)
TodayView   → LiveView (sheet, detente grande) · MetricInfoSheet (sheet; incl. Recuperación — hoja resumida, FER-232) · MetricDetailScreen (sheet, .focus: HRV/FC reposo — FER-185) · WhyVerdictSheet (sheet) · SupportView (toolbar)
CuerpoView  → RecoveryDetailScreen (sheet «Instrumento»: Recuperación — FER-225) ·
             StrainDetailScreen (sheet claro «Instrumento»: Esfuerzo del día — FER-238) ·
             MetricInfoSheet (sheet claro: SpO₂/FC/Pasos) ·
             MetricDetailScreen (sheet claro, .full: HRV/FC reposo/Respiración — FER-185) ·
             StressDetailScreen (sheet claro «Instrumento»: Estrés — valor de hoy + bandas universales + qué lo mueve + ⓘ por concepto — FER-241) ·
             BodyAgeSheet (sheet claro: Edad corporal + Vitalidad — FER-145) ·
             SleepDetailScreen (sheet claro «Instrumento»: Sueño + regularidad del horario — FER-212) ·
             WorkoutsView · CompareView · MetricExplorerView · DataSourcesView ·
             MetricDetailView (Temp. piel) — los oscuros como sheet fijado a .dark (FER-186)
WorkoutsView → ManualWorkoutSheet (sheet: add / edit)
LiveWorkoutHubRow → LiveWorkoutSheet (sheet, detente medio — grabación en vivo, FER-197)
MetricExplorerView → MetricDetailView (NavigationLink push, sobre el stack de la pestaña «Ajustes» — FER-171)
```

**Barra de pestañas — «Barra de instrumento»** (`CenitApp/App/InstrumentTabBar.swift`, FER-163; reorganizada a
5 tabs en FER-182). Barra inferior custom (la nativa va oculta con `.toolbar(.hidden, for: .tabBar)`, montada vía
`safeAreaInset`) que **adapta su tratamiento a la pestaña activa**: bajo **Hoy** (papel «Instrumento diurno») viste
el papel y respira con la hora (`instrumentoThemeByHour`); bajo Cuerpo / Coach / Entrenar / Ajustes usa el
`StrandPalette` oscuro. El color scheme (barra de estado) sigue la pestaña: solo Hoy es clara (`isLightTab` en
`RootTabView`); En vivo es papel claro pero vive en una **hoja** (`.sheet`) sobre Hoy, no es pestaña (FER-190). La pestaña activa se marca
con tinta + un punto de «ahora» (verde recovery en claro, `accent` en oscuro), nunca con relleno verde. Íconos de
trazo fino: **Hoy** = glifo de dial 24h (`DialTabGlyph`, StrandDesign), el resto glifos de línea (Cuerpo
`chart.xyaxis.line` · Coach `sparkles` · Entrenar `figure.strengthtraining.functional` · Ajustes `gearshape`).

**Nota — «Iniciar en vivo» en el hub Entrenar (FER-197):** el hub Entrenar suma, arriba de Breathe/Intervals, una
fila **«Iniciar en vivo»** (`LiveWorkoutHubRow`, tema oscuro `StrandPalette` como las demás filas). Está
**deshabilitada con un hint** cuando no hay HR en vivo (misma señal que `LiveView`: strap puesto + `bpm`); al
tocarla arranca (`AppModel.startWorkout`) y abre `LiveWorkoutSheet`, una **hoja en «Instrumento» claro** (tema
pasado **explícito** — no se hereda por `.sheet`) con overline **GRABANDO**, cronómetro, **Ritmo / Prom / Pico**
(sin strain) y **Terminar** (`endWorkout`). La grabación vive en `AppModel` (global): cerrar la hoja o cambiar de
pestaña no la detiene; mientras corre, la fila muestra **«Grabando m:ss»** y la reabre. Al terminar, una fila
efímera confirma **«Sesión guardada …»** o avisa el **descarte** (terminó sin HR, `lastWorkoutDiscarded`); la
sesión se guarda como `WorkoutRow` manual y aparece en Workouts (re-etiquetable). Restaura el tracker que se quitó
de En vivo en FER-184; **no toca `LiveView`**.

---

## Dashboard

### TodayView
**Archivo:** `Cenit/Screens/TodayView.swift`  
**Descripción:** Hub principal — número de recuperación dominante, palabra del veredicto, dial de 24h y la rejilla **«Métricas de hoy»** (foto intradía). Reingenierizado al lenguaje **«Instrumento diurno»** en iOS (papel cálido que cambia de tono con la hora del día; color saturado solo en el dato) — FER-135.

| Estado | Condición de entrada |
|--------|---------------------|
| Empty / First launch | Ningún strap visto, sin base importada |
| Base lista (Apple Health) | `hasImportedBaseline` — base sembrada por import (≥4 noches HRV en `repo.days`) y `ownNights < 4`, sin lectura de hoy → `importedBaselineHero` |
| Calibrando (1–3 noches) | Strap visto, `ownNights < 4`, **sin** base importada → `CalibrationProgressCard` |
| Sin lectura de hoy | Strap visto, base propia ≥4 noches, sin offload de hoy |
| Veredicto listo | Recovery score calculado |

**Nota — héroe «Instrumento diurno» (iOS, FER-135 · supersede FER-113):** el héroe reingenierizado muestra **un número dominante** —la recuperación 0–100 en su **color de banda** (`recoveryDataColor`: verde `dataRecovery` / amarillo `warning` / rojo `critical`, por el umbral `RecoveryScorer.band`)— con el **dial de 24h** (`DiurnalDial`, 94px) a su derecha (hora actual + ventana de sueño on-device vía `SleepWindowClock` + amanecer/atardecer vía `SolarClock`, todo en tinta). Debajo, la **palabra del veredicto** en su propio color de nivel (`verdictDataColor`, independiente del número → pueden divergir) con una **«i»** pegada que abre `WhyVerdictSheet`; el puente reconciliador (`Readiness.bridge`) y la salvedad de noche corta se conservan. La síntesis vieja de 3 celdas (Recuperación/HRV/Sueño) se **fundió**: la recuperación es el héroe, HRV y Sueño bajaron a «Métricas clave». Tocar el número abre el detalle de recuperación. El héroe «dos verdades» (cajas Veredicto/Recuperación), el enlace al pie «¿Por qué {veredicto}?» y `RecoveryRing`/`ReadinessGaugeBar` se retiraron del iOS. Todo el subárbol lee `@Environment(\.instrumentoTheme)`, inyectado por hora con `.instrumentoThemeByHour(solar:)` sobre el lienzo `PaperBackground`.

**Nota — héroe unificado (iOS, FER-160 · consolida FER-135/106):** los cuatro layouts del héroe (`emptyHero`/`importedBaselineHero`/`CalibrationProgressCard`/`verdictSection`) se fundieron en **un solo esqueleto** —`heroInstrument`— parametrizado por un enum `HeroState` (`verdict` / `importedBaseline` / `calibrating(nights)` / `waiting`), derivado de las mismas señales de solo-lectura (`heroState`). Estructura común: overline + **numeral dominante** (`heroNumeral`) + `DiurnalDial` (94px) + **cuerpo** (`heroBody`) + **pie** (`heroFooter`). Invariante **«color = listo / tinta = en espera»**: el numeral lleva color de banda solo con veredicto real; va en **tinta** (`ink`) cuando el nivel es `insufficient` (hay número, no hay contexto → numeral en tinta + línea "Aún sin contexto suficiente para un veredicto del día", **sustituye** el caso que antes caía al anillo `heroSection`); **`N/4`** en tinta mientras calibra; **em-dash `—`** en tinta en espera/base Apple. El pie se adapta por modo (pulso vivo / atajo Apple Salud + pulso / CTA "Buscar strap"). El anillo `heroSection`/`RecoveryRing` queda **solo** en `macBody` (macOS, fuera de alcance).

**Nota — héroe concéntrico (iOS, FER-169 · refina FER-160/164):** el `heroInstrument` pasó de *numeral al lado del dial* a un **instrumento concéntrico centrado**: el `DiurnalDial` crece a **180px** y el `heroNumeral` se **superpone en su centro** (vía `ZStack`), sobre un eje vertical centrado (overline + dial-con-numeral + cuerpo). El número de recuperación se centra en el eje del dial gracias a un **«/100» espejo invisible** (`.hidden()`) que balancea el ancho del «/100» visible —que se conserva a la derecha—; misma técnica para el `N/seed` de calibración. Los cuerpos de cada estado (`heroBody`) se **centran**; el pie (`heroFooter`) y la barra de confianza siguen a lo ancho. El `DiurnalDial` **no** cambia su API ni sus colores (FER-165): solo recibe el numeral encima del centro que antes dejaba vacío a propósito. Numeral `instrumentoHero(88→60)` para caber dentro del anillo sin tocar la banda de sueño ni el punto «ahora».

**Nota — narrativa de onboarding por fuente de datos (FER-106, iOS):** los estados previos al primer veredicto reconocen de dónde viene la base. La señal de lectura `hasImportedBaseline` (≥`minNightsSeed` noches con HRV válida en `repo.days` **y** `ownNights < minNightsSeed`) significa "la base la sembró Apple Health, no la banda" y enruta al modo `importedBaseline` de `heroInstrument` (FER-160): numeral em-dash "—" en tinta + chip "Base · Apple Salud" (en tono de dato `dataSpO2`) + "Falta la lectura de hoy" + "Usa tu banda para sumar… la lectura de hoy" — nunca muestra "0 de 4" como si no hubiera base. Su pie se adapta: CTA "Buscar strap" si no se ha visto strap, `LiveHeartbeatRow` si ya. Sin import, el modo `calibrating` mantiene el conteo 0→4 (numeral `N/4` + night-dots) con copy de **base propia** (no "veredicto") + un atajo "¿Tienes historial en Apple Salud? Conéctalo…" que abre Data Sources. Sin import/permiso, `hasImportedBaseline` es falso por construcción, así que ningún estado promete una base de Apple Health que no existe. Es el hermano de FER-105 (la línea de confianza del veredicto, que cubre el momento *después* del primer veredicto).

**Nota — indicador de sincronización (iOS):** cuando `live.backfilling == true`, la `syncMeta` en la `utilityRow` muestra "Sincronizando historial…" en tinta terciaria del tema (`inkTertiary`) en lugar del texto habitual "Sincronizado hace X" / "Última sincronización: nunca". No hay pill ni color prominente; el texto vuelve al estado normal al terminar el backfill. El pill `SyncingHistoryNote` se conserva solo en el path macOS de esta vista.

**Nota — pull-to-refresh propio que dibuja el dial (iOS, FER-222 · reemplaza el nativo de FER-204):** el `iosBody` ya **no** usa `.refreshable` (ni su ruedita gris de iOS). El `ScrollView` publica el offset de su tope en un coordinate space propio (`todayPullScroll`) vía un `GeometryReader` de fondo (`TodayScrollOffsetKey`) y `.scrollBounceBehavior(.always)` (rebota aunque el contenido quepa exacto, para que el tirón funcione sin el `.refreshable`); `handlePullOffset` mapea el tirón a `pullProgress` (0→1), que **arma el arco verde del `DiurnalDial`** (parámetro nuevo `armProgress`, crece hasta ~0.90 del aro proporcional al desplazamiento). Al cruzar `pullThreshold` (96pt) se dispara **una vez por gesto** la misma acción de FER-204 (`pullToSync` vía `triggerPullSync`: háptica `.impact(weight: .medium)` sobre `syncHaptic` + `syncNow()`/`scan()` + «soltar pronto» ~1.2 s + `repo.refresh()`), y el dial pasa a **girar** (modo `syncing` de FER-221, encendido de inmediato por `pullSyncing` aunque el offload tarde o no arranque). Soltar antes del umbral no dispara. La acción (`pullToSync`) ramifica por estado igual que antes: conectada → `syncNow()` (offload `.manual`, sin rate-limit); banda conocida pero desconectada (`lastSyncedAt != nil`) → `scan()`, y el handshake de reconexión auto-dispara el sync (`requestSync(.connect)`); sin banda conocida → solo `repo.refresh()` local, sin escaneo ni error. **VoiceOver**: como ya no hay `.refreshable` (que regalaba una acción de refrescar accesible), la `utilityRow` del header expone una **acción personalizada «Sincronizar»** equivalente al gesto (vía `triggerPullSync`). **Reduce Motion**: no se dibuja el arco progresivo (`pullProgress` se queda en 0) — el gesto sigue armando + disparando con su háptica, y el dial reposa. El offload largo sigue reflejándose en `syncMeta`; al llegar datos los scores se recalculan solos vía `repo.refreshSeq`. No toca el protocolo BLE — reusa `syncNow()`/`scan()` existentes.

**Nota — Frecuencia cardiaca en Métricas clave (FER-137 · recoloreada FER-135, iOS):** la sección-gráfica de HR de 24h suelta se retiró del `iosBody`. Ahora la FC continua del día es un renglón más de "Métricas clave" (`MetricRow` "Frecuencia cardíaca", línea en el dato `dataHeart`: promedio del día + sparkline de la curva del día), justo encima de "FC en reposo" (par de pulso). Al tocarlo abre `MetricInfoSheet` con `id "heart_rate"`: la curva de 24h (más alta, ~260pt) + Mín/Prom/Máx + una línea de contexto, sin bandas ni párrafo. Sin lecturas del día → renglón "—" y sheet con "Aún no hay lecturas de hoy".

**Nota — tarjeta "Sources" → `SourcesSummaryCard` (estilo FER-119 · ubicación FER-137):** el resumen de fuentes (overline "Sources", una `sourceRow` por fuente —WHOOP en `accent`, Apple Health en `metricCyan`, tinte solo en el glifo— y `syncLine` con `ConnectionDot` bajo un divider, visible solo si `hasData || showsSync`) se extrajo al componente auto-contenido `SourcesSummaryCard` (lee `repo`/`live` y carga sus propios conteos). Vive al **fondo de `DataSourcesView`** y en el Today de macOS (heredado).

**Nota — sección "Fuentes" de vuelta en Hoy (iOS, FER-164 · *retirada en FER-189*: Hoy ya no muestra Fuentes — vive en Fuentes de datos / Ajustes; `iosSourcesSection`/`sourceRow` eliminados):** una variante tematizada de la carta de fuentes regresó al **fondo del `iosBody`** (`iosSourcesSection` + `sourceRow`), en lenguaje «Instrumento diurno» y con **jerarquía reducida**: un overline callado "FUENTES" (no un título como "Métricas clave"), una fila por fuente con el **glifo en color del dato** (WHOOP `dataRecovery` / Apple Salud `dataSpO2`, color solo en el glifo), nombre en `ink` y conteo tabular en `inkSecondary`, divididas por la misma regla de 1pt. **Sin** la línea "Historial sincronizado" (ya vive en `syncMeta` del header). Renderiza nada si no hay ninguna fuente con datos. La `SourcesSummaryCard` compartida queda intacta para sus otros hosts.

**Nota — escala sistémica «Instrumento diurno · L» (iOS, FER-164):** segunda pasada de proporción para llenar la columna de forma armoniosa: héroe `instrumentoHero(76→88)`, títulos de estado vacío `hero(28→32)`, "Métricas clave" `title2→title1`, overline `InstrumentoType.overline` 11→12; `MetricRow` con renglón más alto (padding 12→15), sparkline 50×16→60×26 (`lineWidth` 2.0), valor `number(18→20)` + unidad nuevo token `StrandFont.unit`, y etiqueta que nunca se recorta (`ViewThatFits`: una línea, o el chip baja a segunda línea). El punto de bpm de `LiveHeartbeatRow` se centra (`.center`). La **barra de estado** se vuelve tinta oscura solo en Hoy: el color scheme lo decide `ContentView` según la pestaña activa (`RootTabView` publica `isTodayActive`), con el gate de onboarding/terms en oscuro.

**Nota — Métricas clave con banda de referencia (iOS, FER-135/155 · *superado por FER-180*: la tendencia 14d salió de Hoy hacia la hoja / «Cuerpo»):** cada `MetricRow` (Esfuerzo del día, Sueño, HRV, Frecuencia cardíaca, FC en reposo, Oxígeno en sangre, Pasos) dibuja su **gráfica de 14 días** con una **banda de referencia p25–p75** (`ReferenceRange.interquartile`, en tinta `hairlineStrong`) detrás de la línea; la **línea va en el color del dato** de cada métrica (`dataStrain`/`dataSleep`/`dataHrv`/`dataHeart`/`dataSpO2`/`dataSteps`), mientras valor, etiqueta y unidad van en **tinta** del tema (`ink`/`inkSecondary`/`inkTertiary`). Tap de la fila → `MetricInfoSheet`.

**Nota — affordance de tappable en los renglones (iOS, FER-161 · *superado por FER-180*):** cada `MetricRow` muestra un `chevron.right` tenue (12pt, `inkTertiary`, su propio gap) a la derecha del valor para comunicar que abre detalle; el renglón completo sigue siendo el tap target (envuelto en `MetricRowButtonStyle`, que añade un **fondo pressed sutil** `ink.opacity(0.05)` mientras se mantiene el toque). El chevron se muestra también en renglones sin dato (`—`). Accesibilidad: cada fila es un **botón** con hint "Abre el detalle"; el renglón sin dato lee "sin dato de hoy" en vez de "guion".

**Nota — «Métricas clave» (lista 14d) → «Métricas de hoy» (rejilla intradía) (iOS, FER-180 · supersede FER-155/161):** la nueva IA del rediseño separa **Hoy = foto del día** de **Cuerpo = tendencia**. La sección `iosMetricsSection` dejó de ser una **lista** de `MetricRow` (label · sparkline 14d + banda p25–p75 · valor · chevron) y pasó a una **rejilla 2×4 de 8 tiles** `TodayMetricTile` («Métricas de hoy»). Cada tile: **etiqueta (overline en tinta)** · **valor de hoy en su color de dato** (`dataStrain`/`dataSleep`/`dataHrv`/`dataHeart`/`dataSpO2`/`dataSteps`; Estrés bandeado por `verdict`/`warning`/`critical` según nivel 0–3) + unidad · pie con la **Δ vs ayer** (mejora→`verdict`, empeora→`critical`, igual→`inkTertiary`, **sin valencia** —Esfuerzo, FC— en tinta neutra), el badge **«Apple Salud»** cuando el valor vino de Apple (`resolveMeasured`/`fromApple`), o nada (sin ayer / sin valor). **Sin sparkline de 14 días.** Tile tematizado (`surface` + hairline, `cornerRadius` `NoopMetrics.cardRadius`, `tileHeight`), nunca el `NoopCard` oscuro; pulsado vía `TileButtonStyle` (overlay redondeado). Las **8 tiles**: Esfuerzo del día · Sueño · HRV · Frecuencia cardíaca (promedio del día, **sin Δ** — no hay promedio diurno de ayer guardado) · FC en reposo · Oxígeno en sangre · Pasos (sin meta) · **Estrés** (proxy 0–3 vía `StressModel`, cargado en `loadAll`). **Recuperación NO es tile** (ya es el numeral del héroe). La **tendencia 14d** ya no vive en Hoy: sigue accesible al tocar un tile (la hoja la trae, `trendLoader`), interino hasta el Detalle de Métrica de «Cuerpo». Tap de un tile → `MetricInfoSheet` de esa métrica (`strain`/`sleep`/`hrv`/`heart_rate`/`rhr`/`spo2`/`steps`/**`stress`** nuevo). El nudge «Conectar Apple Salud» se conserva al pie de la sección.

**Nota — Hoy cabe en una pantalla (iOS, FER-189 · sobre FER-180):** tres ajustes de composición para que Hoy (estado veredicto típico) entre sin scroll, sin tocar el héroe (dial 180 intacto). (1) **«Verlo latido a latido» (`LiveHeartbeatRow`) se mudó del pie del héroe al PIE de Hoy** (`iosBody`, tras las tiles, sólo si `strapSeen`): el héroe queda limpio —overline + dial-con-numeral + veredicto—; `heroFooter` ahora sólo lleva el CTA «Buscar strap» (sin strap) o el atajo Apple Salud (calibrando), nada en veredicto/espera-con-strap. (2) **Se retiró la sección «Fuentes»** de Hoy (`iosSourcesSection`/`sourceRow`/`metricSeparator` eliminados; vive en Fuentes de datos / Ajustes). (3) **Las tiles bajan de alto** (`TodayMetricTile`: 104 → **76pt fijo**, padding 14→10, valor `number(24→22)`, etiqueta a **una línea** con `minimumScaleFactor`), para una rejilla 2×4 compacta y pareja.

**Nota — pulso vivo en el encabezado de «Métricas de hoy» (iOS, FER-194 · supersede el punto (1) de FER-189):** la fila full-width «Verlo latido a latido» (`LiveHeartbeatRow`) del pie se **eliminó**; su acceso al monitor latido a latido se mudó al **trailing del encabezado** «Today's metrics» como una **pastilla de pulso** (`LivePulsePill`): cápsula `surface` + hairline con `heart.fill` en tinta + **punto de pulso** (`dataHeart` al transmitir, tinta si no) + **bpm** del día (`liveBpm`) + «bpm»; sin lectura → «—», sigue tappable. Sólo aparece si `strapSeen` (si no, el encabezado queda solo con el título y el héroe ofrece «Buscar strap»). Al tocarla abre el **mismo** `LiveView` en hoja (`.sheet`, FER-190) — el monitor no cambia. Libera el pie de Hoy (regla «color sólo en el dato»: únicamente el punto lleva color). El tile «Frecuencia cardiaca» (promedio del día) se conserva; la rejilla sigue 2×4.

**Nota — Hoy cabe en una pantalla en calibrando (iOS, FER-202 · continúa FER-189 · revisa FER-169/164):** el estado **calibrando** (el más alto de Hoy) aún se desbordaba; cuatro recortes (~115pt) para que entre sin scroll en iPhone 15/16, sin tocar datos ni `HeroState`. (1) **Dial `DiurnalDial` 180 → 118px** y **numeral `instrumentoHero(60→52)`**. (2) **El «/100» (y el `N/seed` de calibración) pasa de *«/100» espejo invisible a la derecha* a *apilado pequeño y centrado DEBAJO del número*** (`heroNumeral`: `HStack` con mirror → `VStack` centrado): queda centrado de verdad sobre el eje del dial y sin desbordar el aro — **supersede el truco de FER-169**. (3) **`calibrationConfidence` compacto**: la procedencia «· base Apple Salud» se pliega en la misma línea de la etiqueta (antes era un 3.er renglón) + barra 6→5px. (4) **Ritmo**: gap de sección 28→18, inset superior 20→12, spacing del héroe 14→11, y **tiles `TodayMetricTile` 76 → 70pt** (padding vertical 10→8). El estado **veredicto** sigue cabiendo holgado.

**Nota — dial del veredicto de vuelta a 180 (iOS, FER-205 · revierte el punto (1) de FER-202):** al dueño no le gustó el dial encogido, así que el `DiurnalDial` regresó **118 → 180px** y el numeral **52 → 60** (`heroNumeral`, los 4 estados). Se **conserva** el «/100»/«N/seed» apilado y centrado de FER-202 y las demás compactaciones (calibración a 2 renglones, tiles 70pt, ritmo 18/12/11). Con el dial grande, Hoy puede volver a requerir algo de scroll en estado calibrando — trade-off aceptado por el dueño.

**Componentes:** `HealthAlertBanner`, `PaperBackground` (lienzo de papel por hora, FER-135), `heroInstrument` (héroe unificado de 4 modos vía `HeroState`, FER-160), `DiurnalDial` (dial 24h del héroe, FER-135), `LivePulsePill` (pastilla de pulso en el encabezado de «Métricas de hoy», FER-194 · reemplaza `LiveHeartbeatRow`), `WhyVerdictSheet`, `TodayMetricTile`/`TileButtonStyle` (rejilla «Métricas de hoy» 2×4, valor + Δ vs ayer, tiles 70pt, realce al pulsar FER-213, FER-180/189/202) · macOS (heredado): `MetricRow`, `RecoveryRing`, `StatTile ×10`, `ChartCard (HR Trend)`, `SourcesSummaryCard`, `ReadinessGaugeBar`, `readinessSection`  
**Navegación:** → `LiveView` (sheet detente grande, "beat by beat" — FER-190) · → `MetricInfoSheet` (sheet, tap de cualquier **tile** de «Métricas de hoy» —incl. la variante **`stress`** nueva, FER-180— · tap del **número de recuperación** del héroe → hoja resumida `recovery`, FER-232) · → `WhyVerdictSheet` (sheet, **«i»** junto a la palabra del veredicto) · → `DataSourcesView` (sheet, «Conectar Apple Salud») · → `SupportView` (toolbar ❤)

**Nota — `WhyVerdictSheet` en tema claro (FER-167):** el sheet «¿Por qué {veredicto}?» se migró del fondo oscuro `StrandPalette.surfaceBase` al **tema claro «Instrumento»** (igual que `MetricInfoSheet` en FER-162). `TodayView` le pasa el `InstrumentoTheme` **explícito** (no se propaga por `.sheet`); papel/tinta/superficies del tema. Los colores de nivel del chip y la leyenda **espejean `TodayView.verdictDataColor`** (primed/balanced → `verdict`, strained → `warning`, rundown → `critical`, insufficient → `inkTertiary`) para que el héroe y el sheet nunca discrepen; el `colorName` del chip sigue ese mapeo (verde/ámbar/rojo/gris). Copy es-MX + de (FER-113 ya tenía es; FER-167 añade el `de` de los nombres de nivel y el color «rojo»).

**Nota — explicación tras ⓘ en `MetricInfoSheet` (FER-243):** la explicación de texto (`info.headline`) ya **no** se muestra siempre bajo el header; arranca **oculta** y se despliega in-place con una **ⓘ `info.circle`** junto al nombre de la métrica (estado `headlineExpanded`). La ⓘ va en `inkTertiary` cerrada y en el `metricHue` de la métrica cuando está abierta; anima con `StrandMotion.interactive`. Aplica a todas las métricas del sheet (Sueño, Estrés, etc.). El resto del sheet (curvas, bandas, método, nota) no cambia.

**Nota — gráfica con bandas de clasificación en `MetricInfoSheet` (FER-244):** para **Sueño** y **Estrés**, la gráfica «Últimos 14 días» deja el eje Y auto-escalado (en Sueño venía en minutos) y se ancla a las clasificaciones de la métrica vía `TrendChart(bands:bandColor:yAxisValues:)` (StrandDesign). La banda donde cae el último valor se resalta (franja `bandColor.opacity(0.12)` + bordes), las vecinas quedan insinuadas por las grid-lines del eje en los umbrales, y bajo el título aparece «‹Banda› · N de los últimos N días en este rango» (helper puro `TrendBands.activeBand`). Sueño se convierte a **horas**; Estrés usa su score 0–3. `MetricInfo.Band` ganó `lower`/`upper` (solo poblados en sleep/stress). Las demás métricas pasan `bands` vacío y conservan la gráfica de antes.

**Nota — realce al pulsar en los tiles (iOS, FER-213 · ajusta el «pulsado» de FER-180):** `TileButtonStyle` pasó del **darken** (overlay `ink.opacity(0.05)`) a un **realce**: al pulsar, el tile se **eleva** (`scaleEffect(1.03)`) y su borde pasa a `hairlineStrong`, sin sombra; en reposo no hay marca. Es lo único que sobrevivió de FER-210 (el zoom-morph de apertura se **revirtió** — PR #171); la apertura del detalle sigue siendo el `.sheet` estándar (desde abajo).

**Nota — el dial gira al sincronizar (iOS, FER-221):** el `DiurnalDial` estrena un modo **«sincronizando»** (parámetro `syncing: Bool`, pasado desde `TodayView` como `live.backfilling`): mientras la banda descarga su historial, un **arco de progreso `dataRecovery`** con punto líder **gira** sobre el bezel (`StrandMotion.spin()`, ~1.5 s/vuelta, indeterminado — sin %, el protocolo no revela el total), el **now-dot fijo de la hora se oculta** (su verde se muda al arco) y el resto del reloj (arco de día, banda de sueño, ticks) **permanece fijo**. En `TodayView`, el numeral del héroe se **atenúa** a `inkTertiary` mientras `live.backfilling` (`heroNumeralInk`) y vuelve a tinta al terminar. **Reduce Motion**: el arco **no gira** (reposa estático) y el `accessibilityLabel` del dial antepone «Sincronizando». **La honesty line del header (`syncMeta`) no cambia** — todo el protagonismo del sync pasa al dial, en lugar de la ruedita nativa. Reemplaza la señal genérica de sync en Hoy. El mismo modo `syncing` lo reusa el pull-to-refresh propio de **FER-222**, donde además el arco se **arma** con el tirón (`armProgress`) antes de girar (ver la nota de pull-to-refresh arriba).

---

### HealthView
**Archivo:** `Cenit/Screens/HealthView.swift`  
**Descripción:** Vitales en vivo — HR desde la correa, respiración, SpO₂, RHR, HRV, temperatura de piel.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin datos | Sin HR en vivo ni datos de hoy |
| Streaming HR | Strap bonded + HR > 0 + worn |
| Datos históricos | Datos de hoy disponibles |

**Componentes:** `Sparkline`, `StatePill (STREAMING/IDLE)`, `StatTile ×5`

---

### SleepDetailScreen
**Archivo:** `Cenit/Screens/SleepDetailScreen.swift`  
**Descripción:** Detalle de Sueño «Instrumento» (claro) — el sueño migrado del viejo `SleepView` oscuro al lenguaje «Instrumento» (FER-212). Se abre desde **Cuerpo** como **sheet** con el `InstrumentoTheme` pasado **explícito** (no se propaga por `.sheet`, FER-162) y **sin `NavigationStack` anidado** (FER-171). Es un **superset** del viejo SleepView (hipnograma, etapas —ahora en **%**, no minutos—, anoche-vs-típico, tendencia de duración con banda 7–9 h + deuda, métricas de la noche: rendimiento, eficiencia, restaurador, respiración, despertares) **más un bloque nuevo de regularidad del horario** (motor `SleepRegularity`, FER-218: score 0–100 vía SD del punto medio + desfase de fin de semana + estado «se está afinando»). Reusa `Hypnogram`/`TrendChart` de `StrandDesign` y el scaffold de `MetricDetailScreen` (`block`/`hero`/`SheetPaperBackground`/`methodDisclosure`). Es presentación pura sobre un `SleepDetailModel` que el llamador (Cuerpo) construye desde `repo` (la pantalla queda sin DB).
**Pasada de UI (FER-227):** ritmo por espacio — secciones separadas por `NoopMetrics.sectionGap` **sin filete** entre ellas (el hairline solo divide dentro de un grupo). Las **tiles de «Métricas de la noche» son tocables** (cada una con una **ⓘ `info.circle`** en la esquina) y abren su `MetricInfoSheet` con headline + **mini-tendencia 14d** (`trendLoader` sobre series precomputadas en `SleepDetailModel`) + bandas; ids nuevos `sleep_performance`/`sleep_efficiency`/`sleep_restorative`/`sleep_awakenings`/`sleep_latency` (+ `resp_rate` reusa `MetricInfo.respiratory`). Una **ⓘ junto al overline «Anoche»** abre `SleepStagesInfoSheet`, una tarjeta combinada que explica REM/profundo/ligero/despierto + por qué son aproximadas (absorbe el viejo caption «Etapas aproximadas»). Copy reescrito bajo «Tendencia de duración» (eje + **deuda de la semana** etiquetada) y **footer de fuente eliminado** (consistencia con el resto). Ambos sheets nuevos son `.sheet` anidados con tema explícito, sin `NavigationStack`.
**Ajustes (FER-234):** el **hipnograma** estrena scrub con el dedo (`Hypnogram.showsHover: true` + un `highPriorityGesture(DragGesture)` en iOS, igual que el `scrubGesture` de `TrendChart`): arrastrar muestra etapa + rango de hora + duración. La tile de **Respiración** ya trae el valor de anoche (`latestStrapNight` recibe `respRate` de `days.last?.respRateBpm`; la sesión cacheada no lo carga). El token `StrandPalette.sleepREM` pasó de `#5BE0C7` (mint) a **`#3E9E8C`** (teal apagado) en todos lados.

Las 8 secciones (orden): Hero (horas dormidas) · Anoche (hipnograma + etapas en %) · **Regularidad del horario** (destacado, en `surface`) · Anoche vs lo típico (por etapa, en %) · Tendencia de duración (30d + banda + deuda) · Métricas de la noche (rejilla) · Ver el método · Footer de fuente.

| Estado | Condición de entrada |
|--------|---------------------|
| Cargando | `model.loaded == false` (sin noche → copy «Cargando tu historial de sueño…») |
| Sin datos de noche | `model.night == nil` y ya cargó (invita a importar / conectar Apple Salud / dormir con la correa) |
| Apple Health | Noche desde Apple Salud (sin reloj real → barra proporcional + badge «Apple Health») |
| WHOOP · hipnograma | Intervalos de etapa persistidos (`model.intervals.count >= 2`) |
| WHOOP · estimado | Sin segmentos por época → barra apilada proporcional |
| Regularidad afinándose | `< SleepRegularity.minNights` noches con horario → «Se está afinando · N noches por venir» (sin número falso) |

**Componentes:** `Hypnogram`, `TrendChart`, barra de etapas apilada, fila etapa-vs-típico (con marcador en el promedio personal), bloque de regularidad, rejilla `metricTile`, `DisclosureGroup` («Ver el método»). El tile de **Latencia se omite** de la rejilla cuando no hay dato (el caché no trae latencia de onset), reacomodando sin hueco.

---

### StrainDetailScreen
**Archivo:** `Cenit/Screens/StrainDetailScreen.swift`  
**Descripción:** Detalle de Esfuerzo «Instrumento» (claro) — migra «Esfuerzo del día» (Day Strain) del viejo `MetricInfoSheet` al lenguaje del Detalle de Métrica (FER-238). Hermana de `RecoveryDetailScreen`/`SleepDetailScreen` (igual que ellas, **no** extiende `MetricDetailScreen`/`MetricDetailSpec`, que son para vitales de serie escalar única): reusa su lenguaje visual (`hero`/`InfoAccordion`/`SheetPaperBackground`/`methodDisclosure`/`statCell` + la window-math de la tendencia) con su propio `StrainDetailModel`, porque el esfuerzo es una métrica **compuesta** con forma propia (hero = valor de **hoy** 0–21, no promedio móvil; visualización firma = **curva intradía acumulada**; referencia = **zonas fijas**, no un rango personal). Se abre **solo desde Cuerpo** (la fila «Day Strain»). En **Hoy**, tocar el tile de Esfuerzo mantiene la **hoja resumida** `MetricInfoSheet` (consistencia «foto del día»), no esta pantalla. Sheet con `InstrumentoTheme` **explícito** (no se propaga por `.sheet`, FER-162), **sin `NavigationStack` anidado** (FER-171). No crea matemática: consume la curva de `CuerpoView.loadStrainCurve()` (HR del día → `StrainScorer.cumulativeStrain`, async) y la serie/estadísticas de `repo.days`/`ComparisonEngine`/`SeriesShape`. Presentación pura sobre un `StrainDetailModel` que el llamador construye desde `repo` (sin DB); la curva intradía se inyecta como `curveLoader` async (es I/O de DB).

Los bloques (orden), **cada uno con su ⓘ `InfoAccordion`** salvo el método: 1) **Hero** — valor de hoy 0–21 en `dataStrain` (`—`+tinta neutra sin score) + lectura por zona · 2) **Cómo se acumuló hoy** — curva intradía acumulada (`TrendChart`, eje por hora; estados cargando/sin actividad) · 3) **Zonas** — las 4 bandas fijas de `MetricInfo.strain` (Rest/Light 0–7 · Moderate 7–14 · Hard 14–18 · Extreme 18–21) con la activa marcada en `dataStrain` · 4) **Tendencia** — `SegmentedPillControl`(`ExploreRange`) + `TrendChart` (media móvil 7d, decimada) + **Prom/Mín/Máx** + % vs el mes pasado; se omite con <2 puntos · 4.5) **Qué mueve tu esfuerzo** (FER-239) — tendencias **direccionales reales** entre el esfuerzo y otras señales —**recuperación del mismo día** y **esfuerzo del día anterior** (lag +1)— calculadas de `repo.days` con `WhatMovesStrainEngine` (`StrandAnalytics`, puro + test) reusando `CorrelationEngine`/`trend`; una frase es-MX por relación, **sin coeficiente y sin causa**, chip «tendencia, no causa», ⓘ con método+gate (Plews 2013 / Vesterinen 2016). Mismo gate que FER-209 (**≥42 pares ~6 sem + |r|≥0.20 + p<0.05**); si nada lo cruza, muestra un **estado vacío honesto** («Aún no hay suficientes datos…») en vez de ocultarse, siempre que la pantalla ya tenga datos (FER-246; en cold-start sí se oculta). Descarta predictores circulares (entrenamientos/pasos/kcal son componentes del propio strain) · 5) **Ver el método** (TRIMP por zonas + escala log, cita Edwards 1993 / Banister 1991). Pie: fuente «tu correa, en el dispositivo» (strain es solo-strap). Estados: cargando → well; sin datos → solo hero con lectura honesta.

### RecoveryDetailScreen
**Archivo:** `Cenit/Screens/RecoveryDetailScreen.swift`  
**Descripción:** Detalle de Recuperación «Instrumento» (claro) — el siguiente «sabor» del Detalle de Métrica tras Sueño (FER-225). Hermana de `MetricDetailScreen` (igual que `SleepDetailScreen`): reusa su lenguaje visual (scaffold `block`/`hero`/`InfoAccordion`/`SheetPaperBackground`/`methodDisclosure`/`statCell`) pero con su propio `RecoveryDetailModel`, porque la recuperación es un **score compuesto** con bloques propios, no un vital de serie escalar. Se abre desde **Cuerpo** (la fila héroe). En **Hoy**, tocar el número del veredicto mantiene la **hoja resumida** `MetricInfoSheet` (consistencia «foto del día», FER-232), no esta pantalla. Sheet con `InstrumentoTheme` **explícito** (no se propaga por `.sheet`, FER-162), **sin `NavigationStack` anidado** (FER-171). Consume `StrandAnalytics` tal cual (no crea matemática nueva; el pronóstico es FER-188): score + banda de `RecoveryScorer`, estado por driver + carga de `ReadinessEngine` (sus señales comparten la base del scorer), calibración de `RecoveryScorer.calibrationNights`, estadísticas de `ComparisonEngine`. Presentación pura sobre un `RecoveryDetailModel` que el llamador construye desde `repo` (sin DB).

Los 8 bloques (orden), **cada uno con su ⓘ `InfoAccordion`** salvo el método: 1) **Hero** — score 0–100 en color de banda (verde ≥67 `verdict` / ámbar 34–67 `warning` / rojo <34 `critical`, por `RecoveryScorer.band`) + lectura · 2) **Qué lo explica** — cada driver (HRV 60 / FC reposo 20 / Sueño 15 / Temp 10 / Respiración 5, pesos de `RecoveryScorer.w*`) con su **estado vs tu base** (flag de `ReadinessEngine.signals`; Sueño se deriva de la eficiencia vs `sleepPerfCenter`) y una barra peso=largo, estado=color · 3) **Tu rango normal** — media ± σ de los últimos 30 días (`ComparisonEngine.stat`) · 4) **Calendario · 90 días** — `YearHeatStrip` **re-tintado** (chrome cálido, celdas vacías en `hairline`, bandas de Instrumento) y **a todo el ancho**; **tocar un día** lo resalta con un aro y muestra su lectura (fecha · puntaje en color de banda · estado) debajo, FER-235 · 5) **Consistencia (CV)** — `SeriesShape.coefficientOfVariation` · 6) **Carga reciente** — `acwr`/`monotony`/`loadBand` de `ReadinessEngine` como **contexto honesto, sin claim de lesión** (Impellizzeri 2020) · 7) **Selector de periodo + Tendencia** — `SegmentedPillControl`(`ExploreRange`) + `TrendChart` (media móvil 7d, decimada) + **Prom/Mediana/Mín/Máx/σ** · 8) **Ver el método** (z-score + logística + cita). El Calendario se lee arriba (en el lugar de la Tendencia) y la Tendencia va al fondo (FER-237).

| Estado | Condición de entrada |
|--------|---------------------|
| Cargando | `model.loaded == false` (well con spinner) |
| Calibrando | `model.calibration != nil` (`RecoveryScorer.calibrationNights` en [1,4)) → «N / 4 noches» + barra, sin gráficas |
| Con datos | hay score o serie de recuperación → los 8 bloques |
| Día seleccionado (calendario) | tocar un día → aro de selección + lectura «fecha · puntaje · estado» debajo; día sin lectura → «sin lectura» (FER-235) |
| Sin datos / offline | cargó, sin score y sin historia → hero «—» con copy honesto (usa la banda; no promete datos) |

**Componentes:** `InfoAccordion`, `TrendChart`, `YearHeatStrip` (+ `YearHeatStrip.weekColumns` para llenar el ancho · `onSelect`/`selectionColor` para tocar un día, FER-235), `SegmentedPillControl`, `RecoveryDay`, `InstrumentoTheme`. **Analytics:** `RecoveryScorer` (banda, pesos, calibración), `ReadinessEngine` (señales por driver + carga/monotonía), `ComparisonEngine` (estadísticas + mes-vs-mes), `SeriesShape` (media móvil, CV, decimación), `Baselines.minNightsSeed`.

---

### StressDetailScreen
**Archivo:** `Cenit/Screens/StressDetailScreen.swift`  
**Descripción:** Detalle de Estrés en lenguaje «Instrumento» (FER-241). Lo abre **solo** la fila «Stress» de `CuerpoView` (el tile de Estrés en **Hoy** NO cambia — sigue abriendo la hoja resumida `MetricInfoSheet`). Hermano de `RecoveryDetailScreen`/`SleepDetailScreen`: pantalla dedicada, no extiende `MetricDetailScreen` (ese es para vitales de serie escalar). Consume `StressModel` tal cual (no crea matemática). Hero = **valor de HOY** (no media 7d) en color de banda, porque el índice ya viene normalizado a la base de cada quien; las bandas son **universales** (0–1/1–2/2–3) por la misma razón.

| Estado | Condición de entrada |
|--------|---------------------|
| Con datos | `StressModel` válido (score + tendencia) |
| Sin datos | `model == nil` → hero «—» + cómo obtener datos |
| Pocos días | `fullTrend.count < 2` → se ocultan tendencia/consistencia |

**Bloques (cada uno con su ⓘ vía `InfoAccordion`, salvo placeholder y método):** Hero (valor de hoy + banda + lectura) · Tendencia (selector de periodo + línea diaria 0–3 sobre las bandas + mes-vs-mes en es-MX + Prom/Mín/Máx) · Rango normal (bandas universales, la de hoy resaltada) · **Tiempo en calma** (% días en banda baja, 30d) · Qué lo mueve (RHR/HRV de hoy vs base, en tarjetas) · Consistencia (CV) · **Estrés por momento del día (PLACEHOLDER deshabilitado** — el cruce con calendario es FER-38) · Ver el método. *(Tiempo en calma sube antes de Qué lo mueve — FER-247)*

**Componentes:** `InfoAccordion`, `TrendChart`, `SegmentedPillControl`, `InstrumentoTheme`. **Analytics:** `StressModel`/`StressMath`/`StressBand` (de `StressView.swift`), `ComparisonEngine` (estadísticas + mes-vs-mes), `SeriesShape` (CV, decimación).

> Nota: `StressView` (la pantalla oscura completa, `Cenit/Screens/StressView.swift`) es **código heredado no referenciado**; se conserva porque alberga `StressModel`/`StressBand`/`StressRamp`/`StressMath`, que sí usan Hoy y Cuerpo.

---

## Actividad

### WorkoutsView
**Archivo:** `Cenit/Screens/WorkoutsView.swift`  
**Descripción:** Log de actividad — importado (WHOOP, Apple), detectado automáticamente, manual.

| Estado | Condición de entrada |
|--------|---------------------|
| Cargando | `loaded == false` |
| Sin sesiones | `allRows.isEmpty` |
| Ventana vacía (auto-widen) | Rango seleccionado sin sesiones, expande a siguiente |
| Con sesiones | Sesiones en el rango actual |

**Componentes:** `SegmentedPillControl (7D–All)`, `StatTile ×5`, `Activity Breakdown`, `HR Zones`, `Sessions table`  
**Navegación:** → `ManualWorkoutSheet` (sheet: add · edit vía context menu)

---

### CuerpoView
**Archivo:** `Cenit/Screens/CuerpoView.swift`  
**Descripción:** Landing curado de la capa «historia / entre-días» (pestaña **Cuerpo**, FER-186). Estilo Apple Salud (Resumen) en papel claro «Instrumento» (color solo en el dato): una columna de secciones, cada fila un `MetricRow` (label · sparkline 14d + banda p25–p75 · valor en su color de dato · chevron) que abre un detalle.

**Secciones:** Recuperación (fila héroe destacada, en `surface`) · Descanso & carga (Sueño · Esfuerzo del día · Estrés) · Vitales (HRV · FC en reposo · SpO₂ · Frecuencia cardíaca · Respiración · Temp. de piel) · Actividad (Pasos · Entrenamientos · **«Cómo amaneces tras cada deporte»** — mini-bloque Activity Cost, FER-139) · Longevidad (**Edad física** activa — número + delta vs edad, FER-141 · Vitalidad → «Próximamente», FER-145) · acciones al pie (Comparar · Ver todas las métricas).

La fila **Edad física** es custom (no `MetricRow`): el delta vive bajo la etiqueta, sin sparkline, y el número se tiñe por **dirección** (verde más joven / ámbar mayor / tinta igual / `—` sin dato); en cobertura parcial lleva el chip «Estimado». Toca → `FitnessAgeDetailView`.

| Estado | Condición de entrada |
|--------|---------------------|
| Con datos | Filas pobladas desde `repo.displayDays` (valores + sparklines) |
| Calibrando | Recuperación muestra «N/4» + «Calibrando tu base»; el resto en «—» con esqueleto |
| Sin permiso / offline | Muestra lo guardado; las métricas solo-Apple (Pasos) invitan a conectar sin prometer datos |

**Apertura del detalle (FER-185 ya aterrizó para los 3 vitales):** **HRV · FC en reposo · Respiración** abren el **`MetricDetailScreen`** unificado (sheet claro «Instrumento», `depth: .full`, tema explícito, sin `NavigationStack` anidado); **Sueño** abre el **`SleepDetailScreen`** claro «Instrumento» (sheet, tema explícito, sin stack anidado — FER-212); **Recuperación** (la fila héroe) abre el **`RecoveryDetailScreen`** «Instrumento» (sheet, tema explícito, sin stack anidado — FER-225), ya no la `MetricInfoSheet`. **Esfuerzo del día** abre el **`StrainDetailScreen`** «Instrumento» (sheet, tema explícito, sin stack anidado — FER-238), ya no la `MetricInfoSheet` (Hoy sí la conserva). El resto sigue su puente: SpO₂/FC/Pasos/Estrés→`MetricInfoSheet` claro; Entrenamientos→`WorkoutsView`, Temp. piel→`MetricDetailView` del catálogo, Comparar→`CompareView`, Ver todas→`MetricExplorerView` — estos últimos como **sheet oscuro fijado a `.dark`** (un tab claro no puede empujar una pantalla oscura sin romper la barra de estado). El mini-bloque **«Cómo amaneces tras cada deporte»** (Activity Cost, FER-139) en «Actividad» abre su propia **hoja clara** `ActivityRecoverySheet` (hermana de `MetricInfoSheet`, tema explícito): una tarjeta por deporte —en el orden del motor— con la frase de **asociación** (no causa), badge de confianza (`Sólido`/`Juntando datos`) y «n sesiones», más «Ver el método» con los confusores; sin datos suficientes → estado «Juntando datos».

**Componentes:** `MetricRow`, `Sparkline` (+ `ReferenceRange.interquartile`), `MetricInfoSheet`, `MetricDetailScreen` (+ `MetricDetailSpec`), `ActivityRecoverySheet` (FER-139), `FitnessAgeDetailView`, `InlineFlagChip`, `InstrumentoTheme` (`instrumentoThemeByHour`). **Analytics:** `ActivityCostEngine` + `ActivityCostInputs` (StrandAnalytics, vía `Repository.activityCosts()`).

---

### MetricDetailScreen
**Archivo:** `Cenit/Screens/MetricDetailScreen.swift`  
**Descripción:** El **Detalle de Métrica unificado y reutilizable** (FER-185). Una sola pantalla «Instrumento» clara, parametrizada por un `MetricDetailSpec` (`Cenit/Data/MetricDetailSpec.swift`: descriptor + `MetricInfo` reutilizado + `BlockSet` + `HeroKind` + config de base) y un `Depth`. Reemplaza —solo para los 3 vitales **HRV · FC en reposo · Frecuencia respiratoria**— los dos caminos previos (`MetricInfoSheet` y el `MetricDetailView` oscuro). Se presenta vía `.sheet(item:)`, **sin `NavigationStack` anidado** (evita el crash FER-171) y con el `InstrumentoTheme` **explícito** (no se propaga por `.sheet`). Héroe = **media móvil de 7 días** (`SeriesShape.latestMovingAverage`), no el dato del día; «hoy» va como contexto secundario.

**Profundidad (un solo árbol de vistas filtrado, nunca dos pantallas):**
- `.focus` (desde **Hoy**, tile HRV/FC reposo) → foto del día: rango corto + intersección `[seriesChartBand, normalRange, method, nightVitals]`.
- `.full` (desde **Cuerpo**) → todos los bloques que declara el spec.

**Bloques por métrica (`BlockSet`):** HRV = selector · gráfica+banda · rango normal · consistencia (CV) · tendencia · vitales de la noche · **qué la mueve** · método (héroe = media 7d). FC en reposo = selector · gráfica+banda · rango normal · tendencia · **qué la mueve** · método. Respiración = selector · gráfica+banda · rango normal · tendencia · vitales de la noche · método.

**«Qué la mueve» (`whatMovesIt` · FER-209, solo HRV y FC en reposo):** una **tendencia direccional real** entre el vital y otra señal —**sueño de la misma noche** y **esfuerzo del día anterior** (lag +1)— calculada de `repo.displayDays` con `CorrelationEngine` (Pearson/lagged) y **degradada a dirección**: una frase es-MX (p. ej. «suele ser más alta las noches que duermes más»), **sin coeficiente y sin causa**, con el chip «tendencia, no causa». Gate de suficiencia/fuerza (`CorrelationEngine.trend`): **≥42 pares (~6 semanas)** + `|r| ≥ 0.20` + `p < 0.05`; si ningún par lo cruza, muestra un **estado vacío honesto** («Aún no hay suficientes datos…») en vez de ocultarse, siempre que haya serie (FER-246; cold-start sí se oculta). Orquestación en `Cenit/Data/WhatMovesIt.swift`; gate + traducción r→dirección en `StrandAnalytics/MetricTrend.swift` (con `swift test`).

| Estado | Condición |
|--------|-----------|
| Con datos (≥2 pts) | Media móvil 7d (`Sparkline`) + banda p25–p75 (`ReferenceRange.interquartile`); rango normal (`Baselines.rollingMeanSD` ± σ, nº noches); tendencia (`ComparisonEngine.monthOverMonth` + tira Prom/Mediana/Mín/Máx/σ); consistencia (`SeriesShape.coefficientOfVariation`) |
| Ventana vacía | Auto-ensancha al siguiente rango con datos + aviso «Mostrando los últimos N días» |
| Un solo punto | Valor sin línea + nota |
| Sin suficiente historial (<2) | Bloque de calibración «N / 7 noches» |
| Sin permiso / offline | Muestra lo guardado (`repo.displayDays`); el origen lo inyecta el llamador |

**Datos:** series de los 3 vitales desde `repo.displayDays` (no `series("my-whoop")`, vacío para BLE); loaders inyectados (serie completa por clave; vitales de la noche). **Componentes:** `SegmentedPillControl` (`ExploreRange`, extraído a `Cenit/Data/ExploreRange.swift`), `Sparkline`, `ReferenceRange`, `MetricInfo`/`MetricInfoSheet` (método/bandas/copy reutilizados), `SeriesShape` (StrandAnalytics), `Baselines`/`ComparisonEngine`, `InstrumentoTheme`.

---

### FitnessAgeDetailView
**Archivo:** `Cenit/Screens/FitnessAgeDetailView.swift`  
**Descripción:** Detalle de **Edad física** (Fitness Age, modelo Nes/HUNT — FER-122/141), abierto al tocar la fila «Edad física» en Cuerpo › Longevidad. Hoja clara «Instrumento» con el tema pasado explícito (no se propaga por `.sheet`). El número es el dato dominante, teñido por **dirección** (verde = más joven, ámbar = mayor, tinta = igual). Debajo, un bloque **VO₂max** muestra el dato **medido por Apple Salud** (etiquetado por fuente, FER-215) con una referencia del promedio por edad/sexo; **no** alimenta la Edad física (es complementario).

| Estado | Qué muestra |
|--------|-------------|
| `ready` / `estimate` | Numeral héroe (`instrumentoHero(64)`) + «años» · delta vs edad cronológica · banda «±5 años» · tirita de **descargo** («comparación de fitness, no edad biológica ni diagnóstico») · **Qué la mueve** (FC en reposo `dataHeart` · Actividad `dataStrain`) · **Qué estamos usando** (checklist de cobertura) · método Nes/HUNT al pie. `estimate` añade el chip «Estimado». |
| `notReady` | Sin numeral: pozo vacío honesto («Todavía no podemos calcular…») + checklist de **qué falta** (FC en reposo N/4 noches) + descargo. |
| Bloque **VO₂max** (FER-215) | Independiente de la edad: *con dato Apple* → «N ml/kg/min» + badge «Apple Salud» + «el promedio para tu edad ronda M» (`VO2maxReference`); *sin dato + Apple no conectado* → nudge a conectar; *sin dato + conectado* → oculto. |

**Origen de datos:** `FitnessAgeEngine.snapshot(...)` (orquestación pura en `StrandAnalytics`, FER-141) sobre la ventana de 7 días de `repo.displayDays` (FC nocturna + días activos + strain medio 0–21) + edad/sexo de `ProfileStore`. El **VO₂max** viene de Apple Salud (`AppleDaily.vo2max`, ya en el live sync de `HealthKitBridge`), contextualizado con `VO2maxReference.expected(age:sex:)` (aprox. FRIEND p50).

**Componentes:** `InstrumentoTheme`, `InlineFlagChip`, `StrandFont`, `VO2maxReference` (StrandAnalytics · FER-215); patrones visuales de `MetricInfoSheet` (tirita y secciones en `surface`).

---

### TrendsView
**Archivo:** `Cenit/Screens/TrendsView.swift`  
**Descripción:** Análisis longitudinal — Recovery, HRV, RHR, Day Strain. *(Ya no es la pestaña Cuerpo; accesible vía debug-nav / histórico — reemplazada por `CuerpoView` en FER-186.)*

| Estado | Condición de entrada |
|--------|---------------------|
| Ventana vacía | Sin puntos en el rango; expande automáticamente |
| Un solo punto | Solo 1 día disponible |
| Múltiples puntos | ≥ 2 puntos; renderiza gráficas |

**Componentes:** `SegmentedPillControl (W–ALL)`, `Hero ChartCard (Recovery)`, `ChartCard ×3 (HRV/RHR/Strain)`, `YearHeatStrip`

---

### InsightsView
**Archivo:** `Cenit/Screens/InsightsView.swift`  
**Descripción:** Correlaciones — comportamientos que afectan recovery/HRV/sleep/RHR (Pearson r, Cohen's d).

| Estado | Condición de entrada |
|--------|---------------------|
| Calculando | Correlaciones en proceso |
| Sin journal | Sin entradas de journal |
| Con comportamientos | Journal + outcomes disponibles |
| Correlaciones (Pearson r) | Métricas cruzadas calculadas |

**Componentes:** `JournalLogCard`, `Behavior Effects Cards (Cohen's d)`, `RBar chart (Pearson r)`, `Metric Relationships Card`

---

## Análisis

### MetricExplorerView / MetricDetailView
**Archivo:** `Cenit/Screens/MetricExplorerView.swift`  
**Descripción:** Catálogo de métricas por categoría (Sleep, Strain, Workouts, Vitals, Body). Tap → dossier completo de una métrica.

| Estado | Condición de entrada |
|--------|---------------------|
| Lista por categoría | Vista raíz |
| Detalle · sin datos | Ventana sin puntos (auto-widen) |
| Detalle · un punto | 1 día disponible en el rango |
| Detalle · tendencia | ≥ 2 puntos; muestra gráfica |

**Componentes:** `MetricCatalog grouped list`, `Hero StatTile`, `ChartCard (tendencia)`, `Avg/Min/Max footer`, `Banding vs baseline`  
**Navegación:** → `MetricDetailView` (NavigationLink push; cuelga del único `NavigationStack` de la pestaña «Ajustes» —Explore vive en su sección «Más» desde FER-182—, sin stack anidado — FER-171)

---

### CompareView
**Archivo:** `Cenit/Screens/CompareView.swift`  
**Descripción:** Superponer 2–4 métricas en gráfica normalizada (0–1) + Pearson r entre pares.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin selección | `selected.isEmpty` |
| < 2 métricas | Solo 1 métrica seleccionada |
| 2+ métricas | Gráfica overlay + tarjetas de correlación |

**Componentes:** `Multi-select picker`, `SegmentedPillControl`, `Overlay ChartCard (normalizado 0–1)`, `Correlation rows (Pearson r + p-value)`

---

### AppleHealthView
**Archivo:** `Cenit/Screens/AppleHealthView.swift`  
**Descripción:** Historia de Apple Health — Steps, Active Energy, VO₂ Max, vitales, cuerpo, sueño.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin datos | Fuente `apple-health` vacía |
| Ventana vacía (auto-widen) | Rango sin puntos |
| Con datos | Puntos disponibles en el rango |

**Componentes:** `StatTile hero por métrica`, `ChartCard ×4 secciones (Heart / Activity / Body / Sleep)`, `SegmentedPillControl`

---

### IntelligenceView
**Archivo:** `Cenit/Screens/IntelligenceView.swift`  
**Descripción:** Scores on-device (recovery, strain, sleep desde streams crudos de la correa, sin cloud).

| Estado | Condición de entrada |
|--------|---------------------|
| Calculando | `IntelligenceEngine` en progreso |
| Sin datos (mid-offload o pending wear) | Muestra `DataPendingNote` sin pill de sincronización; el offload en curso ya se refleja en `syncMeta` de TodayView |
| Resultados por día | Análisis reciente disponible |

**Componentes:** `Explainer Card (pesos: HRV 60% / RHR 20% / sleep 15% / resp 5%)`, `Day Cards (Recovery/Strain/Sleep + NOOP badge)`, `Toolbar Recompute`

---

## Dispositivo

### LiveView
**Archivo:** `Cenit/Screens/LiveView.swift`  
**Descripción:** Monitor puro como **una sola hoja** (`.sheet` detente grande, FER-190) en tema claro «Instrumento diurno» (FER-181/184): todo cabe en una vista sin scroll (un `ScrollView` solo degrada en pantallas chicas / Dynamic Type grande). Papel cálido, etiquetas en tinta, color **solo en el dato** (FC/ECG/latidos en `dataHeart`; indicadores «en vivo»/guardado en `dataRecovery`). La **jugada clave de FER-190**: «Capturing live» + «Completes on sync» + el recibo de conteos se fusionan en **una lista de Señales** con dos sub-grupos etiquetados; cada renglón = estado vivo/sync **+ conteo guardado**. Sin strain (vive en Hoy), **sin gestión de correa** (→ Ajustes), **sin batería del strap** (→ Ajustes) y **sin bloque de entrenamiento** (→ *Más › Workouts*). La única acción es el CTA «Conectar» en desconectado; una caída corta por *duty-cycling* de la banda mantiene el monitor **pausado** bajo «Reconectando…» en vez de colapsar al CTA (FER-195). El tema se pasa **explícito** (no se propaga por `.sheet`).

| Estado | Condición de entrada |
|--------|---------------------|
| Conectada · transmitiendo | `live.connected` + HR en vivo (`worn` + heartRate) → hoja completa, FC/R-R con valor vivo + punto verde |
| Conectada · idle (no puesta) | `live.connected` sin señal viva → «—» en los vivos; conteos/cobertura visibles |
| Reconectando (caída corta) | hubo enlace y `live.connected` cayó hace <15 s (`showsReconnecting`, sin guía de re-emparejado) → **monitor pausado en su lugar** (FC «—», ECG plano, sin punto «en vivo») + pill «Reconectando…» (ámbar `warning`); NO colapsa al CTA mientras la banda reconecta sola (FER-195) |
| Desconectada / sin correa | `!live.connected` sin enlace previo en esta apertura, o tras >15 s sin reconectar, o con guía de re-emparejado activa → pill «Desconectada» + ECG plano + mensaje + **CTA «Conectar»** |
| monitorOnly mode | `monitorOnly: true` (hoja de Hoy "beat by beat", esquema claro) |

**Componentes:** `header` (título + `connectionPill`), `hero` (ECG `dataHeart`/plano + bpm + «en vivo» + latidos de sesión + `rrTachogram`), `signalsSection` (2 grupos: «Capturing live» FC·R-R / «Completes on sync» SpO₂·Temp·Resp·Movimiento, cada renglón con `storedCount`; columnas de ancho fijo; único encabezado de columna **«records»** sobre los conteos en ambos grupos, FER-192/193), `coverageStrip` (28 d **por fuente**: Correa `dataRecovery` / Apple Health `dataSpO2` / Sin datos `hairlineStrong` + leyenda con conteos — reutiliza la clasificación de `DataSourcesView`/`repo.appleHealthDays`, FER-196), `savedFooter` (chips iPhone + iCloud + `verifyButton` con escudo; o línea de aviso/última-sync según estado), `disconnectedState` (CTA «Conectar»), más el estado intermedio **«Reconectando…»** (`showsReconnecting` + ventana `reconnectGraceSeconds` 15 s que pausa el monitor en una caída corta, FER-195). Gestión de correa, batería y entrenamiento **removidos** → Ajustes / *Más › Workouts*. La hoja **abre a la altura del contenido** (detente medido, FER-196); unidad de FC localizada (es «lpm»).

---

### AutomationsView
**Archivo:** `Cenit/Screens/AutomationsView.swift`  
**Descripción:** Double-tap → acción Mac, wear on/off → lock, coaching haptic, alarmas, illness watch.

| Estado | Condición de entrada |
|--------|---------------------|
| Strap no bonded | Sin strap vinculado |
| Strap bonded | Strap vinculado |

**Componentes:** `StatePill (bonded/not)`, `Action picker (None / App / Shortcut)`, `Shortcut name field`, `Test button`, `Moments list (últimos 5 double-taps)`

---

### BreathingView
**Archivo:** `Cenit/Screens/BreathingView.swift`  
**Descripción:** Trainer de respiración con biofeedback HRV en vivo (pacing haptic + visual).

| Estado | Condición de entrada |
|--------|---------------------|
| Setup (pace selector) | Pantalla inicial |
| Idle · bonded | Strap conectado, listo para iniciar |
| Corriendo | Sesión activa + timer + haptics |
| Completo | Sesión terminada |

**Componentes:** `Pace selector (Relax 4–6 / Coherence 5.5 / Box 4–4)`, `Timer display`, `Live HR + zone`, `Rolling RMSSD chart`, `Strap bonded pill`

---

### IntervalTimerView
**Archivo:** `Cenit/Screens/IntervalTimerView.swift`  
**Descripción:** HIIT timer haptic silencioso (work/rest, buzzes en transiciones).

| Estado | Condición de entrada |
|--------|---------------------|
| Config | Pantalla inicial (inputs) |
| Idle | Configurado, listo para iniciar |
| Corriendo | Timer activo, fase actual visible |
| Completo | Rondas terminadas |

**Componentes:** `Duration inputs (Work / Rest / Rounds)`, `Timer display grande`, `Progress ring (phase)`, `Round counter`, `Start / Pause / Reset`

---

## App

### CoachView
**Archivo:** `Cenit/Screens/CoachView.swift`  
**Descripción:** LLM coaching — pregunta sobre recovery/strain/sleep, integración OpenAI/Anthropic.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin clave API | `keyDraft` vacío, sin key guardada |
| Sin consentimiento | Key guardada, toggle data sharing off |
| Vacío (consentido) | Consent dado, sin mensajes aún |
| Con mensajes | Transcript con bubbles |
| Error (API / red) | Error en llamada al LLM |

**Componentes:** `Setup Card (provider/model/key)`, `Consent Bar (toggle)`, `Transcript (bubbles)`, `Suggestion Chips (scroll H)`, `Composer + send button`, `Privacy Footnote`

---

### SettingsView
**Archivo:** `Cenit/Screens/SettingsView.swift`  
**Descripción:** Configuración — perfil (edad, sexo, peso, altura), unidades, strap (estado + controles + **registro del strap** embebido, restaurado en FER-199), experimental, backup, about.

| Estado | Condición de entrada |
|--------|---------------------|
| Vista única (scrollable) | Siempre |

**Componentes:** `SettingsSection cards`, `FormRow (age/sex/weight/height)`, `Units toggles (metric/imperial / °C/°F)`, `Strap card (estado + Re-scan/Disconnect + registro del strap con Copiar/Guardar)`, `Experimental toggle (Puffin)`, `Backup card (export/restore)`, `About card`  
**Navegación:** → `WhatsNewView` (sheet)

---

### DataSourcesView
**Archivo:** `Cenit/Screens/DataSourcesView.swift`  
**Descripción:** Importar datos — WHOOP export (.zip), Apple Health export, sincronización en vivo Apple Health (iOS).

| Estado | Condición de entrada |
|--------|---------------------|
| Idle | Sin proceso en curso |
| Importando WHOOP | `WhoopImporter` corriendo |
| Importando Apple Health | `HealthImporter` corriendo |
| Import completo | Proceso terminado, muestra conteos |

**Componentes:** `WHOOP Export Card`, `Apple Health Export Card`, `Apple Health Live Card (iOS, toggle)`, `Live Strap Card`, `SourcesSummaryCard` (resumen de fuentes al pie, solo iOS · FER-137), `File importer (fileImporter)`

---

### SupportView
**Archivo:** `Cenit/Screens/SupportView.swift`  
**Descripción:** Donaciones + contacto + atribución. Contenido estático.

| Estado | Condición de entrada |
|--------|---------------------|
| Estático | Siempre |

**Componentes:** `Built On Card (atribución)`, `Donate Card (BTC/ETH + copy)`, `Contact Card (mailto)`, `Disclaimer Card`

---

## Sheets y Modales

### ManualWorkoutSheet
**Archivo:** `Cenit/Screens/ManualWorkoutSheet.swift`  
**Presentado por:** `WorkoutsView` (add / edit via context menu)

| Estado | Condición de entrada |
|--------|---------------------|
| Modo agregar | `editing == nil` |
| Modo editar | `editing != nil` (precargado) |
| Validación fallida | Campos requeridos inválidos; Save desactivado |

**Componentes:** `Sport TextField`, `DatePicker (start)`, `Duration spinner (minutos)`, `Avg HR (opcional)`, `kcal (opcional)`

---

### MetricInfoSheet
**Archivo:** `Cenit/Screens/MetricInfoSheet.swift`  
**Presentado por:** `TodayView` (tap de un **tile** de «Métricas de hoy») y `CuerpoView` (filas con hoja clara). **Recuperación ya no usa esta hoja** — desde FER-225 abre `RecoveryDetailScreen` «Instrumento» (Hoy y Cuerpo); la variante `recovery` de `MetricInfo` (las dos filas de Recuperación de abajo) queda sin call sites.

| Estado | Condición de entrada |
|--------|---------------------|
| Estático por métrica | Siempre (strain / sleep / HRV / RHR / SpO₂ / steps) |
| Esfuerzo · con curva | Variante Day Strain, hay puntaje del día y suficiente FC: gráfica «Cómo se acumuló hoy» (esfuerzo acumulado 00:00→ahora, eje Y auto-escalado) |
| Esfuerzo · cargando | Variante Day Strain mientras se calcula la curva (placeholder) |
| Esfuerzo · sin datos | Variante Day Strain sin puntaje / poca actividad: mensaje «Aún no hay suficiente actividad del día para graficar.» |
| Recuperación · con dato | Variante `recovery`: frase llana + desglose de pesos (HRV 60 / FC reposo 20 / Sueño 15 / Temp. piel 10 / Respiración 5) + desplegable «Ver el método» (z-scores + RMSSD, Task Force 1996) + disclaimer (FER-108) |
| Recuperación · calibrando | Variante `recovery` con `recovery == nil`: tarjeta «Calibrando línea base» (N/`minNightsSeed`), pesos atenuados, sin desplegable |
| HRV · con dato | Variante `hrv`: frase llana + nota «es personal» + desplegable «Ver el método» (RMSSD, 300–2000 ms, Malik 20%, ≥20 latidos) (FER-109) |
| HRV · sin dato | Variante `hrv` con `avgHrv == nil`: la nota explica por qué no hay HRV de anoche (FER-109) |
| Cualquier métrica · sin permiso Apple Salud | Métrica que puede venir de Apple Salud (Sueño / HRV / FC en reposo / Oxígeno / Pasos) sin valor y con Apple Salud no conectada: en vez de la nota normal, una línea «Esta lectura puede venir de Apple Salud. Conéctala desde Hoy para verla aquí.» (sin botón; la acción vive en Hoy). Strain y Frecuencia cardíaca (strap-only) nunca la muestran. (FER-162) |

**Nota — tema claro «Instrumento» + copy es-MX (FER-162):** el sheet se presenta en el **tema claro por hora** (`InstrumentoTheme`, pasado explícito desde `TodayView` porque NO se propaga por `.sheet`): papel, tinta y superficies del tema, número del encabezado en el **color de la métrica** (`dataStrain`/`dataSleep`/`dataHrv`/`dataHeart`/`dataSpO2`/`dataSteps`/`dataRecovery`; banda de recuperación para `recovery`) o en tinta secundaria cuando no hay dato; zona activa resaltada con realce + punto + flecha en el color de la métrica, inactivas en tinta tenue. **Todo el copy** (nombres, headlines, zonas, notas, «Ver el método», citas, disclaimer) vive en `Localizable.xcstrings` (es-MX + de) — ya no hay literales en inglés. Las gráficas (`TrendChart`) reciben gradiente del color de la métrica y colores de eje legibles sobre papel.

**Componentes:** `Metric name + headline`, `Valor actual (color de métrica / tinta)`, `Bands (3–4 rangos + active highlight)`, `Nota opcional · o línea de conexión a Apple Salud (FER-162)`, `TrendChart de esfuerzo acumulado (solo Day Strain, FER-110)`, `TrendChart 14 días / curva HR 24h inline en tema claro`, `DisclosureGroup «Ver el método» (Recovery FER-108 + HRV FER-109)`, `Weight breakdown + calibration card (solo Recovery)`

---

### WhatsNewView
**Archivo:** `Cenit/Screens/WhatsNewView.swift`  
**Presentado por:** `SettingsView` ("What's New") · auto-shown on app update

| Estado | Condición de entrada |
|--------|---------------------|
| Lista scrollable | Siempre |

**Componentes:** `Expectations Card`, `Release Cards (AppChangelog.releases)`

---

## Resumen

| Sección | Pantallas | Estados |
|---------|-----------|---------|
| Dashboard | 4 | 14 |
| Actividad | 3 | 10 |
| Análisis | 4 | 13 |
| Dispositivo | 4 | 13 |
| App | 4 | 8 |
| Sheets & Modales | 3 | 6 |
| **Total** | **22** | **~64** |

*Actualizado: 2026-06-16*
