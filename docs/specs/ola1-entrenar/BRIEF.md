# Brief común · Ola 1 de Entrenar (Cénit) · taller de requerimientos · 2026-09-02

Repo (worktree, SOLO lectura para ti): /Users/fer.iracheta/code/noop/.claude/worktrees/new-session-ac9284
Reglas duras del repo (CLAUDE.md): 100 % offline, sin cuenta, sin red; matemática transparente con método citado + test; sin claims clínicos;
sistema de diseño StrandDesign («Liquid Glass · El Eje»: lienzo blanco, tinta, verde primario) es ley; migraciones append-only vía
`CenitStore.addColumnIfMissing`; copy es-MX que no supone género; una idea por oración. NO compiles ni corras swift build/test.
Decisión vigente FER-85: el veredicto del cuerpo NUNCA cambia la rutina del día ni sugiere movilidad; solo difiere la subida de peso.
Propuesta base (léela): /private/tmp/claude-501/-Users-fer-iracheta-code-noop--claude-worktrees-new-session-ac9284/d9d4b932-78bc-42b0-9b01-58f45f8317c4/scratchpad/ola1-a-fondo.html (HTML; léelo con cat, es texto).

## Las cinco piezas
① Carga sin FC: una sesión de fuerza sin Apple Watch entra a la carga del día (escala 0–21) con session-RPE (Foster 2001): duración × esfuerzo.
   Pregunta de un toque al cerrar («¿qué tan duro estuvo?», 5–10, prellenada con promedio de RPE de series de trabajo, saltable). Con FC manda la FC. Sin dato no se estima. Etiqueta «estimada».
② RPE gobierna la progresión: ProgressionState gana el esfuerzo por serie. Cumplió reps y RPE ≤ 8 en todas → sube en 1 sesión (no 2);
   8.5–9 → como hoy; alguna serie ≥ 9.5 → mantiene (no cuenta para subir ni para deload); sin RPE → como hoy. Veredicto sigue difiriendo encima. Interruptor «Usar mi esfuerzo» en setup de progresión.
③ Tipos de serie: SetKind gana `amrap` y `drop`. AMRAP: reps objetivo «máx», cuenta a volumen/progresión/récords/1RM. Drop: sub-serie sin descanso a −20 % (PlateMath), cuenta a volumen, no a progresión ni récords. «Al fallo» = atajo que pone RPE 10 (no es tipo).
④ Import CSV de Strong y Hevy: entrada en Ajustes › Datos y fuentes › Importar; detecta dialecto por columnas; vista previa (sesiones, ejercicios reconocidos, por resolver, duplicados); pantalla de resolver nombres (sugerido / elegir / crear propio); idempotente por origen+hora; sin FC no inventa carga; si trae RPE, ① calcula carga estimada; récords/1RM/mapa se recalculan solos.
⑤ Programas con descarga: Programa = calendario semanal existente + contador de semanas (4–6) + regla de última semana (series −40 %, mín 1; peso −10 % redondeado a discos; reinicia contadores de estancamiento). Tira de semanas en Tu Plan; héroe «Semana de descarga» en el hub; fila «Programas» en Crear plan con 4 motores de dominio público (lineal novato, PPL 6 días, superior/inferior 4, cuerpo completo 3). Import desde tu IA gana campos opcionales «semanas» y «descarga».

## Dónde vive hoy lo que se toca (archivo:línea, verificado 2026-09-01)
- Regla de progresión: Packages/StrandAnalytics/Sources/StrandAnalytics/ProgressionState.swift (classify 105-153; metGoal 93-96; PastSession 48-60; deload 16-18).
- Veredicto → carga: Packages/StrandAnalytics/Sources/StrandAnalytics/TrainingRegulation.swift:100-130 (allowsRaise, gatesTraining).
- Strain por FC: Packages/StrandAnalytics/Sources/StrandAnalytics/StrainScorer.swift (Edwards/Banister, escala 0–21). ACWR/monotonía: ReadinessEngine.swift:170-180, 282-329, 378-406, 633 (strainToLoad, la inversa que hay que usar al revés).
- Modelo de serie: Packages/StrandTraining/Sources/StrandTraining/Training.swift:312-345 (SetKind work/warmup; SetEntry con rpe 6–10, restTakenS). Sesión: StrengthSession (strain: Double?, avgHr). Calendario semanal: RoutineSchedule 98-113. Descansos 10-25. Superseries 197-202.
- PlateMath (discos, calentamiento): Packages/StrandAnalytics/Sources/StrandAnalytics/PlateMath.swift:22-169.
- 1RM: OneRepMax.swift (Epley/Brzycki, tope 12 reps, tendencia 90 d).
- Volumen semanal: Packages/StrandTraining/Sources/StrandTraining/TrainingWeeks.swift:41-163. Mapa muscular: MuscleFatigueMap.swift.
- Export CSV propio: Packages/StrandTraining/Sources/StrandTraining/StrengthCSV.swift (header línea 10). Import desde IA + alias de nombres: Packages/StrandImport/Sources/StrandImport/WorkoutProgram.swift, ExerciseAliasTable.swift, ImportCoordinator.swift.
- Plantillas: Packages/StrandTraining/Sources/StrandTraining/StarterTemplates.swift:77-148.
- Base de datos: Packages/CenitStore/Sources/CenitStore/Database.swift (migraciones; customExercise 278-286; addColumnIfMissing).
- App: Cenit/Screens/EntrenarView.swift (hub; héroe; regla FER-85 en 883-897; first-run 1138-1281), Cenit/Screens/StrengthSessionModel.swift (sesión viva: auto-descanso 608-621, addSet 815-822, prefill 843-851), Cenit/Screens/Hoja/RoutineSheetLiveLogic.swift (PRs 524-564; superseries 779-933; editar/sustituir 298-925), Cenit/Screens/SessionKeypad.swift, Cenit/Screens/LiveStrengthSheet.swift (recibo, achievementLine 1510-1521; escala RPE 125-149), Cenit/Screens/ReceiptPrinterScreen.swift, Cenit/Screens/WeeklyPlanEditorView.swift (Tu Plan; volumen 1084-1126), Cenit/Screens/CrearPlanScreen.swift, Cenit/Screens/RoutineEditorScreen.swift, Cenit/Screens/ProgressionSetupScreen.swift, Cenit/Screens/DataSourcesView.swift (import/export 736-812), Cenit/Screens/WorkoutHistoryScreen.swift, Cenit/Screens/WorkoutImportView.swift, Cenit/App/AppModel+Strength.swift (guardar sesión, HKWorkout 140-200), CenitWidgets/RestLiveActivity.swift, CenitWatch/.
- Docs: docs/FEATURES.md (Entrenar 144-224), docs/ARCHITECTURE.md, docs/DECISIONS.md, docs/design-system/DESIGN.md, LIQUID-GLASS.md, CATALOGO.md.

## Formato de entrega de cada agente
Markdown, español de México, compacto. Todo lo que afirmes sobre el código actual va con archivo:línea. Lo que no verificaste, dilo. Sin código de producción: specs, reglas, estados, copy y criterios de aceptación VERIFICABLES (cada uno una frase comprobable por un QA).
