# Auditoría A — Construcciones a mano vs. el catálogo (FER-279)

> **Solo reporte.** Línea Grok (3 barridos, 38 archivos de pantalla auditados — 32 leídos completos,
> los 4 gigantes por secciones de UI + grep exhaustivo de superficies), consolidado por el director
> desde el transcript del lane (el worktree del lane murió antes del push; los hallazgos citan
> archivo:línea verificables). No son hallazgos: geometría de datos, `#Preview`/DEBUG, exenciones
> `dato/sistema/unico` justificadas, y chrome interno de piezas del catálogo.

## Veredicto global

El vocabulario **NO cubre aún el árbol**: quedan ~30 hallazgos en **6 clases transversales**. La
buena noticia: son clases, no 30 problemas — matar las 6 mata casi todo (regla del repo). Las
pantallas Liquid migradas recientes (detalles de métrica, Sueño/Estrés/Preparación, Compare,
Onboarding) salieron **limpias**: el patrón de deuda vive en Entrenar/hojas de fuerza e importación.

## Las 6 clases (kill-the-class, por palanca)

### 1 · CTAs de tinta hechos a mano — duplicado de `StrandCTAButton` (≥9 sitios)
`fill` + `RoundedRectangle(ctaRadius…)` + label grotesk: la anatomía exacta del catálogo.
Sitios: `LiveStrengthSheets.swift:117` · `LiveStrengthSheet.swift:1380,1442,1454` ·
`StarterTemplatesSheet.swift:221,245` · `PlatesScreen.swift:264` · `ManualWorkoutSheet.swift:144` ·
`ExerciseLibraryScreen.swift:598`. **Acción:** reemplazo directo por `StrandCTAButton`/`LiquidGlassButton`.

### 2 · Cápsulas outline de acción — pieza que FALTA (≥15 sitios, la clase más regada)
`Capsule().strokeBorder(hairlineStrong)` ± fill como control tocable: «Use», raise pill, Start/Stop
cardio, «Change rest», accesorios del keypad, chips de filtro de biblioteca, Match/Create/Omit del
import, «Archive»… Sitios núcleo: `LiveStrengthSheets.swift:460` · `RoutineSheetLiveTarjeta.swift:125,336,353,407` ·
`RoutineSheetLive.swift:470` · `RoutineSheetLiveLogic.swift:704` · `SessionKeypad.swift:217` ·
`SetActionPills.swift:73` · `WorkoutImportView.swift:388` · `ExerciseLibraryScreen.swift:206,368,400` ·
`ExerciseDetailScreen.swift:593`. **Acción:** UNA pieza `OutlineCapsule`/chip de acción con estados.

### 3 · Familia banner/aviso partida en 4 dialectos — consolidar
`TodayBanner` (Instrumento) · `LiquidPatternBlock`+tarjeta (Liquid, el bueno) · `AvisoDesconexion`
privado (`HoyModosHost.swift:126-201`) · `connectNudge` (`CuerpoView.swift:1167-1187`) · toasts
undo a mano (`WeeklyPlanEditorView.swift:748,871` · `WorkoutHistoryScreen.swift:1315`) · banners de
error que NO usan `SaveErrorToast` (`WorkoutHistoryScreen.swift:176,1606` · `WorkoutImportView.swift:90`).
**Acción:** una receta Liquid de aviso + `UndoToast` como pieza; demoler los dialectos.

### 4 · Pastillas de estado hechas a mano — `StatePill` no habla Liquid
`statusPill` duplicado idéntico en `BreathingView.swift:182-196` y `IntervalTimerView.swift:199-211`
(El Eje: verde opaco / `pastillaSolida`); chips de valencia Δ% (`WorkoutHistoryScreen.swift:645` ·
`ExerciseDetailScreen.swift:710` · `WorkoutImportView.swift:323,503`); sello de `HojaDecideTuDia.swift:121-141`.
**Acción:** `LiquidStatePill` (+ variante de valencia) y `StatePill` queda de la era vieja.

### 5 · APIs del catálogo incompletas que OBLIGAN al fork (la causa raíz medible)
- `LiquidMetricTile` exige `delta` → Apple Health se fabricó `liquidStatTile` privado ×8
  (`AppleHealthView.swift:436-532`). **Acción:** delta opcional / variante quiet.
