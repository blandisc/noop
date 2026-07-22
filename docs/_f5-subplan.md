# Sub-plan técnico — F5 (épico «La banda nunca existió»)

> Arquitecto. Rama `claude/demolicion-banda-nunca-existio`. Fuente maestra: `docs/_demolicion-banda-plan.md`.
> F5 es UNA fase compile-válida (un commit verde). Este doc es el contrato que `/implement` ejecuta.
> Baseline verificado 2026-07-21: `StrandAnalytics` y `StrandDesign` compilan; con los 3 motores + sus
> 3 tests movidos fuera, `StrandAnalytics` **build y test-target compilan verde** (nada más los referencia).

## Resumen

F5 retira la **maquinaria de descomposición de la recuperación estilo WHOOP** — los motores
`RecoveryImpact` / `RecoveryRules` / `RecoveryChange` (StrandAnalytics), los componentes de dibujo
`ImpactRows` / `FiveRules` (StrandDesign) y los bloques de UI que los renderizan («Hoy, vs tu normal» y
«Qué cambió vs ayer» en RecoveryDetailScreen y MetricInfoSheet). **No toca** `RecoveryScorer`, el campo
`DailyMetric.recovery`, el héroe de recuperación, ni el read-model `SourceLens`/`keep:.band` (F6).

**El hallazgo central que resuelve el encargo:** en Apple-only el usuario **ya no ve ninguno de estos
bloques**. Desde que F4 borró `IntelligenceEngine`, nadie escribe `DailyMetric.recovery` en el path Apple,
así que `repo.today?.recovery == nil`; y los tres motores calculan **band-only** (dropean `appleHealthDays`
fila-completa, FER-519), por lo que `RecoveryImpact.compute` devuelve `nil` en un «hoy» Apple. Toda la UI
que los consume está detrás de `if let impact = …, !impact.signals.isEmpty` → **no renderiza**. Por tanto
**F5 es una demolición de código muerto-en-prod con CERO cambio visible** para el usuario Apple-only. No es
un rediseño: el reemplazo del héroe de recuperación es **FER-1030** (veredicto por ejes), fuera de F5.

Además, `RecoveryRules` (StrandAnalytics) y `FiveRulesView` (StrandDesign) **ya están muertos**: 0
llamadores de producción (solo tests + un comentario). La «curva intradía / cinco reglas» se retiró antes.

## Supuestos

- F1–F4 aplicadas en la rama (verificado: `IntelligenceEngine.swift` y `CircadianEngine.swift` no existen).
  **Observación fuera de alcance:** `usesWhoop` sigue presente en `Cenit/Data/Repository.swift` y
  `Packages/CenitStore/.../DashboardSnapshot.swift`, y `SourceLens.strapOnlyHistory` **no** está en
  SourceLens (solo un comentario lo menciona) → **F3 no aterrizó del todo**. F5 es **independiente** de eso
  (no toca `usesWhoop` ni `strapOnlyHistory`), pero conviene que el orquestador confirme el estado de F3/F4
  antes de cerrar el épico.
- Greenfield Apple-only: `DailyMetric.recovery == nil` en el path de producción; los 3 motores son band-only
  y devuelven `nil`/`[]` hoy.
- El colapso del read-model (`SourceLens.maskForBaseline`, `keep:.band`, la semántica SDNN↔RMSSD) es **F6** y
  **no se toca aquí**. El borrado del campo `DailyMetric.recovery` y del esquema es **F7**. El rediseño del
  héroe de recuperación es **FER-1030**.

---

## 1. Qué ve el usuario — HOY vs DESPUÉS

**HOY (Apple-only):**
- **Hoy:** sin número de recuperación (score `nil`). El bloque `autonomicTrendCardBlock`
  (`TodayView.swift:1167`, gate `repo.today?.recovery == nil`) muestra la **AutonomicTrendCard** («cómo
  vienes», RMSSD) + el bloque de **sueño de anoche**. Tocar la entrada de recuperación
  (`TodayView.swift:1568`) abre `MetricInfoSheet .recovery`, que muestra «—» / progreso de calibración +
  método; su `impactBlock` **no renderiza** (impact `nil`).
