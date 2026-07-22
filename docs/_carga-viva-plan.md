# Diseño técnico — «CARGA VIVA»: la carga (ACWR) funciona en Apple-only greenfield

> Arquitecto. Rama `claude/carga-viva-apple`. Carril **PESADO** (matemática on-device + dato persistido +
> cross-paquete): requiere gate **`/cso` + `/estadistico` + `/qa`** antes de merge.
> Este doc es el contrato que `/implement` ejecuta. NO es la implementación.
>
> **AXIOMA que gobierna el diseño:** mundo greenfield, cero banda. Todo usuario = Apple-only fresco.
> No hay «dato dormido de banda» que reconciliar: en `repo.days` **todas** las filas son filas Apple
> (`deviceId == "apple-health"`), y `imported/computed == []` por construcción (`Repository.swift:366-367`).
>
> Baseline verificado esta sesión: `StrandAnalytics` compila verde (`swift build`, 2.1s). El resto del
> diseño está probado contra el código leído, no adivinado.

---

## Resumen

Hoy la carga (ACWR) está **inerte** en Apple-only: el strain diario estimado desde el HR de workout de
Apple se computa **solo para hoy** y **nunca se persiste**, así que `DailyMetric.strain` es `nil` en todas
las filas Apple → `ReadinessEngine.strainSeries` queda vacío → `count < minChronic(14)` → `acwr == nil`
**permanente** → la tarjeta «Carga» se queda «calibrando» para siempre.

El cómo, en una frase: **persistir el strain diario estimado en la columna `strain` que ya existe (rest→0,
missing→NA), migrar la razón acute:chronic de media móvil rígida a EWMA acoplado (Williams 2017) que decae
en descanso, y poner un piso de días REALES con actividad para que la carga aparezca solo cuando hay señal
—sin mentir con un ACWR de puros ceros— conservando el marco DESCRIPTIVO (nunca «riesgo de lesión»).**

Sin migración de esquema: `DailyMetric.strain` ya existe y en greenfield Apple-only es real estate libre
(la banda no escribe filas).

---

## Supuestos (verificados contra el código)

- **`repo.days` = puras filas Apple.** `Repository.performRefresh` fija `imported=[]`, `computed=[]`,
  `apple=appleRaw` (`Repository.swift:366-368`); `SourceFusion.mergeDaily` sube Apple como capa base. Toda
  fila de `days` es Apple con `strain == nil` (ambos productores escriben `strain: nil` —
  `AppleHealthImport.swift:45` y `HealthKitBridge.swift:424`).
- **El HR de workout de Apple YA se persiste histórico.** `HealthKitBridge` (línea 472-474)
  `insert(Streams(hr: workoutHrSamples))` bajo `apple-health` para **toda** la ventana de sync (no solo hoy).
  El combustible crudo ya está en la DB; lo que falta es scorearlo por día y persistir el resultado. Lo que
  hoy se restringe a «hoy» es la **lectura** en `performRefresh` (`appleHrWindow` = midnight→now,
  `Repository.swift:388`) y el estimado efímero (`strainEstimates[day]`, `repo.today.estimatedStrain`).
- **`StrainScorer.strain(_:maxHR:restingHR:method:sex:)`** (Edwards TRIMP → 0–21, `StrainScorer.swift:222`)
  es la matemática de dosis; no se inventa nada. `SourceFusion.appleStrainEstimates` (`SourceFusion.swift:56`)
  ya la aplica por día. `maxHR`/`sex` vienen del `Profile` vía `strainHRmax`/`strainSex`.
- **`DailyMetric.steps` vive en la fila** (`Models.swift:45`, poblado desde `a.steps`,
  `HealthKitBridge.swift:426`). `activeKcal` NO está en `DailyMetric` (el campo `activeKcalEst` es el estimado
  HR-only de banda, nil en Apple); vive en `AppleDaily.activeKcal` y en `metricSeries["active_kcal"]`. La
  presencia de `HKWorkout` está en `hkWorkouts`/`wkRows` durante el sync.
- **El EWMA ya tiene precedente en el repo:** `Baselines.lambda(halfLife:)` (`Baselines.swift:172-175`,
  `λ = 1 − 0.5^(1/halfLife)`) y toda la maquinaria winsorizada. El patrón se reutiliza; no se importa nada nuevo.
