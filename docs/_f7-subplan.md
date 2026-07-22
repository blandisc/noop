# Diseño técnico — F7: esquema greenfield v1 + naming `strap`→`apple`

> Sub-plan de la Fase 7 del épico «la banda nunca existió». Fuente de verdad del épico:
> `docs/_demolicion-banda-plan.md`. F1–F6 YA están DONE y committeadas en
> `claude/demolicion-banda-nunca-existio`. Este doc es diseño técnico (arquitecto), NO
> implementación. Cada afirmación de código está verificada contra el árbol actual.

## Resumen

Dos cambios de fondo, un solo PR pesado sobre `Packages/CenitStore` + capa app:

1. **Esquema:** colapsar la cadena `v1…v36` a **una sola migración `v1` Apple-only** (solo las
   tablas vivas, sin tablas de streams crudos de banda) y activar
   `migrator.eraseDatabaseOnSchemaChange = true`. Un install con esquema viejo → GRDB **recrea
   la DB vacía** (no intenta migrar, no crashea); el dato Apple regresa por re-sync de HealthKit;
   el dato del usuario (fuerza/dieta/journal) se pierde a propósito (premisa greenfield del dueño).
2. **Naming:** renombrar la partición literal **`"strap"` → `"apple"`** (id de dato, no hardware) y
   los símbolos/campos `strap*`. NO se elimina la noción de `deviceId`: sigue viva y load-bearing
   (separa dato importado de dato **computado on-device** vía el sufijo `-noop`).

## Supuestos

- **Greenfield real:** usuario nuevo, cero preservación. El dueño relajó explícitamente la regla
  dura «migrations append-only» *para este reset v1*. Después de v1 se **vuelve** a append-only.
- La SQLite es un **caché reconstruible** de HealthKit para las métricas Apple; pero
  fuerza/dieta/journal/rutinas **NO** están en HealthKit → un erase los pierde. Aceptable bajo la
  premisa greenfield pre-App-Store; se marca como riesgo/decisión del dueño abajo.
- GRDB 6 (`from: "6.0.0"`, confirmado en `Package.swift`) soporta `eraseDatabaseOnSchemaChange`
  (verificado en `.build/checkouts/GRDB.swift/GRDB/Migration/DatabaseMigrator.swift:105,409`).
- `hrSample` y `rrInterval` **están vivas**: `HealthKitBridge.swift:473` escribe HR de workout
  (`store.insert(Streams(hr:), deviceId: appleDeviceId)`) y el RR nocturno Apple (RMSSD, línea
  ~1009). Se leen en `Repository.hrSamples/rrIntervals` y `Repository.swift:392`.
- Las tablas de streams crudos de banda (`event`, `battery`, `spo2Sample`, `skinTempSample`,
  `respSample`, `gravitySample`, `stepSample`) **no tienen consumidor vivo con dato real**:
  `Repository.nocturnalWarmingMagnitudes()` ya retorna `[]` (FER-1003), `skinTempSamples`/
  `gravitySamples` son dormantes, la termoestabilidad y la forma nocturna se alimentan de valores
  **diarios de Apple** (`dailyMetric.skinTempDevC`, HR nadir), no de estas tablas crudas.
- `CenitStore` compila verde en baseline (`swift build` → `Build complete! 1.70s`, corrido hoy).

## Dónde vive

| Capa | Archivo(s) | Qué cambia |
|---|---|---|
| Paquete `CenitStore` (core) | `Sources/CenitStore/Database.swift` | Reescribir `makeMigrator()` a un solo `v1` + `eraseDatabaseOnSchemaChange`; borrar `renameDevicePartition`. |
| Paquete `CenitStore` (core) | `StreamStore.swift`, `Reads.swift`, `RawOutbox.swift`, `CircadianPhaseStore.swift`, `CenitStore.swift` | Quitar métodos que tocan tablas muertas (limpieza de honestidad; SQL en string ⇒ runtime-safe). |
| Paquete `CenitStore` (tests) | `Tests/CenitStoreTests/MigrationTests.swift` (+ `StoreBackendTests`, `DashboardSnapshotTests`, `StepSampleTests`) | Reescribir: se van los tests de v5/v15…v36/v21-rebuild/v36-rename; entran tests de v1-Apple-only + erase-on-mismatch. |
| App | `Cenit/App/AppModel.swift` | `let deviceId = "apple"` (era `"strap"`) — **fuente única** de la partición base. |
| App | `Cenit/Data/MetricCatalog.swift`, `MetricDetailSpec.swift`, `Cenit/Screens/TodayView.swift`, `CuerpoView.swift`, `ScreenshotFixtures.swift`, `Cenit/Data/DashboardSnapshot`(campo) | Literal `"strap"` de partición → `"apple"` **en lockstep** (ver «Naming» abajo). |

