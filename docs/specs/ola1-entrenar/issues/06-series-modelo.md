## Contexto
Hoy una serie es trabajo o calentamiento. Los programas reales usan «las que puedas» (AMRAP) y «bajar y seguir» (drop). Fuente: `arq-B.md §③` + E18 (v3) + E21/E26 (v4/v5), `gate-biomecanico-1.md` #6, D-Q7.

## Objetivo
`SetMode {standard, amrap, drop}` (eje ortogonal a `SetKind`, columnas ya creadas en E1) con las cuatro reglas (volumen, progresión, récords, 1RM) en UNA tabla, el drop como sub-serie por adyacencia sin FK, y el AMRAP con reps «pendiente».

**Carril:** pesado (modelo + SQL). Gate /biomecanico.

## Reglas y lógica
- `SetMode.counts(for rule: SetRule)`, `SetRule { volume, progression, records, oneRepMax }`: standard sí/sí/sí/sí · amrap sí/sí/sí/sí · drop sí/no/no/no. `SetEntry.counts(for:) = kind == .work && done && mode.counts(for:)`. Calentamiento sigue siendo `kind`.
- **Ningún** filtro `kind == .work` existente se edita (censo ~60 sitios): AMRAP y drop SON `.work`. Solo los 4 puntos de regla leen `mode`.
- Progresión: `StrengthStore.workSetHistory` (`func workSetHistory`, ~:720) excluye `mode = 'drop'` y proyecta `mode`; `ProgressionMath.metGoal` no cambia (AMRAP cumple si `reps >= targetReps`); `RoutineSet.normalizedRepsRangeTop` → nil para AMRAP.
- Récords: `updatePersonalRecords` (~:918), `recomputePR` (~:935), `AppModel+Strength.buildStrengthSummary`, `RoutineSheetLiveLogic.checkForPR` (anclar por símbolo, no por línea) vía `counts(for: .records)` (drop fuera). 1RM: `workSetHistory` ya excluye drop; tope 12 reps intacto.
- «La última vez» (`func lastWorkSets`, ~:689): excluye drop.
- **Drop** = `SetEntry` propio, `mode = .drop`, `position` siguiente a su madre, sin FK. Invariante de store al guardar: un drop sigue a la no-drop anterior del mismo ejercicio; si queda huérfano (posición 0) **conserva** `mode = drop` (cuenta solo volumen), nunca se promueve, nada se borra. Reordenar mueve los drops con su madre.
- **AMRAP pendiente**: `WorkingSet.reps: Int?` y `SetSnapshot.reps: Int?` (nil = pendiente); ✓ bloqueado si nil; nunca se guarda 0.
- Plan: `RoutineSet.mode = .amrap`, `reps` = objetivo, `repsRangeTop = nil`; `repsRangeLabel` → «\(reps)+». `workSetsAreEqual`, `equalizeAll`, `mirrorAcrossRoundsIfSuperset`, `roundsAreEven` y `recetaCount` incluyen `mode`.
- CSV: `set_mode` escribe 'drop'/'amrap' (standard vacío); el lector propio (E8) lo lee.
- Semilla de sesión (`static func make` en `StrengthSessionModel`, ~:1303) copia `mode`; «Agregar drop» inserta en `si+1` con `weightKg = PlateMath.snap(0.8 × madre)`, reps de la madre, `rest = nil`; completar una serie cuyo sucesor es drop NO abre descanso (`restTakenS = nil`, misma convención intra-superserie); máximo 3 escalones. `PlateMath.snap(targetKg:implement:barKg:inventory:fixedStepKg:)` = un solo «redondea a lo construible» (barra → `perSide().achievedKg`; mancuerna/máquina → múltiplo de `minimumIncrement`).
- Hevy `failure` → RPE 10 (0 en reserva); no es tipo.

## Alcance técnico
`Packages/StrandTraining/.../Training.swift` (+SetMode.counts, RoutineSet/SetEntry/SetSnapshot ya con `mode` de E1), nuevo `SetVariants.swift` (fracción 0.8), `Packages/StrandAnalytics/.../PlateMath.swift` (+snap; `ProgressionState.swift` NO se edita: `metGoal` ya basta y E4 es su dueña en esta wave), `Packages/CenitStore/.../StrengthStore.swift` (SQL de los 4 puntos + invariante de adyacencia), `Cenit/Screens/StrengthSessionModel.swift` (WorkingSet.reps Int?, cascada del drop, sin descanso), `Cenit/Screens/RoutineSetEditing.swift`, `Hoja/RoutineSheetLogic.swift:296-329`, `Hoja/RoutineSheetKeypad.swift:41-68`.

## Fuera de alcance
La UI (menú, «máx», chips, recibo): E7.

## Criterios de aceptación
- [ ] `SetModeRulesTests`: la tabla 3×4 completa; warmup false en las 4; drop false en progresión/récords/1RM.
- [ ] `SetModeProgressionTests` (archivo de test nuevo, para no chocar con E4): AMRAP 11 vs objetivo 8 = hit; AMRAP 6 = miss; `metGoal` sin cambio de fórmula.
- [ ] `StrengthStoreTests`: `testWorkSetHistoryExcludesDrop`, `testLastWorkSetsSkipDrop`, `testPRsIgnoreDropHeavierThanRecord`, `testAdjacencyInvariantKeepsOrphanAsDrop`, `testReorderMovesDropsWithMother`.
- [ ] `StrengthSessionSnapshotTests`: AMRAP con reps nil ida y vuelta; JSON pre-v42 decodifica.
- [ ] `RoutineSetEditingTests`: AMRAP en última serie → receta abierta y `recetaCount` ≠ 1 cuando solo difiere `mode`; `equalizeAll` y `mirrorAcrossRoundsIfSuperset` propagan `mode`.
- [ ] `PlateMathSnapTests`: 0.8×80 y 0.9×100 caen en pesos construibles (barra con inventario default; mancuerna múltiplo de incremento).
- [ ] `StrengthCSVTests`: fila drop escribe `drop`; standard vacío.
- [ ] Censo en el PR: los cuatro call sites de regla (volumen, progresión, récords, 1RM) pasan por `SetMode.counts` / `SetEntry.counts(for:)`; ningún filtro `kind == .work` existente se edita (lista de sitios documentada en la descripción del PR).

## Definition of Done
- [ ] `swift test` verde en StrandTraining, StrandAnalytics, CenitStore; `Tools/verify.sh` verde; /biomecanico PASS; /qa PASS.
