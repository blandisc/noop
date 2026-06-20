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
  Coach    → BucleView (pantalla única «el Bucle», FER-292; reemplaza el hub Intelligence · Insights · Coach)
  Entrenar → EntrenarView (hub claro «Instrumento», FER-343): tarjeta «Hoy» + banda de recuperación · «Mis rutinas» (nueva → builder; editar/borrar por menú) · Herramientas (En vivo · Biblioteca → ExerciseLibraryScreen · Respira · Intervalos · Dieta → DietCaptureView: captura BYO-LLM + tracker diario de apego, FER-371/372)
  EntrenarView → RoutineBuilderScreen (sheet: nueva/editar, FER-346) → ExerciseLibraryScreen (sheet add) · RoutineExerciseEditor (sheet)
  ExerciseLibraryScreen (push desde Herramientas, FER-346) → ExerciseDetailScreen (sheet) · CreateExerciseSheet (sheet)
  Ajustes  → AjustesView (raíz clara «Instrumento», FER-337): Perfil · Tu strap (estado + Log de la banda + 5/MG)
             · filas → Unidades y formato · Datos y fuentes · Automatizaciones · Acerca de y soporte
             (mató «Más» + el doble nivel lista→Settings; Explore/Compare/Workouts viven en Cuerpo;
              Sueño · Health · Stress en «Cuerpo» como métricas — FER-186)
AjustesView → UnidadesSheet · StrapLogSheet (sheets claros) · DataSourcesView · AutomationsView · SupportView
             (sheets oscuros «pinned» a .dark en transición hasta su reskin — FER-338/69/67)
DataSourcesView → AppleHealthView (push, «Ver datos importados»)
TodayView   → LiveView (sheet, detente grande) · MetricInfoSheet (sheet; incl. Recuperación — hoja resumida, FER-232) · MetricDetailScreen (sheet, .focus: HRV/FC reposo — FER-185) · WhyVerdictSheet (sheet) · SupportView (toolbar)
             MetricInfoSheet --«Ver más»--> RecoveryDetailScreen / SleepDetailScreen / StrainDetailScreen / StressDetailScreen / MetricDetailScreen .full (detalle rico, sin cambiar de pestaña — FER-251)
CuerpoView  → RecoveryDetailScreen (sheet «Instrumento»: Recuperación — FER-225) ·
             StrainDetailScreen (sheet claro «Instrumento»: Esfuerzo del día — FER-238) ·
             MetricDetailScreen (sheet claro, .full: HRV/FC reposo/Respiración/SpO₂/Frecuencia cardíaca/Pasos — FER-185; SpO₂ con banda clínica fija 95–100% + «Noches bajo 95%» — FER-252; Frecuencia cardíaca con curva intradía + pico marcado + piso de reposo + «Tiempo en zonas» — FER-253; Pasos = conteo de hoy + promedio 7d + tendencia diaria, sin bandas — FER-254) ·
             StressDetailScreen (sheet claro «Instrumento»: Estrés — valor de hoy + bandas universales + qué lo mueve + ⓘ por concepto — FER-241; **«Estrés a lo largo del día»**: el «mapa del día» = carril vertical con la curva intradía cruzada con el calendario, EventKit on-device + `StressEngine`, `StressDayMapBlock` — FER-377) ·
             SkinTempDetailScreen (sheet claro «Instrumento»: Temperatura de la piel — última lectura + tendencia con banda ±típica + consistencia en SD °C — FER-256) ·
             BodyAgeSheet (sheet claro: Edad corporal + Vitalidad — FER-145) ·
             SleepDetailScreen (sheet claro «Instrumento»: Sueño + regularidad del horario — FER-212) ·
             WorkoutsView (sheet claro «Instrumento» + NavigationStack propio — FER-260) ·
             CompareView · MetricExplorerView · DataSourcesView — estos oscuros como sheet fijado a .dark (FER-186)
