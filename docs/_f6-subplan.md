# Sub-plan técnico — F6 (épico «La banda nunca existió») — LA FASE DE CIENCIA

> Arquitecto. Rama `claude/demolicion-banda-nunca-existio`. Fuente maestra: `docs/_demolicion-banda-plan.md`.
> F6 es UNA fase compile-válida (un commit verde). Este doc es el contrato que `/implement` ejecuta.
> **Diseñado contra el estado POST-F5** (los bloques `RecoveryImpact`/`RecoveryChange`/`ImpactRows`/`FiveRules`
> y sus secciones de UI ya NO existen; F6 no los menciona).
> Baseline verificado 2026-07-21 (esta sesión): `StrandAnalytics` compila; `SourceLensTests` (12) y
> `VitalitySourceInvarianceTests` (3) → **verde**. `Repository.swift:366-367` confirma `imported = []` y
> `computed = []` → **el invariante `appleHealthDays == Set(days.map(\.day))` se cumple por construcción**.

---

## Resumen

F6 colapsa el read-model multi-fuente a Apple-only **sin cambiar un solo número de lo que hoy se muestra**.
El hallazgo central: en greenfield Apple-only `appleHealthDays` == **todos** los días, así que cada llamada al
lente colapsa a una forma cerrada y determinista:

- `SourceLens.maskForBaseline(days, keep:.band, appleDays: todos)` → **nila TODAS las columnas cross-source en
  TODAS las filas** (avgHrv/restingHr/respRateBpm/skinTempDevC/stages), dejando strain/steps/duración intactos.
- `SourceLens.maskHrv(days, keep:.band, appleDays: todos)` → **nila TODOS los `avgHrv`**, resto intacto.
- `SourceLens.maskForBaseline(days, keep:.apple, appleDays: todos)` → **identidad** (`days` verbatim).
- `SourceLens.strapOnlyHistory(days, appleDays: todos)` → **`[]`** (lista vacía).

**El punto de ciencia que gobierna todo F6:** ese enmascarado **NO es andamiaje muerto — es ciencia
load-bearing.** En una fila Apple greenfield, `avgHrv` = **SDNN** de Apple, `restingHr` = RHR sedentario de
Apple (~+10-13 bpm sobre el nadir de banda), `skinTempDevC` = Δ de Apple contra su propia base. Los motores
band-domain (VitalityEngine con norma RMSSD-por-edad, InsightEngine con base HRV, ReadinessEngine señal HRV,
WhatMovesIt HRV) fueron construidos alrededor del **RMSSD de banda**. Si F6 les pasara `days` crudo,
ingerirían SDNN de Apple **como si fuera RMSSD** → **exactamente FER-519/629** (base meanHRV mezclada ≈43.8 ms
vs banda ≈49.6 ms; RMSSD≠SDNN, sin conversión publicada — Task Force 1996, Circulation 93(5):1043-1065;
Shaffer & Ginsberg 2017, Front Public Health 5:258). Por tanto el enmascarado **se conserva**; lo que muere es
la **selección de fuente** (`keep:`/`appleDays:`/`Source`/`strapOnlyHistory`), que en un mundo de una sola
fuente ya no decide nada.

El RMSSD nocturno REAL de Apple (`apple_rmssd_night`) tiene su propio camino, **`SourceFusion.autonomicTrend`**,
que **no pasa por `SourceLens` ni por `DailyMetric.avgHrv`** — lee la partición densa `apple_rmssd_night` del
`metricSeries`. Ese camino VIVE y F6 **no lo toca**: el héroe autonómico no cambia de número.

En una frase: **F6 sustituye cada lente `keep:.band` por un limpiador incondicional de columnas band-domain
(que nila lo mismo, byte por byte), colapsa cada `keep:.apple` a `days`, borra `strapOnlyHistory` + `Source` +
el threading de `appleHealthDays`, y prueba con un test de no-regresión que (a) el resultado es idéntico y
(b) que quitar el limpiado reintroduciría FER-519.**

---

## Supuestos (verificados contra el código, no adivinados)

- **F1-F4 y F5 aplicadas.** `IntelligenceEngine`/`CircadianEngine` no existen; los bloques Impact/Change/Rules
  de F5 tampoco. `SourceLens.strapOnlyHistory` YA vive en `SourceLens.swift:100` (reubicado en F4).