- **`ReadinessEngine.acwrSeries` invariante:** su último punto == el `acwr` de `evaluate` (mismo fold). Debe
  preservarse tras el cambio a EWMA.

---

## Dónde vive (tabla de fronteras)

| Pieza | Paquete/archivo | Por qué ahí |
|---|---|---|
| **Estimador de carga diaria** (rest→0 vs missing→NA + score por día) | **NUEVO** `Packages/StrandAnalytics/Sources/StrandAnalytics/AppleLoadEstimator.swift` (pure) | Matemática de dosis + regla rest/missing = math-level → lo más profundo. Foundation + BiometricStreams + StrandModels, cero DB/UIKit. Cubrible por `swift test` sin app/HealthKit. |
| **ACWR EWMA acoplado + piso de días activos** | `Packages/StrandAnalytics/…/ReadinessEngine.swift` (editar) | La razón acute:chronic y su gate ya viven aquí; el cambio es interno tras la misma API pública. |
| **Persistir el strain diario estimado** (orquestación) | `CenitApp/Health/HealthKitBridge.swift` + `Cenit/Data/AppleHealthImport.swift` (editar) | Escribir a `DailyMetric.strain` es trabajo de shell (tiene HR por día, steps, kcal, presencia de workout, y el `Profile`). El shell llama al estimador puro; no reimplementa math. |
| **Estimado vivo de HOY** (número intradía «Carga del día») | `Cenit/Data/Repository.swift` (sin cambio de fondo) | Se conserva `appleStrainEstimates` midnight→now para el héroe intradía; solo hoy. Ver «Reconciliación hoy». |
| **Presentación** | `Cenit/Screens/TrainingLoadSheet.swift`, `TodayView.swift`, `CuerpoView.swift`, `RecoveryDetailScreen.swift` | Solo consumen; NO se rediseñan aquí (eso es `/ui`). Los valores cambian, las firmas no. |

**Contratos públicos que cambian:** ninguno en firma. `AppleLoadEstimator` es API pública **nueva** (aditiva).
`ReadinessEngine.evaluate/acwrSeries/loadBand/acwr*Threshold` mantienen su firma; **cambian valores**, no tipos.

---

## Diseño

### Pieza 1 — `AppleLoadEstimator` (pure, StrandAnalytics)

Una función pura por día que resuelve la ambigüedad **descanso real vs dato faltante** y devuelve la dosis:

```
enum DayLoad: Equatable, Sendable { case rest        // strain = 0  (día tranquilo, cuenta como descanso)
                                     case load(Double)// strain 0–21 desde el HR de workout
                                     case missing }   // NA — excluir del fold (día activo sin workout formal)

struct DayActivity {           // lo que el shell le pasa por día (todo ya disponible en el sync/import)
    let workoutHR: [HRSample]  // HR de HKWorkouts de ese día local (puede estar vacío)
    let steps: Int?            // DailyMetric.steps / AppleDaily.steps
    let activeKcal: Double?    // AppleDaily.activeKcal / metricSeries["active_kcal"]
    let hasWorkout: Bool       // hubo HKWorkout ese día
}

static func classify(_ a: DayActivity, maxHR: Double?, restingHR: Double, sex: String,
                     cfg: RestThresholds) -> DayLoad
```

Regla (patrón ropensci **Athlytics/CRAN ACWR**: rest→0, missing→NA):
1. Si hay `workoutHR` suficiente → `StrainScorer.strain(...)` → `.load(s)` (si el scorer da nil por HR
   insuficiente, cae a la regla 2/3).
2. Si **no** hay workout y la actividad es baja (`steps < stepsRestMax` **y** `activeKcal < kcalRestMax`) →
   `.rest` (strain 0): día tranquilo, es descanso legítimo y **decae** el EWMA agudo.
3. Si **no** hay workout pero la actividad es alta (steps/kcal sobre el umbral) → `.missing` (NA): hubo
   esfuerzo no registrado; **no** se puede scorear sin HR y meterlo como 0 mentiría. Se **excluye** del fold
   (el EWMA hace hold, no decae ni infla).