WorkoutsView → WorkoutDetailScreen (push, detalle de sesión — FER-261) · ManualWorkoutSheet (sheet: add / edit)
EntrenarView → RutinaDeHoyScreen (push, «Rutina de hoy» — FER-343) · BreathingView (push) · IntervalTimerView (push) · TrainingSoonSheet (sheet, builder «llega pronto» — FER-346)
LiveWorkoutHubRow → LiveWorkoutSheet (sheet, detente medio — grabación en vivo, FER-197; fila «En vivo» del hub Entrenar)
MetricExplorerView → MetricDetailView (NavigationLink push, sobre el stack de la pestaña «Ajustes» — FER-171)
```

**Barra de pestañas — «Barra de instrumento»** (`CenitApp/App/InstrumentTabBar.swift`, FER-163; reorganizada a
5 tabs en FER-182). Barra inferior custom (la nativa va oculta con `.toolbar(.hidden, for: .tabBar)`, montada vía
`safeAreaInset`) que **adapta su tratamiento a la pestaña activa**: bajo **Hoy** (papel «Instrumento diurno») viste
el papel y respira con la hora (`instrumentoThemeByHour`); bajo Ajustes usa el
`StrandPalette` oscuro. El color scheme (barra de estado) sigue la pestaña: Hoy / Cuerpo / Coach / Entrenar son papel claro, Ajustes es oscura (`isLightTab` en
`RootTabView`; Entrenar migrado a «Instrumento» en FER-342); En vivo es papel claro pero vive en una **hoja** (`.sheet`) sobre Hoy, no es pestaña (FER-190). La pestaña activa se marca
con tinta + un punto de «ahora» (verde recovery en claro, `accent` en oscuro), nunca con relleno verde. Íconos de
trazo fino: **Hoy** = glifo de dial 24h (`DialTabGlyph`, StrandDesign), el resto glifos de línea (Cuerpo
`chart.xyaxis.line` · Coach `sparkles` · Entrenar `figure.strengthtraining.functional` · Ajustes `gearshape`).

**Nota — hub «Entrenar» «Instrumento» (FER-343):** el tab Entrenar dejó de ser una lista interina y es ahora
`EntrenarView` (papel claro «Instrumento», puerta del tracker de fuerza — épico FER-39). Estructura: una **tarjeta
«Hoy»** (la rutina del día — por ahora la más reciente, sin scheduler aún — + la **banda de recuperación**) que
abre `RutinaDeHoyScreen`; la sección **«Mis rutinas»** (filas que leen `WhoopStore.routines()`, cada una abre su
plan); y **«Herramientas»** (En vivo · Respira · Intervalos). Estado **vacío** (sin rutinas) → tarjeta con CTA
**«Nueva rutina · o desde plantilla»**. El **builder** (FER-346) y el **inicio guiado serie por serie** (FER-347)
están fuera de alcance: sus accesos muestran una nota honesta «llega pronto» (`TrainingSoonSheet`), sin acción real.
La **banda de recuperación** (`RecoveryBand`, compartida con `RutinaDeHoyScreen`) es solo el **contenedor visual**:
mapea la recuperación de hoy a **Sube / Mantén / Baja** (mapeo provisional por recuperación; la regla con evidencia
—HRV-guided + RIR/RPE— es FER-349) y **se oculta sin recuperación** (no inventa). Navega por **push** sobre el
`trainStack` de la pestaña (warm paper de extremo a extremo → sin puente de barra de estado); ese stack también deja
que la nav de capturas (DEBUG) alcance «Rutina de hoy» / Respira / Intervalos.

**Nota — «Iniciar en vivo» en el hub Entrenar (FER-197 · reubicada FER-343):** dentro de «Herramientas», la
fila **«Iniciar en vivo»** (`LiveWorkoutHubRow`, tema claro «Instrumento»; en FER-343 pasó de `Section` de lista a
fila plana en el `VStack` del hub, lee el tema del entorno). Está
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
| Descargando la noche | Offload en curso (`live.backfilling` o `pullSyncing`) y aún sin recovery — gana sobre base/calibrando/sin-lectura mientras drena → `downloading` (FER-286) |
| Veredicto listo | Recovery score calculado |

**Nota — pulido del handoff «Hoy · Estados» (iOS):** cuatro tratamientos visuales del handoff de diseño, **sin tocar estados ni navegación** (las 7 lecturas del héroe y los datos son los mismos): (1) el lienzo pasa de papel plano a un **gradiente radial** cálido — `PaperBackground` ahora es un `EllipticalGradient` con los tokens *derivados* `InstrumentoTheme.paperHi`/`paperLo` (un pozo de luz arriba-centro que se hace más hondo en el borde; siguen amaneciendo/anocheciendo por hora, computados del `paper` vivo en OKLab, sin tocar el init ni los cuatro anclajes); (2) vuelve el **rótulo de sección «Métricas de hoy»** (`metricsSectionLabel`: overline en tinta terciaria AA + regla hairline) sobre la rejilla — lo había retirado FER-282; (3) los tiles de métrica se leen como **tarjetas blancas con sombra tenue** (`surface` + sombra `ink@5%`, radio nuevo `NoopMetrics.tileRadius` = 17, valor 22→23 con piso de escala 18/23 para conservar AA-grande); (4) la variación vs la media de 7 días va en una **pastilla tintada** por valencia (`positiveText`/`negativeText` al 12 % en cápsula, `layoutPriority` externo para que no se parta el texto) — las métricas **sin** valencia (carga / FC) siguen en tinta neutra sin pastilla. **(5, FER-383)** cada tile gana un **ícono SF Symbol** de la métrica junto a la etiqueta, en el color del dato (`TodayMetricTile.icon`): `bolt.fill` (Strain), `moon.fill` (Sleep), `waveform.path.ecg` (HRV), `heart.fill` (Heart Rate), `bed.double.fill` (Resting HR), `drop.fill` (Blood Oxygen), `figure.walk` (Steps), `gauge.medium` (Stress) — otra licencia consciente sobre «color solo en el dato», como las pastillas. **(6, FER-384)** los tiles **sin lectura** (valor «—») atenúan ícono + valor + unidad al token nuevo `InstrumentoTheme.inkDim` (gris cálido apagado, derivado de `inkTertiary`→`paper`; bajo contraste a propósito, no es texto AA) — por-tile, así en «Base Apple Salud» las filas prestadas siguen a color y las strap-only se apagan (`TodayMetricTile.isEmpty`); y el **tick de la mini-banda** pasa al color de la métrica (ver nota FER-258 abajo).

**Nota — héroe «Instrumento diurno» (iOS, FER-135 · supersede FER-113):** el héroe reingenierizado muestra **un número dominante** —la recuperación 0–100 en su **color de banda** (`recoveryDataColor`: verde `dataRecovery` / amarillo `warning` / rojo `critical`, por el umbral `RecoveryScorer.band`)— con el **dial de 24h** (`DiurnalDial`, 94px) a su derecha (hora actual + ventana de sueño on-device vía `SleepWindowClock` + amanecer/atardecer vía `SolarClock`, todo en tinta). Debajo, la **palabra del veredicto** en su propio color de nivel (`verdictDataColor`, independiente del número → pueden divergir) con una **«i»** pegada que abre `WhyVerdictSheet`; el puente reconciliador (`Readiness.bridge`) y la salvedad de noche corta se conservan. La síntesis vieja de 3 celdas (Recuperación/HRV/Sueño) se **fundió**: la recuperación es el héroe, HRV y Sueño bajaron a «Métricas clave». Tocar el número abre el detalle de recuperación. El héroe «dos verdades» (cajas Veredicto/Recuperación), el enlace al pie «¿Por qué {veredicto}?» y `RecoveryRing`/`ReadinessGaugeBar` se retiraron del iOS. Todo el subárbol lee `@Environment(\.instrumentoTheme)`, inyectado por hora con `.instrumentoThemeByHour(solar:)` sobre el lienzo `PaperBackground`.

**Nota — héroe unificado (iOS, FER-160 · consolida FER-135/106):** los cuatro layouts del héroe (`emptyHero`/`importedBaselineHero`/`CalibrationProgressCard`/`verdictSection`) se fundieron en **un solo esqueleto** —`heroInstrument`— parametrizado por un enum `HeroState` (`verdict` / `importedBaseline` / `calibrating(nights)` / `waiting`), derivado de las mismas señales de solo-lectura (`heroState`). Estructura común: overline + **numeral dominante** (`heroNumeral`) + `DiurnalDial` (94px) + **cuerpo** (`heroBody`) + **pie** (`heroFooter`). Invariante **«color = listo / tinta = en espera»**: el numeral lleva color de banda solo con veredicto real; va en **tinta** (`ink`) cuando el nivel es `insufficient` (hay número, no hay contexto → numeral en tinta + línea "Aún sin contexto suficiente para un veredicto del día", **sustituye** el caso que antes caía al anillo `heroSection`); **`N/4`** en tinta mientras calibra; **em-dash `—`** en tinta en espera/base Apple. El pie se adapta por modo (pulso vivo / atajo Apple Salud + pulso / CTA "Buscar strap"). El anillo `heroSection`/`RecoveryRing` queda **solo** en `macBody` (macOS, fuera de alcance).

**Nota — héroe concéntrico (iOS, FER-169 · refina FER-160/164):** el `heroInstrument` pasó de *numeral al lado del dial* a un **instrumento concéntrico centrado**: el `DiurnalDial` crece a **180px** y el `heroNumeral` se **superpone en su centro** (vía `ZStack`), sobre un eje vertical centrado (overline + dial-con-numeral + cuerpo). El número de recuperación se centra en el eje del dial gracias a un **«/100» espejo invisible** (`.hidden()`) que balancea el ancho del «/100» visible —que se conserva a la derecha—; misma técnica para el `N/seed` de calibración. Los cuerpos de cada estado (`heroBody`) se **centran**; el pie (`heroFooter`) y la barra de confianza siguen a lo ancho. El `DiurnalDial` **no** cambia su API ni sus colores (FER-165): solo recibe el numeral encima del centro que antes dejaba vacío a propósito. Numeral `instrumentoHero(88→60)` para caber dentro del anillo sin tocar la banda de sueño ni el punto «ahora».

**Nota — narrativa de onboarding por fuente de datos (FER-106, iOS):** los estados previos al primer veredicto reconocen de dónde viene la base. La señal de lectura `hasImportedBaseline` (≥`minNightsSeed` noches con HRV válida en `repo.days` **y** `ownNights < minNightsSeed`) significa "la base la sembró Apple Health, no la banda" y enruta al modo `importedBaseline` de `heroInstrument` (FER-160): numeral em-dash "—" en tinta + chip "Base · Apple Salud" (en tono de dato `dataSpO2`) + "Falta la lectura de hoy" + "Usa tu banda para sumar… la lectura de hoy" — nunca muestra "0 de 4" como si no hubiera base. Su pie se adapta: CTA "Buscar strap" si no se ha visto strap, `LiveHeartbeatRow` si ya. Sin import, el modo `calibrating` mantiene el conteo 0→4 (numeral `N/4` + night-dots) con copy de **base propia** (no "veredicto") + un atajo "¿Tienes historial en Apple Salud? Conéctalo…" que abre Data Sources. Sin import/permiso, `hasImportedBaseline` es falso por construcción, así que ningún estado promete una base de Apple Health que no existe. Es el hermano de FER-105 (la línea de confianza del veredicto, que cubre el momento *después* del primer veredicto).

**Nota — indicador de sincronización (iOS):** cuando `live.backfilling == true`, la `syncMeta` en la `utilityRow` muestra "Sincronizando historial…" en tinta terciaria del tema (`inkTertiary`) en lugar del texto habitual "Sincronizado hace X" / "Última sincronización: nunca". No hay pill ni color prominente; el texto vuelve al estado normal al terminar el backfill. El pill `SyncingHistoryNote` se conserva solo en el path macOS de esta vista.

**Nota — pull-to-refresh propio que dibuja el dial (iOS, FER-222 · reemplaza el nativo de FER-204):** el `iosBody` ya **no** usa `.refreshable` (ni su ruedita gris de iOS). El `ScrollView` publica el offset de su tope en un coordinate space propio (`todayPullScroll`) vía un `GeometryReader` de fondo (`TodayScrollOffsetKey`) y `.scrollBounceBehavior(.always)` (rebota aunque el contenido quepa exacto, para que el tirón funcione sin el `.refreshable`); `handlePullOffset` mapea el tirón a `pullProgress` (0→1), que **arma el arco verde del `DiurnalDial`** (parámetro nuevo `armProgress`, crece hasta ~0.90 del aro proporcional al desplazamiento). Al cruzar `pullThreshold` (96pt) se dispara **una vez por gesto** la misma acción de FER-204 (`pullToSync` vía `triggerPullSync`: háptica `.impact(weight: .medium)` sobre `syncHaptic` + `syncNow()`/`scan()` + «soltar pronto» ~1.2 s + `repo.refresh()`), y el dial pasa a **girar** (modo `syncing` de FER-221, encendido de inmediato por `pullSyncing` aunque el offload tarde o no arranque). Soltar antes del umbral no dispara. La acción (`pullToSync`) ramifica por estado igual que antes: conectada → `syncNow()` (offload `.manual`, sin rate-limit); banda conocida pero desconectada (`lastSyncedAt != nil`) → `scan()`, y el handshake de reconexión auto-dispara el sync (`requestSync(.connect)`); sin banda conocida → solo `repo.refresh()` local, sin escaneo ni error. **VoiceOver**: como ya no hay `.refreshable` (que regalaba una acción de refrescar accesible), la `utilityRow` del header expone una **acción personalizada «Sincronizar»** equivalente al gesto (vía `triggerPullSync`). **Reduce Motion**: no se dibuja el arco progresivo (`pullProgress` se queda en 0) — el gesto sigue armando + disparando con su háptica, y el dial reposa. El offload largo sigue reflejándose en `syncMeta`; al llegar datos los scores se recalculan solos vía `repo.refreshSeq`. No toca el protocolo BLE — reusa `syncNow()`/`scan()` existentes.

**Nota — pista descubrible del pull-to-refresh (iOS, FER-293 · supersede FER-270/FER-274):** la pista que invita al gesto (`syncHint`, overlay `.top` que **no** ocupa alto de layout) pasó de un `chevron.down` mudo a un **chevron que rebota suave** (`StrandMotion.bob`, repeatForever autoreverses) **+ el microcopy «Desliza para actualizar»** (`StrandFont.caption`, `inkTertiary`) apilado debajo. Cambios de visibilidad (`showsSyncHint`): (1) se muestra **con o sin strap** —jalar igual recarga datos locales—, ya no solo con banda; (2) se desvanece al **iniciar el gesto** (`pullProgress > 0`) revelando el arco del dial, y mientras `live.backfilling || pullSyncing`; (3) tras el **primer** pull-to-sync (`didFirstPullSync`) se retiran el texto y el rebote pero **el chevron permanece** como cue sutil — sigue descubrible, en vez de apagarse para siempre como en FER-270. **Reduce Motion**: sin rebote (chevron + texto estáticos). **VoiceOver**: la pista es `accessibilityHidden` — su equivalente es la acción «Sincronizar» del header (ver nota anterior).

**Nota — Frecuencia cardiaca en Métricas clave (FER-137 · recoloreada FER-135, iOS):** la sección-gráfica de HR de 24h suelta se retiró del `iosBody`. Ahora la FC continua del día es un renglón más de "Métricas clave" (`MetricRow` "Frecuencia cardíaca", línea en el dato `dataHeart`: promedio del día + sparkline de la curva del día), justo encima de "FC en reposo" (par de pulso). Al tocarlo abre `MetricInfoSheet` con `id "heart_rate"`: la curva de 24h (más alta, ~260pt) + Mín/Prom/Máx + una línea de contexto, sin bandas ni párrafo. Sin lecturas del día → renglón "—" y sheet con "Aún no hay lecturas de hoy".

**Nota — tarjeta "Sources" → `SourcesSummaryCard` (estilo FER-119 · ubicación FER-137):** el resumen de fuentes (overline "Sources", una `sourceRow` por fuente —WHOOP en `accent`, Apple Health en `metricCyan`, tinte solo en el glifo— y `syncLine` con `ConnectionDot` bajo un divider, visible solo si `hasData || showsSync`) se extrajo al componente auto-contenido `SourcesSummaryCard` (lee `repo`/`live` y carga sus propios conteos). Vive al **fondo de `DataSourcesView`** y en el Today de macOS (heredado).

**Nota — sección "Fuentes" de vuelta en Hoy (iOS, FER-164 · *retirada en FER-189*: Hoy ya no muestra Fuentes — vive en Fuentes de datos / Ajustes; `iosSourcesSection`/`sourceRow` eliminados):** una variante tematizada de la carta de fuentes regresó al **fondo del `iosBody`** (`iosSourcesSection` + `sourceRow`), en lenguaje «Instrumento diurno» y con **jerarquía reducida**: un overline callado "FUENTES" (no un título como "Métricas clave"), una fila por fuente con el **glifo en color del dato** (WHOOP `dataRecovery` / Apple Salud `dataSpO2`, color solo en el glifo), nombre en `ink` y conteo tabular en `inkSecondary`, divididas por la misma regla de 1pt. **Sin** la línea "Historial sincronizado" (ya vive en `syncMeta` del header). Renderiza nada si no hay ninguna fuente con datos. La `SourcesSummaryCard` compartida queda intacta para sus otros hosts.

**Nota — escala sistémica «Instrumento diurno · L» (iOS, FER-164):** segunda pasada de proporción para llenar la columna de forma armoniosa: héroe `instrumentoHero(76→88)`, títulos de estado vacío `hero(28→32)`, "Métricas clave" `title2→title1`, overline `InstrumentoType.overline` 11→12; `MetricRow` con renglón más alto (padding 12→15), sparkline 50×16→60×26 (`lineWidth` 2.0), valor `number(18→20)` + unidad nuevo token `StrandFont.unit`, y etiqueta que nunca se recorta (`ViewThatFits`: una línea, o el chip baja a segunda línea). El punto de bpm de `LiveHeartbeatRow` se centra (`.center`). La **barra de estado** se vuelve tinta oscura solo en Hoy: el color scheme lo decide `ContentView` según la pestaña activa (`RootTabView` publica `isTodayActive`), con el gate de onboarding/terms en oscuro.

**Nota — Métricas clave con banda de referencia (iOS, FER-135/155 · *superado por FER-180*: la tendencia 14d salió de Hoy hacia la hoja / «Cuerpo»):** cada `MetricRow` (Esfuerzo del día, Sueño, HRV, Frecuencia cardíaca, FC en reposo, Oxígeno en sangre, Pasos) dibuja su **gráfica de 14 días** con una **banda de referencia p25–p75** (`ReferenceRange.interquartile`, en tinta `hairlineStrong`) detrás de la línea; la **línea va en el color del dato** de cada métrica (`dataStrain`/`dataSleep`/`dataHrv`/`dataHeart`/`dataSpO2`/`dataSteps`), mientras valor, etiqueta y unidad van en **tinta** del tema (`ink`/`inkSecondary`/`inkTertiary`). Tap de la fila → `MetricInfoSheet`.

**Nota — affordance de tappable en los renglones (iOS, FER-161 · *superado por FER-180*):** cada `MetricRow` muestra un `chevron.right` tenue (12pt, `inkTertiary`, su propio gap) a la derecha del valor para comunicar que abre detalle; el renglón completo sigue siendo el tap target (envuelto en `MetricRowButtonStyle`, que añade un **fondo pressed sutil** `ink.opacity(0.05)` mientras se mantiene el toque). El chevron se muestra también en renglones sin dato (`—`). Accesibilidad: cada fila es un **botón** con hint "Abre el detalle"; el renglón sin dato lee "sin dato de hoy" en vez de "guion".

**Nota — «Métricas clave» (lista 14d) → «Métricas de hoy» (rejilla intradía) (iOS, FER-180 · supersede FER-155/161):** la nueva IA del rediseño separa **Hoy = foto del día** de **Cuerpo = tendencia**. La sección `iosMetricsSection` dejó de ser una **lista** de `MetricRow` (label · sparkline 14d + banda p25–p75 · valor · chevron) y pasó a una **rejilla 2×4 de 8 tiles** `TodayMetricTile` («Métricas de hoy»). Cada tile: **etiqueta (overline en tinta)** · **valor de hoy en su color de dato** (`dataStrain`/`dataSleep`/`dataHrv`/`dataHeart`/`dataSpO2`/`dataSteps`; Estrés bandeado por `verdict`/`warning`/`critical` según nivel 0–3) + unidad · pie con la **Δ vs ayer** (mejora→`verdict`, empeora→`critical`, igual→`inkTertiary`, **sin valencia** —Esfuerzo, FC— en tinta neutra), el badge **«Apple Salud»** cuando el valor vino de Apple (`resolveMeasured`/`fromApple`), o nada (sin ayer / sin valor). **Sin sparkline de 14 días.** Tile tematizado (`surface` + hairline, `cornerRadius` `NoopMetrics.cardRadius`, `tileHeight`), nunca el `NoopCard` oscuro; pulsado vía `TileButtonStyle` (overlay redondeado). Las **8 tiles**: Esfuerzo del día · Sueño · HRV · Frecuencia cardíaca (promedio del día, **sin Δ** — no hay promedio diurno de ayer guardado) · FC en reposo · Oxígeno en sangre · Pasos (sin meta) · **Estrés** (proxy 0–3 vía `StressModel`, cargado en `loadAll`). **Recuperación NO es tile** (ya es el numeral del héroe). La **tendencia 14d** ya no vive en Hoy: sigue accesible al tocar un tile (la hoja la trae, `trendLoader`), interino hasta el Detalle de Métrica de «Cuerpo». Tap de un tile → `MetricInfoSheet` de esa métrica (`strain`/`sleep`/`hrv`/`heart_rate`/`rhr`/`spo2`/`steps`/**`stress`** nuevo). El nudge «Conectar Apple Salud» se conserva al pie de la sección.

**Nota — procedencia Apple Salud al pie del detalle (iOS):** las hojas `MetricInfoSheet` que abre Hoy muestran, **al pie** (tras nota/disclaimer, antes de «Ver más»), una línea discreta de procedencia `appleSourceLine` —`heart.fill` en `dataHeart` + «Apple Health», texto en `inkTertiary`— **sólo cuando el valor mostrado vino de Apple Salud y no del strap**. Es dinámica, no fija por métrica: `TodayView.metricSheet(for:)` resuelve `fromApple` por lectura con la misma `resolveMeasured(...).fromApple` que las tiles (HRV/FCrep/Sueño/SpO₂ pueden venir de cualquier fuente; pasos = siempre Apple; esfuerzo/FC/recuperación/estrés = nunca) y la pasa como `appleSource:` sólo si hay valor (`displayValue != "—"`), por lo que no choca con el hint «conéctate a Apple Salud». Extiende al detalle la misma convención de marca de los tiles (FER-278); los datos del strap siguen sin marca.

**Nota — Hoy cabe en una pantalla (iOS, FER-189 · sobre FER-180):** tres ajustes de composición para que Hoy (estado veredicto típico) entre sin scroll, sin tocar el héroe (dial 180 intacto). (1) **«Verlo latido a latido» (`LiveHeartbeatRow`) se mudó del pie del héroe al PIE de Hoy** (`iosBody`, tras las tiles, sólo si `strapSeen`): el héroe queda limpio —overline + dial-con-numeral + veredicto—; `heroFooter` ahora sólo lleva el CTA «Buscar strap» (sin strap) o el atajo Apple Salud (calibrando), nada en veredicto/espera-con-strap. (2) **Se retiró la sección «Fuentes»** de Hoy (`iosSourcesSection`/`sourceRow`/`metricSeparator` eliminados; vive en Fuentes de datos / Ajustes). (3) **Las tiles bajan de alto** (`TodayMetricTile`: 104 → **76pt fijo**, padding 14→10, valor `number(24→22)`, etiqueta a **una línea** con `minimumScaleFactor`), para una rejilla 2×4 compacta y pareja.

**Nota — pulso vivo en el encabezado de «Métricas de hoy» (iOS, FER-194 · supersede el punto (1) de FER-189):** la fila full-width «Verlo latido a latido» (`LiveHeartbeatRow`) del pie se **eliminó**; su acceso al monitor latido a latido se mudó al **trailing del encabezado** «Today's metrics» como una **pastilla de pulso** (`LivePulsePill`): cápsula `surface` + hairline con `heart.fill` en tinta + **punto de pulso** (`dataHeart` al transmitir, tinta si no) + **bpm** del día (`liveBpm`) + «bpm»; sin lectura → «—», sigue tappable. Sólo aparece si `strapSeen` (si no, el encabezado queda solo con el título y el héroe ofrece «Buscar strap»). Al tocarla abre el **mismo** `LiveView` en hoja (`.sheet`, FER-190) — el monitor no cambia. Libera el pie de Hoy (regla «color sólo en el dato»: únicamente el punto lleva color). El tile «Frecuencia cardiaca» (promedio del día) se conserva; la rejilla sigue 2×4.

**Nota — Hoy cabe en una pantalla en calibrando (iOS, FER-202 · continúa FER-189 · revisa FER-169/164):** el estado **calibrando** (el más alto de Hoy) aún se desbordaba; cuatro recortes (~115pt) para que entre sin scroll en iPhone 15/16, sin tocar datos ni `HeroState`. (1) **Dial `DiurnalDial` 180 → 118px** y **numeral `instrumentoHero(60→52)`**. (2) **El «/100» (y el `N/seed` de calibración) pasa de *«/100» espejo invisible a la derecha* a *apilado pequeño y centrado DEBAJO del número*** (`heroNumeral`: `HStack` con mirror → `VStack` centrado): queda centrado de verdad sobre el eje del dial y sin desbordar el aro — **supersede el truco de FER-169**. (3) **`calibrationConfidence` compacto**: la procedencia «· base Apple Salud» se pliega en la misma línea de la etiqueta (antes era un 3.er renglón) + barra 6→5px. (4) **Ritmo**: gap de sección 28→18, inset superior 20→12, spacing del héroe 14→11, y **tiles `TodayMetricTile` 76 → 70pt** (padding vertical 10→8). El estado **veredicto** sigue cabiendo holgado.

**Nota — «Métricas de hoy» se compara vs tu media de 7 días, no vs ayer (iOS, FER-258 · supersede el «Δ vs ayer» de FER-180/233):** cada `TodayMetricTile` dejó de comparar contra ayer y ahora contra la **media de 7 días** de esa métrica. La media + el rango típico **p25–p75** se computan on-device de `repo.displayDays` (días anteriores a hoy, helpers `baselineDays`/`history`/`tileContext`/`bandViz`; estrés vía `stressHistory` del proxy 0–3 de `StressModel`), reusando `ReferenceRange.interquartile` (StrandDesign). El pie del tile muestra **flecha + magnitud absoluta + «vs tu media 7d»** (VoiceOver: «sobre/bajo tu media de 7 días», flecha oculta); dentro del deadband → **«En tu media de 7 días»**; con <4 días de base → **«Aún construyendo tu media»** (sin flecha ni banda); sin valor de hoy → línea vacía. Bajo el valor, la nueva **`MetricBand`** dibuja el rango típico (`hairline`/`hairlineStrong`, en gris) con un **tick en el color de la métrica** (`MetricBand.tickColor` = `valueColor`; **FER-384**, antes `inkTertiary`) en el valor de hoy — la pista y la banda siguen en gris; el tick a color es licencia consciente sobre «color solo en el dato», como las pastillas/íconos. Polaridad reusa el `betterHigher` previo (HRV/Sueño/SpO₂/Pasos suben=bueno; FC reposo/Estrés suben=malo; Esfuerzo y FC sin valencia). **Tiles 70 → 88pt** para acomodar banda + pie (puede reintroducir algo de scroll en calibrando — trade-off aceptado, ver FER-205). Strings es/en/de en `Localizable.xcstrings`.

**Nota — encabezado compacto «Hoy» + sync inline + pulso como chip (iOS, FER-265 · sobre FER-258/194/233):** el título grande «Today's metrics» (`title1`, 28pt) se retiró; en su lugar un **sello «Hoy»** (overline `inkSecondary`) + la **sincronización inline** (`SyncInline`, que **sube desde el pie**): glifo `arrow.triangle.2.circlepath` + tiempo relativo en reposo, glifo **girando** (`StrandMotion.spin()`, respeta Reduce Motion) + **«N paquetes»** / «Sincronizando…» al hacer backfill. El pulso vivo `LivePulsePill` se rediseñó a **chip tocable** (punto que late + bpm + `chevron.right`, sin el `heart.fill` ni la cápsula ancha). El encabezado usa `ViewThatFits`: a Dynamic Type grande el chip baja a una segunda línea. **`syncMeta` se eliminó** (su contenido vive ahora arriba); el pie de la rejilla queda solo con la leyenda de fuentes (W · ♥) + el nudge. **Tiles 88 → 76pt**: la mini-banda y el cambio vs media van en **una sola línea** de pie (banda flexible + flecha/magnitud + «vs media» · deadband «En tu media» · poca historia «Aún construyendo tu media»), en vez de dos. Mata el desborde de FER-258. Strings nuevas (`vs avg`/`At your average`/`%lld packets`) es/en/de.

**Nota — sin sello «Today» + pulso junto al veredicto (iOS, FER-282 · reubica FER-194/265):** el **encabezado de «Métricas de hoy» se eliminó** —el sello «Hoy» se quitó y la pastilla de pulso `LivePulsePill` se **mudó a la línea del veredicto**—, así que la rejilla de tiles sube pegada al héroe (recupera ~26pt, ayuda a que Hoy quepa). En la línea del veredicto, la **palabra** del veredicto + «i» quedan **centradas en el eje del dial** y la pastilla se **ancla a la derecha** en la misma altura (helper `withPulsePill`: un placeholder invisible del mismo ancho a la izquierda hace de espejo para no descentrar la palabra; en Dynamic Type grande la pastilla **baja debajo** vía `ViewThatFits` en vez de encimarse). El mismo anclaje aplica a los otros estados con strap visto (calibrando: junto a los night-dots; espera-con-strap: junto al titular; base-Apple: junto al chip). La pastilla sigue tocable → `LiveView`; sin strap no aparece (igual que antes).

**Nota — dial del veredicto de vuelta a 180 (iOS, FER-205 · revierte el punto (1) de FER-202):** al dueño no le gustó el dial encogido, así que el `DiurnalDial` regresó **118 → 180px** y el numeral **52 → 60** (`heroNumeral`, los 4 estados). Se **conserva** el «/100»/«N/seed» apilado y centrado de FER-202 y las demás compactaciones (calibración a 2 renglones, tiles 70pt, ritmo 18/12/11). Con el dial grande, Hoy puede volver a requerir algo de scroll en estado calibrando — trade-off aceptado por el dueño.

**Nota — tiles de día honestos a medianoche (iOS, FER-341):** al cruzar la medianoche, antes del sync de la mañana, los tiles **de día** dejan de mostrar el dato de ayer bajo el encabezado de hoy. (1) **Esfuerzo del día**: el esfuerzo del día EN CURSO se calcula sobre su propio **día civil** (no la ventana de detección de sueño de ~42h, que recién pasada la medianoche es toda de ayer) — `AnalyticsEngine.analyzeDay(strainCivilDayOnly:)` que `IntelligenceEngine` activa solo para `offset == 0`; temprano en el día → `strain` nil → tile «—». Días pasados intactos (cero regresión). (2) **Sueño**: `resolveMeasured(todayOnly:)` quita el respaldo «hoy/ayer» **solo** para el sueño → sin sueño de hoy muestra el placeholder **«Esta noche»** (`TodayMetricTile.placeholder`). Las nocturnas (HRV/FC reposo/SpO₂) **conservan** la ventana hoy/ayer (decisión del dueño). Así el héroe, el encabezado y estos dos tiles concuerdan sobre si hay datos de hoy.

**Componentes:** `HealthAlertBanner`, `PaperBackground` (lienzo de papel por hora, FER-135), `heroInstrument` (héroe unificado de 4 modos vía `HeroState`, FER-160), `DiurnalDial` (dial 24h del héroe, FER-135), `LivePulsePill` (pastilla de pulso tocable en la línea del veredicto, anclada a la derecha — punto + bpm + chevron, FER-194/265/282), `SyncInline` (sincronización inline en la línea de estado del header, FER-265/278), `WhyVerdictSheet`, `TodayMetricTile`/`TileButtonStyle`/`MetricBand` (rejilla «Métricas de hoy» 2×4, valor + mini-banda p25–p75 + cambio vs media en una línea, tiles 76pt, realce al pulsar FER-213, FER-180/189/202/258/265) · macOS (heredado): `MetricRow`, `RecoveryRing`, `StatTile ×10`, `ChartCard (HR Trend)`, `SourcesSummaryCard`, `ReadinessGaugeBar`, `readinessSection`  
**Navegación:** → `LiveView` (sheet detente grande, "beat by beat" — FER-190) · → `MetricInfoSheet` (sheet, tap de cualquier **tile** de «Métricas de hoy» —incl. la variante **`stress`** nueva, FER-180— · tap del **número de recuperación** del héroe → hoja resumida `recovery`, FER-232) · → `WhyVerdictSheet` (sheet, **«i»** junto a la palabra del veredicto) · → `DataSourcesView` (sheet, «Conectar Apple Salud») · → `SupportView` (toolbar ❤)

**Nota — «Ver más»: de la hoja resumida al detalle rico (FER-251):** `MetricInfoSheet` recibe un `onSeeMore: (() -> Void)?` opcional; cuando no es `nil` dibuja un enlace **«Ver más»** al pie, alineado a la derecha (pastilla en el color de la métrica + chevron). Al tocarlo, Hoy **profundiza en sitio** (sin cambiar de pestaña): cierra el resumen y presenta el **mismo** detalle rico que abre Cuerpo — `RecoveryDetailScreen` (Recuperación), `SleepDetailScreen` (Sueño), `StrainDetailScreen` (Esfuerzo), `StressDetailScreen` (Estrés) o `MetricDetailScreen` `.full` (HRV/FC reposo/Frecuencia cardíaca/Pasos) — reusando las **mismas factories estáticas** (`RecoveryDetailModel.build` / `SleepDetailModel.build` / `StrainDetailModel.build` / `MetricDetailSpec.hrv`/`.restingHR`/`.heartRate`/`.steps`), así que el detalle es idéntico desde ambas pestañas. La presentación sheet-sobre-sheet se difiere al `onDismiss` del resumen (`pendingSeeMore`) para que iOS no se trague el segundo `.sheet`; al cerrar el detalle el usuario vuelve a Hoy. **Frecuencia cardíaca y Pasos ya abren su detalle rico** (FER-253/254); **SpO₂ aún no muestra el enlace** (FER-252).

**Nota — `WhyVerdictSheet` en tema claro (FER-167):** el sheet «¿Por qué {veredicto}?» se migró del fondo oscuro `StrandPalette.surfaceBase` al **tema claro «Instrumento»** (igual que `MetricInfoSheet` en FER-162). `TodayView` le pasa el `InstrumentoTheme` **explícito** (no se propaga por `.sheet`); papel/tinta/superficies del tema. Los colores de nivel del chip y la leyenda **espejean `TodayView.verdictDataColor`** (primed/balanced → `verdict`, strained → `warning`, rundown → `critical`, insufficient → `inkTertiary`) para que el héroe y el sheet nunca discrepen; el `colorName` del chip sigue ese mapeo (verde/ámbar/rojo/gris). Copy es-MX + de (FER-113 ya tenía es; FER-167 añade el `de` de los nombres de nivel y el color «rojo»).

**Nota — la «noche corta» se explica en el sheet (FER-285):** cuando el día sale con **confianza baja por noche corta** (`readiness.confidenceLow`, umbral `ReadinessEngine.shortNightMinutes = 360`), el Hero ya solo muestra una **línea corta** «Noche corta — confianza baja» (antes mostraba el `confidenceNote` largo del engine); la **explicación** vive en `WhyVerdictSheet`, que estrena un **bloque** (en tono `warning`) «Confianza baja — noche corta» con copy **dinámica** según las **horas reales de anoche** —`TodayView` le pasa `repo.today?.totalSleepMin` como `sleepMinutes`, porque `Readiness` no lo carga—: «Anoche dormiste 5 h 12 min, por debajo de las 6 h. Una noche corta deprime tu HRV…». Sin el dato, dice «menos de 6 h». Strings es/en/de en `Localizable.xcstrings`.

**Nota — explicación tras ⓘ en `MetricInfoSheet` (FER-243):** la explicación de texto (`info.headline`) ya **no** se muestra siempre bajo el header; arranca **oculta** y se despliega in-place con una **ⓘ `info.circle`** junto al nombre de la métrica (estado `headlineExpanded`). La ⓘ va en `inkTertiary` cerrada y en el `metricHue` de la métrica cuando está abierta; anima con `StrandMotion.interactive`. Aplica a todas las métricas del sheet (Sueño, Estrés, etc.). El resto del sheet (curvas, bandas, método, nota) no cambia.

**Nota — gráfica con bandas de clasificación en `MetricInfoSheet` (FER-244):** para **Sueño** y **Estrés**, la gráfica «Últimos 14 días» deja el eje Y auto-escalado (en Sueño venía en minutos) y se ancla a las clasificaciones de la métrica vía `TrendChart(bands:bandColor:yAxisValues:)` (StrandDesign). La banda donde cae el último valor se resalta (franja `bandColor.opacity(0.12)` + bordes), las vecinas quedan insinuadas por las grid-lines del eje en los umbrales, y bajo el título aparece «‹Banda› · N de los últimos N días en este rango» (helper puro `TrendBands.activeBand`). Sueño se convierte a **horas**; Estrés usa su score 0–3. `MetricInfo.Band` ganó `lower`/`upper` (solo poblados en sleep/stress). Las demás métricas pasan `bands` vacío y conservan la gráfica de antes.

**Nota — realce al pulsar en los tiles (iOS, FER-213 · ajusta el «pulsado» de FER-180):** `TileButtonStyle` pasó del **darken** (overlay `ink.opacity(0.05)`) a un **realce**: al pulsar, el tile se **eleva** (`scaleEffect(1.03)`) y su borde pasa a `hairlineStrong`, sin sombra; en reposo no hay marca. Es lo único que sobrevivió de FER-210 (el zoom-morph de apertura se **revirtió** — PR #171); la apertura del detalle sigue siendo el `.sheet` estándar (desde abajo).

**Nota — el dial gira al sincronizar (iOS, FER-221):** el `DiurnalDial` estrena un modo **«sincronizando»** (parámetro `syncing: Bool`, pasado desde `TodayView` como `live.backfilling`): mientras la banda descarga su historial, un **arco de progreso `dataRecovery`** con punto líder **gira** sobre el bezel (`StrandMotion.spin()`, ~1.5 s/vuelta, indeterminado — sin %, el protocolo no revela el total), el **now-dot fijo de la hora se oculta** (su verde se muda al arco) y el resto del reloj (arco de día, banda de sueño, ticks) **permanece fijo**. En `TodayView`, el numeral del héroe se **atenúa** a `inkTertiary` mientras `live.backfilling` (`heroNumeralInk`) y vuelve a tinta al terminar. **Reduce Motion**: el arco **no gira** (reposa estático) y el `accessibilityLabel` del dial antepone «Sincronizando». **La honesty line del header (`syncMeta`) no cambia** — todo el protagonismo del sync pasa al dial, en lugar de la ruedita nativa. Reemplaza la señal genérica de sync en Hoy. El mismo modo `syncing` lo reusa el pull-to-refresh propio de **FER-222**, donde además el arco se **arma** con el tirón (`armProgress`) antes de girar (ver la nota de pull-to-refresh arriba).

**Nota — el Hero dice «Descargando la noche…» mientras drena (iOS, FER-286):** `HeroState` estrena un quinto modo, **`downloading`**, que gana sobre `importedBaseline`/`calibrating`/`waiting` (no sobre `verdict`) cuando hay un offload en curso (`live.backfilling || pullSyncing`) y aún no hay recovery de hoy. Antes, en ese momento el Hero caía a `importedBaseline` y mostraba «Falta la lectura de hoy / Usa tu banda…» —engañoso, porque el dato venía en camino—. Ahora muestra titular **«Descargando la noche…»** + línea «Tus datos de anoche están llegando. La primera sincronización del día puede tardar unos minutos.», con el numeral em-dash «—» en tinta y **sin pie** (no «Buscar strap»: el strap ya está conectado). Reusa la misma señal que ya hace girar el dial (FER-221), sin agregar otra; al completar el offload y computarse la recovery, pasa a `verdict`. Motivado por el diagnóstico de sync mañanero de la WHOOP 4.0 (una noche desconectada bufferea ~19,400 frames a 1 Hz y el offload tarda minutos). Strings es/en/de en `Localizable.xcstrings`.

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
**Descripción:** Detalle de Sueño «Instrumento» (claro) — el sueño migrado del viejo `SleepView` oscuro al lenguaje «Instrumento» (FER-212). Se abre desde **Cuerpo** como **sheet** con el `InstrumentoTheme` pasado **explícito** (no se propaga por `.sheet`, FER-162) y **sin `NavigationStack` anidado** (FER-171). Es un **superset** del viejo SleepView (hipnograma, etapas —ahora en **%**, no minutos—, anoche-vs-típico, tendencia de duración (14 noches + 4 bandas de clasificación, idéntica a la hoja de Hoy) + **`TrendStatSummary`** debajo (promedio en horas protagonista + rango «Varió entre X y Y»; sin chip vs el periodo anterior porque es ventana fija sin serie larga — FER-250) + bloque propio de deuda semanal (cifra dominante + barras por noche arrastrables), métricas de la noche: rendimiento, eficiencia, restaurador, respiración, despertares) **más un bloque nuevo de regularidad del horario** (motor `SleepRegularity`, FER-218: score 0–100 vía SD del punto medio + desfase de fin de semana + estado «se está afinando»; **aviso de siesta excluida** al pie cuando la ventana descartó ≥1 sesión < 3 h —solo la noche principal cuenta—, FER-310). Reusa `Hypnogram`/`TrendChart` de `StrandDesign` y el scaffold de `MetricDetailScreen` (`block`/`hero`/`SheetPaperBackground`/`methodDisclosure`). Es presentación pura sobre un `SleepDetailModel` que el llamador (Cuerpo) construye desde `repo` (la pantalla queda sin DB).
**Pasada de UI (FER-227):** ritmo por espacio — secciones separadas por `NoopMetrics.sectionGap` **sin filete** entre ellas (el hairline solo divide dentro de un grupo). Las **tiles de «Métricas de la noche» son tocables** (cada una con una **ⓘ `info.circle`** en la esquina) y abren su `MetricInfoSheet` con headline + **mini-tendencia 14d** (`trendLoader` sobre series precomputadas en `SleepDetailModel`) + bandas; ids nuevos `sleep_performance`/`sleep_efficiency`/`sleep_restorative`/`sleep_awakenings`/`sleep_latency` (+ `resp_rate` reusa `MetricInfo.respiratory`). Una **ⓘ junto al overline «Anoche»** abre `SleepStagesInfoSheet`, una tarjeta combinada que explica REM/profundo/ligero/despierto + por qué son aproximadas (absorbe el viejo caption «Etapas aproximadas»). **footer de fuente eliminado** (consistencia con el resto). **Tendencia de duración y deuda unificadas con Hoy (FER-249 v2):** la gráfica de tendencia pasó de 30d/1-banda a **14 noches + 4 bandas de clasificación** (Short/Adequate/Optimal/Extended, activa resaltada, encabezado de conteo, ticks en 6/7/9 h) — la misma `bandedTrend` que la hoja de Sueño en Hoy. La **deuda semanal** dejó de ser una línea de texto y es ahora su **propio bloque**: la cifra acumulada como dato dominante (en `warning`) + un **bar chart por noche** (`Charts.BarMark`) con la necesidad como regla cero — barra abajo (`warning`) si la noche se quedó corta, arriba (`verdict`) si la superó; se oculta sin deuda ≥15 min. **Pulido FER-249 v3:** la tendencia perdió el relleno de área (`showsArea:false`, enturbiaba las bandas) y la **banda activa ahora SIEMPRE muestra su etiqueta** aunque sea delgada (fix en `TrendChart.bandLayer`: la franja «Suficiente» 6–7 h era la más delgada y su etiqueta se saltaba, justo la que importa). La deuda dejó de ser un `BarMark` crudo y pasó al componente nuevo **`DebtBars`** de `StrandDesign`: mismas barras por noche pero **arrastrables** como las demás gráficas (reusa `scrubGesture`/`CrosshairRule`/`ChartTooltip`) — al arrastrar, cada noche muestra cuánto dormiste + su deuda de esa noche. **Estadísticas bajo la gráfica (FER-250):** la vieja tira Avg/Min/Max/Nights se reemplazó por `TrendStatSummary` (promedio protagonista + rango; sin chip porque no hay serie periodo-vs-periodo). Ambos sheets nuevos son `.sheet` anidados con tema explícito, sin `NavigationStack`.
**Ajustes (FER-234):** el **hipnograma** estrena scrub con el dedo (`Hypnogram.showsHover: true` + un `highPriorityGesture(DragGesture)` en iOS, igual que el `scrubGesture` de `TrendChart`): arrastrar muestra etapa + rango de hora + duración. La tile de **Respiración** ya trae el valor de anoche (`latestStrapNight` recibe `respRate` de `days.last?.respRateBpm`; la sesión cacheada no lo carga). El token `StrandPalette.sleepREM` pasó de `#5BE0C7` (mint) a **`#3E9E8C`** (teal apagado) en todos lados.

