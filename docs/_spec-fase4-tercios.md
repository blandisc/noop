# SPEC HIJA v2 — FASE 4 · Contraste por tercios de la noche

> Estado: **v2 — cerrada tras 2 rondas adversariales (2 escépticos + Grok + /estadistico).** Todos los
> ejes en check. Aterrizada en firmas reales (`~/code/noop`, 2026-08-01). Regla del plan padre:
> descriptiva, **NO vota**.

## 0 · Qué es y qué NO es
FC **mediana** del primer tercio del sueño menos la del último tercio, contra tu propio normal.
Motivación mecanística (alcohol/ejercicio vespertino elevan la FC nocturna asimétrico entre mitades,
Myllymäki — **la firma `/cso`**): es **motivación, no claim**. **NO VOTA.** Nunca timing del nadir.
Nunca copy prescriptivo.

## 1 · La ruta (una sola — resuelve el falso verde del marco)
El delta se computa **en el refresh completo**, se **persiste un escalar por noche**, la UI **solo lee**.
```
Repository.performRefresh(full:)  ──► por cada sesión de sueño de las prefix(14) recientes:
    asleep = segmentos de stagesJSON con stage != "wake"     ← wall-clock (StageSegment, :460-462)
             (OJO: la etiqueta es "wake", NO "awake")
    NightThirds.compute(hr: hrForNights de la sesión, asleep:)   ← MISMO marco wall-clock → nunca nil
    upsertMetricSeries([MetricPoint(day: dayKey, key: "night_thirds_delta", value: deltaBpm)],
                       deviceId: appleComputedDeviceId)          ← "apple-health-noop", :42
SleepDetailScreen  ──► LEE metricSeries(deviceId: appleComputedDeviceId,   ← accesor NUEVO, ver §5/N1
                       key: "night_thirds_delta") + calcula z.
```
- **Marco (F4-D1):** `compute` se llama **solo desde el refresh**, con `hrForNights`
  (`store.hrSamples(deviceId:"apple-health")`, wall-clock, `:440-442`) y los segmentos de `stagesJSON`
  (wall-clock, `:460-462`) de la **misma** sesión → un solo reloj. Nunca ve `model.intervals`
  (relativos — el bug que mata a `NightAutonomicShape`).
- **Persistencia (F4-D2):** `upsertMetricSeries(_ rows:[MetricPoint], deviceId:)`
  (`MetricSeriesStore.swift:31`), `MetricPoint(day:key:value:)`. `ON CONFLICT(deviceId,day,key) DO
  UPDATE` → idempotente por día, **acumula** entre refreshes. `metricSeries` es KV genérica → **sin
  migración**. Exemplar vivo: `apple_rmssd_night` (NO `night_warming_c`, que está dormante).
- **Cold-start honesto (F4-D2 residual):** solo se computan las **14 noches recientes por refresh** y
  **NO durante el import masivo**. Un usuario con meses de historial Apple **arranca en 0 deltas y
  tarda ~30 días** en llenar la ventana del z. El estado «calibrando» aplica ~1 mes tras instalar, no
  solo a cuentas nuevas. Backfill del import es una fase futura, no ésta.

## 2 · Motor puro — API cerrada
```swift
public enum NightThirds {
    public enum Confidence: String, Equatable, Sendable { case estimate, solid }   // sin .unreadable

    public struct Result: Equatable, Sendable {
        public let firstThirdBpm: Double     // MEDIANA del primer tercio dormido
        public let lastThirdBpm: Double      // MEDIANA del último tercio dormido
        public let deltaBpm: Double          // lastThirdBpm - firstThirdBpm
        public let confidence: Confidence
        public init(firstThirdBpm: Double, lastThirdBpm: Double, deltaBpm: Double, confidence: Confidence)
    }
    public static let minAsleepSec: Int = 10_800        // 3 h = NightAutonomicShape.minAsleepSec
    public static let minSamplesPerThird: Int = 12      // piso: 1 h a muestreo Apple ~5 min (§7)

    /// hr y asleep en el MISMO marco (wall-clock unix s). El caller (refresh) lo garantiza.
    public static func compute(hr: [HRSample], asleep: [NightAutonomicShape.AsleepSpan]) -> Result?
}
```
`HRSample = BiometricStreams.HRSample { ts: Int, bpm: Int }`. **Sin `tzOffsetSeconds`**. Devuelve `nil`
si `asleep` vacío, total dormido `< minAsleepSec`, o algún tercio con `< 2` muestras.