**Contratos públicos que cambian:**
- `CenitStoreInfo.schemaVersion` pasa de `36` a `1` (es derivado de `migrations.count`, no manual —
  no hay que tocar constante; sí hay que actualizar el test que lo fija en 36).
- Se **borra** el símbolo público `CenitStore.renameDevicePartition(_:from:to:)` (solo lo usaba v36 +
  su test).
- Se borran métodos públicos de `Reads`/`StreamStore` de streams muertos (ver lista). Ningún caller
  vivo los consume con expectativa de dato → seguro.

## Diseño

### Decisión 1 — Esquema: COLAPSAR a `v1` (recomendado) vs dejar dormido

**Recomendación: COLAPSAR a un solo `v1` Apple-only + `eraseDatabaseOnSchemaChange = true`.**

Por qué colapsar y no «dejar tablas dormidas + reset»:
- El dueño pidió «como si la banda nunca hubiera existido». Una cadena `v1…v36` con 8 tablas de
  streams de banda + `deviceIdMap` + `renameDevicePartition('my-whoop'→'strap')` es exactamente lo
  contrario: es el fósil de la banda. Colapsar deja el esquema honesto.
- **`eraseDatabaseOnSchemaChange` ES el mecanismo GRDB-nativo, battle-tested, para justo esto**: al
  abrir, si las migraciones grabadas en `grdb_migrations` no son un prefijo de las registradas
  (aquí: la DB vieja tiene `v1…v36`, el migrador nuevo solo tiene un `v1` con cuerpo distinto),
  GRDB **borra el archivo y re-corre desde cero** — no intenta migrar, no puede crashear por
  esquema incompatible. Es la mitigación #3 del plan maestro, implementada por la librería.
- Alternativa (dormido + reset manual): mantener las 36 migraciones y añadir un `v37` que dropee las
  tablas de banda. Descartada: (a) sigue arrastrando la historia de banda en el código; (b) no honra
  greenfield; (c) más superficie (36 migraciones + drops) que un `v1` limpio; (d) no resuelve el
  arranque sobre un esquema roto tan limpio como el erase.

**Manejo del arranque sin crash (el punto crítico):**
- Fresh install (sin archivo): `v1` corre, esquema limpio Apple-only. 
- Install con DB vieja (`v1…v36` grabadas): `migrate()` detecta el mismatch → como
  `eraseDatabaseOnSchemaChange = true`, **borra `.sqlite`/`-wal`/`-shm` y re-corre `v1`**. Cero
  intento de migrar el esquema viejo → cero «duplicate column»/«no such table»/rollback wedge.
  Las métricas Apple vuelven por re-sync de HealthKit en el primer arranque.
- Se preserva el patrón actual de apertura intacto: `CenitStore.init` sigue llamando
  `makeMigrator().migrate(dbWriter)` (`CenitStore.swift:42`); el WAL/PRAGMAs de `prepareDatabase`
  no cambian. `eraseDatabaseOnSchemaChange` opera *dentro* de `migrate()`.

**`v1` crea EXACTAMENTE el estado final de las tablas vivas** (misma forma de columna que hoy tras
v1…v36), para minimizar blast radius: `StreamStore`/`Reads`/`CenitStore.resolvedDeviceId` siguen
viendo `hrSample`/`rrInterval` como INTEGER-surrogate WITHOUT ROWID + `deviceIdMap`, así que su
código **no cambia**. Se mantiene `deviceIdMap` (es una optimización de clave de partición, no algo
de banda) creado **vacío** — la primera escritura de la partición `"apple"` inserta su mapping on
demand (`resolvedDeviceId(createIfMissing:true)`); no hace falta el «floor insert» de v21.

