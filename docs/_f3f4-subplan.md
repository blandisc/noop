# Sub-plan técnico — F3+F4 (épico «La banda nunca existió»)

> Arquitecto. Rama `claude/demolicion-banda-nunca-existio`. Fuente maestra: `docs/_demolicion-banda-plan.md`.
> F3 y F4 van **como UNA sola fase compile-válida** (un commit verde). Este doc es el contrato que `/implement` ejecuta.
> Baseline verificado: `StrandAnalytics` compila y `swift test --filter DataSourceModeTests|CircadianEngineTests|StepsEstimateEngineTests` → **42 tests, 0 fallas** (2026-07-21).

## Resumen

F3 colapsa la ramificación por fuente (`usesWhoop`/`usesAppleHealth`, pineada a Apple) y F4 borra el motor
orquestador muerto (`IntelligenceEngine`) más los dos motores band-only (`CircadianEngine`,
`StepsEstimateEngine`) y los campos de calibración de pasos-estimados de `Profile`. Van juntas porque el
cuerpo de `IntelligenceEngine.analyzeRecent` **type-checkea** `CircadianEngine`/`StepsEstimateEngine` aunque
el `guard mode.usesWhoop` (línea 209) lo haga inalcanzable: no se pueden borrar los motores hasta que muera
el orquestador, y el orquestador es el único no-op que `usesWhoop` sigue protegiendo.

**El hallazgo central que resuelve el encargo:** de los «10 llamadores» que el brief atribuye a
`IntelligenceEngine`, **7 son solo comentarios o dependencias de datos, no llamadas a símbolos**
(WorkoutDetailScreen, RecoveryDetailScreen, CalendarDayMap, Repository, HealthKitBridge, Profile mencionan
el nombre en `//`; WorkoutSource no lo menciona). Los **llamadores reales de código** son cuatro, todos en
`AppModel*`, y de todo `IntelligenceEngine` **sobrevive UN solo símbolo vivo: `strapOnlyHistory`** (usado por
`AppModel+Illness.swift:85`). Todo lo demás muere.

## Supuestos

- F1 (borrado de `WhoopProtocol`) y F2 (pantallas reloj/viaje) están DONE y verdes. Verificado:
  `RelojCorporalSheet.swift`/`PlanViajeSheet.swift` ya no existen; `estimatePhase`/`suggestedBedtime` solo
  se referencian dentro de `IntelligenceEngine.swift`.
- Greenfield Apple-only: `SourceModeStore.mode` está pineado a `.appleHealthOnly` y rechaza cualquier cambio
  (`SourceModeStore.swift:15-17`). Por tanto `usesWhoop == false` y `usesAppleHealth == true` son **constantes**.
- El colapso del read-model `SourceLens`/`SourceFusion`/`keep:.band` y la semántica SDNN↔RMSSD son **F6** y
  **no se tocan aquí** (ver «Frontera con F6»).
- El esquema greenfield v1, el naming `strap→apple` y el borrado de tablas de streams crudos son **F7**.

---

## 1. IntelligenceEngine: cada símbolo → MUERE / VIVE

`IntelligenceEngine.swift` (879 LOC). Clasificación de todos sus miembros accesibles:

| Símbolo (IntelligenceEngine.swift) | MUERE / VIVE | Quién lo usa (real) |
|---|---|---|
| `class IntelligenceEngine` + `init` | **MUERE** | `AppModel.swift:46` (prop `intelligence`), `:161` (init) |
| `let estimatesSteps` (:34) | **MUERE** | Solo `AppModel:161` pasa `false`; su test D3 (`testEstimatesStepsIsExactlyTheWhoop4Bit`) vivía en WhoopProtocol tests → **ya borrado en F1** |
| `skinTempOffsetC` (computed, :46) | **MUERE** | Interno del cuerpo muerto |
| `static skinTempOffsetC(estimatesSteps:)` (:50) | **MUERE** | Solo `runAnalysis` (muerto) |
| `static motionWindowDays(estimatesSteps:)` (:54) | **MUERE** | Solo `runAnalysis` (muerto) |
| `@Published results / computing / note` (:56-58) | **MUERE** | **Ningún consumidor externo** (grep de `.intelligence.results`/`intelligence.computing` = 0) |
| `lastPassAnalyzedDays` (DEBUG, :75) | **MUERE** | Solo instrumentación interna |
| `struct Computed` (:78) | **MUERE** | Solo interno |
| `analyzeRecent(maxDays:force:)` (:186) | **MUERE** (no-op: `guard mode.usesWhoop else { return [] }` :209) | `AppModel+Analysis:60,66,139`, `AppModel+Maintenance:37` — todas descartan o reciben `[]` |
| `struct NightResult / AnalysisCache / AnalysisInputs / AnalysisOutput` | **MUERE** | Solo internos al pase |
| `static computedDailiesChanged(_:vsStored:)` (:174) | **MUERE** | Solo `runAnalysis:618` + `IntelligenceRefreshGateTests` (se borra) |
| `static runAnalysis` (:298, private) | **MUERE** | El pase muerto |
| `static recomputeRecovery` (:798, private) | **MUERE** | El pase muerto |
| `static recomputeSkinTempDev` (:818, private) | **MUERE** | El pase muerto |
| `static let applePriorMaxNights` (:851) | **MUERE** | `runAnalysis` + `IntelligenceBaselinePriorTests` (se borra) |
| `static applePriorDays(_:maxNights:)` (:856) | **MUERE** | `runAnalysis` + `IntelligenceBaselinePriorTests` (se borra) |
| `static foldApplePrior(into:apple:priorDays:)` (:865) | **MUERE** | `runAnalysis` + `IntelligenceBaselinePriorTests` (se borra) |
| `private extension DailyMetric.with(recovery:skinTempDevC:)` (:873) | **MUERE** | Solo `runAnalysis` |
| **`static strapOnlyHistory(_:appleHealthDays:)` (:840)** | **VIVE** | **`AppModel+Illness.swift:85`** (prod) + `IllnessWatchSourceTests`, `IntelligenceBaselinePriorTests` (tests) |

**Conclusión: 1 símbolo vivo (`strapOnlyHistory`), todo lo demás muere con la clase.**

---

## 2. Lo VIVO: dónde re-ubicar `strapOnlyHistory`

`strapOnlyHistory` es `nonisolated static`, puro (`[DailyMetric] × Set<String> -> [DailyMetric]`), sin estado
de actor ni store. Su comentario propio (`IntelligenceEngine.swift:836`) lo declara **hermano de
`SourceLens`** (StrandAnalytics, FER-623/631): la variante «drop de fila completa» del enmascarado por
columna de `SourceLens.maskForBaseline`.

**Recomendación: mover `strapOnlyHistory` VERBATIM a `Packages/StrandAnalytics/Sources/StrandAnalytics/SourceLens.swift`**,
como `public static` dentro del enum `SourceLens`. Verificado que es viable: `SourceLens.swift` ya
`import StrandModels` y opera sobre `[DailyMetric]`; `DailyMetric` vive en `StrandModels/Models.swift:26`.

```swift
// Añadir dentro de `public enum SourceLens` (SourceLens.swift):
/// Whole-row sibling of `maskForBaseline` (FER-519): drops Apple-only nights before a band-anchored fold.
/// Pure; `appleHealthDays == []` es la identidad. (Reubicado desde IntelligenceEngine en F4.)
public static func strapOnlyHistory(_ hist: [DailyMetric], appleHealthDays: Set<String>) -> [DailyMetric] {
    appleHealthDays.isEmpty ? hist : hist.filter { !appleHealthDays.contains($0.day) }
}
```