- **RecoveryDetailScreen** (abierta desde Hoy / Cuerpo / Entrenar): `heroFlat` con «—» + «No recovery yet…»
  (o el estado de calibración); los bloques «Hoy, vs tu normal» y «Qué cambió vs ayer» están **ocultos**
  (impact/change `nil`); Tendencia/Calendario **ocultos** (serie de recovery vacía).

**DESPUÉS de F5:** **visualmente idéntico.** Se borran ~1,900 LOC de maquinaria band-era que ya estaba
invisible. Intactos: `RecoveryScorer` (banda/calibración), la AutonomicTrendCard, el sueño, el héroe
`heroFlat`, el Panorama (carga/ACWR) y la calibración. Lo que reemplaza el «lugar» del número sigue siendo
lo que ya está hoy (tendencia autonómica + sueño); su rediseño formal es FER-1030.

---

## 2. Tabla símbolo/archivo → MUERE / VIVE / DIFERIR-a-F7

### StrandAnalytics (paquete puro)
| Símbolo / archivo | Acción | Nota |
|---|---|---|
| `RecoveryImpact.swift` (enum completo) | **MUERE** | Descomposición band-only «qué la movió». Consumidores solo en la UI que muere. |
| `RecoveryRules.swift` (enum completo) | **MUERE** | **Ya muerto en app** (0 callers de prod; solo tests + comentario de FiveRules). |
| `RecoveryChange.swift` (enum completo) | **MUERE** | Depende de `RecoveryImpact`; solo lo usa RecoveryDetailScreen. |
| `RecoveryScorer` (`recovery`/`band`/`calibrationNights`/`logisticK/Z0`/`wHRV…`/`bandYellowMax`/`bandRedMax`) | **VIVE** | Consumido por `ReadinessEngine`, `TrainingRegulation`, `DailyBrief`, el héroe de RecoveryDetail y la calibración de Hoy. **No tocar.** |
| `ReadinessEngine.Flag` + su color | **VIVE** | Usado en CuerpoView / TrainingLoadSheet / MetricInfoSheet / Panorama. |

### StrandDesign (sistema de diseño)
| Símbolo / archivo | Acción | Nota |
|---|---|---|
| `ImpactRows.swift` (`ImpactSignalRow`, `ImpactDivergentBar`, `ImpactAxisLegend`) | **MUERE** | Únicos consumidores = los bloques impact de RecoveryDetail + MetricInfoSheet (mueren). 0 uso intra-paquete (verificado). |
| `FiveRules.swift` (`FiveRulesView`) | **MUERE** | **Ya muerto** (0 callers en app; solo su `#Preview`). |