`RestThresholds { stepsRestMax, kcalRestMax }` es un **punto de calibración**, NO validado. Punto de partida
propuesto (decisión final de `/estadistico`): `stepsRestMax ≈ 6000 pasos`, `kcalRestMax ≈ 250 kcal` de
energía activa. Racional: por debajo de ~6k pasos y ~250 kcal activas el día es sedentario típico; por
encima, hubo movimiento que un TRIMP sin HR no puede honrar. Deben salir de literatura de umbral de actividad
diaria, no de intuición — `/estadistico` los fija o los deja como default+bandera.

### Pieza 2 — ACWR EWMA acoplado + piso de días activos (`ReadinessEngine`)

**Sustituye** el fold de media móvil rígida (`ReadinessEngine.swift:276-298`):

- Hoy: `strainSeries = sorted.compactMap { $0.strain }.map(strainToLoad)` — **descarta nils** (colapsa el
  calendario, borra la distinción rest/missing) y usa medias de sufijo 7d/28d.
- Nuevo: construir la **secuencia diaria por día calendario** (con huecos explícitos), linealizar con
  `strainToLoad`, y correr **EWMA acoplado** (Williams et al. 2017, *Br J Sports Med* 51:209):
  - `λ_acute  = 2/(N_a+1)`, `N_a = 7`  → 0.25
  - `λ_chronic= 2/(N_c+1)`, `N_c = 28` → ~0.069  (mismos horizontes que hoy)
  - `EWMA_t = load_t·λ + EWMA_{t-1}·(1−λ)` sobre la secuencia; **día `.rest` (0) SÍ se pliega** (decae el
    agudo → mata el «congelado»); **día `.missing` hace hold** (carry-forward, ni decae ni infla).
  - `acwr = EWMA_acute / EWMA_chronic` (mismas bandas **0.8 / 1.3 / 1.5** intactas — `loadBand(forACWR:)`
    no cambia).
- **Seeding:** sembrar ambos EWMA con el primer valor observado (o la media del primer bloque disponible),
  para que el arranque no explote. `/estadistico` valida el seeding.

**Piso de días REALES con actividad (mitiga el hallazgo CSO del zero-fill trivializando `minChronic`):**
el gate de hoy (`strainSeries.count >= minChronic(14)` + `chronic > 0`) es trivial de alcanzar con puros
ceros — 14 días de calendario con 0 workouts lo pasan por conteo de filas. Reemplazar/complementar con:

```
minChronicDays  = 14   // días de COBERTURA (rest+load), como hoy — el EWMA necesita historia
minActiveDays   = 4    // días con strain > 0 (load real) dentro de la ventana crónica  ← NUEVO piso
```

`acwr` se emite **solo si** `coverageDays ≥ minChronicDays` **Y** `activeDays ≥ minActiveDays` **Y**
`EWMA_chronic > 0`. Antes de eso → `nil` → la tarjeta muestra estado vacío honesto (ver abajo), no un ACWR
de ceros. `minActiveDays` es punto de calibración de `/estadistico` (propuesto: 4 días de esfuerzo real en
28). Esto es el corazón del diseño: **la carga aparece cuando hay señal de carga, no cuando pasó el
calendario.**

**Monotony:** se conserva (Foster 1998) pero ahora corre sobre la secuencia con días `.rest=0` incluidos
(antes `compactMap` los borraba) — es lo correcto para Foster (los días de descanso SON parte de la
monotonía). Cambia el denominador; se re-pinnea el test.

**`acwrSeries`:** se reimplementa como el mismo replay EWMA de una sola pasada O(n) (más barato que el
`windowMean` actual). Invariante preservado: **el último punto == `evaluate.acwr`** (test explícito).

### Pieza 3 — Persistencia (dónde vive el strain diario estimado)

**Recomendación: escribir el estimado en la columna `DailyMetric.strain` existente**, partición
`apple-health`, en los DOS productores que ya construyen las filas Apple:

- `HealthKitBridge.sync` (`HealthKitBridge.swift:420-427`): al armar `dmRows`, agrupar `workoutHrSamples`
  por día local (`DayKey.local`), llamar `AppleLoadEstimator.classify` con `steps`/`activeKcal`/`hasWorkout`
  de `byDay`+`hkWorkouts` y el `Profile`, y escribir `strain: <DayLoad>` (0 para `.rest`, valor para
  `.load`, `nil` para `.missing`).
