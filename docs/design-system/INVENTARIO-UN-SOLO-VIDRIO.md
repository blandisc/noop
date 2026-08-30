# Inventario «Un solo vidrio» (FER-233 → épico FER-229)

**Fecha:** 2026-08-29  
**Alcance:** lectura + este doc. No modifica código.  
**Fuentes:** grep/lectura en este worktree; tabla DNA de `AUDIT-FRONTEND-GROK.md` (presente en el worktree `orquesta-fer-29-e4dcfb`; no está en la raíz de *este* worktree).  
**Regímenes canónicos (FER-229):** **mosaico** (Entrenar, identidad por tesela) · **sobrio** (default Hoy/detalles, color en el número/gota).

Cada fila de vidrio y cada pantalla de papel lleva **destino**. Donde el dueño/arquitecto deben pinarlo, se marca «(a decidir por arquitecto/dueño)».

---

## 1) Superficies de vidrio

### 1.1 Recetas `liquidGlass(_:)` — `LiquidGlassRecipe`

Archivo: `Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/LiquidGlassRecipes.swift`

| Receta | Definición | Destino propuesto |
|---|---|---|
| `.superficie` | `:20` | **Funde** en la API unificada como caso neutro/sobrio (tarjeta/tile). |
| `.pastilla` | `:22` | **Funde** (cápsula translúcida). |
| `.pastillaElevada` | `:24` | **Funde** (misma pastilla + `e/1`). Hoy solo se declara/implementa (`:69`); sin call sites de producto aparte del enum. |
| `.lente` | `:26` | **Funde** (dock / elementos flotantes; p. ej. `LiquidTabBar.swift:80`). |
| `.superficieSolida` | `:31` | **Conserva como caso** opaco (anti vidrio-sobre-vidrio dentro de hoja). Misma forma/chrome que `.superficie`, sin blur/`glassEffect` (`LiquidSolidLayer` `:223`). |
| `.pastillaSolida` | `:34` | **Conserva como caso** opaco hermano de `.pastilla`. |
| `.superficieAtmosfera` | `:41` | **Conserva como caso** Hoy/atmósfera (relleno `.30` + canto tinta; p. ej. `MatrizHoyFace.swift:419`, `LiquidAtmosfera.swift:174`). |

Puerta pública: `func liquidGlass(_ recipe: LiquidGlassRecipe)` en `:49`.

### 1.2 `EntrenarVidrioReceta` (hub teñido)

Archivo: `Packages/StrandDesign/Sources/StrandDesign/Entrenar/EntrenarVidrio.swift`

| Pieza | Ruta:línea | Destino propuesto |
|---|---|---|
| `EntrenarTono` (`neutro`…`ambar`) | `:22` | **Funde** → `LiquidTono` (o nombre que fije el arquitecto) con contrato `base`/`rotulo`/`tesela` (`:27`, `:44`, `:61`). |
| `EntrenarFamily.tono` | `:77` | **Funde** con el enum de tono (puente familia→tono). |
| `EntrenarVidrioMetrics` | `:91` | **Funde** en métricas de la receta unificada (intensidad, highlights, sombras). |
| `EntrenarVidrioReceta` (modifier privado) | `:145` | **Funde** en `liquidGlass(tono:regimen:)` — decisión pinada FER-229 §4. |
| `EntrenarModulo` | `:224` | **Funde** (contenedor mosaico a lo ancho; aplica `EntrenarVidrioReceta` en `:252`). |
| `EntrenarTile` | `:258` | **Funde** (tile 2-col; aplica la misma receta en `:272`). |

### 1.3 `.entrenarHojaFondo(tono:)`

Archivo: `Packages/StrandDesign/Sources/StrandDesign/Entrenar/EntrenarHojaFondo.swift`  
API: `:55` · cristal edge-to-edge: `:83`–`:87` (`glassEffect` en `Rectangle`).

**Destino propuesto:** **Funde** como régimen de *fondo de hoja* teñido (no tarjeta flotante) de la API unificada — misma intensidad que módulos (`EntrenarVidrioMetrics.intensidadDefault`, citado en `:97`–`:100`). Alternativa si la forma edge-to-edge no cabe en `liquidGlass`: **conserva como caso** de presentación. «(a decidir por arquitecto/dueño)» el nombre del parámetro (`regimen: .hoja` vs API aparte).