### Tabla — qué MUERE vs qué VIVE (en `v1`)

| Tabla | Estado | Razón |
|---|---|---|
| `deviceIdMap` | **VIVE** (vacía) | surrogate de partición (v21), no banda; mantiene `hrSample`/`rrInterval` sin tocar su lectura. |
| `hrSample` (INT deviceId, WITHOUT ROWID, STRICT) | **VIVE** | HR de workout Apple (`HealthKitBridge:473`). |
| `rrInterval` (INT deviceId, WITHOUT ROWID, STRICT) | **VIVE** | RR nocturno Apple → RMSSD (`apple_rmssd_night`). |
| `dailyMetric` (columnas finales v4+v7+v11+v32) | **VIVE** | métricas diarias; incl. `skinTempDevC`/`respRateBpm`/`spo2Pct`/`steps`/`activeKcalEst`/`recovery`/`strain`/`effortConfidence`/`restConfidence` (columnas Apple, **no** las tablas de streams crudos). |
| `metricSeries` + `idx_metricSeries_device_key_day` | **VIVE** | `apple_rmssd_night`, computados. |
| `sleepSession` | **VIVE** | sueño. |
| `journal` | **VIVE** | prompts diarios usuario. |
| `workout` | **VIVE** | workouts (Apple + detectados). |
| `appleDaily` | **VIVE** | agregados diarios Apple. |
| `cursors` | **VIVE** | flags one-time (VACUUM gate en `AppModel+Maintenance`). |
| `experiment` | **VIVE** | N-of-1. |
| `dietPlan`, `dietAdherence` (incl. `optionIndex`) | **VIVE** | dieta. |
| `customExercise`(+`bodyParts`/`gifUrl`), `routine`(+`folderId`), `routineExercise`(+`supersetGroup`/`hrRest*`/`progression*`/`progressionIgnoreRecovery`), `strengthSession`(+`energyKcal`/`energySource`), `setEntry`(+`rpe`), `personalRecord`, `routineSet`(+`rest*`), `routineFolder`, `routineSchedule`, `learnedExerciseAlias`, `exerciseTypeOverride`, `progressionOptOut`, `strengthExerciseNote`, `inProgressStrengthSession` | **VIVE** | dominio fuerza/rutinas. |
| `device` | **MUERE** | registro de banda (mac/firstSeen/lastSeen). Ver limpieza `upsertDevice`. |
| `event` | **MUERE** | eventos de banda. |
| `battery` | **MUERE** | batería de banda. |
| `rawBatch` | **MUERE** | outbox de frames crudos (RawOutbox). |
| `spo2Sample` | **MUERE** | ADC crudo, nunca leído (ya vaciado en v20). |
| `skinTempSample` | **MUERE** | stream crudo de banda; la **columna diaria** `dailyMetric.skinTempDevC` (Apple) vive. |
| `respSample` | **MUERE** | stream crudo; columna diaria `respRateBpm` (Apple) vive. |
| `gravitySample` | **MUERE** | acelerómetro de banda. |
| `stepSample` | **MUERE** | contador de pasos de banda; pasos Apple viven en `dailyMetric.steps`/`appleDaily.steps`. |
| `circadianPhase` | **MUERE** | cosinor del acelerómetro; `CircadianEngine` murió en F4, pantallas en F2. |

> **Nota `dailyMetric.recovery`:** la COLUMNA se mantiene (REAL nullable, inofensiva). F5 retiró el
> *número* 0-100 y `RecoveryImpact`; verificar en `/implement` si algún escritor la sigue poblando.
> Dropearla es limpieza opcional, no F7 — no vale el riesgo de dejar un writer huérfano.

### Decisión 2 — `deviceId = "strap"`: RENOMBRAR a `"apple"`, NO eliminar