- **Greenfield sólido:** `Repository.swift:366-367` fija `imported = []`, `computed = []`, `apple = appleRaw`.
  → `days = mergeDaily(imported:[], computed:[], apple:).days` = exactamente las filas Apple, y
  `appleHealthDays = merged.appleDays` = exactamente esos day-keys. **No existe una fila non-Apple en `days`**
  (la estimación de strain FER-883 se superficializa por `repo.today`, **nunca se pliega a `days`** —
  `SourceFusion.swift:49`). Invariante: `appleHealthDays == Set(days.map(\.day))`.
- **`ReadinessEngine.evaluate` lee `avgHrv`, `restingHr`, `respRateBpm`, `skinTempDevC` Y `strain`**
  (`ReadinessEngine.swift:213-276`). Importa QUÉ consume cada llamador de su `Readiness` (señal-verdict vs
  ACWR/carga) — ver la tabla.
- **`crossSourceMasked()` nila** `deepMin/remMin/lightMin/restingHr/avgHrv/skinTempDevC/respRateBpm`; **NO
  nila** `strain/steps/totalSleepMin/efficiency/spo2Pct/...` (`SourceLens.swift:120-123`). Por eso todo lo
  ACWR/strain-derivado es inmune al enmascarado.
- Fuera de F6: el borrado del campo `DailyMetric.avgHrv`/esquema y el retiro de `repo.appleHealthDays` como
  concepto = **F7**. El rediseño del héroe = **FER-1030**. `SourceFusion` completo (merge/fusion/sleep) = F7.

---

## 1. Los 7 (9 call-sites) consumidores → lee-HOY / lee-tras-F6 / riesgo

Notación: `clearBandColumns(d)` ≡ `d.map { $0.crossSourceMasked() }` (el nuevo helper que reemplaza
`maskForBaseline(_, keep:.band, appleDays:)`); `clearBandHrv(d)` ≡ `d.map { $0.hrvMasked() }` (reemplaza
`maskHrv(_, keep:.band, appleDays:)`). Ambos son **incondicionales** (sin `keep`, sin `appleDays`).

| # | Consumidor (archivo:línea) | Qué LEE hoy del resultado | Lee TRAS F6 | Riesgo / por qué es identidad |
|---|---|---|---|---|
| 1 | `TodayView.computeDerived:354` `band = maskHrv(keep:.band)` | `avgHrv` nilado (SDNN Apple fuera); `restingHr`/`resp`/`skinTemp` Apple **intactos** → `ReadinessEngine` **veredicto** (señales HRV/RHR/resp/skinTemp) | `clearBandHrv(days)` | **CRÍT.** Identidad exacta: con appleDays=todos, `maskHrv` ya nila todo `avgHrv`. El RMSSD real del veredicto NO sale de aquí (aquí queda vacío) → sale de `AutonomicTrend`, intacto. El veredicto Apple-only ya corre sobre RHR/resp/skinTemp de Apple + HRV vacío. |
| 1b | `TodayView.computeDerived:364` `acwrMasked = maskForBaseline(keep:.band)` | solo `strain` (no se nila) → `acwr`/serie/`TrainingLoadModel` | `clearBandColumns(days)` | Identidad: `strain` nunca se nila. |
| 1c | `TodayView.bandDays` prop `:381` `maskHrv(keep:.band)` | igual que #1 (fallback en frío del veredicto) | `clearBandHrv(repo.days)` | Identidad. Debe coincidir con #1 (misma verdad). |
| 2 | `RecoveryDetailScreen.swift:672` `bandDays = maskForBaseline(keep:.band)` | solo `strain` → `ReadinessEngine.acwr/monotony/loadBand` (`LoadState`) | `clearBandColumns(days)` | **CRÍT (lo que F5 conservó).** Identidad: de `bandDays` solo se consume `strain`. **NO tocar** `:662-663` (`series`/`recovery`), `:681` `buildHeat`, `:686` `forecast`. |
| 3 | `CuerpoView.swift:1335` `bandMasked` | `strain` → `ReadinessEngine`/`acwrSeries`/`TrainingLoadModel` | `clearBandColumns(days)` | Identidad. |
| 3b | `CuerpoView.swift:1376` `recentBand` → `VitalityInputsBuilder`/`VitalityEngine` (Body Age) | `restingHr` **y** `avgHrv` nilados (Apple-only) → `nightlyRestingHR`=[], `nightlyRMSSD`=[] → **factores RHR y HRV AUSENTES**; Body Age corre con sleep/steps/regularidad | `clearBandColumns(recent)` | **CRÍT.** Identidad (Body Age byte-idéntico). ⚠️ **Tentación de ciencia:** alimentar `apple_rmssd_night` al factor HRV = mejora legítima PERO **cambia Body Age** → FUERA de F6 (issue nuevo). |
| 4 | `InsightsProvider.rank:57` `bandDays` → `InsightEngine` | `avgHrv`/`restingHr`/`resp` nilados → baselines HRV/RHR/resp y sus correlaciones **dormidos**; `strain`/ACWR/comportamiento/dieta **vivos** | `clearBandColumns(days)` | **ALTO.** Identidad. Pasar `days` crudo = **REINTRODUCE FER-519** (SDNN en la base HRV). |
| 5 | `WhatMovesIt.findings("hrv"):61` `maskHrv(keep:.band)` | `avgHrv` nilado → serie HRV vacía → **0 findings** (bloque oculto) | `clearBandHrv(days)` **o** retirar el `case "hrv"` (equivalente) | **ALTO.** Identidad. El `case "rhr"` lee `restingHr` Apple crudo (sin lente, `:65`) → **sin cambio**. |
| 6 | `CyclePhaseSheet:50` `maskForBaseline(keep:.band)` | `avgHrv`/`skinTemp` nilados → `CyclePhaseEngine` vacío → estado «necesita banda» | `clearBandColumns(repo.days)` | **MED.** Identidad. La vista **SIGUE accesible** desde `AjustesView.swift:131` (`CyclePhaseSheet()`), gate `cyclePhaseOn` — **no está huérfana**; band-only por diseño (`CyclePhaseView.swift:48`). |
| 7 | `AppModel+Illness.swift:85,90,128` `strapOnlyHistory` + `maskForBaseline(keep:.apple/signalSource)` | `signalSource`=`.apple` (constante); `vitalsDays`=`maskForBaseline(keep:.apple)`=**identidad** → lee `restingHr` Apple + `avgHrv`=**SDNN** within-source; `skinTempDays`=identidad; `strapDays`=**EMPTY** (solo la rama `.band` muerta lo usa) | `vitalsDays`=`days`; `skinTempDays`=`days`; **borrar** `strapDays`, `signalSource`, la rama `.band` | **CRÍT.** Identidad. ⚠️ El uso de **SDNN aquí es DELIBERADO** (z within-source contra la propia norma Apple — válido pese a SDNN≠RMSSD; Shaffer & Ginsberg 2017). **NO enrutar a RMSSD, NO mezclar historia.** |