- `AppleHealthImport.importExport` (`AppleHealthImport.swift:39-48`): igual, sobre `result.daily` +
  `result.workouts`. (El import trae HR de workout crudo también; si no lo trae por día, el import escribe
  rest/missing por steps/kcal y el sync rellena `.load` cuando llega el HR — degradación honesta.)

Justificación de riesgo (por qué la columna existente y no una serie/migración nueva):
- **Cero migración** (regla append-only intacta): la columna `strain` ya existe (`dailyMetric`, v-actual).
  En greenfield la banda no escribe filas → `strain` está libre; poblarla con el estimado Apple **es** su
  uso natural (igual que `avgHrv`=SDNN de Apple, `restingHr`, `steps` ya viven en la fila Apple).
- **Cero plumbing:** `ReadinessEngine`, `StrainCeiling`, `acwrSeries` ya leen `days.strain`. `days` mergea
  las filas Apple → el strain fluye a todos los consumidores sin tocar el merge.
- **Estimado-ness por fuente, no por columna:** en Apple-only **todo** strain es estimado. `isStrainEstimated`
  se resuelve como «fila de fuente Apple con strain» (o simplemente `true` en el pin `.appleHealthOnly`),
  conservando el marco «~» sin columna extra.

**Ventana de cobertura (riesgo aceptado, igual que steps/kcal):** el sync foreground usa ventana delta
(`lastSync` + back-margin), así que el backfill histórico de strain ocurre en el **primer** full sync / en el
import; los deltas actualizan días recientes. Días fuera de toda ventana quedan `nil` (mismo comportamiento
que steps/sueño hoy). El primer full sync cubre la ventana completa.

**Reconciliación con el HOY vivo:** se **conserva** el path efímero `appleStrainEstimates` midnight→now
(`Repository.swift:388-426`) para el número intradía «Carga del día» del héroe (crece durante el día). Para
ACWR se lee el `days.strain` **persistido** (medida trailing; el parcial de hoy subestima levemente el agudo
y se autocorrige al cierre). Es la misma dualidad que ya existe (persistido vs `repo.today`); no se rompe.

### Concurrencia

Sin cambio de modelo. El estimador es puro (corre donde ya corre el ensamblado). La escritura va por el mismo
`repo.storeHandle()` serializado del `actor CenitStore` (`upsertDailyMetrics`), dentro del bloque de escritura
que ya existe en `HealthKitBridge` (líneas 465-475). No se introduce isolation nuevo.

### Migración

**Ninguna.** Se reutiliza `DailyMetric.strain`. (Si `/implement` decidiera —contra esta recomendación— una
serie derivada aparte, sería `metricSeries` key bajo `apple-health-noop`, que es **aditivo sin migración**;
pero la recomendación es la columna existente.)

---

## Validación contra reglas duras

- **Offline only:** ✅ todo on-device; el estimador es Foundation-pure, cero red/telemetría/cuenta.
- **BLE no destructivo + CRC:** N/A — no toca `WhoopProtocol` ni bytes salientes.
- **Pureza de paquetes:** ✅ `AppleLoadEstimator` vive en `StrandAnalytics`, depende solo de
  Foundation + `BiometricStreams` (`HRSample`) + `StrandModels`; ningún `import UIKit/AppKit/CoreBluetooth/GRDB`.
- **Migraciones append-only:** ✅ **sin migración** (columna existente). No se edita ninguna migración shipped.
- **Decoded-first durability:** ✅ el strain es un derivado; se escribe **después** de que el HR crudo ya se
  commiteó (el HR ya está persistido, independiente). El raw sigue siendo prunable; el strain persistido se
  recomputa desde HR cuando el día cambia.
- **Math transparente:** ✅ EWMA-ACWR = **Williams 2017** (*BJSM* 51:209); bandas = **Gabbett 2016** (*BJSM*
  50:273); descriptivo-no-predictivo = **Impellizzeri 2020** (*BJSM* 54:1451; el ACWR NO predice lesión);
  monotony = **Foster 1998**; dosis = Edwards TRIMP (`StrainScorer`); rest→0/missing→NA = convención
  Athlytics/CRAN ACWR. Cada regla con test. `/cso`+`/estadistico` verifican citas y aritmética.