Verificado: `deviceId` **no es cruft de banda vestigial**, es una clave de partición viva que
separa tres orígenes:
- `"strap"` (`AppModel.deviceId`, pasado como `noopDeviceId`): base import+computado. **→ `"apple"`**.
- `"strap-noop"` (`Repository.computedDeviceId = deviceId + "-noop"`): métricas **computadas
  on-device** (metricSeries + workouts detectados). **→ `"apple-noop"` automático** (derivado, sin
  cambio de código).
- `"apple-health"` (`AppModel.appleDeviceId`) y `"apple-health-noop"`: partición Apple separada. **Ya
  limpia, NO se toca.**

Eliminar `deviceId` colapsaría la separación import/computado (`-noop`) — eso es un cambio de
read-model tamaño F6, NO un renombre. **Fuera de alcance de F7.** Recomendación: renombrar el
literal, conservar el mecanismo.

> Matiz honesto para el dueño: tras el renombre coexisten `"apple"` (base) y `"apple-health"`
> (import Apple crudo) como dos particiones «apple». Es correcto (siempre fueron distintas; solo la
> etiqueta de la base era de banda). Renombrar la base a algo como `"cenit"` en vez de `"apple"`
> evitaría la ambigüedad conceptual — decisión de nombre para el dueño. El plan asume `"apple"`.

### Naming `strap` → `apple`: sitios concretos

**Tier 1 — LOCKSTEP obligatorio (correctitud de ruteo de dato; un sitio olvidado = lecturas vacías
en silencio, patrón FER-519/629).** El literal `"strap"` como id de partición debe moverse junto:

- `Cenit/App/AppModel.swift:25` — `let deviceId = "strap"` → `"apple"` (**fuente**).
- `Cenit/App/AppModel.swift:146` — `Repository(deviceId: "strap")` → usar la var `deviceId`
  (idealmente `Repository(deviceId: deviceId)` para eliminar el segundo literal).
- `Cenit/Screens/TodayView.swift:2439` — `series(key:"stress", source:"strap")` → `"apple"`.
- `Cenit/Screens/CuerpoView.swift:1285` — idem.
- `Cenit/Data/MetricDetailSpec.swift:191, 240` — `source: "strap"` → `"apple"`.
- `Cenit/Data/MetricCatalog.swift` — ~34 entradas con columna `source` = `"strap"` (avg_hr, max_hr,
  energy_kcal, recovery, hrv, rhr, resp_rate, spo2, skin_temp, sleep_*, strain, hr_zones*,
  strength_min, stress, …). **VERIFICAR primero** si `MetricCatalog.source` se usa como partición de
  lectura (`Repository.series(source:)`) o solo como etiqueta de agrupación de display. Si es
  partición → renombre lockstep obligatorio. Si es solo label → sigue siendo deseable por honestidad,
  riesgo bajo. (Esta verificación es un paso del secuenciado, no un supuesto.)
- `Cenit/App/ScreenshotFixtures.swift:338` — `journalDeviceId = "strap"` → `"apple"` (+ `:197` ya usa
  `model.deviceId`, hereda el cambio).

**Tier 2 — símbolos/campos/copy (renombre puro, riesgo bajo, mismo PR):**
- `Packages/CenitStore/Sources/CenitStore/DashboardSnapshot.swift:16` — campo `strapDeviceId`
  → `appleDeviceId` (su VALOR viene del caller `Repository.swift:345`; renombre cosmético).
- `Cenit/Data/Repository.swift` — vars locales `strapDeviceId`, `strapSleeps`, `strapDays`,
  `computedDeviceId` (comentarios «strap»), `storedStrapDays` (`DataSourcesView.swift:533`).
- `Cenit/Screens/SleepDetailScreen.swift:1386,1421` — `latestStrapNight`, `strapSessions` (vars).
- `Cenit/Screens/TodayView.swift:295,2492`, `CuerpoView.swift:37`, `MetricDetailScreen.swift:24` —
  vars/comentarios `strapHrv`, `bandDays`, notas «series("strap")».