**Adyacente, FUERA de F6 (no es del read-model, no usa `SourceLens`):** `TodayView.computeHrvCounts(days:appleDays:)`
(`:356`) cuenta `ownNights`/`recoveryCalibration` excluyendo `appleDays` — pertenece al **número de recuperación
retirado** (F5/FER-1030), no al lente. F6 **no lo toca**.

---

## 2. Qué MUERE vs qué VIVE del read-model

### `SourceLens.swift` (StrandAnalytics)
| Símbolo | Acción | Nota |
|---|---|---|
| `enum Source { case band, apple }` | **MUERE** | Con una sola fuente no hay qué seleccionar. |
| `keeps(_:keep:appleDays:)` (private) | **MUERE** | Clasificaba fila por fuente. |
| `mask(_:keep:appleDays:blank:)` (private, incl. fast-path identidad) | **MUERE** | Colapsa al `.map` incondicional en cada helper. |
| `maskHrv(_:keep:appleDays:)` | **COLAPSA** → `clearBandHrv(_ days) = days.map { $0.hrvMasked() }` | Sin params; nila `avgHrv` en toda fila. |
| `maskForBaseline(_:keep:appleDays:)` | **COLAPSA** → `clearBandColumns(_ days) = days.map { $0.crossSourceMasked() }` | Sin params; nila toda columna cross-source. |
| `strapOnlyHistory(_:appleHealthDays:)` | **MUERE** | Solo lo usaba la rama `.band` muerta de illness. |
| `crossSourceMasked()` / `hrvMasked()` (private ext `DailyMetric`) | **VIVEN** | Son los cuerpos de los dos helpers. |

Resultado: `SourceLens` deja de ser un árbitro multi-fuente y queda como **«limpiador de columnas
band-domain»** — la utilidad que impide que un motor band-domain ingiera SDNN/offsets de Apple. Sobrevive
consolidado (no se inlinea ni se borra el enum entero) porque **la ciencia FER-519 sigue viva**; solo la
selección de fuente murió. **Recomiendo renombrar** `maskForBaseline`→`clearBandColumns` y
`maskHrv`→`clearBandHrv`: dejar el nombre `keep`/`mask...` sería una mentira semántica (ya no «keep a source»,
sino «clear the band-domain columns»). Es borderline-F7 (naming) pero justificado porque **el significado
cambió**, no solo el nombre.