**Hojas / pantallas que lo usan (producción, Cenit + previews DS):**

| Call site | Ruta:línea | Tono |
|---|---|---|
| `ManualWorkoutSheet` | `Cenit/Screens/ManualWorkoutSheet.swift:111` | `.neutro` |
| `RPESheet` | `Cenit/Screens/LiveStrengthSheets.swift:63` | `.ambar` |
| `NoteSheet` | `Cenit/Screens/LiveStrengthSheets.swift:206` | `.ambar` |
| `ChangeExerciseSheet` | `Cenit/Screens/LiveStrengthSheets.swift:385` | `.neutro` |
| `WorkshopTricksScreen` | `Cenit/Screens/WorkshopTricksScreen.swift:79` | `.neutro` |
| `LiveStrengthSheet` (raíz fullScreen) | `Cenit/Screens/LiveStrengthSheet.swift:269` | `.neutro` |
| `WeekEditorSheet` | `Cenit/Screens/WeekEditorSheet.swift:67` | `.neutro` |
| `IntervalTimerView` | `Cenit/Screens/IntervalTimerView.swift:112` | `.neutro` |
| `ExerciseDetailScreen` | `Cenit/Screens/ExerciseDetailScreen.swift:128` | `.neutro` |
| `BreathingView` | `Cenit/Screens/BreathingView.swift:113` | `.neutro` |
| `StarterTemplatesSheet` | `Cenit/Screens/StarterTemplatesSheet.swift:53` | `.neutro` |
| `ProgressionSetupScreen` | `Cenit/Screens/ProgressionSetupScreen.swift:147` | `.verde` |
| `WorkoutImportView` | `Cenit/Screens/WorkoutImportView.swift:87` | `.neutro` |
| `SavedTicketsScreen` | `Cenit/Screens/SavedTicketsScreen.swift:79` | `.neutro` |
| `ExerciseLibraryScreen` | `Cenit/Screens/ExerciseLibraryScreen.swift:92` | `.neutro` |
| `CreateExerciseSheet` | `Cenit/Screens/ExerciseLibraryScreen.swift:619` | `.neutro` |
| `ReceiptPrinterScreen` | `Cenit/Screens/ReceiptPrinterScreen.swift:85` | `.neutro` |
| `WorkoutHistoryScreen` (+ detalle) | `Cenit/Screens/WorkoutHistoryScreen.swift:153`, `:1610` | `.neutro` |
| `CrearPlanScreen` | `Cenit/Screens/CrearPlanScreen.swift:69` | `.neutro` |
| `PlatesScreen` | `Cenit/Screens/PlatesScreen.swift:59` | `.ambar` |
| `RestEditorScreen` | `Cenit/Screens/RestEditorScreen.swift:195` | `.verde` |
| `WeeklyPlanEditorView` | `Cenit/Screens/WeeklyPlanEditorView.swift:118` | `.neutro` |
| `TrainingBodyScreen` (+ hoja) | `Cenit/Screens/TrainingBodyScreen.swift:190`, `:944` | `.neutro` |
| `WorkoutEditSheet` | `Cenit/Screens/WorkoutEditSheet.swift:102` | `.neutro` |
| Previews DS (`EntrenarFila*`, `EntrenarNotaCampo`, `EntrenarStepperSegundos`, `EntrenarHojaFondo`) | `Packages/StrandDesign/.../Entrenar/*.swift` | varios |

El menú documental de 11 superficies de la Ola 2 vive en el comentario de cabecera `EntrenarHojaFondo.swift:25`–`:39` (Progression, Rest, RPE, Note, Plates, ChangeExercise, ExerciseDetail, Library, CreateExercise, summaryPhase, emptyAdHoc).

### 1.4 `LiquidModulo`

Archivo: `Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/LiquidModulo.swift`  
Struct `:18` · vidrio `:65`–`:69` (densidad por `index` + aurora en filo).