## 3 · Algoritmo cerrado
1. Filtrar `hr` a muestras dentro de algún `AsleepSpan` **y** con `30 <= bpm <= 120` (filtro de
   artefactos PPG, mismo que `NocturnalRestingHR`). Ordenar por `ts`.
2. **Partición por tiempo DORMIDO acumulado:** concatenar spans dormidos en `T` s; cada muestra recibe
   `p ∈ [0,T)` = segundos dormidos hasta su `ts`. primer tercio = `p < T/3`; último = `p >= 2T/3`.
3. **`firstThirdBpm` = MEDIANA de los `bpm` del primer tercio** (no media — /estadistico #1: un solo
   artefacto de 140 bpm mueve la media +6 bpm, del orden del delta; `NightAutonomicShape` ya evita la
   media cruda). Igual el último. `deltaBpm = lastThirdBpm - firstThirdBpm`. Mediana en `Double`.
4. `confidence = .solid` si ambos tercios `>= minSamplesPerThird`; `.estimate` si ambos `>= 2` pero
   alguno `< minSamplesPerThird`. Algún tercio `< 2` → `nil`.
5. Puro, determinista, Foundation + BiometricStreams. Sin `Date()`, sin I/O.

## 4 · «Vs tu normal» (z descriptivo)
En la UI, sobre la serie persistida de `deltaBpm` leída con el **accesor nuevo** (§5/N1):
- Nueva `MetricCfg` `"night_thirds_delta"`: `minVal=-30, maxVal=30, floorSpread=2.5, halfLifeB=14,
  halfLifeS=21, logDomain=false`. ⚠️ **`floorSpread` y `bounds` son product-calibration knobs, NO
  validados** (/estadistico #2 — con `2.0` el piso σ=2.506 bpm queda al ras del ruido de medición del
  delta; `2.5` lo sube por encima). Los firma `/cso`/`/estadistico` sobre datos reales.
- Lectura: ≥30 días de la serie → `[Double?]` oldest→newest (map `MetricPoint.value`, `nil` para días
  faltantes). `state = Baselines.rollingMeanSD(deltas, cfg:, window:30)`; `dev = deviation(hoy, state)`.