### `SourceFusion.swift` (StrandAnalytics) — **F6 NO TOCA NADA AQUÍ**
`autonomicTrend` (**el RMSSD real de Apple, el héroe**), `mergeDaily`, `strainEstimateEligibleDays`,
`appleStrainEstimates`, `fusionByDay`, `mergeSleep*`, `appleSleepsNotCoveredByStrap`, `fillingNils`: **VIVEN**.
El colapso de sus firmas multi-fuente (imported/computed vacíos) es **F7**.

### App-shell
- `repo.appleHealthDays` (`Repository.swift:68/130/543`): **VIVE** (la produce `mergeDaily`; `RecoveryDetailModel.isAppleHealth`
  la lee, `:698`). F6 solo **deja de pasarla** a los call-sites del lente. Su retiro (siempre == todos los días)
  es **F7**.
- `AppModel+Illness`: `signalSource`, `strapDays`, la rama `.band` y `repo.dataSourceMode == .appleHealthOnly`
  (`:87`) → **MUEREN** (constantes). `vitalsDays`/`skinTempDays` → `days`.

---

## 3. ¿Se puede colapsar SIN cambiar el número? (pregunta clave 3)

**Sí, por construcción — y aquí está el mapa de dónde PODRÍA cambiar (regresión) y cómo se evita:**

| Superficie mostrada | ¿Cambia el número? | Por qué / salvaguarda |
|---|---|---|
| **AutonomicTrend** (héroe «cómo vienes») | **NO** | No pasa por `SourceLens`; lee `apple_rmssd_night` vía `SourceFusion.autonomicTrend`. F6 no lo toca. |
| **Body Age / Vitality** | **NO** | `clearBandColumns` nila `restingHr`+`avgHrv` idéntico a `maskForBaseline(keep:.band, appleDays:todos)` → factores RHR+HRV ausentes igual que hoy. **Pin:** test de identidad downstream por `VitalityInputsBuilder`. |
| **Fitness Age** | **NO** | Lee `last7` de `displayDays` (`CuerpoView:1356`), **no** de `recentBand` — fuera del lente. |
| **Veredicto Hoy** (`ReadinessEngine`) | **NO** | `clearBandHrv` == `maskHrv(keep:.band, todos)`; RHR/resp/skinTemp Apple intactos en ambos. |
| **Carga/ACWR/Panorama** (Hoy, Cuerpo, RecoveryDetail) | **NO** | `strain` nunca se nila; ACWR idéntico. |
| **Patrones / Daily Brief** (`InsightsProvider`) | **NO** | Baselines HRV/RHR dormidos hoy y tras F6; strain/comportamiento/dieta idénticos. |
| **Illness watch** | **NO** | `vitalsDays`=`days` == `maskForBaseline(keep:.apple, todos)`; z within-source Apple SDNN idéntico. |
| **DÓNDE PODRÍA CAMBIAR (evitar)** | ⚠️ | (a) pasar `days` crudo a un motor band-domain → sube SDNN a HRV (FER-519); (b) enrutar `apple_rmssd_night` al factor HRV de Body Age/veredicto → «arregla» la dormancia pero **cambia el número** = cambio de producto, no F6; (c) illness → cambiar `vitalsDays` a algo ≠ `days` o «corregir» el SDNN. |

**Salvaguarda dura:** F6 **jamás** sustituye un `keep:.band` por `days` crudo — solo por `clearBand*`. Y **jamás**
introduce `apple_rmssd_night` en un consumidor que hoy no lo lee. Eso es lo que fija el test de no-regresión.

---

## 4. Secuencia de edición ORDENADA (una fase, verde al final)

> Leaf-first: primero el paquete (helpers nuevos), luego los consumidores, al final los tests. El helper nuevo
> se añade **antes** de borrar el viejo para que el paquete compile en cada paso.

**A. StrandAnalytics — introducir los helpers colapsados (aditivo):**
1. `SourceLens.swift`: añadir `public static func clearBandColumns(_ days:) = days.map { $0.crossSourceMasked() }`
   y `clearBandHrv(_ days:) = days.map { $0.hrvMasked() }`. Reescribir el comentario del enum a la realidad
   greenfield (single-source; el limpiado impide ingerir SDNN/offsets de Apple; cita FER-519). `swift build`.