**Destino propuesto:** **Conserva como caso** del régimen sobrio de Hoy (aurora de datos + densidad progresiva). No es un `.liquidGlass` suelto a propósito (`:15`–`:16`). Fusearlo a la API genérica perdería índice/aurora — solo fundir si la API unificada modela esos parámetros. «(a decidir por arquitecto/dueño)» si se expresa como `liquidGlass(.modulo(index:aurora:))` o queda componente.

### 1.5 `ConfirmCard.cardGlassFill`

Archivo: `Packages/StrandDesign/Sources/StrandDesign/ConfirmCard.swift`  
`cardGlassFill` `:189`–`:193` · forma `UnevenRoundedRectangle` solo arriba `:169`–`:170`.

**Destino propuesto:** **Conserva como caso** — `.liquidGlass(_:)` no expone esquinas parciales (comentario `:173`–`:174`). Fusear cuando la API acepte `shape:`/hoja anclada; hasta entonces no romper ConfirmCard.

### 1.6 Otras recetas / superficies de vidrio encontradas

| Superficie | Ruta:línea | Destino propuesto |
|---|---|---|
| `LiquidVeil` | `LiquidGlassRecipes.swift:260` | **Conserva como caso** (velo status bar; no es receta con forma). |
| `LiquidSheetFondo` | `LiquidGlassRecipes.swift:309` | **Fuera de alcance de la fusión de vidrio teñido** — hoy es *papel* + plasta + streak (`:327`–`:334`), no `glassEffect`. Sigue siendo el fondo de hojas de métrica; alinear calidez/tono en stage de docs/ADN, no fundir en `EntrenarVidrio`. |
| `LiquidSphere` | `LiquidGlassRecipes.swift:438` · nativo `:455` | **Conserva como caso** esférico (tint del tono al 10 %). |
| `LiquidTabBar` lente + `glassEffect` local | `LiquidTabBar.swift:80`, `:94` | **Funde** vía `.lente`; el `glassEffect` directo del dock es detalle de implementación a absorber. |
| `EntrenarCapsulaPuerta` | `EntrenarCapsulaPuerta.swift:31`, fill `:58` | **Funde** o **conserva como átomo** mosaico (cápsula blanca `.72`, no `EntrenarTono`). «(a decidir por arquitecto/dueño)» si pasa a `liquidGlass(.pastilla, tono: .neutro)`. |
| `HojaTarjetaSuperserie` cristal cian local | `HojaTarjetaSuperserie.swift:12`–`:31`, render `:179`–`:189` | **Funde** en régimen mosaico `tono: .cian` — hoy duplica la receta teñida *sin* pasar por `EntrenarVidrio` (`:6`). |
| `HojaRondaDivisor.cianRotulo` | `HojaRondaDivisor.swift:24` (`#136A78`) | **Funde** → `tono.cian.rotulo` (hex duplicado). |
| `SheetPaper` (Instrumento) | `SheetPaper.swift:12`, `:28` | **Fuera de alcance del vidrio** — papel de sheet Instrumento; muere con la migración de pantallas de papel (sección 2), no se funde a `liquidGlass`. |

---

## 2) Pantallas de papel a migrar

Base: filas DNA **Instrumento** / «papel muerto» / huérfanas de `AUDIT-FRONTEND-GROK.md` (tabla resumen `#2`, `#28`–`#39`, `#42`, `#44`–`#45`, `#53`–`#54`, `#57`, `#59`–`#64`, más residuales) **cruzadas** con grep actual de `theme.paper` / `InstrumentoTheme` en `Cenit/`.

> Nota de frescura: varias filas del audit ya llevan `.entrenarHojaFondo` (Rest, Progression, Library, Plates, etc.). Esas **ya no son papel como fondo**; salen de esta lista de migración de papel y quedan como limpieza residual de `InstrumentoTheme` (toolbar/theme param), fuera del conteo ~15–18.

### 2.1 Lista (~17 superficies) con destino