Las 8 secciones (orden): Hero (horas dormidas) · Anoche (hipnograma + etapas en %) · **Regularidad del horario** (destacado, en `surface`) · Anoche vs lo típico (por etapa, en %) · Tendencia de duración (14 noches + 4 bandas) · Deuda semanal (cifra dominante + barras por noche) · Métricas de la noche (rejilla) · Ver el método.

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

Los bloques (orden), **cada uno con su ⓘ `InfoAccordion`** salvo el método: 1) **Hero** — valor de hoy 0–21 en `dataStrain` (`—`+tinta neutra sin score) + lectura por zona · 2) **Tendencia** — `SegmentedPillControl`(`ExploreRange`) + `TrendChart` (media móvil 7d, decimada) + **`TrendStatSummary`** (promedio protagonista + chip vs el periodo anterior en es-MX + línea de rango «Varió entre X y Y»; esfuerzo = polaridad **neutral**, chip gris — FER-250); se omite con <2 puntos · 3) **Cómo se acumuló hoy** — curva intradía acumulada (`TrendChart`, eje por hora; estados cargando/sin actividad) · 4) **Zonas** — las 4 bandas fijas de `MetricInfo.strain` (Rest/Light 0–7 · Moderate 7–14 · Hard 14–18 · Extreme 18–21) con la activa marcada en `dataStrain` · 5) **Qué mueve tu esfuerzo** (FER-239) — tendencias **direccionales reales** entre el esfuerzo y otras señales —**recuperación del mismo día** y **esfuerzo del día anterior** (lag +1)— calculadas de `repo.days` con `WhatMovesStrainEngine` (`StrandAnalytics`, puro + test) reusando `CorrelationEngine`/`trend`; una frase es-MX por relación, **sin coeficiente y sin causa**, chip «tendencia, no causa», ⓘ con método+gate (Plews 2013 / Vesterinen 2016). Mismo gate que FER-209 (**≥42 pares ~6 sem + |r|≥0.20 + p<0.05**); si nada lo cruza, muestra un **estado vacío honesto** («Aún no hay suficientes datos…») en vez de ocultarse, siempre que la pantalla ya tenga datos (FER-246; en cold-start sí se oculta). Descarta predictores circulares (entrenamientos/pasos/kcal son componentes del propio strain) · 6) **Ver el método** (TRIMP por zonas + escala log, cita Edwards 1993 / Banister 1991). *(Tendencia sube al 2° lugar y se eliminó el pie de fuente — FER-248)* Estados: cargando → well; sin datos → solo hero con lectura honesta.

