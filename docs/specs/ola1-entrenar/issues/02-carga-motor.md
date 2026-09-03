## Contexto
Hoy la carga diaria (escala 0–21) sale solo de la FC: `AppModel+Strength.endStrengthSession` (`:191-198`) solo escribe `strain` desde FC si `hrSamples.count >= 2`; sin FC la sesión queda sin strain. `AppleLoadEstimator.classify` (`:86-97`) marca `.rest` cuando no hay workout conocido y la actividad es baja, y una sesión Cénit sin Watch no aporta ningún workout con FC a ese día: el día queda como descanso. Ciencia (gate CSO): la FC no discrimina la intensidad en fuerza (Falk Neto 2020); el esfuerzo percibido sí (Day 2004, Sweet 2004, Haddad 2017). Fuente: `arq-A.md §①` con enmiendas E7/E8/E22 (v2–v4); **E17 retirada por D-Q13** (se pregunta siempre), `gate-estadistico-1.md` (H1–H10), `cso-session-rpe-reloj.md`, decisiones D-Q12/D-Q13.

## Objetivo
Un motor puro que convierta minutos × esfuerzo en la misma escala 0–21, y un overlay en lectura que meta esa carga (medida o estimada) en `repo.days` para ACWR/monotonía y en `strainByDay` para el acta, sin persistir en `dailyMetric` y sin añadir votante al veredicto.

**Carril:** pesado (analítica). Gates: /estadistico y /cso antes del merge.

## Reglas y lógica (constantes nombradas, cabecera con citas)
- `SessionRPELoad` (StrandAnalytics): `cr10(rpe) = 1.5·rpe − 5` (6→4, 8→7, 10→10); `au = minutes × cr10`; `trimp = k × au`; `strain = StrainScorer.trimpToStrain(trimp)`. `k` default **0.29** (calibration default; 50 min × RPE 8 → strain ≈ 10.9, banda de test 10–12). `minDurationS = 300`, `maxDurationS = 3·3600` (tope para estimar), rango RPE 6–10 (fuera → nil). Cita: «carga por esfuerzo: minutos × RPE de sesión (escala RIR mapeada a CR-10), calibrada contra TRIMP de FC; inspirado en session-RPE (Foster 2001), no literal».
- `StrainScorer.strainToTrimp(_:)` público = inversa exacta; `ReadinessEngine.strainToLoad` delega (cero cambio numérico; `ReadinessEngineTests` sigue verde sin editar).
- **Pregunta**: se hace SIEMPRE al cerrar fuerza, también con reloj (D-Q13 manda sobre E17/N8). **Fuente por sesión de fuerza**: si `sessionRpe != nil` → `strain = SessionRPELoad`, `strainSource = 'rpe'`; si no y hay FC con cobertura ≥ 0.8 → `strain = StrainScorer.strain(hr)`, `strainSource = 'hr'`; si no → `strain = nil`. La FC, cuando existe, sigue alimentando `avgHr` y `SessionRecoveryCost` (costo cardiovascular) aunque la carga sea por esfuerzo. Nunca se suman. Cobertura = (suma de los intervalos entre muestras consecutivas de FC con Δt < 300 s) / `elapsedSeconds`, es decir, el tiempo con FC plausible, no la fracción de agujeros. Medido ⇔ `StrainScorer.hasEnoughData` ∧ `coverage ≥ minHRCoverage (0.8)`. Anclas: 50 min con 12 min de FC → `.rpe`; con 41 min → `.hr`.
- **Prefill** (StrandTraining `SessionRPE.prefill(sets:)`): media del RPE de series `.work` hechas (drops excluidos, warmups excluidos), redondeada a 0.5, clamp 6–10, nil si ninguna trae RPE. Es «sugerido»: la capa app decide `sessionRpeSource` ('prefill' si se aceptó sin tocar, 'answered' si se tocó).
- **Calibración de k**: pares (au, trimpHR) de sesiones con `strainSource` cualquiera pero FC con cobertura ≥ 0.8 y `sessionRpe != nil`; estimador = mediana de razones trimp/au; `minCalibrationPairs = 5`; clamp [0.05, 1.0]; refit solo al duplicarse pares (5, 10, 20, 40) y aceptar si |Δ| > 15 %; al aceptar, recomputar en un solo write todas las sesiones `.rpe` (se persiste `trimpPerAU` por sesión).
- **Overlay por día** (`SourceFusion.overlayStrengthLoad(days:loads:workouts:today:)`): solo días cerrados (`day < today`); por día, Σ en espacio TRIMP de las sesiones Cénit; contra la carga Apple del día: **suma** si el intervalo de la sesión no traslapa ningún HKWorkout usado por Apple, **máximo** si traslapa; día con sesión sin strain y base 0 → `nil` (hold, nunca 0); día sin fila base → fila sintética solo-strain; sintetizar filas **solo desde la primera fila base con strain no-nil** o, sin base, en `[hoy−56, hoy)`. Se aplica en `Repository.assembleDashboard` después de `daysNeedingStrainEstimate` y antes de publicar `days`/`displayDays`. `DashboardData` gana `strengthEstimatedDays: Set<String>`.
- `strainByDay[today]` (entrada de `Preparedness`) gana la sesión de fuerza del día (presencia): el eje `load` marca `inRange` como con un entreno de Apple. **No se añade votante**; `Preparedness` no cambia.
- Sesión que cruza medianoche → día de inicio.

