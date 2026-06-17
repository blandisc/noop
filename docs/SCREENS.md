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
Tab bar → 18 destinos principales
SettingsView → WhatsNewView (sheet)
TodayView   → LiveView (fullScreenCover) · MetricInfoSheet (sheet) · WhyVerdictSheet (sheet) · SupportView (toolbar)
WorkoutsView → ManualWorkoutSheet (sheet: add / edit)
MetricExplorerView → MetricDetailView (NavigationLink push, sobre el stack de la pestaña «Más» — FER-171)
```

**Barra de pestañas — «Barra de instrumento»** (`CenitApp/App/InstrumentTabBar.swift`, FER-163). Barra inferior
custom (la nativa va oculta con `.toolbar(.hidden, for: .tabBar)`, montada vía `safeAreaInset`) que **adapta su
tratamiento a la pestaña activa**: bajo **Hoy** viste el papel de «Instrumento diurno» y respira con la hora
(`instrumentoThemeByHour`); bajo Tendencias / En vivo / Sueño / Más usa el `StrandPalette` oscuro. La pestaña activa
se marca con tinta + un punto de «ahora» (verde recovery en claro, `accent` en oscuro), nunca con relleno verde.
Íconos de trazo fino: **Hoy** = glifo de dial 24h (`DialTabGlyph`, StrandDesign), **Sueño** = luna, el resto líneas.

---

## Dashboard

### TodayView
**Archivo:** `Cenit/Screens/TodayView.swift`  
**Descripción:** Hub principal — número de recuperación dominante, palabra del veredicto, dial de 24h y métricas clave. Reingenierizado al lenguaje **«Instrumento diurno»** en iOS (papel cálido que cambia de tono con la hora del día; color saturado solo en el dato) — FER-135.

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

**Nota — Frecuencia cardiaca en Métricas clave (FER-137 · recoloreada FER-135, iOS):** la sección-gráfica de HR de 24h suelta se retiró del `iosBody`. Ahora la FC continua del día es un renglón más de "Métricas clave" (`MetricRow` "Frecuencia cardíaca", línea en el dato `dataHeart`: promedio del día + sparkline de la curva del día), justo encima de "FC en reposo" (par de pulso). Al tocarlo abre `MetricInfoSheet` con `id "heart_rate"`: la curva de 24h (más alta, ~260pt) + Mín/Prom/Máx + una línea de contexto, sin bandas ni párrafo. Sin lecturas del día → renglón "—" y sheet con "Aún no hay lecturas de hoy".

**Nota — tarjeta "Sources" → `SourcesSummaryCard` (estilo FER-119 · ubicación FER-137):** el resumen de fuentes (overline "Sources", una `sourceRow` por fuente —WHOOP en `accent`, Apple Health en `metricCyan`, tinte solo en el glifo— y `syncLine` con `ConnectionDot` bajo un divider, visible solo si `hasData || showsSync`) se extrajo al componente auto-contenido `SourcesSummaryCard` (lee `repo`/`live` y carga sus propios conteos). Vive al **fondo de `DataSourcesView`** y en el Today de macOS (heredado).

**Nota — sección "Fuentes" de vuelta en Hoy (iOS, FER-164):** una variante tematizada de la carta de fuentes regresó al **fondo del `iosBody`** (`iosSourcesSection` + `sourceRow`), en lenguaje «Instrumento diurno» y con **jerarquía reducida**: un overline callado "FUENTES" (no un título como "Métricas clave"), una fila por fuente con el **glifo en color del dato** (WHOOP `dataRecovery` / Apple Salud `dataSpO2`, color solo en el glifo), nombre en `ink` y conteo tabular en `inkSecondary`, divididas por la misma regla de 1pt. **Sin** la línea "Historial sincronizado" (ya vive en `syncMeta` del header). Renderiza nada si no hay ninguna fuente con datos. La `SourcesSummaryCard` compartida queda intacta para sus otros hosts.

**Nota — escala sistémica «Instrumento diurno · L» (iOS, FER-164):** segunda pasada de proporción para llenar la columna de forma armoniosa: héroe `instrumentoHero(76→88)`, títulos de estado vacío `hero(28→32)`, "Métricas clave" `title2→title1`, overline `InstrumentoType.overline` 11→12; `MetricRow` con renglón más alto (padding 12→15), sparkline 50×16→60×26 (`lineWidth` 2.0), valor `number(18→20)` + unidad nuevo token `StrandFont.unit`, y etiqueta que nunca se recorta (`ViewThatFits`: una línea, o el chip baja a segunda línea). El punto de bpm de `LiveHeartbeatRow` se centra (`.center`). La **barra de estado** se vuelve tinta oscura solo en Hoy: el color scheme lo decide `ContentView` según la pestaña activa (`RootTabView` publica `isTodayActive`), con el gate de onboarding/terms en oscuro.

**Nota — Métricas clave con banda de referencia (iOS, FER-135/155):** cada `MetricRow` (Esfuerzo del día, Sueño, HRV, Frecuencia cardíaca, FC en reposo, Oxígeno en sangre, Pasos) dibuja su **gráfica de 14 días** con una **banda de referencia p25–p75** (`ReferenceRange.interquartile`, en tinta `hairlineStrong`) detrás de la línea; la **línea va en el color del dato** de cada métrica (`dataStrain`/`dataSleep`/`dataHrv`/`dataHeart`/`dataSpO2`/`dataSteps`), mientras valor, etiqueta y unidad van en **tinta** del tema (`ink`/`inkSecondary`/`inkTertiary`). Tap de la fila → `MetricInfoSheet`.

**Nota — affordance de tappable en los renglones (iOS, FER-161):** cada `MetricRow` muestra un `chevron.right` tenue (12pt, `inkTertiary`, su propio gap) a la derecha del valor para comunicar que abre detalle; el renglón completo sigue siendo el tap target (envuelto en `MetricRowButtonStyle`, que añade un **fondo pressed sutil** `ink.opacity(0.05)` mientras se mantiene el toque). El chevron se muestra también en renglones sin dato (`—`). Accesibilidad: cada fila es un **botón** con hint "Abre el detalle"; el renglón sin dato lee "sin dato de hoy" en vez de "guion".

**Componentes:** `HealthAlertBanner`, `PaperBackground` (lienzo de papel por hora, FER-135), `heroInstrument` (héroe unificado de 4 modos vía `HeroState`, FER-160), `DiurnalDial` (dial 24h del héroe, FER-135), `LiveHeartbeatRow`, `WhyVerdictSheet`, `MetricRow` (Métricas clave iOS con banda p25–p75 + color por métrica; incl. **Frecuencia cardíaca** → sheet de curva 24h, FER-137), `iosSourcesSection`/`sourceRow` (carta "Fuentes" al fondo, FER-164) · macOS (heredado): `RecoveryRing`, `StatTile ×10`, `ChartCard (HR Trend)`, `SourcesSummaryCard`, `ReadinessGaugeBar`, `readinessSection`  
**Navegación:** → `LiveView` (fullScreenCover, "beat by beat") · → `MetricInfoSheet` (sheet, tap de cualquier fila de «Métricas clave» · tap del **número de recuperación** del héroe → explicador «cómo se calcula», FER-108/109) · → `WhyVerdictSheet` (sheet, **«i»** junto a la palabra del veredicto) · → `DataSourcesView` (sheet, «Conectar Apple Salud») · → `SupportView` (toolbar ❤)

**Nota — `WhyVerdictSheet` en tema claro (FER-167):** el sheet «¿Por qué {veredicto}?» se migró del fondo oscuro `StrandPalette.surfaceBase` al **tema claro «Instrumento»** (igual que `MetricInfoSheet` en FER-162). `TodayView` le pasa el `InstrumentoTheme` **explícito** (no se propaga por `.sheet`); papel/tinta/superficies del tema. Los colores de nivel del chip y la leyenda **espejean `TodayView.verdictDataColor`** (primed/balanced → `verdict`, strained → `warning`, rundown → `critical`, insufficient → `inkTertiary`) para que el héroe y el sheet nunca discrepen; el `colorName` del chip sigue ese mapeo (verde/ámbar/rojo/gris). Copy es-MX + de (FER-113 ya tenía es; FER-167 añade el `de` de los nombres de nivel y el color «rojo»).

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

### SleepView
**Archivo:** `Cenit/Screens/SleepView.swift`  
**Descripción:** Análisis de sueño — etapas, eficiencia, consistencia, vs. típico.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin datos de noche | Sin intervalos de sueño registrados (muestra `ComingSoon`, sin pill de sincronización) |
| Apple Health | Fuente `apple-health` (sin duración en cama) |
| WHOOP · hipnograma | Intervalos WHOOP persistidos |
| WHOOP · estimado | Hipnograma aproximado (stacked bar) |

**Componentes:** `ChartCard (hipnograma/stacked bar)`, `StatTile ×7`, `Stages vs Typical Card`, `Duration Trend ChartCard`

---

### StressView
**Archivo:** `Cenit/Screens/StressView.swift`  
**Descripción:** Monitor de estrés 0–3 basado en RHR + HRV vs. baseline 30 días.

| Estado | Condición de entrada |
|--------|---------------------|
| Calculando | `StressModel` en cálculo |
| Sin datos | Historial vacío |
| Score calculado | z-score disponible |

**Componentes:** `Hero Gauge Card`, `StatTile ×2 (RHR / HRV vs. 30d)`, `ChartCard (tendencia)`, `Metodología (z-score)`

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

### TrendsView
**Archivo:** `Cenit/Screens/TrendsView.swift`  
**Descripción:** Análisis longitudinal — Recovery, HRV, RHR, Day Strain.

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
**Navegación:** → `MetricDetailView` (NavigationLink push; cuelga del único `NavigationStack` de la pestaña «Más», sin stack anidado — FER-171)

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
**Descripción:** Monitor ECG en vivo + gestión de correa (pairing, model picker, workout logging, offload).

| Estado | Condición de entrada |
|--------|---------------------|
| No bonded | Sin strap vinculado |
| Bonded, sin conexión | Strap conocido pero desconectado |
| Conectado, no puesto | `state == .connected` + `worn == false` |
| Puesto · Streaming | `worn == true` + HR en vivo |
| monitorOnly mode | `monitorOnly: true` (desde TodayView "beat by beat") |

**Componentes:** `ECG Hero Sparkline`, `Session Tally`, `Live Signals (zone / %max)`, `Sync Signals (battery / last sync)`, `Data Receipt (frame counts)`, `Coverage Strip (28d heat map)`, `Strap Management (model picker / buzz / offload / forget)`

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
**Descripción:** Configuración — perfil (edad, sexo, peso, altura), unidades, strap, experimental, backup, about.

| Estado | Condición de entrada |
|--------|---------------------|
| Vista única (scrollable) | Siempre |

**Componentes:** `SettingsSection cards`, `FormRow (age/sex/weight/height)`, `Units toggles (metric/imperial / °C/°F)`, `Strap card`, `Experimental toggle (Puffin)`, `Backup card (export/restore)`, `About card`  
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
**Presentado por:** `TodayView` (tap cualquier métrica del grid · tap de los stats **Recuperación** / **HRV** en la fila de síntesis)

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