### RecoveryDetailScreen
**Archivo:** `Cenit/Screens/RecoveryDetailScreen.swift`  
**Descripción:** Detalle de Recuperación «Instrumento» (claro) — el siguiente «sabor» del Detalle de Métrica tras Sueño (FER-225). Hermana de `MetricDetailScreen` (igual que `SleepDetailScreen`): reusa su lenguaje visual (scaffold `block`/`hero`/`InfoAccordion`/`SheetPaperBackground`/`methodDisclosure`/`statCell`) pero con su propio `RecoveryDetailModel`, porque la recuperación es un **score compuesto** con bloques propios, no un vital de serie escalar. Se abre desde **Cuerpo** (la fila héroe). En **Hoy**, tocar el número del veredicto mantiene la **hoja resumida** `MetricInfoSheet` (consistencia «foto del día», FER-232), no esta pantalla. Sheet con `InstrumentoTheme` **explícito** (no se propaga por `.sheet`, FER-162), **sin `NavigationStack` anidado** (FER-171). Consume `StrandAnalytics` tal cual (no crea matemática nueva): score + banda de `RecoveryScorer`, estado por driver + carga de `ReadinessEngine` (sus señales comparten la base del scorer), calibración de `RecoveryScorer.calibrationNights`, estadísticas de `ComparisonEngine`, y el **pronóstico de mañana** vía `RecoveryForecast` (motor FER-188), envuelto aquí en su bloque (FER-277). Presentación pura sobre un `RecoveryDetailModel` que el llamador construye desde `repo` (sin DB); `build(...)` recibe `importedSleep` para alimentar la deuda de sueño del pronóstico.