**B. App — re-apuntar los 9 call-sites `keep:.band` → helper sin params:**
2. `TodayView.swift:354,364,381` → `clearBandHrv`/`clearBandColumns`/`clearBandHrv` (quitar `keep:`/`appleDays:`).
3. `RecoveryDetailScreen.swift:672` → `clearBandColumns(days)`. **NO tocar** `:662-686`.
4. `CuerpoView.swift:1335,1376` → `clearBandColumns`.
5. `InsightsProvider.swift:57` → `clearBandColumns(days)`. `appleDays` param del `rank`: puede quedar sin uso
   → quitarlo del seam (y de su caller `:40`) o dejarlo `_` (recomiendo quitarlo; F7 si molesta).
6. `WhatMovesIt.swift:61` → `clearBandHrv(days)` (o retirar el `case "hrv"`; recomiendo `clearBandHrv` para no
   cambiar el shape del switch). `appleDays` param queda sin uso → limpiar firma `findings(...)` y su caller.
7. `CyclePhaseView.swift:50` → `clearBandColumns(repo.days)`.

**C. App — colapsar illness (`keep:.apple` → identidad; borrar la rama muerta):**
8. `AppModel+Illness.swift`:
   - Borrar `:85` (`strapDays`), `:87` (`signalSource`).
   - `:89-91` `vitalsDays` → `let vitalsDays = days`.
   - `:128` `skinTempDays` → `let skinTempDays = days`.
   - `resp` ya lee `days` (`:133`) — sin cambio.
   - Actualizar el comentario `:71-84` a Apple-only (conservar la cita SDNN within-source deliberada).

**D. StrandAnalytics — retirar la maquinaria de selección de fuente (ya sin consumidor tras B+C):**
9. `SourceLens.swift`: borrar `maskHrv`, `maskForBaseline`, `strapOnlyHistory`, `mask`, `keeps`, `enum Source`.
   Conservar `clearBandColumns`/`clearBandHrv` + las ext privadas `crossSourceMasked`/`hrvMasked`.

**E. Tests (§5).**

**F. Verificar:** `cd Packages/StrandAnalytics && swift build && swift test` → verde. El compile iOS completo
(pasos B/C tocan `Cenit/**`) va **uno a la vez, máquina idle**
(`while pgrep -x xcodebuild XCBBuildService; do sleep 30; done`), nunca en paralelo (regla anti-OOM de CLAUDE.md).

---

## 5. Tests: borrar / actualizar / el NUEVO de no-regresión

| Test | Acción | Motivo |
|---|---|---|
| `StrandAnalytics/.../SourceLensTests.swift` | **ACTUALIZAR** | Reescribir los casos `keep:.band`/`keep:.apple`/`appleDays` a `clearBandColumns`/`clearBandHrv`. El invariante columna≡fila (`testBaselineMaskEqualsStrapOnlyRowDrop`) pierde su lado `strapOnlyHistory` (muere) → conservar la aserción de columnas. Los tests de `keep:.apple` complemento/identidad se retiran (fuente única). |
| `StrandAnalytics/.../VitalitySourceInvarianceTests.swift` | **ACTUALIZAR** | `maskForBaseline(keep:.band)` → `clearBandColumns`. **Conservar las aserciones** (Apple-only → factor HRV/RHR ausente, `rmssd/rmssdNorm` nil): son el pin de que Body Age no cambia. |
| `CenitUnitTests/InsightsProviderSourceInvarianceTests.swift` | **ACTUALIZAR** | Re-apuntar al helper; conservar aserciones. |
| `CenitUnitTests/IntelligenceBaselinePriorTests.swift` | **PARTIR/BORRAR** | Los casos `strapOnlyHistory` (`:24,29,45`) mueren con la función. Si no queda nada vivo, borrar el archivo. |
| `CenitUnitTests/IllnessWatchSourceTests.swift` | **REESCRIBIR** | Los 3 usos de `strapOnlyHistory` (`:53,72,99`) + el caso FER-884 («Apple-only ⇒ strapOnlyHistory EMPTY») se sustituyen por: «illness Apple-only lee `days` directo, z within-source Apple SDNN/RHR». La semántica NO cambia (era ya el comportamiento efectivo); cambia el símbolo. |
| **NUEVO: `StrandAnalytics/.../SourceLensCollapseTests.swift`** | **CREAR** | El test de no-regresión SDNN↔RMSSD (abajo). |

