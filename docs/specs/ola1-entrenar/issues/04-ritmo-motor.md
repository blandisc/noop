## Contexto
El RPE por serie (6–10, RIR) se guarda y no gobierna nada: `ProgressionMath.classify` solo mira reps. Fuente: `arq-A.md §②` + E9/E13/E16 y `gate-biomecanico-1.md` #2/#3/#4 (Helms 2016, Zourdos 2016, Steele 2017). Decisiones D-Q1, D-Q6.

## Objetivo
La regla de doble progresión gana un «ritmo»: Constante (2 sesiones), Rápido (1), Según reps en reserva (1 si sobraron ≥2; espera si llegaste al fallo; tope de 3). Sin caso nuevo en `ProgressionState`, veredicto encima (FER-85).

**Carril:** pesado (analítica). Gate /biomecanico.

## Reglas y lógica
- `PastSession` gana `workSetRPE: [Double?] = []` (paralelo a `workSetReps`). `ProgressionInput` gana `useRPE: Bool = false` (mapea a `progressionUseRPE`).
- Constantes: `rpeComfortableMax = 8.0` (≥2 en reserva), `rpeLimitMin = 9.5` (0 en reserva), `atLimitStreakCap = ProgressionMath.deloadStallThreshold` (3).
- `effort(_:) → { comfortable, standard, atLimit, unknown }`: `unknown` si falta RPE en alguna serie de trabajo o `count != workSetReps.count`; `atLimit` si alguna ≥ 9.5; `comfortable` si todas ≤ 8.0; si no `standard`.
- `classify` con `useRPE`: (a) newest met ∧ comfortable → subida ahora (mismos gates `incrementKg > 0` y `deferRaise`); (b) met ∧ atLimit → invisible al `metRun` (no suma ni rompe; sí ancla `currentKg`), salvo tope: tras 3 met-atLimit consecutivas, las tres cuentan como `standard` (con n=2 → `.readyToAdvance` o `.deferred`); (c) miss sigue siendo miss (deload como hoy); (d) standard/unknown → como hoy. Con `useRPE == false` → byte-idéntico a hoy.
- Caller: `ProgressionPlanner.pastSessions` mapea `WorkSetHistoryRow.rpe` (ya expuesto) a `workSetRPE`; `evaluate` pasa `useRPE`; expone `ProgressionMath.effort(lastVisible)` y el conteo de al-límite para el copy.
- Plantillas: las banderas `progressionUseRPE` por slot las escribe **E10** (única dueña de `StarterTemplates.swift`/`ProgramTemplate`); este issue solo consume `progressionUseRPE` ya persistido.

## Alcance técnico
`Packages/StrandAnalytics/.../ProgressionState.swift` (símbolos `ProgressionMath.PastSession` :52-59 y `classify` :105-153), `Cenit/Data/ProgressionPlanner.swift` (`pastSessions`, `evaluate`).

## Fuera de alcance
La pantalla de progresión y el copy del hub (E5).

## Criterios de aceptación
- [ ] `ProgressionStateTests`: `testUseRPEFalseIsByteIdenticalOnExistingSuite` (toda la suite actual con `useRPE=false`); `testComfortableMetRaisesInOneSession`; `testComfortableRaiseStillDeferredByVerdict`; `testAtLimitMetIsInvisibleToMetRun` ([met@10, met@8] con n=2 → `.inCycle(1, of: 2)`); `testThreeAtLimitInARowCountAsStandard` ([met@10×3], n=2, deferRaise=false → `.readyToAdvance`); `testAtLimitMissStillCountsTowardDeload`; `testMissingRPEBehavesLikeToday`; `testThresholdsAreNamedConstants`.
- [ ] `ProgressionPlannerTests` (app): `pastSessions` lleva RPE; `evaluate` con `progressionUseRPE` false no cambia resultado.

## Definition of Done
- [ ] `swift test` StrandAnalytics + StrandTraining verde; `Tools/verify.sh` verde; reporte /biomecanico PASS en el PR.