Los 9 bloques (orden), **cada uno con su ⓘ `InfoAccordion`** salvo el método: 1) **Hero** — score 0–100 en color de banda (verde ≥67 `verdict` / ámbar 34–67 `warning` / rojo <34 `critical`, por `RecoveryScorer.band`) + lectura · 2) **Qué lo explica** — cada driver (HRV 60 / FC reposo 20 / Sueño 15 / Temp 10 / Respiración 5, pesos de `RecoveryScorer.w*`) con su **estado vs tu base** (flag de `ReadinessEngine.signals`; Sueño se deriva de la eficiencia vs `sleepPerfCenter`) y una barra peso=largo, estado=color · 3) **Mañana, si descansas igual** — pronóstico a 1 día de `RecoveryForecast` (FER-188/277): número `~X` (el dato, en `dataRecovery`) + barra de **rango probable** + chip de dirección (↑ subiendo / → estable / ↓ bajando, en **tinta** — color solo en el dato) + línea de encuadre «proyección, no garantía»; sin base (< ~2 semanas) muestra **«Aún calibrando»** en el mismo slot; alimentado por la serie de recovery + la deuda de sueño importada · 4) **Tu rango normal** — media ± σ de los últimos 30 días (`ComparisonEngine.stat`) · 5) **Calendario · 90 días** — `YearHeatStrip` **re-tintado** (chrome cálido, celdas vacías en `hairline`, bandas de Instrumento) y **a todo el ancho**; **tocar un día** lo resalta con un aro y muestra su lectura (fecha · puntaje en color de banda · estado) debajo, FER-235 · 6) **Consistencia** — `SeriesShape.coefficientOfVariation` vía **`ConsistencySummary`** (la palabra Estable/Variable como protagonista en verde/ámbar + «±X% semana a semana» demotado; «(CV)» fuera del título, la def. técnica en la ⓘ — FER-255) · 7) **Carga reciente** — `acwr`/`monotony`/`loadBand` de `ReadinessEngine` como **contexto honesto, sin claim de lesión** (Impellizzeri 2020) · 8) **Selector de periodo + Tendencia** — `SegmentedPillControl`(`ExploreRange`) + `TrendChart` (media móvil 7d, decimada) + **`TrendStatSummary`** (promedio protagonista + chip vs el periodo anterior + rango; recuperación = polaridad **subir es bueno**, chip verde al subir — FER-250, sustituye la vieja tira de 5 columnas Prom/Mediana/Mín/Máx/σ) · 9) **Ver el método** (z-score + logística + cita). El Calendario se lee arriba (en el lugar de la Tendencia) y la Tendencia va al fondo (FER-237).

| Estado | Condición de entrada |
|--------|---------------------|
| Cargando | `model.loaded == false` (well con spinner) |
| Calibrando | `model.calibration != nil` (`RecoveryScorer.calibrationNights` en [1,4)) → «N / 4 noches» + barra, sin gráficas |
| Con datos | hay score o serie de recuperación → los 9 bloques |
| Pronóstico calibrando | en «Con datos» pero `model.forecast == nil` (< ~2 semanas de días válidos) → el bloque «Mañana, si descansas igual» muestra «Aún calibrando» (FER-277) |
| Día seleccionado (calendario) | tocar un día → aro de selección + lectura «fecha · puntaje · estado» debajo; día sin lectura → «sin lectura» (FER-235) |
| Sin datos / offline | cargó, sin score y sin historia → hero «—» con copy honesto (usa la banda; no promete datos) |

**Componentes:** `InfoAccordion`, `TrendChart`, `YearHeatStrip` (+ `YearHeatStrip.weekColumns` para llenar el ancho · `onSelect`/`selectionColor` para tocar un día, FER-235), `SegmentedPillControl`, `RecoveryDay`, `InstrumentoTheme`. **Analytics:** `RecoveryScorer` (banda, pesos, calibración), `ReadinessEngine` (señales por driver + carga/monotonía), `ComparisonEngine` (estadísticas + periodo-vs-periodo), `SeriesShape` (media móvil, CV, decimación), `Baselines.minNightsSeed`.

---

### StressDetailScreen
**Archivo:** `Cenit/Screens/StressDetailScreen.swift`  
**Descripción:** Detalle de Estrés en lenguaje «Instrumento» (FER-241). Lo abre **solo** la fila «Stress» de `CuerpoView` (el tile de Estrés en **Hoy** NO cambia — sigue abriendo la hoja resumida `MetricInfoSheet`). Hermano de `RecoveryDetailScreen`/`SleepDetailScreen`: pantalla dedicada, no extiende `MetricDetailScreen` (ese es para vitales de serie escalar). Consume `StressModel` tal cual (no crea matemática). Hero = **valor de HOY** (no media 7d) en color de banda, porque el índice ya viene normalizado a la base de cada quien; las bandas son **universales** (0–1/1–2/2–3) por la misma razón.

| Estado | Condición de entrada |
|--------|---------------------|
| Con datos | `StressModel` válido (score + tendencia) |
| Sin datos | `model == nil` → hero «—» + cómo obtener datos |
| Pocos días | `fullTrend.count < 2` → se ocultan tendencia/consistencia |

**Bloques (cada uno con su ⓘ vía `InfoAccordion`, salvo placeholder y método):** Hero (valor de hoy + banda + lectura) · Tendencia (selector de periodo + línea diaria 0–3 con las zonas Bajo/Moderado/Alto dibujadas por la propia `TrendChart` vía `bands:`/`yAxisValues: [0,1,2,3]`, eje Y alineado con las bandas — antes era un fondo aparte que se desfasaba, FER-247 + **`TrendStatSummary`**: promedio protagonista + chip vs el periodo anterior en es-MX + rango; estrés = polaridad **bajar es bueno**, chip verde al bajar — FER-250) · Rango normal (bandas universales, la de hoy resaltada) · **Tiempo en calma** (% días en banda baja, 30d) · Qué lo mueve (RHR/HRV de hoy vs base, en tarjetas) · Consistencia (vía **`ConsistencySummary`**: palabra Estable/Variable protagonista + ±% demotado, «(CV)» fuera del título — FER-255) · **Estrés por momento del día (PLACEHOLDER deshabilitado** — el cruce con calendario es FER-38) · Ver el método. *(Tiempo en calma sube antes de Qué lo mueve — FER-247)*

**Componentes:** `InfoAccordion`, `TrendChart`, `SegmentedPillControl`, `InstrumentoTheme`. **Analytics:** `StressModel`/`StressMath`/`StressBand` (de `StressView.swift`), `ComparisonEngine` (estadísticas + periodo-vs-periodo), `SeriesShape` (CV, decimación).

> Nota: `StressView` (la pantalla oscura completa, `Cenit/Screens/StressView.swift`) es **código heredado no referenciado**; se conserva porque alberga `StressModel`/`StressBand`/`StressRamp`/`StressMath`, que sí usan Hoy y Cuerpo.

---

### SkinTempDetailScreen
**Archivo:** `Cenit/Screens/SkinTempDetailScreen.swift`  
**Descripción:** Detalle de Temperatura de la piel en lenguaje «Instrumento» (FER-256). Lo abre la fila «Skin Temperature» de `CuerpoView`, reemplazando la antigua hoja **oscura** del catálogo (`MetricExplorerView`). Hermano de `StrainDetailScreen`/`StressDetailScreen`: pantalla dedicada, no extiende `MetricDetailScreen`. El dato es una **desviación** (±°C) respecto a la base nocturna, centrada en ~0 y de polaridad **neutral** (más no es bueno ni malo); eso dicta sus decisiones: hero = **última lectura** con signo (coincide con la fila), chip vs el periodo anterior en **delta absoluto °C** (un % sobre media ≈0 mentiría), consistencia en **SD °C** (no CV%), y una banda de **variación típica** (±1 SD) alrededor de 0 en vez de umbrales clínicos inventados. Construido desde `repo.displayDays` (DB-free); no crea matemática.

| Estado | Condición de entrada |
|--------|---------------------|
| Con datos | `today` y/o serie de `skin_temp` con ≥2 puntos |
| Sin datos | `today == nil` y serie vacía → hero «—» + cómo obtener datos |
| Pocos días | serie `< 2` puntos → se ocultan tendencia/consistencia |

**Bloques (cada uno con su ⓘ vía `InfoAccordion`, salvo el método):** Hero (última lectura ±°C en ink neutral + lectura no clínica) · Tendencia (selector de periodo + línea diaria sobre la **banda ±típica** dibujada por la propia `TrendChart` vía `bands:` + **`TrendStatSummary`** con chip en **delta absoluto °C** — `absoluteChange`, polaridad **neutral**) · Consistencia (**SD en °C** como dato protagonista, sin veredicto Estable/Variable porque skin temp no tiene umbral validado) · Ver el método. *(Descarta «Rango normal» con umbrales fijos, «Qué lo mueve» y el placeholder de calendario — no aplican honestamente a una desviación neutral.)*

**Componentes:** `InfoAccordion`, `TrendChart`, `SegmentedPillControl`, `TrendStatSummary` (modo `absoluteChange`, FER-256), `InstrumentoTheme`. **Analytics:** `ComparisonEngine` (media, rango, SD vía `stat.stdev`, periodo-vs-periodo), `SeriesShape` (decimación).

---

## Actividad

### WorkoutsView
**Archivo:** `Cenit/Screens/WorkoutsView.swift`  
**Descripción:** Bitácora de actividad — importado (WHOOP, Apple), detectado automáticamente, manual. Rediseñada al «Instrumento diurno» (FER-260): pantalla **clara** (ya no oscura), presentada como `.sheet` desde Cuerpo con su propio `NavigationStack` (tema explícito inyectado al raíz). Destilada: **un número protagonista** (sesiones del periodo, ember) + filtro de rango con auto-ampliación · apoyos quietos (tiempo activo · más frecuente) · lista **«Por deporte»** (sin cards anidadas) · lista de **«Sesiones»** tap-eables. Se retiró la tabla de 7 columnas, el grid de StatTiles y la barra de zonas agregada (esta última se movió al detalle de sesión).

| Estado | Condición de entrada |
|--------|---------------------|
| Cargando | `loaded == false` → `LoadingStateView` |
| Sin sesiones | `allRows.isEmpty` → onboarding (`EmptyStateView`-style: Agregar entrenamiento · Orígenes de datos) |
| Ventana vacía (auto-widen) | Rango seleccionado sin sesiones, expande al siguiente (caption en `warning`) |
| Con sesiones | Sesiones en el rango actual |
| Sin permiso HealthKit | No es muro: muestra lo local + línea opcional al pie «Conecta Apple Salud…» |

**Componentes:** `instrumentoHero`, `SegmentedPillControl (7D–All, theme)`, `SourceBadge`, `QuietButton`, `LoadingStateView`  
**Navegación:** cada fila de sesión → `WorkoutDetailScreen` (push en el stack de la sheet, FER-261); `+` / Agregar → `ManualWorkoutSheet` (sheet: add · edit); Orígenes de datos → `DataSourcesView` (sheet oscuro autocontenido)

---

### WorkoutDetailScreen
**Archivo:** `Cenit/Screens/WorkoutDetailScreen.swift`  
**Descripción:** Detalle de **una** sesión, «Instrumento» claro (FER-261). Se pushea dentro del `NavigationStack` de `WorkoutsView` (sin stack anidado, FER-171), tema explícito. Héroe que **degrada con honestidad**: esfuerzo (strain) → FC media → duración (nunca un 0/«—» falso). Bloques por hairline: **Zonas de FC** (solo si la sesión las trae, rampa cálida `hrZoneRamp`) · FC media/máx · distancia/energía (apoyos en tinta, con disclaimer «Estimado por la fuente» si no es WHOOP) · notas (si manual) · origen (`SourceBadge`) · nota de método. CRUD por **menú •••** según fuente (manual: editar/borrar · detectada: re-etiquetar/descartar · importada: duplicar como manual); reusa `Repository` tal cual.

| Estado | Condición de entrada |
|--------|---------------------|
| Esfuerzo | `row.strain != nil` (héroe ember `/ 21` + nota 0–21) |
| FC media (degradado) | sin strain, `avgHr != nil` (héroe rosa + nota «solo WHOOP calcula esfuerzo») |
| Duración (último recurso) | sin strain ni FC (héroe en tinta) |
| Con zonas / sin zonas | bloque de zonas presente solo si `zonesJSON` parsea |

**Componentes:** `instrumentoHero`, barra de zonas (`hrZoneRamp`), `SourceBadge`, `ManualWorkoutSheet` (edit/duplicate), menú `ellipsis.circle`  
**Navegación:** back → `WorkoutsView`; menú ••• → `ManualWorkoutSheet` (edit / duplicate)

---

