## Contexto
Quien cambia de app llega con historial cero. Hevy captura usuarios de Strong con un import de CSV. Formatos verificados contra archivos reales (repos públicos, 2026-09-02): Strong `Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE[,Notes,Workout Notes]` (fecha `yyyy-MM-dd HH:mm:ss` local; `Duration` «35m»/«1h 5m»; `Set Order` «W» = calentamiento; unidad solo si la cabecera dice `Weight (kg|lbs)`); Hevy `title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg|weight_lbs,reps,distance_km,duration_seconds,rpe` (fecha `d MMM yyyy, HH:mm` con mes en el idioma de la cuenta; `set_type` warmup/normal/failure/dropset). Fuente: `arq-A.md §④` con E10 (v2) y N5/N6 (v3), `ux-C.md`, `gate-estadistico-1.md` H7.

## Objetivo
Lector puro de tres dialectos (strong, hevy, cenit) con fixtures reales, reconciliación de nombres reutilizada, ids deterministas e importación en un solo write.

**Carril:** pesado (datos on-device). Lo teclea Grok con este spec; Claude revisa el diff. **Depende de E1 y E2 mergeados** (usa `SessionRPE.prefill` y `SessionRPELoad`).

## Reglas y lógica
- `StrengthCSVImporter` (StrandImport, Foundation-only): `Dialect { strong, hevy, cenit }`; `detectDialect(header:)` por CONJUNTO de nombres de columna (nunca posición; normaliza BOM/UTF-16/`;`); `parse(text:dialect:weightUnit:) throws -> ImportedStrengthHistory { sessions, skipped: [RowIssue] }`.
- Unidades: Hevy por cabecera; Strong por cabecera si existe, si no `weightUnit` obligatorio (`throw .unitRequired`; la UI pregunta con pista «peso más alto del archivo: 315 → 143 kg»). lb→kg ×0.45359237 redondeado a 0.01 (reusa `WorkoutWeightUnit`).
- Fechas: Strong `TimeZone.current`; Hevy tabla propia de meses en/es/pt/fr/de, `en_US_POSIX` primero. Fecha ilegible → `RowIssue`, nunca inventada. Duración Strong → `endTs`; Hevy `end_time`.
- Tipos: Hevy warmup→`.warmup`; normal→`.work`; failure→`.work` + `rpe = 10`; dropset→`.work` + `mode = .drop`. Strong «W»→`.warmup`, número→`.work`; valores desconocidos → serie omitida con conteo. RPE < 6 o > 10 → `rpe = nil` (nunca clampear).
- Reconciliación (capa app): `WorkoutExerciseReconciler` + `ExerciseAliasTable.bundled` + alias aprendidos, extraído de `WorkoutImportView` a un componente compartido; ampliar `Tools/bake-exercisedb/build_aliases.py` con los ~100 nombres más comunes de cada app; ambiguos («Row», «Press», «Curl», «Fly») nunca auto-casan.
- Idempotencia: `id = "\(source)-\(startTs)"`; `saveSessions(_:)` = un `syncWrite` que repite `saveSession` (incl. `updatePersonalRecords` con el `ts` original: el hub no celebra récords de 2022). «Ya estaban» = `existingSessionIds`. Traslape entre orígenes a ±30 min → `ImportedStrengthHistory.possibleDuplicates: [(session: ImportedSession, existing: (id, source, title, startTs))]`, expuesto con `startTs`/`source`/`title` para que E9 pinte «Posibles duplicados · N · fuera» sin inventar campos; **default fuera**, toggle = forzar.
- Persistencia: `StrengthSession(routineId: nil, deviceId: nil, avgHr: nil, source:, title:, notes:)`; `sessionRpe = SessionRPE.prefill(sets)`, `sessionRpeSource = 'prefill'`, `strain = SessionRPELoad` si hay duración y RPE (`strainSource = 'rpe'`); si no, `strain = nil`. El overlay (E2) solo cuenta lo posterior a la primera fila base o ≤ 56 días.
- Dialecto `cenit`: lee el export propio incluyendo `set_mode`, `rpe`, `rest_taken_s`; ida y vuelta sin pérdida.
- Concurrencia: parse en `Task.detached`; un hop al actor; un refresh.

## Alcance técnico
Nuevo `Packages/StrandImport/.../StrengthCSVImport.swift` + `Tests/Resources/{hevy_kg,hevy_lb,strong_current,strong_legacy,cenit_roundtrip}.csv` (archivos reales, anonimizados); `StrengthStore.saveSessions`/`existingSessionIds`; `Tools/bake-exercisedb/build_aliases.py` → `exercise-aliases.json`.

## Fuera de alcance
Pantallas (E9). Crear rutinas desde nombres (D-Q9).

## Criterios de aceptación
- [ ] `StrengthCSVImportTests`: `testDetectsHevyByColumns`, `testDetectsStrongByColumns`, `testDetectsCenitByColumns`, `testRejectsUnknownHeader`, `testHevyKgParsesSetsAndRPE`, `testHevyLbConvertsToKg`, `testHevyDateWithSpanishMonth`, `testStrongParsesDurationToEndTs`, `testStrongWarmupW`, `testStrongWithoutUnitRequiresUnit`, `testSessionKeyIsSourcePlusStart`, `testFailureSetBecomesRPE10`, `testDropsetBecomesModeDrop`, `testUnknownSetTypeIsSkippedWithCount`, `testRPEBelow6IsNil`, `testMalformedRowIsSkippedNotFatal`, `testCenitRoundTripLossless`.
- [ ] `WorkoutAutoMatchTests`: `testStrongHevyTop100Resolve` (≥ 90 % auto) y `testTrapsDoNotAutoMatch` ampliado.
- [ ] `StrengthStoreTests`: `testSaveSessionsBatchIsIdempotentById`; `testSaveSessionsBatchUnderTwoSecondsFor1000Sessions`; `testImportedPRsKeepOriginalTs`.
- [ ] Los 5 fixtures existen en el repo antes del merge (bloqueante).

## Definition of Done
- [ ] `swift test` StrandImport + CenitStore verde; `Tools/verify.sh` verde; /qa PASS.