### El test de no-regresión SDNN↔RMSSD (qué FIJA, concreto)

Vive en StrandAnalytics (puro, sin app/HealthKit). Fija **tres** cosas — que el refactor es transparente,
que el limpiado es load-bearing, y que Body Age no cambia:

```swift
// Fixture: historia densa donde CADA fila es un día Apple (avgHrv = SDNN, restingHr = RHR Apple,
// respRateBpm, skinTempDevC, deepMin/remMin/lightMin, + strain/steps/totalSleepMin).
// Réplicas locales del lente legacy para comparar contra el nuevo helper:
//   legacyBandBaseline(d, apple) = d.map { apple.contains($0.day) ? $0.crossSourceMasked-equivalent : $0 }
//   (o simplemente: el comportamiento documentado con appleDays == Set(d.map(\.day)))

func test_collapseIsByteIdentityWhenAllApple() {
    let all = Set(days.map(\.day))
    XCTAssertEqual(SourceLens.clearBandColumns(days), legacyMaskForBaselineBand(days, appleDays: all))
    XCTAssertEqual(SourceLens.clearBandHrv(days),      legacyMaskHrvBand(days, appleDays: all))
}

func test_clearBandColumnsNilsExactlyBandDomain_keepsStrain() {
    for r in SourceLens.clearBandColumns(days) {
        XCTAssertNil(r.avgHrv); XCTAssertNil(r.restingHr); XCTAssertNil(r.respRateBpm)
        XCTAssertNil(r.skinTempDevC); XCTAssertNil(r.deepMin); XCTAssertNil(r.remMin); XCTAssertNil(r.lightMin)
        XCTAssertNotNil(r.strain); XCTAssertNotNil(r.steps); XCTAssertNotNil(r.totalSleepMin)  // sobreviven
    }
}

func test_clearBandHrvNilsOnlyHrv_keepsRestingHR() {
    for r in SourceLens.clearBandHrv(days) { XCTAssertNil(r.avgHrv); XCTAssertNotNil(r.restingHr) }
}

// LA ASERCIÓN DE ORO — el limpiado es load-bearing: pasar `days` CRUDO (SDNN en avgHrv) a un motor
// band-domain produce un resultado DISTINTO que el limpiado → quitar el limpiado reintroduce FER-519.
func test_rawAppleSDNNwouldContaminateReadiness_FER519() {
    let raw     = ReadinessEngine.evaluate(days: days,                              today: todayKey)
    let cleared = ReadinessEngine.evaluate(days: SourceLens.clearBandColumns(days), today: todayKey)
    let rawHRV     = raw.signals.first { $0.key == "hrv" }
    let clearedHRV = cleared.signals.first { $0.key == "hrv" }
    XCTAssertNotNil(rawHRV, "SDNN crudo HABRÍA puntuado una señal HRV (el bug)")
    XCTAssertNil(clearedHRV, "limpiado ⇒ sin señal HRV band-domain de una fila Apple")
}

// Body Age no cambia: inputs de Vitality desde el limpiado == desde el lente legacy, HRV+RHR ausentes.
func test_vitalityInputsUnchanged_HRVandRHRabsentInAppleOnly() {
    let viaHelper = VitalityInputsBuilder.build(fromNightly: SourceLens.clearBandColumns(recent), ...)
    let viaLegacy = VitalityInputsBuilder.build(fromNightly: legacyMaskForBaselineBand(recent, all), ...)
    XCTAssertEqual(viaHelper.rmssd, viaLegacy.rmssd)         // ambos nil
    XCTAssertNil(viaHelper.rmssd); XCTAssertNil(viaHelper.rmssdNorm)
}
```

`legacyMaskForBaselineBand`/`legacyMaskHrvBand` se escriben inline en el test (2 líneas cada uno, replicando
la semántica documentada) para que el test **sobreviva** al borrado del símbolo legacy y siga siendo el
contrato para siempre.

---

## 6. Los 3 riesgos de CIENCIA (para el gate `/cso` + `/estadistico` + Grok)

1. **Reintroducir FER-519/629 (contaminación silenciosa).** Cualquier call-site que pase `days` crudo (con
   SDNN en `avgHrv`, RHR Apple en `restingHr`) a un motor band-domain (Vitality/Insight/Readiness/WhatMovesIt).
   El verdict/insight se corrompería sin error visible.
   **Mitigación:** los 9 sitios `keep:.band` se sustituyen SOLO por `clearBand*` (nunca por `days`);
   `test_rawAppleSDNNwouldContaminateReadiness_FER519` falla si alguien quita el limpiado.