- Comentarios internos con «strap»/«my-whoop» en `CenitStore.swift:37`, `WorkoutSource.swift:34`,
  `DailyStressModel.swift:11`, `Reads.swift`, `StreamStore.swift`: reescribir los que un lector del
  código encontraría engañosos; **no** churn gratis en cada mención.
- **Copy visible es-MX** (`Cenit/Resources/Localizable.xcstrings`, ~259 hits «strap»/«banda»/WHOOP):
  el barrido de copy residual visible es **F8** («docs + copy final») por el plan maestro. F7 toca
  solo el copy visible que sea *un id de dato disfrazado* (no hay ninguno confirmado). Dejar el
  barrido de strings es-MX a F8 evita colisión de dos fases sobre el mismo `.xcstrings`.

### Limpieza de código huérfano (mismo PR, honestidad greenfield)

SQL vive en string literals ⇒ dropear una tabla **no** rompe el compile de código que la consulta
(falla en runtime, y todo caller vivo ya va por `try?` → `[]`). Por eso estos borrados son
**seguros y leaf-first**; se hacen por honestidad, no por compile:

- `StreamStore.swift`: quitar `upsertDevice`, `deviceRowForTest`, las ramas `INSERT INTO
  event/battery/skinTempSample/respSample/gravitySample/stepSample` dentro de `insert()` (las de
  `hrSample`/`rrInterval` se quedan), `storageStats_rowCountsForTest`, `stepCountForTest`,
  `sampleCounts`.
- `Reads.swift`: quitar `events`, `batterySamples`, `spo2Samples`, `skinTempSamples`, `stepSamples`,
  `respSamples`, `gravitySamples`, `storageStats`, `streamDayCounts` (verificar cada uno sin caller
  vivo con dato real primero).
- `RawOutbox.swift`: retirar (outbox de `rawBatch`, muerto).
- `CircadianPhaseStore.swift` + `Repository.latestCircadianPhase` + su caller (dormante): retirar
  transitivamente, o dejar retornando `nil` si el caller aún compila — decidir en `/implement`.
- `CenitStore.swift:242` (`Repository`): borrar `try? await s.upsertDevice(id: deviceId, name:
  "Historial de banda")`.
- `Cenit/Data/Repository.swift:653,677`: `skinTempSamples`/`gravitySamples` (dormantes) → retirar.

> Regla de corte: si retirar un método obliga a tocar >1 caller vivo, se deja dormido (retorna `[]`)
> y se anota; F7 no debe convertirse en un refactor de read-model. La meta dura es: **compila al
> final + esquema honesto**, no cero-líneas-muertas.

### Migración

`v1` (única) — append-only ya no aplica *dentro* de F7 (reset greenfield autorizado por el dueño).
Contenido: `CREATE` de todas las tablas VIVAS en su forma final (arriba). `MigrationTests` nuevo la
cubre. `migrator.eraseDatabaseOnSchemaChange = true`.

### Concurrencia

Sin cambios. `CenitStore` sigue siendo `actor`; `migrate()` corre en `init` sobre el executor del
actor. `eraseDatabaseOnSchemaChange` opera dentro de `migrate()` sobre el `DatabaseWriter` — mismo
isolation domain. La partición base es un literal en `@MainActor AppModel`; su cambio no toca
isolation.

## Validación contra reglas duras

- **Offline only:** N/A al cambio; el reset re-sincroniza de **HealthKit local**, cero red. ✅
- **BLE no destructivo / CRC:** N/A — F7 *elimina* el rastro de banda del esquema; no toca
  `WhoopProtocol` (ya borrado en F1) ni emite bytes. ✅
- **Pureza de paquetes:** `CenitStore` sigue Foundation+GRDB, sin UIKit/CoreBluetooth. El cambio no
  introduce imports de framework. ✅
- **Migraciones append-only:** **relajada a propósito por el dueño** solo para este reset v1
  (documentado en el plan maestro y en Supuestos). Se **restaura** para todo lo posterior a v1 (ver
  Riesgo 1). ✅ (con la nota).
- **Decoded-first durability:** N/A — se elimina el path raw (`rawBatch`/RawOutbox); ya no hay raw
  que encolar. Lo decodificado (`hrSample`/`rrInterval`/`dailyMetric`) sigue siendo la fuente. ✅