## Fuerza · tracker (Entrenar) — FER-346

Builder de rutinas + biblioteca de ejercicios, sobre el modelo de fuerza (FER-345) + migración v15 (superset). DNA **«báscula de papel»**: el peso domina por tamaño en **tinta**, el único color es la línea de tendencia del **1RM estimado** (`dataStrain`, hue de salida); jerarquía por espacio + hairlines, sin card-in-card. Pesos almacenados SI (kg), mostrados en la unidad del usuario (`UnitFormatter`). El catálogo semilla (free-exercise-db) es contenido en inglés (nombres/músculos), no chrome — se muestra title-cased; el chrome se localiza por `Localizable.xcstrings`.

### Punto de entrada — «Mis rutinas» vive en EntrenarView (FER-343)
La lista de rutinas guardadas es la sección «Mis rutinas» de `EntrenarView` (FER-343), no una pantalla aparte. FER-346 conecta ahí el builder real (reemplaza el placeholder «coming soon» de FER-343): «New routine» y el estado vacío abren `RoutineBuilderScreen(.new)` como **sheet** (un id de rutina no cabe en el path tipado del tab, FER-171); cada fila de rutina gana un **menú contextual** con «Edit routine» (→ `RoutineBuilderScreen(.edit)`) y «Delete routine». La «Biblioteca» se alcanza desde Herramientas (push) o desde el estado vacío.

### RoutineBuilderScreen — builder
**Archivo:** `Cenit/Screens/RoutineBuilderScreen.swift`  
**Descripción:** Crea/edita una rutina (sheet con `NavigationStack` propio + Cancel/Save). Nombre editable; **lista reordenable** (`List` + `.onMove`/`.onDelete` vía `EditButton`, patrón HIG); **superset** por menú de fila («Superset with next» / «Break superset») con regla vertical + overline «SUPERSET»; agregar desde la biblioteca (multi-add, sheet); tap en fila → editor. Guardar → `repo.saveRoutine`.

| Estado | Condición |
|--------|-----------|
| Vacía | `items.isEmpty` → prompt + «Add exercise» |
| Con ejercicios | lista reordenable + superset + Save |
| Reordenar/borrar | `EditButton` activa el modo de edición |

**Componentes:** `List(.plain)` reordenable, menú `ellipsis`, `EditButton`, regla de superset, `QuietButton`, `RoutineExerciseEditor` (sheet)
**Navegación:** «Add exercise» → `ExerciseLibraryScreen` (add-mode, sheet); fila/Edit → `RoutineExerciseEditor` (sheet)

### RoutineExerciseEditor — editor por ejercicio
**Archivo:** `Cenit/Screens/RoutineBuilderScreen.swift` (privado)  
**Descripción:** Hoja para afinar un slot: **series de trabajo** (objetivo de series/reps/peso, steppers en tinta), **calentamiento auto desde %** (chips 40/60/80 toggleables — no cuentan para PR ni volumen), **descanso** `Por FC | Fijo` (segmented; stepper de segundos solo en Fijo). Campos según `ExerciseType` (reps/peso solo donde aplican).

### ExerciseLibraryScreen — biblioteca
**Archivo:** `Cenit/Screens/ExerciseLibraryScreen.swift`  
**Descripción:** Explora el catálogo on-device (semilla + ejercicios propios, vía `repo.allExercises`). Dos modos de una vista: **browse** (destino del hub — tap abre el detalle) y **add** (presentada por el builder con `onAdd` — multi-selección + «Add N»). Buscar + filtros de **músculo** y **equipo** (menús). «Create exercise» abre el formulario.

| Estado | Condición |
|--------|-----------|
| Browse | `onAdd == nil` → tap fila abre detalle |
| Add | `onAdd != nil` → checkmarks + barra «Add N» |
| Filtrado vacío | `filtered.isEmpty` → línea honesta |

**Componentes:** campo de búsqueda, `Menu` de filtros (chip), `LazyVStack` de filas, `CreateExerciseSheet` (sheet)
**Navegación:** fila (browse) → `ExerciseDetailScreen` (sheet); «Create exercise» → `CreateExerciseSheet` (sheet); «Add N» (add) → `onAdd` + dismiss

### ExerciseDetailScreen — detalle de ejercicio
**Archivo:** `Cenit/Screens/ExerciseDetailScreen.swift`  
**Descripción:** Un ejercicio: **músculos** (primario a tinta llena, asistentes a media tinta = el peso 1.0/0.5 del modelo), **historial** (mejor marca / última vez, pesos héroe en tinta) y **1RM estimado** (Epley 1985, `StrandAnalytics.OneRepMax`): número en tinta + **sparkline en ámbar `dataStrain`** (con scrub). Sin historial → estado honesto (músculos + el porqué, nada fabricado).

| Estado | Condición |
|--------|-----------|
| Con historial | `!history.isEmpty` → mejor marca + última vez + 1RM |
| 1RM con tendencia | `spark.count >= 2` → `Sparkline` ámbar |
| Sin historial | `history.isEmpty` → bloque honesto |

**Componentes:** barras de músculo en tinta, `instrumentoHero` (pesos), `Sparkline` (`dataStrain`), cita Epley
**Navegación:** presentada como sheet (desde la biblioteca); Done → cierra

---

### CuerpoView
**Archivo:** `Cenit/Screens/CuerpoView.swift`  
**Descripción:** Landing curado de la capa «historia / entre-días» (pestaña **Cuerpo**, FER-186; rediseño a **tarjetas por dominio**). Papel claro «Instrumento» (color solo en el dato): el `body` es una columna de **tarjetas de dominio** (`theme.surface` + hairline, `cardRadius` 16) — ya NO una lista plana de `MetricRow`. Orden vertical: **Título + fecha** → **Recuperación** (tarjeta héroe, el único numeral dominante `instrumentoHero(56)` + tendencia 14d) → **Descanso & carga** / **Vitales** / **Actividad** / **Longevidad** → nudge de conectar → acciones al pie. Cada **stat** dentro de una tarjeta es su propio destino al detalle (el atajo directo que tenían las filas); el **chevron de la cabecera** de cada tarjeta abre Explore. Solo el héroe lleva tendencia en el landing; los stats densos son un número (label · valor en su color de dato · leyenda opcional), sin sparkline.

**Tarjetas:** Recuperación (héroe: overline + numeral por banda + «/100» + subtítulo + `Sparkline` 14d 104×46 + «14-day»; calibrando → «N/4» en tinta + barra de progreso; sin lectura → «—») · Descanso & carga (3 columnas con separador: Sueño · Esfuerzo del día · Estrés) · Vitales (rejilla 3×2: HRV · FC en reposo · SpO₂ · Frecuencia cardíaca · Respiración · Temp. de piel) · Actividad (Pasos · Entrenamientos·14d, + **«Cómo amaneces tras cada deporte»** — insight Activity Cost FER-139 anidado bajo una hairline **dentro** de la tarjeta, no card-in-card) · Longevidad (3 columnas con micro-leyenda: **Edad física** FER-141 · **Edad corporal** FER-145 · **VO₂ máx** FER-257) · acciones al pie (Comparar · Ver todas las métricas).

El stat **Edad física** se tiñe por **dirección** (verde más joven / ámbar mayor / tinta igual / `—` sin dato), con leyenda compacta («N yr younger/older» o el bloqueo honesto «RHR N/4 nights») y chip «Estimate» en cobertura parcial. Toca → `FitnessAgeDetailView`.

| Estado | Condición de entrada |
|--------|---------------------|
| Con datos | Stats poblados desde `repo.displayDays`; el héroe lleva su tendencia 14d |
| Calibrando | Recuperación muestra «N/4» + «Calibrando tu base» + barra de progreso; el resto en «—» |
| Sin dato (stat) | Valor «—» en tinta (nunca en hue); Entrenamientos vacío → «—» (VoiceOver: «sin entrenamientos aún») |
| Sin permiso / offline | Muestra lo guardado; las métricas solo-Apple (Pasos) invitan a conectar sin prometer datos |

**Apertura del detalle (FER-185 ya aterrizó para los 3 vitales):** **HRV · FC en reposo · Respiración** abren el **`MetricDetailScreen`** unificado (sheet claro «Instrumento», `depth: .full`, tema explícito, sin `NavigationStack` anidado); **Sueño** abre el **`SleepDetailScreen`** claro «Instrumento» (sheet, tema explícito, sin stack anidado — FER-212); **Recuperación** (la fila héroe) abre el **`RecoveryDetailScreen`** «Instrumento» (sheet, tema explícito, sin stack anidado — FER-225), ya no la `MetricInfoSheet`. **Esfuerzo del día** abre el **`StrainDetailScreen`** «Instrumento» (sheet, tema explícito, sin stack anidado — FER-238), ya no la `MetricInfoSheet` (Hoy sí la conserva). **SpO₂** (FER-252) y **Frecuencia cardíaca** (FER-253) también abren ya el **`MetricDetailScreen`** unificado (Frecuencia cardíaca con curva intradía + pico + piso de reposo + «Tiempo en zonas»). **Temperatura de la piel** abre el **`SkinTempDetailScreen`** «Instrumento» (sheet, tema explícito, sin stack anidado — FER-256), ya no la pantalla oscura del catálogo. **VO₂ máx** (Longevidad) abre el **`MetricDetailScreen`** con la factory `.vo2max` (dato esporádico de Apple Salud, hero = última lectura leída contra tus pares por edad/sexo — FER-257). El resto sigue su puente: Pasos/Estrés→`MetricInfoSheet` claro; **Entrenamientos→`WorkoutsView`** ahora es **sheet claro «Instrumento»** con su propio `NavigationStack` (FER-260), no oscuro; Comparar→`CompareView` (FER-268) y Ver todas→`MetricExplorerView` (FER-272) ya son **sheets claros «Instrumento»** con su propio `NavigationStack`; **Data Sources** también pasó a hoja clara «Instrumento» (FER-338), así que ya no quedan hojas oscuras en estos detalles. El mini-bloque **«Cómo amaneces tras cada deporte»** (Activity Cost, FER-139) en «Actividad» abre su propia **hoja clara** `ActivityRecoverySheet` (hermana de `MetricInfoSheet`, tema explícito): una tarjeta por deporte —en el orden del motor— con la frase de **asociación** (no causa), badge de confianza (`Sólido`/`Juntando datos`) y «n sesiones», más «Ver el método» con los confusores; sin datos suficientes → estado «Juntando datos».

**Componentes:** tarjetas de dominio + columnas de stat locales (sobre `theme.surface`/hairline), `Sparkline` (solo el héroe), `instrumentoHero`/`instrumentoOverline`, `InlineFlagChip` (chips «Apple»/«Estimate»), `MetricInfoSheet`, `MetricDetailScreen` (+ `MetricDetailSpec`), `ActivityRecoverySheet` (FER-139), `FitnessAgeDetailView`, `InstrumentoTheme` (`instrumentoThemeByHour`). **Analytics:** `ActivityCostEngine` + `ActivityCostInputs` (StrandAnalytics, vía `Repository.activityCosts()`). *(El `MetricRow`/`ReferenceRange` de la lista vieja salió del landing; la capa de datos —`loadAll`, `resolveMeasured`, `vitalSeries`, todos los `.sheet`— quedó intacta.)*

---

### MetricDetailScreen
**Archivo:** `Cenit/Screens/MetricDetailScreen.swift`  
**Descripción:** El **Detalle de Métrica unificado y reutilizable** (FER-185). Una sola pantalla «Instrumento» clara, parametrizada por un `MetricDetailSpec` (`Cenit/Data/MetricDetailSpec.swift`: descriptor + `MetricInfo` reutilizado + `BlockSet` + `HeroKind` + config de base) y un `Depth`. Reemplaza —solo para los 3 vitales **HRV · FC en reposo · Frecuencia respiratoria**— los dos caminos previos (`MetricInfoSheet` y el `MetricDetailView` oscuro). Se presenta vía `.sheet(item:)`, **sin `NavigationStack` anidado** (evita el crash FER-171) y con el `InstrumentoTheme` **explícito** (no se propaga por `.sheet`). Héroe = **media móvil de 7 días** (`SeriesShape.latestMovingAverage`), no el dato del día; «hoy» va como contexto secundario.

**Frecuencia cardíaca — ruta intradía (FER-253):** a diferencia de los vitales nocturnos (serie por día), Heart Rate no tiene serie diaria: su dato es la **curva intradía de HOY** (buckets de 5 min, reusa el mismo `hrPoints` que la hoja resumida). Por eso entra por una ruta aparte (`HeroKind.intradayAverage`, `BlockSet.intradayCurve`/`.hrZones`): héroe = **promedio del día** (mín·máx + piso de reposo de anoche como contexto), bloque protagonista = la **curva** (`TrendChart` con el **pico** marcado vía `markedPoint` y la **FC en reposo** como **línea de referencia** punteada vía `referenceLine`, ambos aditivos default-off en `TrendChart`) + Mín/Prom/Máx, luego **«Tiempo en zonas · hoy»** (minutos en Z1–Z5 como % de FCmáx vía `HRZones`/`profile.hrMax`, Tanaka; titular = min elevado zona 3+) y «Ver el método». Sin base personal / tendencia / vitales-de-la-noche (no aplican a una curva de un solo día). Sin lecturas hoy → héroe «—» + well «Aún no hay lecturas de hoy» (HR es **solo-strap**: no hay estado «sin permiso Apple Salud»). Se abre desde **Cuerpo** y vía **«Ver más»** desde Hoy.