### App (Cenit)
| Símbolo / archivo:línea | Acción | Nota |
|---|---|---|
| `RecoveryDetailScreen.swift` — body `:100-105` (los 2 `seccion` de impact/change) | **MUERE** | Se borran las 2 invocaciones. |
| `…` `levelAttributionCard` `:276`, `levelHeadline` `:296`, `positionPhraseStandalone` `:324`, `levelSignalRow` `:334`, `levelLegend` `:349`, `driverName` `:357`, `driverLabel` `:369`, `baseBandWord` `:383`, `impactBarely` `:270` | **MUERE** | Solo los usa el bloque impact. |
| `…` `changeSinceYesterdayContent` `:396`, `signed` `:420`, `moverBare` `:423`, `moverUnitWord` `:428`, `impactBarely` (bloque 2b) | **MUERE** | Solo los usa el bloque change. `signed` no se usa en otro lado. |
| `…` model `impact` `:792` / `change` `:795` (props) + su cómputo en `build` `:881`,`:888-905` + los 2 args del init | **MUERE** | Cuidado: el cómputo de `bandDays`/readiness/load `:861-877` **VIVE** (F6). Cortar limpio: borrar `:879-905`, conservar `:861-877`. |
| `…` `flagColor` `:354` | **VIVE** | Lo usa el Panorama (`:465`). |
| `…` héroe (`heroField`/`heroFlat`/`bandColor`/`heroVerdict*`), Tendencia, Calendario, `hasPanorama`/`panoramaContent` `:447-451`, `calibrationBlock`, `forecast` | **VIVE** | Leen el campo dormido; retiro = F7 / FER-1030. |
| `…` `SourceLens.maskForBaseline(days, keep:.band, …)` `:861` | **VIVE (F6)** | **Frontera dura. No tocar.** |
| `MetricInfoSheet.swift` — `impactBlock` `:1180`, `impactHeadline` `:1204`, `impactRow` `:1220`, `baseBandWord` `:1237`, `positionPhrase` `:1245`, `impactLegend` `:1254`, `impactLabel` `:1259`, `impactFlag` `:1272`, `impactColor` `:1277`, `impactBarely` `:1173` + las 2 invocaciones `:191`,`:239` | **MUERE** | Todos son privados del bloque impact. |
| `MetricInfoSheet.swift` — `methodDisclosure`, `calibrationCard`, `levelsBlock`, `recoveryReading`, `recoveryZoneMeter`, `headlineText` | **VIVE** | La hoja de recuperación sigue (menos su impact). |
| `MetricInfoCatalog.swift` — `var impact: RecoveryImpact.Result? = nil` `:27`; param `impact:` `:514`; `impact: impact,` `:552` | **MUERE** | El resto del builder `.recovery` (headline/method/calibration/`levelsMetric:.recovery`) **VIVE**. `import StrandAnalytics` se queda (usa `MetricLevels`/`Baselines`). |
| `TodayView.swift` — `recoveryInfo` `:971-979`: el cómputo `todayImpact` `:973-974` + el arg `impact:` `:978` | **MUERE** | `recoveryInfo` sigue devolviendo `.recovery(score:calibrationNights:nightsNeeded:)`. |
| `TodayView.swift` — `recoveryScore` `:964`, entrada `:1568`, `autonomicTrendCardBlock` `:1167` | **VIVE** | El héroe/entrada son FER-1030; el fallback autonómico se queda. |

### Diferir a F7 (no F5)
| Símbolo | Nota |
|---|---|
| `DailyMetric.recovery` (campo) | Sigue `nil` en Apple-only; retirar el campo = F7 (esquema). Dejarlo `nil` **no rompe nada** (verificado: RepositoryMergeTests ya afirma `recovery == nil` en filas Apple). |
| `RecoveryForecast` (StrandAnalytics) + su bloque | Band-era dormido (lee `.recovery` → serie vacía → devuelve `nil`, gate limpio). Fuera del alcance de F5 (brief acota a Impact/Rules/Change). Barrer en F7. |
| Héroe de recuperación `/100` en RecoveryDetail + entrada en Hoy | Rediseño = **FER-1030**; retiro del número persistido = F7. |

---

## 3. Secuencia de edición ORDENADA (una fase, verde al final)

> Orden leaf-first: primero los consumidores de app (para que al borrar los motores no queden referencias),
> luego los motores de paquete, al final los componentes de diseño y los tests.

**A. App — quitar los bloques consumidores (deja de referenciar los 3 motores):**
1. `Cenit/Screens/TodayView.swift` `recoveryInfo`: borrar el cómputo `todayImpact` (`:973-974`) y el arg
   `impact: todayImpact` (`:978`). Queda `.recovery(score:calibrationNights:nightsNeeded:)`.
2. `Cenit/Screens/MetricInfoCatalog.swift`: borrar `var impact` (`:27`), el param `impact:` del builder
   `.recovery` (`:514`) y el arg `impact: impact,` (`:552`). Conservar `import StrandAnalytics`.
3. `Cenit/Screens/MetricInfoSheet.swift`: borrar los helpers del bloque impact (`impactBlock`,
   `impactHeadline`, `impactRow`, `baseBandWord`, `positionPhrase`, `impactLegend`, `impactLabel`,
   `impactFlag`, `impactColor`, `impactBarely`) y sus 2 invocaciones (`:191`, `:239`). No tocar `impactColor`
   -consumidores externos: `impactColor` es privado del bloque; el `ReadinessEngine.Flag.color` sí vive.
