# Plan de demolición — «La banda nunca existió» (greenfield Apple-only)

> Estado: GO. Decisiones del dueño cerradas 2026-07-21. Rama: `claude/demolicion-banda-nunca-existio`.
> Este doc es la fuente de verdad del épico. Cada fase compila y se commitea sola.

## Premisa
Llevar Cénit a un mundo greenfield donde la banda WHOOP **nunca existió**. Usuario **nuevo** que jamás tuvo la versión anterior → **cero preservación de datos**, esquema DB v1 limpio Apple-only. Sin ETL, sin migraciones append-only, sin reset legacy.

## Decisiones cerradas del dueño
1. Demolición TOTAL de la banda (código + UX + esquema).
2. Retirar el número de **recuperación 0-100** estilo WHOOP y sus bloques fantasma. La **tendencia autonómica (RMSSD)** y el sueño se quedan.
3. Retirar **reloj corporal** y **plan de viaje / jet-lag** (perdían su sensor: el acelerómetro de la banda; Apple no lo da).
4. Usuario nuevo, greenfield, sin preservar fuerza/rutinas/dieta/journal.

## SE QUEDA VIVO (no romper — verificado en código)
- `BiometricStreams` — vocabulario del camino Apple (HRSample/RRInterval/Streams: HR de workout + RR nocturna).
- `StrainScorer` — vivo vía sesión de fuerza (AppModel+Strength).
- `RecoveryScorer.calibrationNights` y `tanakaHRmax` — independientes del número retirado.
- RMSSD nocturno (FER-1008), tendencia autonómica (AutonomicTrend/ReadinessEngine).
- Body Age / Fitness Age — tienen coverage-gate, corren con Apple.
- `ThermalStabilityEngine` ← `appleSleepingWristTemperature` (Apple) → SkinTempDetailScreen. **VIVE.**
- `NightAutonomicShape` ← HR nadir de Apple → SleepDetailScreen. **VIVE.**
- `NocturnalDC` ← RR nocturno de Apple → SleepDetailScreen. **VIVE.**

## MUERE
- `Packages/WhoopProtocol` — paquete completo (57 archivos, 0 imports, no linkeado).
- `IntelligenceEngine` (879 LOC, no-op en prod).
- `CircadianEngine` + `StepsEstimateEngine` (+ pantallas RelojCorporalSheet, PlanViajeSheet, JetLagPlanStore). Steps de Apple son reales → estimador redundante.
- Número recuperación 0-100: `RecoveryImpact` (+ Rules/Change/ImpactRows) y sus bloques en TodayView.
- `DataSourceMode` / `usesWhoop` / `SourceModeStore` → colapsar a la única realidad Apple.
- `SourceLens` / `SourceFusion` multi-fuente / `keep:.band` → lectura Apple directa. **Zona delicada: no reintroducir FER-519/629 (leer SDNN donde iba RMSSD).**
- Naming `strap`→`apple` (greenfield: incluye ids/esquema, no solo copy).
- Esquema DB → v1 limpio: sin tablas de streams crudos de banda (gravity, skinTemp raw, resp raw, spo2 raw, step raw, event, battery, rawBatch/RawOutbox). OJO: skinTemp/resp/spo2/steps siguen VIVAS como **columnas diarias de DailyMetric** alimentadas por Apple — muere la tabla de streams crudos, NO la columna.
- Importador WHOOP CSV (según auditoría ya borrado — verificar).
- Docs: ARCHITECTURE.md, README.md, BUILD.md, CLAUDE.md.