- **Gate de madurez ENDURECIDO (/estadistico #3):** el descriptor solo se muestra si `state.trusted`
  (`nValid >= minNightsTrust = 14`), **no** `usable`(4): es una **métrica-diferencia** (más varianza
  que una media), y con 4 noches el centro está montado en ruido. Por debajo de 14 → «calibrando ·
  faltan N noches».
- Descriptor con zona muerta `|z| <= 1.0` (= `Deviation.inNormalRange`): «como de costumbre»;
  `z > 1.0` «más de lo típico»; `z < -1.0` «menos de lo típico».

## 5 · Dueño de archivos + accesor de lectura (N1)
| Archivo | Rol |
|---|---|
| `Packages/StrandAnalytics/.../NightThirds.swift` (**nuevo**) | Motor puro |
| `Packages/StrandAnalytics/Tests/.../NightThirdsTests.swift` (**nuevo**) | CAs de motor |
| `Cenit/Data/Repository.swift` | Computar en refresh (loop `:446-468`) + `upsertMetricSeries` + **accesor de lectura NUEVO** |
| `Cenit/Screens/SleepDetailScreen.swift` | Leer escalar + z + módulo descriptivo (imita `nightShapeContent`) |
| `Packages/StrandAnalytics/.../Baselines.swift` | Alta `MetricCfg` `"night_thirds_delta"` |

⚠️ **N1 (bloqueante de wiring):** el accesor de lectura DEBE apuntar a `deviceId: appleComputedDeviceId`
(`"apple-health-noop"`), **no** al `computedDeviceId` (`+"-noop"` sobre el strap) del patrón
`computedSeries`/`stressDaySummaries`. Reusar ese patrón lee la partición equivocada → serie vacía → el
z nunca pinta (otro falso verde). Es un **método nuevo**, no `computedSeries`. **NO** toca
`TodayView`/`CuerpoView` (la ruta única elimina el plumbing de HR vivo). Vive en el paquete por
`AsleepSpan` (público) + `Baselines`.

## 6 · Criterios de aceptación (numéricos y testeables)
- **CA1 (delta):** noche 8 h, primer tercio 60±1, último 70±1 → `deltaBpm ≈ +10` (±1), `.solid`.
  (Mediana ≈ media en dato limpio → el número no cambia vs media.)
- **CA2 (sin contraste):** uniforme 65±1 → `deltaBpm ≈ 0` (±1).
- **CA2b (robustez — /estadistico #1):** CA1 + **un artefacto de 140 bpm** inyectado en un tercio →
  `deltaBpm` cambia `< 1` bpm (la mediana lo absorbe). Con media simple cambiaría `> 2` bpm: esto
  prueba que la mediana hace algo.
- **CA3 (partición por sueño, no reloj):** HR con **gradiente monótono 55→75** + **gap awake 40 min**
  en `t ≈ 0.5·(fin−inicio)` de reloj. Fijar `X` (valor por-sueño) y `X'` (valor por-reloj) ejecutando;
  el test **assert `lastThirdBpm == X` y documenta `X' ≠ X`** (blinda contra un gap donde coincidan).
- **CA4 (pureza):** Foundation + BiometricStreams, sin `Date()`. Mismo input → mismo output.
- **CA5 (cobertura):** un tercio con 5 muestras (< 12) → `.estimate`; un tercio `< 2` → `nil`.
- **CA6 (aditividad):** verificar **por diff** que `nightShapeContent` no se edita. (No asertar «Apple
  no ve cambio».)
- **CA7 (z con gate trusted):** 30 noches delta ~+2 (`trusted`), noche +12 → `z ≈ 3.19`
  (con `floorSpread=2.5`; el número exacto se mueve con el knob firmado — fijar ejecutando) → «más de
  lo típico»; noche +2 → `|z| ≈ 0` → «como de costumbre».
- **CA7b (bordes del gate):** con `nValid == 4` **y** con `nValid == 13` → `trusted == false` →
  «calibrando», **no** descriptor; con `nValid == 14` → descriptor.
- **CA8 (persistencia):** tras un refresh, `metricSeries` tiene `(appleComputedDeviceId,
  "night_thirds_delta", day, deltaBpm)`; la UI la lee con el accesor nuevo, sin recomputar de crudo.

## 7 · Riesgo admitido + coherencia
Apple muestrea FC en sueño ~cada 5 min → ~32/tercio → `.solid` es el caso común; `minSamplesPerThird=12`
es **piso** (1 h de cobertura), no gate frecuente. El delta depende del hipnograma de Apple (κ≈0.53):
el copy hedgea — es una **lectura**, no medición de precisión.

## 8 · Gates antes de producción
`/estadistico` (firma `floorSpread` + gate trusted sobre datos reales), `/cso` (Myllymäki + hedge
κ≈0.53), `/arquitecto` (write-through + accesor N1 + clave de serie), `/ui`+`/ux` (módulo descriptivo),
`/qa`. Etiqueta `ci-app` OBLIGATORIA.