- **Math transparente:** N/A — F7 no toca analítica. El único riesgo matemático (leer SDNN donde va
  RMSSD) lo blindó F6; F7 **no** re-abre ese read-model (solo renombra el literal de partición). ✅

## Pruebas (invariantes) — `MigrationTests` reescrito

- **Fresh install produce el esquema Apple-only exacto** → test: `tableNames()` == conjunto VIVO;
  ninguna de {device,event,battery,rawBatch,spo2Sample,skinTempSample,respSample,gravitySample,
  stepSample,circadianPhase} presente. [corrido: ⬜ diseño]
- **`schemaVersion == 1`, `latestMigration == "v1"`** (reemplaza el assert de 36). [⬜]
- **`hrSample`/`rrInterval` quedan WITHOUT ROWID + INTEGER deviceId + `deviceIdMap` existe vacío** →
  test `sqlite_master` contiene `WITHOUT ROWID`; `deviceIdMap` count == 0 en fresh. [⬜]
- **erase-on-mismatch:** abrir una DB sembrada con un migrador viejo (registrar un `v1` distinto +
  `v2` dummy) y luego migrar con el migrador nuevo → la DB se recrea, esquema nuevo, sin throw.
  (GRDB ya lo prueba en su suite; aquí un test de humo sobre `makeMigrator()`.) [⬜]
- **Round-trip de escritura on-demand del surrogate** para partición `"apple"` (adaptar
  `testV21StringApiRoundTripAndOnDemandMapping`). [⬜]
- **No-regresión de ruteo (naming):** un test app-layer/o de fixture que escribe bajo
  `AppModel.deviceId` y lee vía `MetricCatalog.source`/`series(source:)` y obtiene los mismos datos
  — prueba que el literal está en lockstep (evita la lectura vacía). [⬜]
- **Baseline anclado:** `swift build` de `CenitStore` verde HOY (pre-F7). [corrido: ✅]

> Tests a BORRAR (prueban esquema/máquina muertos): `testMigratorRegistersContiguousVersions`
> (assert 36/v36), `testV5AddsSyncedColumn`, `testV20*`, `testV21*` (rebuild/atomic/vacuum),
> `testV23/24/25/29/31*`, `testV36*` (rename), `testV15/16/17/18*` … se reemplazan por asserts de
> propiedad final del `v1` (PKs, columnas presentes), no por asserts de deltas de migración.

## Alternativas y riesgos

**Alternativas evaluadas:**
- *Dejar `v1…v36` + un `v37` que dropee las tablas de banda (dormido → reset).* Descartada: arrastra
  la historia de banda, no honra greenfield, más superficie, no resuelve el arranque sobre esquema
  roto tan limpio como el erase.
- *Eliminar `deviceId` por completo.* Descartada: es un cambio de read-model (colapsa el split
  import/computado `-noop`), tamaño F6, fuera de alcance; alto riesgo de ruteo silencioso.
- *Simplificar `hrSample`/`rrInterval` a TEXT deviceId + borrar `deviceIdMap`/`resolvedDeviceId`.*
  Descartada para F7: toca `StreamStore`/`Reads`/`CenitStore` (más blast radius) sin beneficio real
  bajo volumen Apple; se mantiene el surrogate intacto.

**Riesgos (top 3):**
1. **`eraseDatabaseOnSchemaChange=true` en producción pierde dato NO-recuperable de HealthKit**
   (fuerza/dieta/journal/rutinas) si un futuro cambio redefine/edita `v1`. Para el ship greenfield
   pre-App-Store es aceptable (usuario nuevo). **Mitigación/recomendación:** (a) tras v1, restaurar
   estricto append-only (v2, v3…) — añadir migraciones NO dispara el erase, solo lo dispara editar/
   reordenar `v1`; (b) decisión del dueño: si se quiere blindar a usuarios reales desde ya, poner el
   flag `false` después de v1 y confiar en que v1 es la línea base. Marcar como decisión abierta.