2. **Enrutar SDNN a RMSSD «para arreglar la dormancia».** Tentación de alimentar `apple_rmssd_night` (RMSSD
   real, ≈ dominio de banda) al factor HRV de Body Age o al veredicto para que «ya no salgan vacíos». Es una
   mejora legítima **pero cambia números mostrados** (Body Age gana un factor; el veredicto gana señal HRV) →
   **cambio de producto, no F6.** F6 preserva la dormancia exacta.
   **Mitigación:** criterio «Body Age/veredicto byte-idénticos»; `test_vitalityInputsUnchanged` lo fija; se
   levanta un issue aparte (junto a FER-1030) para el rewire.

3. **Illness: mezclar su historia o cambiar su fuente.** Illness lee **SDNN de Apple within-source
   deliberadamente** (`vitalsDays = days`, z contra la propia norma Apple — válido pese a SDNN≠RMSSD; Shaffer
   & Ginsberg 2017). Riesgo: al borrar `strapDays`/`signalSource`/rama `.band`, cambiar accidentalmente
   `vitalsDays` a algo ≠ `days`, o «corregir» el SDNN a RMSSD (rompería la base de 28 noches).
   **Mitigación:** `vitalsDays`/`skinTempDays` → exactamente `days`; `resp` ya lee `days`;
   `IllnessWatchSourceTests` reescrito pin el z within-source; el comentario conserva la cita.

**Robustez ganada (nota para el gate):** el helper incondicional `clearBand*` **ya no depende** del invariante
`appleHealthDays == todos los días`. El lente legacy podía dejar pasar SDNN si ese invariante se rompía a
futuro (p.ej. si alguien reañade una fila `computed`); el limpiado incondicional nila band-domain en TODA fila
→ estrictamente más seguro contra una regresión futura.

---

## 7. Criterios técnicos de aceptación (checklist de `/implement`)

- [ ] `SourceLens.swift` NO contiene `enum Source`, `keeps`, `mask`, `maskHrv`, `maskForBaseline`,
      `strapOnlyHistory`. SÍ contiene `clearBandColumns`/`clearBandHrv` (+ ext privadas
      `crossSourceMasked`/`hrvMasked`).
- [ ] `grep -rn "keep: *\.band\|keep: *\.apple\|maskForBaseline\|maskHrv\|strapOnlyHistory\|SourceLens\.Source"
      --include=*.swift Cenit Packages CenitUnitTests` → **0** (código y comentarios de call-site).
- [ ] `grep -rn "appleHealthDays\|appleDays" --include=*.swift` NO aparece como **argumento** a ningún helper de
      `SourceLens` (la prop `repo.appleHealthDays` sigue viva para `isAppleHealth`; su retiro es F7).
- [ ] `AppModel+Illness`: sin `strapDays`, sin `signalSource`, sin rama `.band`, sin `dataSourceMode ==`;
      `vitalsDays == days` y `skinTempDays == days` (`git diff` lo confirma).
- [ ] `SourceFusion.swift` sin cambios (`git diff` vacío) — `autonomicTrend` y el resto intactos. `apple_rmssd_night`
      no aparece en ningún consumidor nuevo.
- [ ] `RecoveryDetailScreen.swift:662-686` sin cambios de lógica (`series`/`recovery`/`buildHeat`/`forecast`);
      `CuerpoView` Fitness Age (`last7`/`displayDays`) sin cambios.
- [ ] `cd Packages/StrandAnalytics && swift build && swift test` → **verde**, incluido el nuevo
      `SourceLensCollapseTests` con `test_rawAppleSDNNwouldContaminateReadiness_FER519` y
      `test_vitalityInputsUnchanged`.
- [ ] `VitalitySourceInvarianceTests` + `InsightsProviderSourceInvarianceTests` (re-apuntados) → **verde**,
      aserciones conservadas.
- [ ] `xcodebuild -project Cenit.xcodeproj -scheme Cenit -destination 'generic/platform=iOS'
      CODE_SIGNING_ALLOWED=NO -jobs 4 build` → **compila** (máquina idle, uno a la vez).
- [ ] En Simulador/dispositivo Apple-only: AutonomicTrend, Body Age, Carga/Panorama, Patrones, Illness y Cycle
      se ven **idénticos** a antes del PR (F6 es transparente).
- [ ] Gate `/cso` + `/estadistico` + Grok: **PASS** sobre los 3 riesgos de ciencia (§6).

