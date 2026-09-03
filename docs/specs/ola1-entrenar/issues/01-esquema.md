## Contexto
Las cinco piezas de la ola 1 necesitan columnas y una tabla nuevas. Si cada pieza abre su migración, tres worktrees chocan en `v42`. Un solo PR de esquema, antes que todo, desbloquea los tres carriles. Fuente: `CONSOLIDACION-v2.md §C` (tabla canónica), `arq-A.md §Migración`, `arq-B.md §Migraciones`.

## Objetivo
Aterrizar v42 y v43 en `CenitStore`, sus modelos en `StrandTraining`, la documentación al día, y los specs del taller copiados al repo.

**Carril:** pesado (migración). Pasa por /arquitecto antes de codear.

## Comportamiento esperado
Ninguno visible. Todo append-only; una base vieja migra sin perder filas; una base que ya tenga alguna columna (re-instalación sobre DB iterada) no truena.

## Reglas y lógica
- **v42**, todo por `CenitStore.addColumnIfMissing`:
  - `strengthSession`: `strainSource TEXT` ('hr'|'rpe'; NULL con strain no-nil = legado hr) · `sessionRpe REAL` (6–10, NULL = sin calificar) · `sessionRpeSource TEXT` ('answered'|'prefill') · `trimpPerAU REAL` · `source TEXT` ('strong'|'hevy'|'cenit-csv'; NULL = Cénit) · `title TEXT` · `programWeek INTEGER` · `deload INTEGER`.
  - `routineExercise.progressionUseRPE INTEGER NOT NULL DEFAULT 0` (semántica: ritmo «Según reps en reserva»).
  - `routineSet.mode TEXT` · `setEntry.mode TEXT` (NULL = standard; valores 'standard'|'amrap'|'drop').
- **v43** (`endMode` amplía la tabla canónica de v2 §C: es pulido post-taller del dueño, «Al terminar el ciclo», ver E10/E11): tabla `program` (`id TEXT PK` = 'active', `name TEXT NOT NULL`, `weeks INTEGER NOT NULL`, `startTs INTEGER NOT NULL`, `deloadRule TEXT NOT NULL` ('volumeOnly'|'volumeAndLoad'|'none'), `endMode TEXT NOT NULL` ('repeat'|'single'), `templateId TEXT NULL`, `createdTs INTEGER NOT NULL`), creada con guard `tableExists`.
- Modelos: `StrengthSession` +6 campos opcionales con default; `RoutineExercise.progressionUseRPE: Bool = false`; `SetMode { standard, amrap, drop }` como `String, Codable` en `Training.swift` junto a `SetKind` (que NO crece); `RoutineSet.mode`/`SetEntry.mode` default `.standard`; `SetSnapshot.mode: SetMode?` (JSON viejo → nil); `Program` struct. Solo tipos y persistencia: sin reglas de negocio (van en E2–E10).
- `StrengthCSV.header` gana `,set_mode` al final (vacío = standard). Test de header actualizado.

## Alcance técnico
- `Packages/CenitStore/Sources/CenitStore/Database.swift` (migrator; patrón `addColumnIfMissing` en `:941-947`; tests con el patrón de `testV40AddsRestTakenS…` en `MigrationTests.swift:1401-1445`), `StrengthStore.swift` (leer/escribir las columnas en `saveSession`/`updateSession`/`recentSessions`/`session(id:)`/`saveRoutine`/`routineExercises`/`routineSet`).
- `Packages/StrandTraining/Sources/StrandTraining/Training.swift`, `StrengthCSV.swift`.
- Docs en el MISMO PR: `docs/ARCHITECTURE.md` §7 (v42/v43; «migrator llega a v43» en :311), `docs/DATA_MODEL.md` (v42/v43 + nota de que v27–v41 quedan pendientes → E14), `docs/DECISIONS.md` (transcribir FER-85 con la orden del dueño del 2026-08-16: «yo sí quiero que el usuario, si quiere, le pueda subir» → la app aconseja, no bloquea; «Otra forma» nunca lee el veredicto; y las decisiones D-Q del épico).
- Copiar los specs del taller a `docs/specs/ola1-entrenar/`: todos los `.md` de la carpeta del taller citada en el épico (consolidaciones, ux, arq, gates, rondas, issues) y la subcarpeta `artefactos/` con los tres HTML del dueño; crear `docs/specs/ola1-entrenar/tips-es.md` con la tabla de copy de tips de E12.

## Fuera de alcance
Cualquier regla que use las columnas (progresión, carga, descarga, dedupe): eso es E2–E10.

## Criterios de aceptación
- [ ] `MigrationTests`: `testV42AddsOla1ColumnsAppendOnly` (migra a v41, inserta filas pre-v42 en strengthSession/routineExercise/routineSet/setEntry, migra a v42: columnas presentes, filas sobreviven con NULL y `progressionUseRPE == 0`).
- [ ] `testV42IsIdempotentWhenColumnsAlreadyExist` (añade a mano las 11 columnas de v42 — strengthSession: strainSource, sessionRpe, sessionRpeSource, trimpPerAU, source, title, programWeek, deload · routineExercise.progressionUseRPE · routineSet.mode · setEntry.mode — y migra: sin throw). `testV43IsIdempotent` crea `program` a mano y migra.
- [ ] `testV43CreatesProgramTableAppendOnly` + `testV43IsIdempotent`.
- [ ] `testSetModeRoundTripsAndNullReadsStandard` (guarda standard/amrap/drop; NULL decodifica `.standard`).
- [ ] `StrengthSessionSnapshotTests`: JSON pre-v42 sin `mode` decodifica; con `mode` ida y vuelta.
- [ ] `StrengthCSVTests.testHeaderColumns` termina en `set_mode`.
- [ ] `git diff Database.swift` solo añade después de la última migración shipped; ninguna migración ≤ v41 cambia.
- [ ] `grep -rn "import GRDB\|import UIKit" Packages/StrandTraining/Sources` = 0.

## Definition of Done
- [ ] `swift test` verde en CenitStore, StrandTraining. `Tools/verify.sh` verde.
- [ ] Docs de arriba actualizadas en el mismo PR; `docs/specs/ola1-entrenar/` presente.
- [ ] PR con `Closes FER-E1`, squash-merge a `iOS`.