- **Marco DESCRIPTIVO (guarda de honestidad):** ✅ el copy actual de `acwrSignal` es puramente descriptivo
  («recent load below/above your usual», sin imperativo de riesgo). **No se cambia una palabra.** La carga
  sigue siendo «tu carga reciente vs tu habitual», nunca «riesgo de lesión».

---

## Pruebas (invariantes)

Paquete (`swift test`, sin app/HealthKit):
- **rest vs missing vs load** → `AppleLoadEstimatorTests`: día tranquilo (steps/kcal bajo, sin workout) → `.rest`(0);
  día activo-sin-workout (steps/kcal alto, sin workout) → `.missing`(NA); día con workout HR → `.load`==`StrainScorer`. [⬜]
- **EWMA acoplado numérico** → `ReadinessEngineTests`: secuencia conocida → ACWR EWMA esperado (re-derivable a mano). [⬜]
- **decae en descanso** → tras N días `.rest`(0) el EWMA agudo baja y ACWR < 1 (no se congela). [⬜]
- **piso de días activos** → 14 días de calendario con `activeDays < minActiveDays` → `acwr == nil` (no ACWR de ceros);
  con `activeDays ≥ minActiveDays` → `acwr != nil`. [⬜]
- **missing hace hold** → intercalar `.missing` no cambia el EWMA vs quitarlos (carry-forward, no inyecta 0). [⬜]
- **invariante acwrSeries** → último punto de `acwrSeries` == `evaluate().acwr` bajo EWMA. [⬜]
- **chronic>0 guard** → todo-ceros → `acwr == nil` (no división por 0, no spike espurio). [⬜]

App (`CenitUnitTests`, compila sin cabeza):
- **carga viva end-to-end (pure merge)** → un `days` de puras filas Apple con strain persistido (rest/load) produce
  `acwr != nil` una vez pasado el piso; con solo nils sigue `nil`. Pinnea la cadena `days → ReadinessEngine`. [⬜]
- **regresión de contrato F6** → los invariantes de fuente única (`SourceLensTests`,
  `F6CollapseIdentityContractTests`) siguen verde. [⬜]

Regresión conocida (churn esperado, `/implement` la actualiza): `ReadinessEngineTests`, `StrainCeilingTests` y
cualquier test que pinnee valores de ACWR/monotony **cambian numéricamente** con EWMA + secuencia-con-ceros. No es
un bug: es el cambio de modelo. Se re-derivan a mano y `/estadistico` los valida.

**Corrido esta sesión:** `swift build` de `StrandAnalytics` → verde (baseline). Los tests nuevos NO se corrieron
(no existen aún; son el contrato de `/implement`). **No afirmo que ningún test nuevo pase.**

---

## Alternativas y riesgos

**Alternativas evaluadas:**
- **Serie derivada aparte** (`metricSeries` key bajo `apple-health-noop`, no tocar `DailyMetric.strain`) —
  *descartada:* obliga a overlay-plumbing en el merge para que `ReadinessEngine` la vea; en greenfield la
  columna `strain` está libre y es su uso semántico natural. Más código, cero beneficio.
- **Mantener media móvil, solo persistir strain** — *descartada:* no cura del todo el «congelado». Con
  zero-fill la SMA también trivializa `minChronic`, y sin decaimiento en descanso el agudo no baja. El GO de
  ciencia (CSO+Grok) fue EWMA acoplado (Williams 2017), que decae con gracia.
- **Score en read-time sobre todo el HR histórico en cada refresh** (sin persistir) — *descartada:* leer el
  HR Apple de años en cada refresh es exactamente lo que FER-970 restringió a hoy por perf. Persistir es el punto.

**Riesgos top-3:**
1. **Zero-fill trivializa `minChronic` → ACWR espurio / spike falso en el primer workout.** Un usuario con 14
   días de calendario y 0 workouts NO debe ver carga; y su primer workout no debe leer «spiking» contra un
   crónico de ceros. *Mitigación:* piso `minActiveDays` (días con strain>0, no filas), + guard `chronic>0`, +
   seeding EWMA que no explota. `/estadistico` fija `minActiveDays` y valida que el primer workout no dispare
   una banda falsa. **Este es el riesgo #1; el diseño lo ataca de frente con el piso.**