---

## 8. Alternativas evaluadas

- **Borrar `SourceLens` entero e inline el limpiado en cada sitio.** Descartada: dispersa la lógica FER-519 por
  7 archivos (justo lo contrario de la consolidación que F4 hizo al mover `strapOnlyHistory` DENTRO de
  `SourceLens`); y el limpiado sigue siendo ciencia viva, no andamiaje.
- **Pasar `days` crudo (sin limpiar) asumiendo que «Apple es la única fuente, ya no hay banda que aislar».**
  **Descartada — es el bug.** La fila Apple carga SDNN en `avgHrv`; los motores band-domain lo tomarían como
  RMSSD → FER-519/629. El limpiado no es sobre «banda vs Apple», es sobre «este motor tiene norma RMSSD y esta
  columna es SDNN».
- **Aprovechar F6 para enrutar `apple_rmssd_night` a Body Age/veredicto.** Descartada para F6: cambia números
  mostrados → cambio de producto que necesita su propio `/pm` (+ gate ciencia), no un colapso transparente.

---

## 9. Actualización de docs/ARCHITECTURE.md

Cambio de arquitectura real (el read-model pierde su dimensión multi-fuente). Diff propuesto para el bloque
`SourceLens` (`docs/ARCHITECTURE.md:533-545`), que `/implement` aplica en el mismo PR:

```
- - **`SourceLens`** (FER-623 / FER-631, formerly `HrvSourceLens`) keeps a baseline pure by source, with two
-   lenses over one row classification (`appleDays` is app knowledge passed in; the package stays pure).
-   `maskHrv(_:keep:appleDays:)` nils only `avgHrv` on the rows of the other source — the FER-623 path: the
-   verdict scores HRV against the band (RMSSD) baseline only, the brief adds an **estimated** SDNN bullet on
-   a band-less day, and `StressModel` z-scores each reading against the baseline of its own source.
-   `maskForBaseline(_:keep:appleDays:)` (FER-631) nils **every cross-source column** — `avgHrv`,
-   `restingHr`, `respRateBpm`, `deepMin`/`remMin`/`lightMin` — for band-anchored consumers (FER-632+): no
-   band↔Apple metric is interchangeable without correction (RMSSD≠SDNN — Task Force 1996, Shaffer &
-   Ginsberg 2017 — plus measured RHR/resp/stage offsets, FER-629). It is the column-level equivalent of
-   `IntelligenceEngine.strapOnlyHistory` (whole-row drop): under the skip-and-hold folds both yield the
-   same single-source baseline (pinned by test). The **z-score is the common currency** across sources;
-   raw ms are never compared between them. `keep: .band, appleDays: []` is the identity for both lenses
-   (a strap-only user is unchanged).
+ - **`SourceLens`** (FER-623 / FER-631; colapsado a single-source en el épico «la banda nunca existió», F6).
+   Apple-only: cada fila diaria carga **SDNN** de Apple en `avgHrv`, RHR sedentario de Apple en `restingHr` y
+   un Δ de temperatura propio — construcciones distintas de las de la banda (RMSSD≠SDNN, sin conversión
+   publicada — Task Force 1996; Shaffer & Ginsberg 2017 — + offsets medidos de RHR/resp/stages, FER-629). Los
+   motores con norma band-domain (VitalityEngine RMSSD-por-edad, InsightEngine, ReadinessEngine señal HRV,
+   WhatMovesIt) **no deben ingerir** esas columnas, así que `clearBandColumns(_)` las nila todas y
+   `clearBandHrv(_)` nila solo `avgHrv` antes de que un motor las pliegue — en greenfield esas sub-features
+   HRV/RHR quedan **dormidas**, no contaminadas. El RMSSD nocturno REAL de Apple fluye por un camino separado
+   (`SourceFusion.autonomicTrend` sobre `apple_rmssd_night`), nunca por este lente. La selección de fuente
+   (`keep`/`appleDays`/`Source`/`strapOnlyHistory`) se retiró: con una sola fuente no hay qué seleccionar.
+   `AppModel+Illness` es la única excepción que lee SDNN de Apple **a propósito** (z within-source contra la
+   propia norma Apple, no contra la de banda).
```

Si algún diagrama o tabla «where logic belongs» describe `SourceLens` como árbitro multi-fuente, anotar que es
single-source (limpiador band-domain). El retiro del campo `avgHrv`/esquema y de `repo.appleHealthDays` se
documenta en F7.