## FASES (leaf-first; cada una compila y se commitea)
- **F0 — Baseline verde:** `swift build && swift test` por paquete tocado; anotar estado antes de cortar.
- **F1 — Eliminar `WhoopProtocol`:** rm paquete + refs en project.yml/Package.swift. Verificar 0 imports. (Casi cero riesgo.)
- **F2 — Retirar SOLO las pantallas** reloj corporal + plan de viaje (RelojCorporalSheet, PlanViajeSheet, JetLagPlanStore + entradas en AjustesView + wiring en AppModel). **NO tocar los motores aquí:** Swift type-checkea el cuerpo de `IntelligenceEngine.analyzeRecent` completo aunque el `guard usesWhoop` (línea 209) lo haga inalcanzable en runtime — borrar `CircadianEngine`/`StepsEstimateEngine` rompe el compile hasta que muera IntelligenceEngine. F2 = solo UI/nav → compila. (Ajuste post-adversarial Grok.)
- **F3 — Colapsar `DataSourceMode`/`usesWhoop`/`SourceModeStore` a Apple.** ALINEADA con F4: `usesWhoop` vive dentro de `IntelligenceEngine.swift:209` y `AppModel+Analysis.swift:53` → van juntas, o F3 fija un pin Apple explícito que F4 remueve.
- **F4 — Borrar `IntelligenceEngine` + los motores band-only** (`CircadianEngine`, `StepsEstimateEngine` + sus tests + campos de calibración de steps en `Profile`) + `strapOnlyHistory`→identidad. Aquí se hace compilable el borrado de motores que F2 dejó pendiente.
- **F5 — Retirar número recuperación 0-100 CON sus pantallas consumidoras en el MISMO paso** (`RecoveryImpact` + sus bloques en TodayView/RecoveryDetail juntos), preservando `calibrationNights`.
- **F6 — Colapso del read-model (`SourceLens`/`SourceFusion`/`keep:.band`). CONTRATO DE DATO EXPLÍCITO (gate ciencia):** «Apple directo» = **RMSSD nocturno real** (`apple_rmssd_night` en metricSeries, patrón `SourceFusion.autonomicTrend:13-18`), **NUNCA `DailyMetric.avgHrv`** (que es SDNN — mezclar reintroduce FER-519/629; meanHRV mezclado ≈43.8ms vs banda ≈49.6ms). Migrar los 7 consumidores con cuidado: TodayView.computeDerived/bandDays (CRÍT), RecoveryDetailScreen (CRÍT), CuerpoView BodyAge/Vitality (CRÍT), InsightsProvider.rank (ALTO), WhatMovesIt clave "hrv" (ALTO), CyclePhaseView (MED), AppModel+Illness (ya apple-aware con SDNN a propósito — no mezclar su historia). + **test de no-regresión SDNN↔RMSSD** sobre esos call sites. Gate `/cso`+`/estadistico`+Grok antes del merge.
- **F7 — Esquema greenfield v1 + naming `strap`→`apple`** (recrear DB limpia si versión no coincide → re-sync HealthKit).
- **F8 — Docs + copy final** (ARCHITECTURE/README/BUILD/CLAUDE + barrido de copy residual).

## Estrategia de build (anti-OOM)
- Preferir `swift build`/`swift test` por paquete individual (sin Xcode, sin OOM) — cubre F1-F6 salvo capa app.
- El compile iOS completo (`xcodebuild ... -jobs 4`) va **uno a la vez**, con la máquina idle (`while pgrep -x xcodebuild XCBBuildService; do sleep 30; done`), solo cuando una fase toca `Cenit/**`.
- Un PR por fase a `iOS` (o agrupar F1-F2 si son limpias). Cada commit verde.

## CÓMO PODRÍA SALIR MAL (auto-adversarial)
1. **F6 reintroduce FER-519/629:** un consumidor pasa a leer SDNN crudo donde iba RMSSD → verdict corrupto en silencio. Mitigación: aislar F6, gate `/cso`+`/estadistico`, re-derivar a mano.
2. **Borrar algo que un motor vivo necesita** (StrainScorer, calibrationNights, ThermalStability/NightAutonomicShape/NocturnalDC). Mitigación: la lista «SE QUEDA VIVO» es explícita; grep de callers antes de cada rm.
3. **F7 reset de DB crashea un install existente.** Mitigación (greenfield): detectar versión de esquema incompatible → recrear DB vacía, sin intentar migrar; el dato Apple regresa por re-sync.
4. **Confundir tabla de streams crudos (muere) con columna diaria (vive)** para skinTemp/resp/spo2/steps. Mitigación: la columna de DailyMetric alimentada por HealthKitBridge se queda.
5. **Grok no cerró su pase adversarial** (se atascó 2×) — verificación crítica hecha por Claude sobre el código real. Re-intentar Grok como gate antes del merge de F6 (la fase de ciencia).