2. **Regresión del marco descriptivo.** El ACWR debe seguir siendo «tu carga vs tu habitual», jamás «riesgo de
   lesión» (Impellizzeri 2020). *Mitigación:* no se cambia copy; se conserva la cita; gate `/cso`.
3. **Regresión numérica en todas las superficies + tests + monotony.** EWMA cambia cada valor de ACWR; los días
   `.rest=0` ahora entran a la monotonía (denominador distinto). *Mitigación:* actualizar tests deliberadamente,
   preservar invariante `acwrSeries`-último==`evaluate`, `/qa` re-deriva a mano. Consumidores enumerados abajo.

**Riesgo abierto (dependencia de producto):** la carga depende de que el usuario tenga **HKWorkouts con HR**.
Un usuario que nunca registra workouts formales cae siempre en `.missing`/`.rest` → ACWR puede no llegar nunca.
Es honesto (sin HR de esfuerzo no hay señal de carga), pero es una **frontera de alcance** que conviene que
`/pm`/`/ux` sepan: el estado vacío debe explicar «registra entrenamientos con tu Apple Watch para que tu carga
aparezca», no prometer un número que no puede existir.

**Consumidores de EWMA afectados (valores cambian, firmas no):**
- `Cenit/Screens/TodayView.swift:355-369` (`computeDerived` → `TrainingLoadModel`, ACWR + serie).
- `Cenit/Screens/CuerpoView.swift:1337-1344` (`loadAll` → `TrainingLoadModel`).
- `Cenit/Screens/RecoveryDetailScreen.swift:673-678` (`LoadState`).
- `Cenit/Screens/TrainingLoadSheet.swift` (presentación; `acwr==nil` → «calibrando»).
- `Packages/StrandAnalytics/…/DailyBrief.swift` (bullet `acwr` desde `readiness.signals`).
- `Packages/StrandAnalytics/…/InsightEngine.swift:560-569` (insight de carga; lee `r.acwr`/`r.loadBand`).
- `Packages/StrandAnalytics/…/StrainCeiling.swift` — lee `days.strain` (se enciende con el strain persistido)
  pero su guard `recovery` lo mantiene `nil` en Apple-only (recovery 0–100 retirado). **Afectado-pero-dormido**;
  NO se migra a EWMA (es un techo sobre crónico, otro concepto). Anotar para `/qa`.

---

## Criterios técnicos de aceptación (checklist de `/implement`)

- [ ] Existe `AppleLoadEstimator` en `StrandAnalytics`, puro (sin GRDB/UIKit/CoreBluetooth), con `classify(...)`
      que devuelve `.rest`/`.load`/`.missing` por la regla rest/missing.
- [ ] `HealthKitBridge.sync` y `AppleHealthImport.importExport` escriben `DailyMetric.strain` desde
      `AppleLoadEstimator` (0 para rest, valor para load, nil para missing), agrupando HR de workout por día local.
- [ ] **Sin migración nueva** en `CenitStore` (la columna `strain` existente se reutiliza); `MigrationTests` intacto.
- [ ] `ReadinessEngine` computa ACWR por **EWMA acoplado** (λ_a=2/8, λ_c=2/29) sobre la secuencia diaria con
      rest=0 plegado y missing en hold; bandas 0.8/1.3/1.5 sin cambio.
- [ ] `ReadinessEngine` emite `acwr` **solo** si `coverageDays ≥ minChronicDays` **y** `activeDays ≥ minActiveDays`
      **y** `chronic>0`; todo-ceros → `nil`.
- [ ] `acwrSeries` reimplementado como replay EWMA; su último punto == `evaluate().acwr` (test verde).
- [ ] Copy de `acwrSignal` **sin cambios** (marco descriptivo, cita Impellizzeri 2020 intacta).
- [ ] Tests nuevos de paquete (estimador + EWMA + piso + hold + invariante) verdes; tests de regresión
      (`ReadinessEngineTests`/`StrainCeilingTests`) re-derivados y verdes.