## Alcance técnico
- Nuevos: `Packages/StrandAnalytics/.../SessionRPELoad.swift`, `Packages/StrandTraining/.../SessionRPE.swift`. Tocados: `StrainScorer.swift` (+`strainToTrimp`), `ReadinessEngine.swift:637` (delegar), `SourceFusion.swift` (+overlay), `CenitStore/DashboardSnapshot.swift` (+`strengthLoads`, +intervalos HKWorkout del rango), `StrengthStore.swift` (+`strengthCalibrationPairs(limit:)`, +`recomputeEstimatedStrain(k:)`), `Cenit/Data/Repository.swift` (`assembleDashboard`), `Cenit/App/AppModel+Strength.swift` en `endStrengthSession` (`:191-198`) y el save path (`attemptStrengthSave`): decidir fuente al guardar.
- Invariante: StrandAnalytics no importa StrandTraining (la app proyecta primitivos).

## Fuera de alcance
La pregunta en el recibo y las etiquetas (E3). Que la carga vote (backlog E13). Tile «hoy parcial».

## Criterios de aceptación (tests con nombre)
- [ ] `HRCoverageTests`: `testCoverageIsPlausibleIntervalTime` (50 min con 12 min de FC → 0.24 → `.rpe`; 41 min → 0.82 → `.hr`).
- [ ] `SessionRPELoadTests`: `testAffineMapAnchors` (6→4, 8→7, 10→10); `testFiftyMinRPE8LandsInBand` (10 ≤ strain ≤ 12 con k default); `testRoundTripStrainToTrimpRelative` (tolerancia relativa 0.3 %); `testShortSessionYieldsNil`; `testDurationCapAtThreeHours`; `testRPEOutOfRangeYieldsNil`; `testFitUsesMedianOfRatiosAndIgnoresOneExtremePair`; `testFitNeedsFivePairs`; `testRefitOnlyWhenPairsDoubleAndDeltaOver15pct`.
- [ ] `SessionRPETests`: `testPrefillMeanOfDoneWorkSetsRoundedHalf`; `testPrefillIgnoresWarmupDropAndUndone`; `testPrefillNilWithoutRPE`.
- [ ] `SourceFusionOverlayTests`: `testDisjointWorkoutsAddInTrimp`; `testOverlappingWorkoutTakesMax`; `testSessionWithoutStrainTurnsRestIntoMissing`; `testTodayIsNeverOverlaid`; `testOverlayStartsAtFirstBaseRow` (5 años importados + 28 días Apple → ACWR ±0.05 vs sin import); `testEstimatedDaysCountAsActive` (14 días con 4 estimados → `evaluate().acwr != nil`; con strain nil → nil; DEBE fallar con el código viejo); `testSessionCrossingMidnightKeysToStartDay`.
- [ ] `ReadinessEngineTests` existentes verdes sin editar expectativas.
- [ ] `StrengthStoreTests`: `testSessionRoundTripsProvenanceColumns`; `testCalibrationPairsRequireCoverageAndRpe`; `testRecomputeEstimatedStrainRewritesOnlyRpeSessions`.
- [ ] Capa app: una sesión con FC de cobertura 0.9 y sin respuesta guarda `strainSource == 'hr'` con el mismo número que antes de este cambio; con respuesta 8 y 52 min guarda `'rpe'` y strain en [10, 12]; sin FC ni respuesta guarda `strain IS NULL`.
- [ ] `grep -rn "import StrandTraining" Packages/StrandAnalytics/Sources` = 0.

## Definition of Done
- [ ] `swift test` verde en StrandAnalytics, StrandTraining, CenitStore; `Tools/verify.sh` verde.
- [ ] Reporte de /estadistico y /cso PASS adjunto al PR (k, mapeo, cobertura, overlay).
- [ ] `docs/ANALYTICS.md` (o el doc de motores vigente) documenta el método con citas.