4. `Cenit/Screens/RecoveryDetailScreen.swift`:
   - body: borrar los 2 `seccion` de «Today, vs your normal» y «What changed since yesterday» (`:100-105`).
   - borrar los helpers del nivel/cambio (`levelAttributionCard`, `levelHeadline`, `positionPhraseStandalone`,
     `levelSignalRow`, `levelLegend`, `driverName`, `driverLabel`, `baseBandWord`, `changeSinceYesterdayContent`,
     `signed`, `moverBare`, `moverUnitWord`, `impactBarely`).
   - model: borrar las props `impact` (`:792`) y `change` (`:795`); en `build`, borrar el cómputo
     `let impact = …` y el bloque `let change: RecoveryChange.Result? = { … }()` (`:879-905`) y los 2 args del
     `RecoveryDetailModel(...)`. **Conservar intacto `:861-877`** (`bandDays`/readiness/load/heat/forecast).
   - **NO tocar** `flagColor` (`:354`, lo usa el Panorama), ni `SourceLens.maskForBaseline` (`:861`, F6).

**B. StrandAnalytics — borrar los motores (ya sin consumidor tras A):**
5. Borrar `RecoveryImpact.swift`, `RecoveryRules.swift`, `RecoveryChange.swift`.

**C. StrandDesign — borrar los componentes (ya sin consumidor tras A):**
6. Borrar `ImpactRows.swift`, `FiveRules.swift`.

**D. Tests (§4).**

**E. Verificar:** `swift build && swift test` de StrandAnalytics y `swift build` de StrandDesign (verdes).
El compile iOS completo (pasos A tocan `Cenit/**`) va **uno a la vez, máquina idle**
(`while pgrep -x xcodebuild XCBBuildService; do sleep 30; done`), nunca en paralelo (regla anti-OOM).

---

## 4. Tests: borrar / actualizar

| Test | Acción | Motivo |
|---|---|---|
| `Packages/StrandAnalytics/.../RecoveryImpactTests.swift` | **BORRAR** | El motor se borra. |
| `Packages/StrandAnalytics/.../RecoveryRulesTests.swift` | **BORRAR** | El motor se borra. |
| `Packages/StrandAnalytics/.../RecoveryChangeTests.swift` | **BORRAR** | El motor se borra. |
| `CenitUnitTests/RecoveryDetailModelTests.swift` | **BORRAR** | Todo el archivo prueba `model.impact` / `model.change` (ambos eliminados); no queda aserción viva. |
| `Packages/StrandAnalytics/.../RecoveryScorerTests.swift`, `RecoveryCalibrationTests.swift`, `ColdStartPriorTests.swift`, `ReadinessEngineTests.swift` | **SIN CAMBIO** | Prueban `RecoveryScorer`/`ReadinessEngine`, que **viven**. Verificado que compilan sin los 3 motores. |
| `CDOAuditRegressionTests` | **SIN CAMBIO** (confirmar) | El build del test-target de StrandAnalytics pasó sin los motores → no los referencia. |

**Verificado (prueba del diseño):** moví los 3 `Recovery{Impact,Rules,Change}.swift` + sus 3 tests fuera del
paquete → `swift build` **verde** y `swift build --build-tests` **verde** (ningún otro source/test los
referencia). Restaurado. Falta el compile iOS de la capa app (riesgo abierto, ver §5).

---

## 5. Riesgos (top 3) y frontera

- **Riesgo 1 — cruzar a F6 sin querer.** El cómputo `bandDays = SourceLens.maskForBaseline(days, keep:.band,
  appleDays:)` (`RecoveryDetailScreen.swift:861`) alimenta Panorama/carga y **vive**. Está a 18 líneas del
  bloque `change` que muere (también consume `appleHealthDays`). **Regla dura: el corte del modelo borra
  `:879-905` y CONSERVA `:861-877`.** No tocar `SourceLens`, `keep:.band`, ni la semántica SDNN↔RMSSD (F6,
  gate `/cso`+`/estadistico`). Mitiga el riesgo #1 del plan maestro (verdict corrupto por leer SDNN donde
  iba RMSSD).