| # | Superficie | Evidencia papel / Instrumento | Destino |
|---|---|---|---|
| 1 | `TermsGateView` | `Cenit/App/TermsGateView.swift:19` (`theme.paper.ignoresSafeArea`) · audit #2 | **Migrar → sobrio** |
| 2 | `AutonomicTrendDetailSheet` | `Cenit/Screens/AutonomicTrendCard.swift:35`–`:37` (`theme.paper` + `.sheetPaper`) · audit #32 | **Migrar → sobrio** |
| 3 | `FusionAgreementRow` | `Cenit/Screens/FusionAgreementRow.swift:79` · audit #33 | **Migrar → sobrio** (parche Instrumento dentro de Explorer Liquid) |
| 4 | `TrainingLoadStrip` | `Cenit/Screens/TrainingLoadStrip.swift:128` · audit #28 | **Migrar → sobrio** (la hoja hermana ya es Liquid) |
| 5 | `HealthAlertBanner` | audit #36 · `Cenit/Screens/HealthAlertBanner.swift` (Instrumento card) | **Migrar → sobrio** |
| 6 | `WorkoutDetailScreen` | `Cenit/Screens/WorkoutDetailScreen.swift:103` · audit #44 | **Migrar → sobrio** |
| 7 | `MetricDetailScreen` (árboles de papel rollback) | `MetricDetailScreen.swift:147` (rollback compilado); vivo ya `LiquidSheetFondo` `:156` · audit #29 | **Archivar** código muerto de papel (borrar rollback; el camino vivo ya es Liquid) |
| 8 | `ShareCardView` | audit #39 · superficie Instrumento de recibo/bitmap | **Migrar → sobrio** *o* **fuera de alcance** si se trata como artefacto de export no-UI. «(a decidir por arquitecto/dueño)» — default propuesto: **migrar tokens sobrio** sin fingir hoja de producto |
| 9 | `SessionKeypad` | audit #61 · `Cenit/Screens/SessionKeypad.swift` (theme Instrumento) | **Migrar → mosaico** (herramienta de serie Entrenar) |
| 10 | `LiveStrengthSheet` residual papel | `LiveStrengthSheet.swift:706`, `:999` (`.background(theme.paper)`); raíz ya `:269` El Eje · audit #53 | **Migrar → mosaico** los sub-estados/acta que aún pintan papel |
| 11 | `RoutineSheet` (hoja fría) | `Cenit/Screens/Hoja/RoutineSheet.swift:173`, `:291`, `:405` · audit #54 | **Migrar → mosaico** |
| 12 | `RoutineSheetLive` | `Cenit/Screens/Hoja/RoutineSheetLive.swift:141` · audit #54 | **Migrar → mosaico** |
| 13 | `ExerciseDetailScreen` chrome Instrumento | Fondo ya El Eje `:128`; residual `toolbarBackground(theme.paper)` `:184` · audit #42 | **Migrar → mosaico** (limpiar chrome/papel residual) |
| 14 | `ContentView` / `StoreFailure` papel | `Cenit/App/ContentView.swift:158`, `:307` · audit #1 | **Migrar → sobrio** |
| 15 | **WhatsNewView** | `Cenit/Screens/WhatsNewView.swift:36`–`:37`; sheet desde `ContentView.swift:133` · audit #37 | **Migrar → sobrio** (sigue alcanzable post-update). *No* archivar mientras el shell la presente. |
| 16 | ~~Dieta (captura)~~ | Archivada FER-239 — archivo y puerta retirados (FER-92 + audit #38) | **Archivada** (borrada; sin ruta de producto) |
| 17 | **Patrones** (BucleView + BucleSheets) | Pantalla + sheets borrados en FER-240; deep-links (`openInsightKey` / `.coach`) neutralizados; off-dock desde FER-992 · audit #63–#64 | **Hecho (FER-240)** — reabrir solo con issue propio + régimen sobrio |

### 2.2 Decisiones explícitas (WhatsNew / Dieta / Patrones)

| Superficie | ¿Huérfana? | Decisión de alcance FER-229 |
|---|---|---|
| **WhatsNewView** | No del todo: `ContentView` aún la presenta tras update (`ContentView.swift:133`) | **Migrar a sobrio** en la ola de papel. Archivar solo si el dueño retira el auto-sheet en el mismo PR. |
| ~~Dieta (captura)~~ | Sí — puerta retirada FER-92; pantalla borrada FER-239 | **Archivada** (borrada; no migrar). |
| **Patrones** (BucleView + BucleSheets) | Sí — archivada FER-240; tab off-dock (audit H-055) | **Hecho.** Si vuelve el producto, nueva issue + sobrio desde cero. |

### 2.3 Fuera de esta lista (no contar como «papel a migrar»)

| Grupo | Razón |
|---|---|
| Hoy, onboarding, hojas Liquid de métrica, Cuerpo landing, Ajustes Liquid | Ya DNA Liquid (audit #4–#27, etc.). |
| Hub Entrenar + hojas con `.entrenarHojaFondo` | Ya régimen mosaico/El Eje; no son papel. |
| Watch OLED / WidgetKit / Live Activity (audit #65–#68) | **Fuera de alcance** del épico FER-229 (Watch OLED excepción viva; widgets no son el sistema de vidrio de app). |
| `ReceiptPrinterScreen` | Objeto térmico documentado (mixto); no es Instrumento papel de navegación. |

---

## 3) Call sites de `EntrenarTono` / `EntrenarVidrio`

Lista grepeable de consumidores **fuera** de `Cenit/Screens/Entrenar/EntrenarHub*.swift`. Incluye definición DS, puentes, hex duplicados y usos en app. Verificación:

```bash
rg -n 'EntrenarTono|EntrenarVidrio|EntrenarVidrioReceta|EntrenarVidrioMetrics|EntrenarModulo|EntrenarTile' \
  Packages Cenit --glob '*.swift'
rg -n '#136A78|#514E86|#0A6B4A|#93445A|#A0500F' Packages Cenit --glob '*.swift'
```

### 3.1 Definición y puente (StrandDesign)

| Archivo | Símbolos / líneas |
|---|---|
| `Packages/StrandDesign/.../Entrenar/EntrenarVidrio.swift` | `EntrenarTono` `:22`; `rotulo` hex `:47`–`:50`, `:63`; `EntrenarFamily.tono` `:77`; `EntrenarVidrioMetrics` `:91`; `EntrenarVidrioReceta` `:145`; `EntrenarModulo` `:224`; `EntrenarTile` `:258` |
| `Packages/StrandDesign/.../Entrenar/EntrenarHojaFondo.swift` | `entrenarHojaFondo(tono:)` `:55`; usa `EntrenarTono` + `EntrenarVidrioMetrics` `:100` |
| `Packages/StrandDesign/.../Entrenar/EntrenarHojaCabecera.swift` | `tono: EntrenarTono` `:29`, `:45` |
| `Packages/StrandDesign/.../Entrenar/EntrenarFilaDiscos.swift` | `tono: EntrenarTono` `:32`, `:40` |
| `Packages/StrandDesign/.../Entrenar/EntrenarFilaEsfuerzo.swift` | `tono: EntrenarTono` `:14`, `:21` |
| `Packages/StrandDesign/.../Entrenar/EntrenarNotaCampo.swift` | `tono: EntrenarTono` `:13`, `:15` |
| `Packages/StrandDesign/.../Entrenar/EntrenarStepperSegundos.swift` | `tono: EntrenarTono` `:12`, `:18` |
| `Packages/StrandDesign/.../Entrenar/EntrenarMiniBarras.swift` | `tono: EntrenarTono` `:32`, `:38` |
| `Packages/StrandDesign/.../Entrenar/EntrenarHistorialLista.swift` | `EntrenarModulo(tono: .neutro)` `:29` |
| `Packages/StrandDesign/.../Entrenar/EntrenarHubMetrics.swift` | docs/refs a `EntrenarVidrio` / `EntrenarModulo` `:5`, `:146`–`:150` |
| `Packages/StrandDesign/.../Entrenar/EntrenarFilaHerramienta.swift` | previews con `tono:` / `.entrenarHojaFondo` `:64`, `:69`, `:85` |

### 3.2 Hex duplicados de tono (no pasan por el enum)

| Archivo | Línea | Hex | Nota |
|---|---|---|---|
| `EntrenarVidrio.swift` | `:47`–`:50`, `:63` | `#514E86` `#136A78` `#0A6B4A` `#93445A` `#A0500F` | Canónicos en `EntrenarTono.rotulo` / `.tesela` |
| `HojaRondaDivisor.swift` | `:24` | `#136A78` | `cianRotulo` — duplica `EntrenarTono.cian.rotulo` |
| `HojaTarjetaSuperserie.swift` | `:48` | `#136A78` | `cianRotulo` privado — mismo duplicado + cristal local |

### 3.3 Call sites Cenit (fuera de `EntrenarHub*`)

| Archivo | Líneas | Qué usa |
|---|---|---|
| `Cenit/Screens/LiveStrengthSheet.swift` | `:1060`, `:1131`, `:1161`–`:1162` | `EntrenarModulo`; `chipTono` → `EntrenarTono` vía `family.tono` |
| `Cenit/Screens/EntrenarView.swift` | `:373` | `(…).family.tono` al armar héroe/hub |
| `Cenit/Screens/Hoja/HojaTarjetaEjercicio.swift` | `:22` | `EntrenarModulo(tono: .neutro)` |
| `Cenit/Screens/Hoja/HojaPlegada.swift` | `:26` | `EntrenarModulo(tono: .neutro)` |
| `Cenit/Screens/Hoja/RoutineSheetLiveTarjeta.swift` | `:28`, `:309`, `:508` | `EntrenarModulo` `.indigo` / `.neutro` |
| `Cenit/Screens/WorkoutHistoryScreen.swift` | `:372`, `:417`–`:418` | `EntrenarModulo` / `EntrenarTile` `.neutro` |
| `Cenit/Screens/LiveStrengthSheets.swift` | `:63`, `:72`, `:96`, `:206`, `:217`, `:231`, `:385` | `.entrenarHojaFondo`; `EntrenarHojaCabecera`; `EntrenarFilaEsfuerzo`; `EntrenarNotaCampo` |
| `Cenit/Screens/PlatesScreen.swift` | `:59`, `:110` | `.entrenarHojaFondo(.ambar)`; `EntrenarFilaDiscos` |
| `Cenit/Screens/ProgressionSetupScreen.swift` | `:91`, `:147` | `EntrenarHojaCabecera`; `.entrenarHojaFondo(.verde)` |
| `Cenit/Screens/RestEditorScreen.swift` | `:195` | `.entrenarHojaFondo(.verde)` |
| `Cenit/Screens/CrearPlanScreen.swift` | `:47`, `:69` | `EntrenarHojaCabecera`; `.entrenarHojaFondo` |
| Resto de hojas con `.entrenarHojaFondo` | ver §1.3 | Todas tipan `EntrenarTono` en la API del modificador |

### 3.4 Solo hub (excluido del criterio «fuera de Hub», listado para no romper al renombrar)

Los archivos `Cenit/Screens/Entrenar/EntrenarHub*.swift` consumen `EntrenarTono` / `EntrenarModulo` / `EntrenarTile` / `family.tono` / `EntrenarMiniBarras` (p. ej. `EntrenarHubHeroe.swift:13`, `EntrenarHubDosis.swift:37`–`:39`, `EntrenarHubMarcasVolumen.swift:57`–`:96`, `EntrenarHubPar.swift:58`–`:65`, `EntrenarHubSemana.swift:27`–`:79`, `EntrenarHubConstancia.swift:37`–`:91`, `EntrenarHubHistorial.swift:32`–`:69`, `EntrenarHubCuerpo.swift:26`). La fusión debe renombrarlos en la misma ola que el enum.

### 3.5 No confundir

`tono:` / `.tono` en hojas Liquid (`SleepDetailScreen`, `StrainDetailScreen`, `LiquidSheetHeader`, etc.) es **Color de señal**, no `EntrenarTono`. No entran en esta lista de fusión.

---

## Cómo verificar este inventario

1. El archivo existe en `docs/design-system/INVENTARIO-UN-SOLO-VIDRIO.md` con las **3 secciones**.
2. Cada superficie de §1 tiene destino funde / conserva / fuera-de-alcance (+ razón).
3. Cada pantalla de §2 tiene destino migrar (régimen) / archivar; WhatsNew, Dieta (archivada FER-239) y Bucle/Patrones están decididos en §2.2.
4. §3 es grepeable con los dos `rg` de arriba; cualquier call site nuevo de `EntrenarTono` fuera del hub debe añadirse aquí antes de fundir.

**Aprobación:** pendiente del dueño (criterio FER-233).