- [ ] `CenitUnitTests`: `days` Apple con strain persistido → `acwr != nil` tras el piso; F6 contract verde.
- [ ] `swift build && swift test` de `StrandAnalytics` verde; `swift build` de `CenitStore` verde.
- [ ] Gate `/cso` + `/estadistico` + `/qa` PASS antes de merge (carril pesado).

---

## Actualización de docs/ARCHITECTURE.md

Cambio de arquitectura menor: el estimado de strain **deja de ser efímero/read-time y pasa a persistirse**.
Diff propuesto (aditivo):

**§8 (Imports) — añadir tras el párrafo del recovery estimate retirado:**

```
> **Estimated daily strain now persists (CARGA VIVA).** The Apple-only training-load path (ACWR) is fueled
> by an ESTIMATED daily strain scored from Apple workout HR by the pure `AppleLoadEstimator` (StrandAnalytics)
> and written into the existing `DailyMetric.strain` column under `apple-health` at ingestion (HealthKitBridge
> sync + AppleHealthImport). A quiet day (low steps/active-kcal, no HKWorkout) writes strain = 0 (real rest,
> decays the acute EWMA); an active day without a formal workout writes nil (NA — excluded, not zero); a
> workout day writes the TRIMP strain. No migration — the column already exists and, greenfield Apple-only,
> the band never writes it. The intraday «Carga del día» hero still reads the ephemeral midnight→now estimate
> (`Repository.appleStrainEstimates`); ACWR reads the persisted daily strain.
```

**§9 (Analytics), viñeta `StrainScorer`/`ReadinessEngine` — añadir línea:**

```
- **`ReadinessEngine` ACWR — EWMA-coupled (CARGA VIVA).** The acute:chronic workload ratio moved from rigid
  moving averages to a coupled EWMA (Williams et al. 2017, BJSM 51:209; λ_a=2/8, λ_c=2/29), fed the daily
  strain sequence with rest days folded as 0 (so it decays on rest) and missing days held (carry-forward).
  Bands 0.8/1.3/1.5 unchanged (Gabbett 2016). It is emitted only past a floor of REAL active days
  (strain>0), not calendar rows, so zero-fill can't trivialize the calibration gate. Descriptive only, never
  an injury predictor (Impellizzeri et al. 2020).
```

---

## RESUMEN (para el orquestador)

**Secuencia ordenada (compila al final de cada paso):**
1. Crear `AppleLoadEstimator` puro en StrandAnalytics (rest→0 / missing→NA / load→TRIMP) + tests. (`swift test`)
2. Migrar `ReadinessEngine` a ACWR EWMA acoplado + piso `minActiveDays` + reimplementar `acwrSeries`; re-derivar tests. (`swift test`)
3. Cablear la persistencia en `HealthKitBridge.sync` y `AppleHealthImport` → escribir `DailyMetric.strain` (0/valor/nil).
4. Verificar consumidores (Today/Cuerpo/RecoveryDetail/TrainingLoadSheet/DailyBrief/InsightEngine) — solo valores, sin firma.
5. `CenitUnitTests` end-to-end (days Apple → acwr != nil) + estado vacío honesto + F6 contract.
6. Gate `/cso` + `/estadistico` (fijan `RestThresholds` y `minActiveDays`) + `/qa`. Actualizar ARCHITECTURE.md.

**Dónde persiste el strain diario estimado:** en la columna **`DailyMetric.strain` existente**, partición
`apple-health`, escrita al ingerir (sync + import). **Sin migración** (columna libre en greenfield).

**Consumidores de EWMA:** ReadinessEngine(acwr/monotony/loadBand/acwrSeries) → TodayView, CuerpoView,
RecoveryDetailScreen, TrainingLoadSheet, DailyBrief, InsightEngine; StrainCeiling afectado-pero-dormido (guard recovery).

**3 riesgos:** (1) zero-fill trivializa `minChronic` → spike falso ⇒ piso de días activos reales;
(2) regresión del marco descriptivo ⇒ copy intacto + `/cso`; (3) regresión numérica + monotony ⇒ re-derivar
tests, preservar invariante `acwrSeries`.

**Ruta del sub-plan:** `/Users/fer.iracheta/code/noop/docs/_carga-viva-plan.md`