- **Riesgo 2 — no corrí el compile iOS** (regla anti-OOM: sin `xcodebuild` en esta sesión). El type-check de
  `TodayView`/`MetricInfoSheet`/`MetricInfoCatalog`/`RecoveryDetailScreen` queda como **riesgo abierto para
  `/implement`**, que debe correr `xcodebuild … -jobs 4` con la máquina idle. Sí verifiqué que StrandAnalytics
  y StrandDesign compilan tras el borrado, y que no hay consumidores intra-paquete.
- **Riesgo 3 — confundir F5 con FER-1030 / F7.** Tentación de «terminar» retirando el héroe `/100`, la entrada
  de Hoy o el campo `DailyMetric.recovery`. **No.** El héroe es FER-1030; el campo/esquema es F7. F5 solo
  quita la maquinaria de descomposición (Impact/Rules/Change + ImpactRows/FiveRules + sus bloques). Si
  `/implement` cree que «falta algo visible», es señal de regresar a `/pm`, no de ampliar el alcance.

**Qué NO toca esta fase:** `RecoveryScorer`, `ReadinessEngine`, `RecoveryForecast`, `SourceLens`/`keep:.band`
(F6), `DailyMetric.recovery` y el esquema (F7), el héroe de recuperación y su entrada (FER-1030), la
AutonomicTrendCard y el sueño, `usesWhoop`/`strapOnlyHistory` (F3, aún pendiente aparte).

---

## 6. Criterios técnicos de aceptación (checklist de `/implement`)

- [ ] `Packages/StrandAnalytics/.../RecoveryImpact.swift`, `RecoveryRules.swift`, `RecoveryChange.swift` NO existen.
- [ ] `Packages/StrandDesign/.../ImpactRows.swift`, `FiveRules.swift` NO existen.
- [ ] `grep -rn "RecoveryImpact\|RecoveryRules\|RecoveryChange" --include=*.swift Cenit CenitApp CenitUnitTests Packages` (excluyendo los archivos borrados) → **0** en código; **0** comentarios residuales.
- [ ] `grep -rn "ImpactSignalRow\|ImpactDivergentBar\|ImpactAxisLegend\|FiveRulesView" --include=*.swift .` → **0**.
- [ ] `MetricInfo` ya no tiene el campo `impact`; el builder `.recovery` ya no recibe `impact:`.
- [ ] `RecoveryDetailModel` ya no tiene props `impact`/`change`; su `build` conserva `bandDays`/`readiness`/`load`/`heat`/`forecast` (`git diff` sobre `:861-877` = vacío).
- [ ] `RecoveryScorer.swift` sin cambios (`git diff` vacío). `SourceLens.swift` sin cambios (F6 intacto).
- [ ] `DailyMetric.recovery` sigue existiendo (F7).
- [ ] Tests borrados: `RecoveryImpactTests`, `RecoveryRulesTests`, `RecoveryChangeTests`, `RecoveryDetailModelTests`.
- [ ] `cd Packages/StrandAnalytics && swift build && swift test` → **verde**. `cd Packages/StrandDesign && swift build` → **verde**.
- [ ] `xcodebuild -project Cenit.xcodeproj -scheme Cenit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -jobs 4 build` → **compila** (máquina idle, uno a la vez).
- [ ] En el Simulador/dispositivo Apple-only: RecoveryDetail y la hoja de recuperación se ven **idénticas** a antes (los bloques impact/change ya estaban ocultos); no aparece ningún hueco ni layout roto.

---

## 7. Actualización de docs/ARCHITECTURE.md

**Sin cambios de arquitectura que documentar.** `docs/ARCHITECTURE.md` no menciona `RecoveryImpact`/
`RecoveryRules`/`RecoveryChange`/`ImpactRows`/`FiveRules` (grep = 0). El barrido de copy/docs residual es F8.
Si `/implement` encuentra una referencia a estos motores en cualquier doc, la quita en el mismo PR.