- `LiquidListRow` sin slot trailing → Ajustes clona filas a mano ×3 (`AjustesView.swift:229-246,493-533`).
  **Acción:** slot `trailing: View`.
- `LiquidGlassButton` sin `.destructive` → cápsula crítica a mano (`DataSourcesView.swift:820-834`).
- `EntrenarCapsulaPuerta` fuerza `›` → cápsula «＋ SET» a mano ×2 (`HojaTarjetaEjercicio.swift:194-208` ·
  `RoutineSheetLiveTarjeta.swift:431`). **Acción:** promover `HojaLiveMetrics` a pieza.

### 6 · Vidrio fuera de la única puerta
`liquidLenteTenida` — receta de vidrio completa (gradiente+especular+canto+sombra) privada en la
capa app (`CuerpoView.swift:1660-1700`); pastillas de vidrio del héroe del hub reinventadas
(`EntrenarHubHeroe.swift:112-126,163-173` — contraste: `empezarPill` en :143 SÍ usa la pieza).
**Acción:** todo vidrio pasa por `liquidGlass(_:)`/`LiquidGlassButton` o se promueve con nombre.

## Piezas que faltan (regla ×3 y controles fuertes de 1 sitio)

| Pieza propuesta | Evidencia |
|---|---|
| Cápsula outline de acción (clase 2) | ≥15 sitios |
| `UndoToast` / snack de tinta | 3 sitios |
| `LiquidStatePill` + valencia | 6 sitios |
| Buscador (`SearchField`) | `LiveStrengthSheets.swift:414-424` |
| `DashedAddRow` (troquel punteado) | `HojaPlegada.swift:63-67` |
| `DashedDropZone` (pegar/soltar) | `WorkoutImportView.swift:225` |
| Chip de inventario de discos | `PlatesScreen.swift:321-323` |
| Fila de sugerencia de import | `WorkoutImportView.swift:351` |
| Stepper de fases / progreso | `WorkoutImportView.swift:572` |
| Tarjeta seleccionable con estados (pace del breathing) | `BreathingView.swift:220-256` |
| Chip de PR / RECORD | `WorkoutHistoryScreen.swift:2017` · `ExerciseDetailScreen.swift:324` |
| Cápsula de confianza punteada | `ActivityRecoverySheet.swift:197-205` (+ Tendencia) |

## Duplicados menores y limítrofes
Header disc/pill de sesión vs `BackButton`/`HeaderActionButton` (`LiveStrengthSheet.swift:808,840` —
el tamaño debe ser parámetro, no fork) · tarjetas surface+stroke sin `instrumentoCard`
(`TrainingBodyScreen.swift:301,1066` · `RestEditorScreen.swift:412` · `WorkoutEditSheet.swift:258` ·
`ExerciseLibraryScreen.swift:574,655`) · `patternBlock` reimplementado (`ProgressionSetupScreen.swift:219-231`) ·
fuente vs `SourceBadge` (`WorkoutHistoryScreen.swift:1965`) · CTA zombie (`RoutineSheetLive.swift:477`) ·
chip de descanso de template (`StarterTemplatesSheet.swift:271`) · flash de PR rosa (limítrofe) ·
sombra del recibo térmico (limítrofe intencional) · chrome de Live Activity (carve-out FER-219, inventario).

## Limpios (para calibrar: el sistema SÍ funciona donde se usó)
`EntrenarView` · hub semana/dosis/par · detalles de métrica Liquid · Sueño/Estrés/SkinTemp/Preparación ·
`CompareView` · `TodayView`+banners buenos · Onboarding · `HealthAlertBanner`/`SaveErrorToast`/
`FusionAgreementRow` (usan las recetas correctas) · TrainingLoad/BodyAge sheets · `Cenit/System`.

## Nota de proceso
El lane murió antes de commitear su consolidado (timeout del wrapper); este doc lo compiló el
director desde el transcript, con spot-checks. Los hallazgos alimentan la síntesis 360 de FER-279
junto con las auditorías B (uso) y C (sistema).