**Profundidad (un solo árbol de vistas filtrado, nunca dos pantallas):**
- `.focus` (desde **Hoy**, tile HRV/FC reposo) → foto del día: rango corto + intersección `[seriesChartBand, normalRange, method, nightVitals]`.
- `.full` (desde **Cuerpo**) → todos los bloques que declara el spec.

**Bloques por métrica (`BlockSet`):** HRV = selector · gráfica+banda · rango normal · consistencia (vía `ConsistencySummary`: palabra protagonista + ±% demotado, «(CV)» fuera del título — FER-255) · tendencia · vitales de la noche · **qué la mueve** · método (héroe = media 7d). FC en reposo = selector · gráfica+banda · rango normal · tendencia · **qué la mueve** · método. Respiración = selector · gráfica+banda · rango normal · tendencia · vitales de la noche · método. SpO₂ (FER-252, héroe = media 7d) = selector · gráfica de valores crudos con banda clínica 95–100% · tabla de bandas fija · «noches bajo 95%» · método. **VO₂ máx (FER-257, dato esporádico de Apple, héroe = última lectura)** = selector · gráfica de **valores medidos crudos** por meses · **cambio en el periodo** · **nivel por edad/sexo** (Bajo/Promedio/Bueno/Excelente vía `VO2maxReference.category`) · **edad cardiorrespiratoria** (`VO2maxReference.equivalentAge`) · **por qué importa** (longevidad, Mandsager 2018/Kodama 2009) · método; el hero lee la última lectura contra la mediana esperada (`VO2maxReference.expected`); sin dato → estado vacío explicativo + nudge a conectar Apple Salud.

**«Qué la mueve» (`whatMovesIt` · FER-209, solo HRV y FC en reposo):** una **tendencia direccional real** entre el vital y otra señal —**sueño de la misma noche** y **esfuerzo del día anterior** (lag +1)— calculada de `repo.displayDays` con `CorrelationEngine` (Pearson/lagged) y **degradada a dirección**: una frase es-MX (p. ej. «suele ser más alta las noches que duermes más»), **sin coeficiente y sin causa**, con el chip «tendencia, no causa». Gate de suficiencia/fuerza (`CorrelationEngine.trend`): **≥42 pares (~6 semanas)** + `|r| ≥ 0.20` + `p < 0.05`; si ningún par lo cruza, muestra un **estado vacío honesto** («Aún no hay suficientes datos…») en vez de ocultarse, siempre que haya serie (FER-246; cold-start sí se oculta). Orquestación en `Cenit/Data/WhatMovesIt.swift`; gate + traducción r→dirección en `StrandAnalytics/MetricTrend.swift` (con `swift test`).

| Estado | Condición |
|--------|-----------|
| Con datos (≥2 pts) | Media móvil 7d (`Sparkline`) + banda p25–p75 (`ReferenceRange.interquartile`); rango normal (`Baselines.rollingMeanSD` ± σ, nº noches); tendencia (`ComparisonEngine.monthOverMonth` + **`TrendStatSummary`**: promedio + chip vs el periodo anterior + rango, polaridad por `descriptor.higherIsBetter` —HRV sube=bueno, FC reposo baja=bueno, respiración neutral— FER-250); consistencia (`SeriesShape.coefficientOfVariation`) |
| Ventana vacía | Auto-ensancha al siguiente rango con datos + aviso «Mostrando los últimos N días» |
| Un solo punto | Valor sin línea + nota |
| Sin suficiente historial (<2) | Bloque de calibración «N / 7 noches» (no aplica a VO₂max: `sparseMeasured` renderiza con ≥1 lectura) |
| Sin dato (VO₂max · `sparseMeasured`) | Estado vacío explicativo «Aún no hay VO₂max…» (sin gráfica) + nudge «Conectar Apple Salud» cuando no hay permiso (FER-257) |
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

### BucleView — «el Bucle» (Coach)
**Archivo:** `Cenit/Screens/BucleView.swift` (+ `Cenit/Screens/BucleSheets.swift`, `Cenit/Screens/GoalSheets.swift`)  
**Descripción:** La pestaña Coach como **una sola pantalla «Instrumento diurno»** (FER-292), alimentada por el `InsightEngine` determinista (FER-290). Reemplaza el hub de 3 filas (Intelligence · Insights · Coach). Tab **clara** (papel cálido; entra en `isLightTab` → status bar correcto). Color SOLO en el dato: el % del veredicto, los efectos con signo (verde = te ayuda / rojo = te cuesta) y el datum de los hallazgos.

| Estado | Condición de entrada |
|--------|---------------------|
| Arranque en frío | Historial propio < 14 noches usables (`usableNights < calibrationTarget`) → «Aún reuniendo señal · X de 14 noches» (contador topado a 14, «Faltan N noches…»); solo se muestra «Pregúntale» |
| Esperando la lectura de hoy | Ya hay ≥14 noches pero aún no llega la lectura de hoy (medianoche → sync de la mañana; `ReadinessEngine.insufficient`) → el héroe «Esperando la lectura de hoy» (+ veredicto de ayer como contexto) reemplaza a la Decisión, pero **palancas, hallazgos y efectos siguen visibles** (FER-340) |
| Con datos | Veredicto + palancas + hallazgos + registro + efectos |
| Sin hallazgos | Hay datos pero el motor no encontró hallazgos → «Todo en orden, sin hallazgos nuevos» |

**Sección «Prueba» — experimentos N-of-1 (FER-307).** Tercer latido del ciclo (Descubre→**Prueba**→Actúa→Aprende), entre «Lo que funciona en ti» y «Hallazgos». Una sola sección que cambia de identidad según el estado del experimento (uno a la vez, MVP):

| Estado de Prueba | Qué muestra |
|------------------|-------------|
| Invitación vacía | Sin experimento y sin candidato: «Pon a prueba una idea» + acceso a «Anota tu día». **Visible aun en arranque en frío** (enseña la mecánica). Informativa: sin tarjeta, sin color |
| Idea por probar | Sin experimento, con candidato: tarjeta-entrada con el candidato más fuerte → `StartExperimentSheet` |
| Tu experimento (en curso) | «Día N de M» + barra de avance + adherencia («cumpliste X de N días») + fecha de veredicto + Cancelar |
| Tu experimento (veredicto) | Resultado: **se sostuvo** (datum a color, el único color del estado) / **no se sostuvo** / **sin señal suficiente**; «Listo» lo descarta (id en `@AppStorage`) |

**Secciones:** Header (`Coach · fecha` + badge «On-device») · **Decisión de hoy** (héroe-frase del `ReadinessEngine` + recuperación como evidencia) · **Tu meta** (ancla de 1 línea bajo Decisión de hoy: sin meta «Ponte una meta →», con meta «Tu meta · foco · fecha» → abre el simulador, FER-311) · **Pregúntale a tus datos** (única puerta; abre `PreguntaleView`, que routea por nivel — ver su entrada) · **Lo que funciona en ti** (palancas curadas del `InsightEngine`, top 2 + «Ver las N»; una palanca confirmada por experimento se marca «probado» vía `InsightEngine.promoteProven`) · **Prueba** (ver arriba) · **Hallazgos** (anomalía/tendencia/relación/pronóstico, topados + «Ver los N») · **Anota tu día** (resumen → hoja Sí/No tri-estado, escribe al journal existente; de ahí sale la adherencia del experimento) · **Efectos de tus hábitos** (explorador histórico por métrica).  
**Hojas (`BucleSheets.swift`):** `PalancaDetailSheet` (evidencia: muestra, significancia, tamaño de efecto, confianza; CTA «Probar esta idea» para un candidato cuando no hay experimento en curso) · `StartExperimentSheet` (confirmación: por qué, los 3 pasos, ventana de 7 días + fecha de veredicto, «Empezar») · `HallazgosListSheet` · `EfectosExplorerSheet` (selector de métrica) · `AnotaTuDiaSheet` (tira de 14 días con scroll; Hoy/Ayer editables Sí/No, días viejos en solo lectura; puntito en días con datos; «lo que no marques se asume No» — FER-313).  
**Hojas de meta (`GoalSheets.swift`, FER-311):** `GoalPickerSheet` (solo selección: 3 focos — Recuperarte mejor / Dormir mejor / Subir tu condición, donde condición revela por divulgación progresiva la señal HRV ↑ ó FC en reposo ↓ — + fecha opcional; persiste en `GoalStore`/UserDefaults) · `SimulatorScreen` (la trayectoria del `TrajectorySimulator`: dos caminos «como vas» vs «si cambias X» + banda de confianza, color SOLO en el camino-palanca; 3 estados — completo con palanca probada / sin palancas (solo «como vas», «si cambias» en gris) / sin base <14 días («Aún reuniendo señal»)). El simulador y el picker se abren `.sheet(item:)` con el tema inyectado; «Cambiar» del simulador reabre el picker.  
**Navegación:** `RootTabView` la monta como `lazyTab(.coach)` directo (ya no `hubTab`). El chat LLM externo se preserva intacto (`AICoachEngine` + Keychain); `CoachView` se rediseñó a «Instrumento diurno» claro (FER-309) y se abre como `.sheet` con el tema inyectado (sin pin `.dark`). Los hallazgos de tendencia llevan sparkline a color por hue (FER-147) y el detalle de palanca muestra barras con/sin desde el campo `Insight.behaviorBreakdown` (FER-309). El veredicto del experimento reusa `ExperimentVerdict`/`BehaviorInsights` (FER-307); la persistencia vive en la tabla `experiment` (`WhoopStore` v12) leída/escrita por `Repository`. **Claridad (FER-312):** los nombres de hábito se muestran en es-MX vía `JournalCatalogStore.esLabel` (la llave del journal no cambia); la pill «On-device» y una ⓘ en «Lo que funciona en ti» / «Hallazgos» / «Efectos de tus hábitos» abren `BucleInfoSheet`; tocar «Decisión de hoy» abre `DecisionExplainerSheet` (qué hacer + por qué + señales del `ReadinessEngine`).

---

### PreguntaleView — «Pregúntale a tus datos» (FER-308 · 331 · 332 · 333)
**Archivo:** `Cenit/Screens/PreguntaleView.swift` (+ `Cenit/AI/CoachAvailability.swift`, `Cenit/AI/OnDeviceCoach.swift`)  
**Descripción:** La hoja de «Pregúntale» del Bucle, unificada en tres niveles. El nivel se decide con `CoachAvailability.current()` (lee `SystemLanguageModel.availability` de Apple, todo detrás de `#if canImport(FoundationModels)` + `@available(iOS 26)`). **Jerarquía invertida (FER-332):** el motor (`CoachGrounding`, StrandAnalytics) clasifica el tema de la pregunta (`CoachTopic`) y arma la respuesta determinista correcta; el modelo on-device **solo la reescribe**, nunca calcula. Si reescribe mal o cita una cifra ajena (`validate()`), se muestra la respuesta del motor tal cual. **Conversación sembrada (FER-331):** el coach abre con `opener()` (hallazgo top del día) + `suggestedChips()` (dinámicos) + `followUpChips()`. **What-if fundamentado (FER-333):** una pregunta «¿y si…?» sobre un hábito registrado devuelve el contraste con/sin de TU historial (`whatIf()` desde `BehaviorBreakdown`) y ofrece convertirlo en experimento de 7 días.
| Estado | Qué se ve |
| --- | --- |
| **On-device** (Apple Intelligence) | Opener + sugerencias; texto libre + «Pensando…» (VoiceOver); respuesta del motor reescrita por `LanguageModelSession`; en un «¿y si…?» con datos, contraste histórico + botón «Convertirlo en experimento de 7 días» → `StartExperimentSheet` (FER-307) |
| **Modo esencial** (`deviceNotEligible`/`appleIntelligenceNotEnabled`/`modelNotReady`/`osTooOld`) | Opener + chips prearmados (`CoachChip`) con respuesta de plantilla del motor (instantánea, sin modelo); explicador «por qué + qué necesitas» (más discreto, debajo del valor) |
| **Nivel 3** (opcional) | Fila «Respuestas más profundas con tu IA» → abre el chat externo `CoachView` (BYO-key, opt-in) — preservado |
**Tono calibrado (FER-333):** `confidenceCaveat(n:)` hace que el coach titubee cuando la muestra es chica («con n días, tómalo como pista»).
**Verificación on-device pendiente (spike):** calidad/latencia del español on-device y la no-conexión del Nivel 2 se validan en hardware iOS 26 / A17 Pro+ (no verificable en CI). El build compila el path FoundationModels contra el SDK iOS 26.
**Navegación:** se presenta como `.sheet` desde `BucleView` (con `behaviorInsights` para el handoff) y el tema «Instrumento» inyectado; el Nivel 3 abre `CoachView` y el handoff abre `StartExperimentSheet` como sub-`.sheet`.

---