2. **Dropear una tabla que resulte viva.** Verificado que las 9 tablas muertas no tienen consumidor
   con dato real (thermal/nocturnal leen columnas diarias de Apple; readers crudos son dormantes/`[]`).
   **Mitigación:** `swift test` del nuevo `MigrationTests` + grep de callers antes de cada borrado;
   la lista MUERE/VIVE de arriba es el contrato. Si aparece un caller vivo, la tabla se queda.
3. **Naming fuera de lockstep** → una parte lee `"apple"` y otra `"strap"` → verdict/serie vacía en
   silencio (clase FER-519/629). **Mitigación:** verificar la semántica de `MetricCatalog.source`
   antes del renombre masivo; test de no-regresión de ruteo; cambiar `AppModel.deviceId` y todos los
   literales `"strap"` de dato en el MISMO commit.

**Riesgo abierto (honestidad):** no corrí `swift test` de `CenitStore` (la suite actual prueba el
esquema viejo que F7 reescribe; sería ruido). Solo anclé `swift build` verde. El diseño del nuevo
`v1` + `MigrationTests` queda por probar en `/implement`. El compile de la capa app (Cenit) tras el
renombre requiere `xcodebuild` (no corrido: regla anti-OOM) — verificar en `/implement` con la
máquina idle.

## Criterios técnicos de aceptación (checklist de `/implement`)

- [ ] `makeMigrator()` registra **exactamente una** migración `"v1"`; `CenitStoreInfo.schemaVersion == 1`.
- [ ] `migrator.eraseDatabaseOnSchemaChange == true`.
- [ ] `tableNames()` sobre fresh install == conjunto VIVO; **cero** tablas de la columna MUERE.
- [ ] `hrSample`/`rrInterval` son `WITHOUT ROWID` con `deviceId` INTEGER; `deviceIdMap` existe y está vacío en fresh.
- [ ] Abrir sobre una DB con migraciones viejas grabadas **recrea** la DB sin throw (test de humo del erase).
- [ ] `CenitStore.renameDevicePartition` y todos los tests `testV36*`/`testV21*` de rebuild/rename **eliminados**; nuevo `MigrationTests` verde.
- [ ] `AppModel.deviceId == "apple"`; **cero** literal `"strap"` como id de dato en `Cenit/`/`CenitApp/` (grep `'"strap"'` no arroja ids de partición; solo comentarios permitidos si los hay).
- [ ] `MetricCatalog`/`MetricDetailSpec`/`TodayView`/`CuerpoView` usan `"apple"` (o la var derivada) coherente con `AppModel.deviceId`; test de no-regresión de ruteo verde.
- [ ] `swift build && swift test` de `CenitStore` verde.
- [ ] Compile iOS completo verde (máquina idle, `-jobs 4`), app arranca en un install limpio Y sobre un install con DB vieja (erase-and-resync), sin crash.
- [ ] Métricas Apple (RMSSD nocturno, sueño, pasos, temp piel) reaparecen tras re-sync en el arranque post-erase.

## Actualización de docs/ARCHITECTURE.md

Sí toca el doc (el esquema es parte del mapa). Diff propuesto (a aplicar por `/implement`):
- Sección de esquema/almacenamiento: reemplazar la narrativa de «cadena v1…v36 + tablas de streams
  crudos de banda + `deviceIdMap`/v21 rebuild + v36 relabel `my-whoop`→`strap`» por: **«esquema
  greenfield `v1` Apple-only; `eraseDatabaseOnSchemaChange` recrea la DB en mismatch y re-sincroniza
  de HealthKit; sin tablas de streams crudos de banda (las columnas diarias Apple viven en
  `dailyMetric`); partición base `"apple"` (+ `-noop` computado), `deviceIdMap` conservado como
  surrogate de partición».**
- Retirar cualquier mención viva a `WhoopProtocol`/streams de banda en el path de almacenamiento
  (coordinar con F8, que ya reescribió gran parte de los docs — evitar doble edición del mismo
  párrafo; F7 solo el bloque de esquema/DB).
- `docs/DATA_MODEL.md`: actualizar la tabla de tablas a la lista VIVA de arriba; marcar las 9 tablas
  retiradas.