**Por qué StrandAnalytics y no una extensión de AppModel:** (a) es puro y ya vive con su hermano `SourceLens`
en ese paquete; (b) consolida TODA la maquinaria FER-519 del read-model en un solo lugar, que es
justo lo que **F6** va a colapsar. Ponerlo en el app-shell lo dejaría fuera del radar de F6.

**Frontera con F6 (CRÍTICA):** el brief y el plan maestro dicen «`strapOnlyHistory`→identidad» en F4. **Eso es
un error de granularidad y se DIFIERE a F6.** Razón: en `AppModel+Illness` (`:85-91`) `strapDays` solo se
consume en la rama `signalSource == .band` (`: strapDays`, línea 91); en Apple-only `signalSource` es
siempre `.apple`, así que esa rama ya está muerta y el consumo real es
`SourceLens.maskForBaseline(days, keep:.apple, ...)`. Colapsar `signalSource`/`keep:` y quitar la rama
`.band` es **read-model = F6**. Volver `strapOnlyHistory` identidad AHORA (antes del gate `/cso`+`/estadistico`)
cambiaría la historia que alimenta el z-score de enfermedad **sin** el gate de ciencia que el plan exige
(riesgo #1 del plan maestro: reintroducir FER-519/629). El movimiento correcto: **F4 reubica verbatim →
F6 borra la función junto con la rama `.band` que la usa.**

---

## 3. Secuencia de edición ORDENADA (una fase, verde al final)

> La fase commitea UNA vez, verde. El orden interno evita romper el type-check a mitad de trabajo (no se
> pueden borrar `CircadianEngine`/`StepsEstimateEngine` mientras `IntelligenceEngine` los referencie).

**A. Preparar el hogar del único símbolo vivo (StrandAnalytics):**
1. `Packages/StrandAnalytics/.../SourceLens.swift`: añadir `SourceLens.strapOnlyHistory` (bloque de §2). `swift build` StrandAnalytics.

**B. Re-apuntar los llamadores de `strapOnlyHistory`:**
2. `Cenit/App/AppModel+Illness.swift:85`: `IntelligenceEngine.strapOnlyHistory` → `SourceLens.strapOnlyHistory` (ya importa StrandAnalytics).
3. Tests: `CenitUnitTests/IllnessWatchSourceTests.swift:53,72,99` y `CenitUnitTests/IntelligenceBaselinePriorTests.swift:114,119,135,173` → `SourceLens.strapOnlyHistory`.

**C. Borrar el orquestador muerto:**
4. Borrar `Cenit/Data/IntelligenceEngine.swift` completo (879 LOC).
5. `Cenit/App/AppModel.swift`: borrar la prop `let intelligence: IntelligenceEngine` (:46) y su init (:160-162, incluido el comentario «Ola 2» y `estimatesSteps: false`).
6. `Cenit/App/AppModel+Analysis.swift`:
   - `startAnalysis()`: tras el `guard self.sources.mode.usesWhoop else { return }` (:53) todo el cuerpo restante (:54-69: los dos `intelligence.analyzeRecent()`, el `Task.sleep` de 6 s, el `while` de 15 min) es MUERTO. Colapsar: `startAnalysis` termina tras la secuencia de launch-refresh (:42-47) → `return`. Quitar el `guard usesWhoop` y todo lo que le sigue.
   - `resumeForegroundAnalysis()` (:95): el `guard sources.mode.usesWhoop else { <force refresh>; return }` siempre toma el `else`; el cuerpo del `else` (:97-101) PASA A SER el cuerpo del método. Borrar la cola `.band` (:103-104, `startAnalysis()`).
   - `applyBaselineEpochAndRecompute()` (:135): borrar `await intelligence.analyzeRecent(force: true)` (:139). Queda `repo.baselineEpoch = ...; Task { await repo.refresh() }`.
7. `Cenit/App/AppModel+Maintenance.swift`, `migrateDayKeysToLocalIfNeeded()`: borrar `let writtenComputed = await intelligence.analyzeRecent(...)` (:37) y el paso-1 `pruneFutureLocalDays(... deviceId: deviceId + "-noop", written: writtenComputed)` (:38, ya no hay quién escriba la fuente `-noop`). CONSERVAR intacto el paso-2 Apple Health (:43-46) y el `setCursor` (:50).

**D. Colapsar F3 (`usesWhoop`/`usesAppleHealth`), la rama false/true gana:**
8. `Packages/StrandAnalytics/.../DataSourceMode.swift`: borrar la propiedad `usesWhoop` (:16). Colapsar `DataSourcePolicy.filter` (:26-34) → `(imported: [], computed: [], apple: apple)` (o borrar `DataSourcePolicy` e inline en su único caller). **Decisión de alcance:** conservar el enum `DataSourceMode` (3 casos) y `usesAppleHealth` como constantes por ahora — el enum sigue leído por `AppModel+Illness:87` (`== .appleHealthOnly`, ruteo SourceLens = F6) y el naming/greenfield es F7. Colapsar `usesAppleHealth` a `true` en sus call-sites es opcional pero simétrico; recomiendo hacerlo en el mismo pase para no dejar una policy a medias (quitar la propiedad y colapsar los 9 sitios de Repository).
9. `Cenit/Data/Repository.swift` — colapsar cada sitio (la rama pineada gana):
   - `:25` `var dataSourceMode = .combined` → `.appleHealthOnly`.
   - `:347-348` `includeApple: true, includeWhoopSeries: false` (dejar el campo `includeWhoopSeries` en `DashboardSnapshot` para F7; solo pasar `false`).
   - `:368` `DataSourcePolicy.filter(...)` → `imported/computed = []`, `apple = appleRaw`.
   - `:372-373` `impSleep/compSleep = []`.
   - `:387,:440` `if usesAppleHealth { X }` → `X`.
   - `:637,:674` `guard usesWhoop else { return [] }` → `return []` directo (métodos band muertos; conservan firma, devuelven vacío).
   - `:730-731` `imported/computed = []`; `:732` `apple = <read apple-health>`.
   - `:786` `guard usesWhoop else { return nil }` → `return nil`.
   - `:1206-1207` `useWhoop = false`, `useApple = true` (simplificar el respectingMode).
   - `:1351,:1365` `usesAppleHealth` → constante `true`.
10. `Cenit/Screens/TodayView.swift`:
    - `:401-419` `whyEmptyExplanation`: `usesWhoop` es `false` → conservar SOLO las cadenas de la rama Apple ya autorizadas (`:408,:414,:417`); borrar las variantes band. **No es copy nuevo** (las cadenas Apple ya existen), es poda de la rama inalcanzable.
    - `:548` `dayMap: usesWhoop ? stressDayMap : nil` → `nil`.
    - `:1055` `if usesWhoop { PullIndicator(...) }` → borrar el bloque band (dial 24h / BPM en vivo son de la banda).
11. `Cenit/Screens/CuerpoView.swift:465` `dayMap: usesWhoop ? stressDayMap : nil` → `nil`.
12. `Cenit/Screens/AjustesView.swift:267`: `if usesWhoop { <navRow CyclePhase> }` es MUERTO → borrar el bloque (la fila Cycle phase). `CyclePhaseView` queda sin punto de entrada; **NO borrar la pantalla aquí** (es consumidor F6/MED). Anotar el huérfano.
13. `Packages/CenitStore/.../DashboardSnapshot.swift`: **sin cambio** (el campo `includeWhoopSeries` y su `if req.includeWhoopSeries` :95 se retiran en F7 con las tablas de streams).

**E. Borrar los motores band-only (ya sin consumidor tras C):**
14. Borrar `Packages/StrandAnalytics/.../CircadianEngine.swift` y `StepsEstimateEngine.swift`. Verificado: 0 referencias intra-paquete (solo un comentario en `IllnessSignalEngine.swift:81`) y 0 fuera del ya-borrado IntelligenceEngine.
15. `Cenit/Data/Profile.swift`: borrar los campos de calibración de pasos-ESTIMADOS (`stepsManualCoefficient` :21, `stepsCalibrationCoefficient` :23, `stepsCalibrationSampleDays` :25, `stepsCalibrationConfidence` :27, `stepsCalibrationManual` :29) + sus keys (`K.stepsManualCoeff`/`stepsCoeff`/`stepsSampleDays`/`stepsConfidence`/`stepsManualFlag` :50-54) + su carga en `init` (:66-70).
16. `Cenit/Screens/AjustesView.swift`: borrar los helpers YA HUÉRFANOS `stepsCalDisplay` (:222-227) y — si se decide incluir `stepTicksPerStep`, ver abajo — `stepTicksDisplay` (:228-233). **Hallazgo:** ambos helpers están definidos pero **NO se renderizan en ninguna parte** (grep de uso = 0); sus navRows se retiraron en una ola previa. Así que el cascade de UI es trivial: borrar los `private var` muertos.

**F. Borrar tests muertos / re-apuntar los vivos** (ver §4).

**G. Verificar:** `swift build && swift test` de StrandAnalytics (paso A/D/E). El compile iOS completo
(pasos que tocan `Cenit/**`) va **uno a la vez, máquina idle** (`while pgrep -x xcodebuild XCBBuildService; do sleep 30; done`), nunca en paralelo — regla anti-OOM de CLAUDE.md.

### Nota sobre `stepTicksPerStep` (divisor nativo 5/MG, FER-665)
Es un campo band-only distinto del estimador 4.0, pero **es de paquete**: vive en `UserProfile`
(`StrandAnalytics/WorkoutDetector.swift:31`) y lo consume `AnalyticsEngine.swift:354` (escalado de pasos).
Borrarlo amplía F4 a cirugía de API en StrandAnalytics/StrandModels. **Recomendación: dejar
`stepTicksPerStep` (Profile + UserProfile + AnalyticsEngine) para F7** (naming/greenfield); anotarlo como
huérfano band-only conocido. El brief acota F4 a «campos de calibración de steps [estimados] en Profile».

### Nota sobre `steps_est` en TodayView
`TodayView.swift:2469` lee `repo.computedSeries(key:"steps_est")`; sin `StepsEstimateEngine` nadie lo
escribe → `stepsEst` queda vacío y el tile cae a los pasos reales de Apple (degradación limpia). Es
inofensivo. **Recomendación: dejarlo en F4** (quitarlo toca `computeDerived`, archivo CRÍT de F6) y barrerlo
en F7. Opcional si `/implement` lo prefiere limpio.

---

## 4. Tests: actualizar / borrar

| Test | Acción | Motivo |
|---|---|---|
| `Packages/StrandAnalytics/.../DataSourceModeTests.swift` | **BORRAR** | Prueba `usesWhoop`/`usesAppleHealth` (propiedades eliminadas). |
| `Packages/StrandAnalytics/.../CircadianEngineTests.swift` | **BORRAR** | El motor se borra. |
| `Packages/StrandAnalytics/.../StepsEstimateEngineTests.swift` | **BORRAR** | El motor se borra. |
| `CenitUnitTests/IntelligenceRefreshGateTests.swift` | **BORRAR** | Prueba `computedDailiesChanged` (muere con el engine). |
| `CenitUnitTests/RepositoryTwoPassTests.swift` | **BORRAR** | Construye `IntelligenceEngine` y prueba el two-pass de `analyzeRecent` (muerto). |
| `CenitUnitTests/IntelligenceBaselinePriorTests.swift` | **PARTIR** | Borrar los casos de `applePriorDays`/`foldApplePrior`/`applePriorMaxNights` (muertos). **Conservar** los de `strapOnlyHistory` (:114,119,135,173) re-apuntados a `SourceLens.strapOnlyHistory`; o migrarlos a `SourceLensTests`. |
| `CenitUnitTests/IllnessWatchSourceTests.swift` | **RE-APUNTAR** | `IntelligenceEngine.strapOnlyHistory` → `SourceLens.strapOnlyHistory` (:53,72,99). La semántica de `.band`/Apple-only sigue siendo F6; el test de identidad no cambia. |
| `Packages/StrandAnalytics/.../SourceLensTests.swift` | **SIN CAMBIO** (ya cubre el equivalente `strapOnlyHistory`, :204,226); opción de hogar para los casos migrados. |
| `CenitStore` `MigrationTests` (circadianPhase v25) | **SIN CAMBIO** | La tabla `circadianPhase` es append-only; queda DORMIDA (se drena/borra en F7, no aquí). |

`CDOAuditRegressionTests`: grep no encontró referencia a `usesWhoop`/`IntelligenceEngine`/los motores
borrados; `/implement` debe confirmar que no rompe (si toca `DataSourceMode` o los engines, ajustar; si no,
sin cambio).

---

## 5. Riesgos y frontera con F6

- **Riesgo top 1 — cruzar a F6 sin querer (SDNN↔RMSSD).** El llamador vivo más fácil de romper es
  `AppModel+Illness.applyIllnessEvaluation` (`:85-91`): mezcla `strapOnlyHistory` (F4) con
  `SourceLens.maskForBaseline(keep:.apple)` + `signalSource` (F6). **Regla dura para esta fase: solo reubicar
  `strapOnlyHistory` verbatim y re-apuntar el símbolo. NO tocar `signalSource`, `SourceLens.Source`,
  `keep:.apple/.band`, ni volver `strapOnlyHistory` identidad.** Eso es F6, con gate `/cso`+`/estadistico`+Grok.
  Mitiga el riesgo #1 del plan maestro (verdict corrupto en silencio por leer SDNN donde iba RMSSD).
- **Riesgo 2 — orden de borrado.** Borrar `CircadianEngine`/`StepsEstimateEngine` antes que `IntelligenceEngine`
  rompe el type-check. Mitigación: seguir el orden A→C→E (motores al final).
- **Riesgo 3 — la fuente computada `-noop` deja de existir.** Tras borrar el engine nadie escribe
  `strap-noop` (daily/sleep/workouts/metricSeries). Consumidores que la leen (`Repository.computedSeries`,
  `latestCircadianPhase`, el tile `steps_est`) degradan a vacío — no crashean. Verificar en el compile iOS que
  ningún path espera filas `-noop` no-vacías. Las tablas siguen DORMIDAS hasta F7.
- **Riesgo 4 — copy.** Las podas en TodayView/AjustesView conservan cadenas **ya autorizadas** para Apple-only
  (no se inventa copy). Si `/implement` cree que falta una cadena, es señal de regresar a `/ux`, no de improvisar.
- **Riesgo abierto — no corrí el compile iOS** (regla anti-OOM: no `xcodebuild` en esta sesión). El type-check
  de la capa app (AppModel/Repository/TodayView/CuerpoView/AjustesView) queda como **riesgo abierto para
  `/implement`**, que debe correr `xcodebuild ... -jobs 4` con la máquina idle. Sí verifiqué que StrandAnalytics
  compila y sus tests pasan (baseline), y que los borrados de paquete (motores, `usesWhoop`) no tienen
  consumidores intra-paquete.

**Qué NO toca esta fase (frontera explícita con F6/F7):**
- F6: `SourceLens`/`SourceFusion`/`keep:.band`, la semántica SDNN↔RMSSD, la rama `.band` de AppModel+Illness,
  el borrado final de `strapOnlyHistory`, y los 7 consumidores del read-model.
- F7: esquema greenfield v1, naming `strap→apple`, `DashboardSnapshot.includeWhoopSeries`, el enum
  `DataSourceMode` completo, `stepTicksPerStep`, y el drenado de tablas dormidas (`circadianPhase`, streams crudos).

---

## 6. Criterios técnicos de aceptación (checklist de `/implement`)

- [ ] `Cenit/Data/IntelligenceEngine.swift` NO existe.
- [ ] `Packages/StrandAnalytics/.../CircadianEngine.swift` y `StepsEstimateEngine.swift` NO existen.
- [ ] `grep -rn "usesWhoop" --include=*.swift Cenit CenitApp Packages` → **0 resultados** (propiedad y todos los call-sites eliminados).
- [ ] `grep -rn "IntelligenceEngine" --include=*.swift Cenit CenitApp CenitUnitTests` → **0 resultados** (ni código ni comentarios residuales).
- [ ] `SourceLens.strapOnlyHistory` existe en StrandAnalytics y `AppModel+Illness.swift` lo llama; su comportamiento es byte-idéntico al original (test de identidad `appleHealthDays == []` pasa).
- [ ] `AppModel` ya no tiene la propiedad `intelligence` ni construye `IntelligenceEngine`.
- [ ] `Profile.swift` ya no tiene `stepsManualCoefficient` ni ningún `stepsCalibration*`; sus keys y su carga en `init` se fueron. `stepTicksPerStep` puede seguir (F7).
- [ ] Tests borrados: `DataSourceModeTests`, `CircadianEngineTests`, `StepsEstimateEngineTests`, `IntelligenceRefreshGateTests`, `RepositoryTwoPassTests`; casos `applePrior*` de `IntelligenceBaselinePriorTests`.
- [ ] `cd Packages/StrandAnalytics && swift build && swift test` → **verde** (sin los 3 tests borrados; `SourceLensTests` sigue verde).
- [ ] `xcodebuild -project Cenit.xcodeproj -scheme Cenit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -jobs 4 build` → **compila** (máquina idle, uno a la vez).
- [ ] `AppModel+Illness.applyIllnessEvaluation` NO cambió `signalSource`/`SourceLens.Source`/`keep:` (F6 intacto): `git diff` sobre esas líneas = solo el rename `IntelligenceEngine.→SourceLens.` en :85.
- [ ] Ningún cambio en `SourceLens.maskHrv`/`maskForBaseline`, `FusionResolver`, ni en el esquema DB.

---

## 7. Actualización de docs/ARCHITECTURE.md

Cambio de arquitectura real (muere un componente del mapa). Diff propuesto para que `/implement` lo aplique
en el mismo PR (ubicar la descripción de `IntelligenceEngine` / la pasada on-device y sustituir):

```
- **IntelligenceEngine** (Cenit/Data) — pasada on-device incremental que puntúa recovery/strain/sleep
-   desde los streams crudos de la banda (HRV-dominante). Corre off-main, gateada por `usesWhoop`.
+ (Retirado — épico «la banda nunca existió», F3+F4.) La pasada on-device band-scoring `IntelligenceEngine`
+   y los motores band-only `CircadianEngine`/`StepsEstimateEngine` se borraron: sin banda no hay streams
+   crudos que puntuar. La recuperación/autonómica ahora sale del path Apple (RMSSD nocturno FER-1008,
+   AutonomicTrend/ReadinessEngine, ThermalStability/NightAutonomicShape/NocturnalDC sobre datos Apple).
+   El único helper sobreviviente, `strapOnlyHistory` (filtro de baseline FER-519), se movió a
+   `StrandAnalytics/SourceLens` como hermano de `maskForBaseline`; su retiro final es F6.
```

Además, si existe una tabla «where logic belongs» o un diagrama que liste `DataSourceMode.usesWhoop` como
selector de fuente, anotar que la fuente es constante Apple (pin `SourceModeStore`). El colapso del enum
`DataSourceMode` completo se documenta en F7.