### InsightsView — retirada de navegación (FER-292)
**Archivo:** `Cenit/Screens/InsightsView.swift`  
**Descripción:** Correlaciones — comportamientos que afectan recovery/HRV/sleep/RHR (Pearson r, Cohen's d). **Ya no está en la navegación:** su contenido lo surte ahora el Bucle (Lo que funciona en ti / Hallazgos / Efectos de tus hábitos) vía el `InsightEngine`. El archivo se conserva (no se borra en FER-292). **Honestidad estadística (FER-299):** el mismo motor que ahora alimenta al Bucle (`CorrelationEngine`/`BehaviorInsights`) usa la cola **Student-t** real para la p y decide significancia por **FDR (Benjamini-Hochberg)** sobre toda la familia, no por prueba individual; las relaciones autocorrelacionadas (recovery→recovery) se marcan «arrastre» y **no muestran p**; el copy de Insights/Compare/Explore enmarca todo como «asociación, no causa».

---

### IntelligenceView — retirada de navegación (FER-292)
**Archivo:** `Cenit/Screens/IntelligenceView.swift`  
**Descripción:** Explicador de cómo se computan los scores on-device. **Ya no está en la navegación** tras el rediseño del Bucle; el archivo se conserva.

---

## Análisis

### MetricExplorerView / MetricDetailView
**Archivo:** `Cenit/Screens/MetricExplorerView.swift`  
**Descripción:** Catálogo de métricas por categoría (Sleep, Strain, Workouts, Vitals, Body) en lenguaje «Instrumento diurno» claro (FER-272): papel cálido, filas directamente sobre el papel separadas por `hairline` (sin `NoopCard` oscuro), color SOLO en el dato (el ícono y el número en el hue de la métrica). Tap → dossier completo de una métrica, también claro. Reemplaza el viejo cluster oscuro fijado a `.dark`.

| Estado | Condición de entrada |
|--------|---------------------|
| Lista por categoría | Vista raíz |
| Detalle · sin datos | Ventana sin puntos (auto-widen) |
| Detalle · un punto | 1 día disponible en el rango |
| Detalle · tendencia | ≥ 2 puntos; muestra gráfica |

**Componentes:** lista por categoría sobre papel (overline + título + count), `MetricRow` (mosaico de ícono en `theme.surface` · título · fuente · unidad · chevron), hero (`instrumentoOverline` + `instrumentoHero(44)` en el accent + «al …»), **`MetricTrendChart`** (selector + línea cruda — FER-269), **`TrendStatSummary`** (Prom · rango · Δ vs periodo previo), «What correlates» (Pearson r del catálogo, barras `verdict`/`critical`), `InstrumentoTheme`  
**Navegación:** se abre desde el pie de Cuerpo («Ver todas») como `.sheet` **claro** con su PROPIO `NavigationStack` (tema inyectado en la raíz, FER-162; sin pin `.dark`); tap métrica → `MetricDetailView` (push dentro del stack del sheet, no anidado a través de la pestaña — FER-171, FER-272)

---

### CompareView
**Archivo:** `Cenit/Screens/CompareView.swift`  
**Descripción:** Superponer 2–4 métricas en gráfica normalizada (0–1) + Pearson r entre pares. En lenguaje «Instrumento diurno» claro (FER-268): papel cálido, color SOLO en el dato (las líneas del overlay + el valor r), jerarquía por espacio. Se abre desde el pie de Cuerpo como `.sheet` claro (tema inyectado en la raíz, sin `NavigationStack` anidado; se cierra arrastrando). Las 4 líneas usan las tintas de dato profundas (`verdict` / `dataHrv` / `dataSleep` / `dataStrain`), legibles sobre el papel.  
**Datos (FER-275):** las métricas que son campos diarios del tablero (recovery/strain/hrv/rhr/resp_rate/spo2/skin_temp/steps/sueño total·deep·rem·light·efficiency/active_kcal) se leen de `repo.displayDays` → resuelven para usuarios de strap **y** de import; las demás (composición corporal Apple, zonas HR, % de sueño derivados) caen al fallback `repo.series()`. Default: Recuperación · Esfuerzo · HRV.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin selección | `selected.isEmpty` |
| < 2 métricas | Solo 1 métrica seleccionada |
| 2+ métricas | Gráfica overlay + tarjetas de correlación |

**Componentes:** `Multi-select picker (addMenu)`, `SegmentedPillControl (theme:)`, `OverlayChart (normalizado 0–1, multi-línea)`, `MultiTooltip`, `Correlation cards (Pearson r)`

---

### AppleHealthView
**Archivo:** `Cenit/Screens/AppleHealthView.swift`  
**Descripción:** Visor por-fuente de Apple Health en **luz «Instrumento diurno»** (FER-338, antes oscura) — Steps, Active Energy, VO₂ Max, vitales, cuerpo, sueño. Se abre desde «Datos y fuentes → Ver datos importados».

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

**Componentes:** `header` (título + `connectionPill`), `hero` (ECG `dataHeart`/plano + bpm + «en vivo» + latidos de sesión + `rrTachogram`), `signalsSection` (2 grupos: «Capturing live» FC·R-R / «Completes on sync» SpO₂·Temp·Resp·Movimiento, cada renglón con `storedCount`; columnas de ancho fijo; único encabezado de columna **«records»** sobre los conteos en ambos grupos, FER-192/193), `coverageStrip` (28 d **por fuente**: Correa `dataRecovery` / Apple Health `dataSpO2` / Sin datos `hairlineStrong` + leyenda con conteos — reutiliza la clasificación de `DataSourcesView`/`repo.appleHealthDays`, FER-196), `savedFooter` (chip iPhone [guardado local, pasivo] + **chip iCloud tappable → respaldo inmediato** con háptico ligero, spinner «Respaldando…» mientras copia y tinta `warning` «No se pudo respaldar» si falla — llama `AutoBackup.backupNow`, solo iOS y solo si ya hay carpeta elegida + respaldo previo, FER-352 — + `verifyButton` con escudo; o línea de aviso/última-sync según estado), `disconnectedState` (CTA «Conectar»), más el estado intermedio **«Reconectando…»** (`showsReconnecting` + ventana `reconnectGraceSeconds` 15 s que pausa el monitor en una caída corta, FER-195). Gestión de correa, batería y entrenamiento **removidos** → Ajustes / *Más › Workouts*. La hoja **abre a la altura del contenido** (detente medido, FER-196); unidad de FC localizada (es «lpm»).

---

### AutomationsView
**Archivo:** `Cenit/Screens/AutomationsView.swift`  
**Descripción:** «Automatizaciones» en **luz «Instrumento diurno»** (FER-69, antes oscura; **saneada iOS-only**: se quitó el toggle «Lock the Mac» y el copy de «este Mac»). Doble toque → acción (atajo / marcar momento), atajo al quitar/poner la banda, coaching háptico, alarma inteligente, aviso de enfermedad. Solo presentación + saneo; la lógica (`BehaviorStore`/alarma/hápticos) no cambia.

| Estado | Condición de entrada |
|--------|---------------------|
| Strap no bonded | Sin strap vinculado |
| Strap bonded | Strap vinculado |

**Componentes (Instrumento):** secciones por espacio (sin card-in-card) — Doble toque (`Picker` + campo de atajo + Test action `QuietButton` + estado de strap inline + momentos) · Uso y presencia (atajos off/on) · Coaching háptico · Alarma inteligente · Aviso de enfermedad; `toggleRow`/`DatePicker`/`Picker` nativos tintados a Instrumento.

---

### EntrenarView
**Archivo:** `Cenit/Screens/EntrenarView.swift`  
**Descripción:** Raíz del tab **Entrenar** (hub claro «Instrumento», FER-343): tarjeta «Hoy» (rutina del día + banda de recuperación) → `RutinaDeHoyScreen`; sección «Mis rutinas» (lee `WhoopStore.routines()`); «Herramientas» (En vivo · Respira · Intervalos). Puerta del tracker de fuerza (épico FER-39). Builder (FER-346) e inicio guiado (FER-347) fuera de alcance → nota honesta `TrainingSoonSheet`.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin rutinas | `routines()` vacío → tarjeta vacía + CTA «Nueva rutina · o desde plantilla» |
| Con rutinas | Tarjeta «Hoy» + «Mis rutinas» |
| Banda de recuperación | con recovery → Sube/Mantén/Baja; sin recovery → oculta (no inventa) |

**Componentes:** `RecoveryBand` (compartida), `LiveWorkoutHubRow` (En vivo), `QuietButton`, `TrainingSoonSheet`, tokens Instrumento (`theme.surface`/`hairline`/`ink`, `NoopMetrics`).

---

### RutinaDeHoyScreen
**Archivo:** `Cenit/Screens/RutinaDeHoyScreen.swift`  
**Descripción:** «Rutina de hoy» — la pantalla **previa al inicio** (FER-343): el plan (ejercicios + esquema objetivo `series × reps · peso` + regla de descanso) y el **slot de la banda de recuperación** (oculto sin recuperación). Push desde `EntrenarView` en «Instrumento» claro. Carga la rutina por id (o la más reciente) de `WhoopStore`; resuelve nombres con `ExerciseCatalog` + ejercicios propios. El **inicio guiado serie por serie** es FER-347 → nota honesta «llega pronto», sin botón funcional. La **regla** de la banda es W3·bucle/FER-349; aquí solo el contenedor visual (`RecoveryBand`).

| Estado | Condición de entrada |
|--------|---------------------|
| Con plan | Rutina con ejercicios |
| Sin ejercicios | Rutina vacía → «Esta rutina aún no tiene ejercicios.» |
| Banda | con recovery → tarjeta Sube/Mantén/Baja; sin recovery → oculta |

**Componentes:** `RecoveryBand` (compartida), filas de plan (esquema `bodyNumber` + chip de descanso), respeta unidades (`UnitPrefs`), tokens Instrumento.

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

### AjustesView
**Archivo:** `Cenit/Screens/AjustesView.swift`  
**Descripción:** La raíz de Ajustes en el lenguaje claro «Instrumento diurno» (FER-337). Abre directo (sin el viejo paso «Settings») y mató el cajón «Más». Perfil (edad/sexo/peso/estatura/FC máx) y «Tu strap» (estado + batería + Re-escanear/Desconectar + Log de la banda + Pruebas 5/MG) a la vista; filas que abren las sub-pantallas. Reemplaza a `SettingsView` (borrado): su respaldo/iCloud se mudó a `DataSourcesView` y su «Acerca de» a `SupportView` (transición que rehúbican FER-338/67). El log de la banda sigue alcanzable (criterio duro).

| Estado | Condición de entrada |
|--------|---------------------|
| Vista única (scrollable) | Siempre |
| Tu strap: vinculado / conectado / idle / desconectado | Según `live.connected` / `live.bonded` |
| Log de la banda: vacío / con líneas | Según `live.log` |

**Componentes:** `section()` (overline + filas, jerarquía por espacio — sin card-in-card), `FormRow` (Stepper/Picker nativos), estado del strap inline (dot en color del dato + batería), `QuietButton`, `navRow` (chevron → sheet), sub-pantallas `UnidadesSheet` / `StrapLogSheet` (claras, tema pasado explícito), sheet oscuro «pinned» a `.dark` para Datos y fuentes / Automatizaciones / Acerca de y soporte (transición)  
**Navegación:** → `UnidadesSheet` · `StrapLogSheet` (sheets claros) · `DataSourcesView` · `AutomationsView` · `SupportView` (sheets oscuros)

---

### DataSourcesView
**Archivo:** `Cenit/Screens/DataSourcesView.swift`  
**Descripción:** «Datos y fuentes» en **luz «Instrumento diurno»** (FER-338, antes oscura): importar (WHOOP `.zip` + Apple Health export), Apple Health en vivo + «Ver datos importados» (→ `AppleHealthView`), Sincronización de la banda (FER-83), Cobertura 30 días, y Respaldo (backup/CSV/iCloud). Tema por hora, color solo en el dato.

| Estado | Condición de entrada |
|--------|---------------------|
| Idle | Sin proceso en curso |
| Importando WHOOP | `WhoopImporter` corriendo |
| Importando Apple Health | `HealthImporter` corriendo |
| Import completo | Proceso terminado, muestra conteos |

**Componentes (Instrumento):** secciones `Importar` · `Apple Health` (+ link al visor) · `Sincronización de la banda` · `Cobertura` (rejilla 30d + `SourcesSummaryCard`) · `Respaldo`; `QuietButton`, `section()`/hairlines (sin card-in-card), `File importer`. Se presenta como sheet **claro** (ya no `.dark`) desde Ajustes/Cuerpo/Hoy/Workouts.

---

### SupportView
**Archivo:** `Cenit/Screens/SupportView.swift`  
**Descripción:** «Acerca de y soporte» en **luz «Instrumento diurno»** (FER-67 fusionó About+Support; **FER-381 la adelgazó**: se quitaron Buscar actualizaciones, la donación y el contacto). Queda: identidad + versión + «What's new» (changelog) + misión + atribución + **un solo** aviso «no afiliado / no es dispositivo médico». Se abre como sheet claro desde Ajustes; en Hoy vía `SupportModalOverlay` (panel claro).

| Estado | Condición de entrada |
|--------|---------------------|
| Estático | Siempre |
| What's New | sheet del changelog |

**Componentes (Instrumento):** secciones por espacio (sin card-in-card) — About (versión + `QuietButton` What's new + misión) · Built on (atribución) · disclaimer al pie; `SupportModalOverlay` (panel de papel para Hoy)

---

## Sheets y Modales

### ManualWorkoutSheet
**Archivo:** `Cenit/Screens/ManualWorkoutSheet.swift`  
**Presentado por:** `WorkoutsView` (add: botón «+») · `WorkoutDetailScreen` (edit / duplicate vía menú •••)

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

*Actualizado: 2026-06-18*
