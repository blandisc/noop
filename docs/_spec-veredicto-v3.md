# SPEC EJECUTABLE — Veredicto de preparación v3 (motor `Preparedness`)

Derivado de la investigación científica 2026-07-24 (CSO + Grok convergidos, citas verificadas).
Objetivo: dejar el motor `Preparedness.swift` (paquete puro StrandAnalytics) alineado con v3,
verificable con `swift test`, SIN mergear (el veredicto lo valida el dueño en iPhone).

## Principio
Medir menos, mejor, y honesto. El veredicto se para en lo que el Apple Watch SÍ mide bien de
noche (FC-reposo + sueño), saca la señal débil (SDNN de día, MAPE 29% — O'Grady 2024), y solo
deja entrar la señal fina (RMSSD nocturno) cuando la noche de verdad la midió densa.

## Alcance de ESTA entrega (paquete, testeable, rama `blandisc/verdict-v3-engine`, NO merge)
Implementable con los datos que `DailyMetric` YA carga (efficiency, deepMin, restingHr, avgHrv,
respRateBpm, skinTempDevC, totalSleepMin) + entradas OPCIONALES nuevas que degradan a no-op:

### CAMBIO 1 — SDNN de día FUERA del voto autonómico  [severidad ALTA, unánime]
- Hoy: `autonomicAxis` compone HRV(0.35)+RHR(0.40)+resp(0.25). `today.avgHrv` = SDNN all-day.
- v3: el voto autonómico se para en **FC-reposo**. `avgHrv` (SDNN) sale del voto (`wHRV=0`),
  se conserva solo como `SignalRead` read-out (share=0) para la pantalla de detalle/tendencia.
- Config: `wHRV: 0.0`, `wRHR: 1.0`, `wResp: 0.0` por defecto (knobs, documentados). La respiración
  sale del voto autonómico (pasa al centinela, CAMBIO 3).
- Evidencia: O'Grady 2024 (SDNN MAPE 28.88% vs RHR MAE 3.73bpm); Apple Vitals no usa HRV.

### CAMBIO 2 — Sueño graduado vs necesidad, no compuerta de 6h  [ALTA]
- Hoy: `sleepDriver` = binario `totalSleepMin < 360 → low`.
- v3: `low` si el déficit vs la NECESIDAD personal es material, con eficiencia como corroboración.
  - Necesidad = `max(needFloorMin, personalNeed)` donde `needFloorMin = 420` (7h, piso poblacional
    Hirshkowitz 2015) y `personalNeed` = base rodante de noches largas (si se pasa; si no, el piso).
    NO usar promedio rodante de lo logrado (normaliza al privado crónico — hallazgo CSO #4).
  - `low` cuando `totalSleepMin < needMin - sleepSlackMin` (slack=45) **o** `efficiency < effFloor`
    (0.80, Ohayon 2017 <75% malo → margen). Gradiente (Van Dongen 2003), no cliff.
- Config: `sleepNeedFloorMin: 420`, `sleepSlackMin: 45`, `sleepEffFloor: 0.80`.

### CAMBIO 3 — Térmico + respiración = centinela corroborado, no votos iguales  [MEDIA]
- Hoy: térmico vota como eje (|dev|≥0.8→out); resp vota dentro del compuesto autonómico.
- v3: temp y resp forman un **centinela**: cuenta como "fuera" (empuja a caution) solo si
  AMBAS corroboran (temp elevada Y resp elevada) — Mishra 2020, Apple Vitals "2+ fuera". Una sola
  señal elevada ya no vota igual (baja falsos positivos: cuarto caliente, cobija).
- El centinela NUNCA fuerza `easy` por sí solo; empuja a `caution` (nudge), consistente con el marco
  "heads-up, no diagnóstico" (DETECT-AHEAD 2024).

### CAMBIO 4 — Ajuste por fase de ciclo (entrada OPCIONAL)  [ALTA, arreglo de mayor impacto]
- Entrada nueva opcional `cyclePhase: CyclePhaseEngine.Phase?` en `Input` (nil = no-op).
- Cuando `.lutealLean`: descontar el corrimiento lúteo antes de calcular z — FC-reposo +~2bpm
  (Shilaih 2017), temp +~0.3°C (Maijala 2019). Ensancha el umbral "fuera" en esos ejes esa fase.
- Sin fase (nil) el comportamiento es idéntico a hoy → cero regresión para quien no la pasa.
- Wiring (Repository → CyclePhaseEngine) = paso /arquitecto posterior; aquí solo el seam + la lógica.

### CAMBIO 5 — RMSSD nocturno re-entra SOLO si denso (entrada OPCIONAL)
- Entrada opcional `nocturnalRMSSD: (z: Double, dense: Bool)?` en `Input` (nil = fuera del voto).
- Solo si `dense == true` (NocturnalHRV: nClean≥60 && nPairs≥30) el RMSSD nocturno entra como
  co-señal del voto autonómico. Ralo/ausente → no vota (queda como tendencia).

### CAMBIO 6 — FC-reposo nocturna (entrada OPCIONAL, mejor ancla)
- Entrada opcional `nocturnalRestingHr: Double?` por día. Cuando presente, el voto autonómico la
  usa en vez de `restingHr` (Apple, despierta). Ausente → usa `restingHr` con hedge de "despierta".
- Estimador (cuando se calcule en Repository): cuantil bajo robusto en sueño PROFUNDO, no nadir
  instantáneo (hallazgo #2, → CDO). Aquí el motor solo consume el número ya calculado.

### CAMBIO 7 — Cold-start en 3 tramos
- `< seed` de FC-reposo/sueño → `lowSignal` ("aún aprendo tu normal").
- `seed..<trust` → veredicto PROVISIONAL (bandera `provisional`) sobre FC-reposo + sueño.
- `≥ trust` → veredicto pleno. (Reusa BaselineStatus/confidence existentes.)

## Lo que se QUEDA igual (no tocar)
- Salida categórica de 4 estados (sin 0-100). Histéresis 2 días. Trend como nudge. `isNightAnchored`.
- `SignalRead` read-out (avgHrv sigue visible en detalle, solo con share 0 en el voto).

## Copy (app-layer, fuera de este paquete) — DESCRIPTIVO no predictivo
Ningún readiness predice desempeño (Doherty/Altini 2025). Las 4 cadenas: "tus señales en reposo vs
tu normal", nunca "vas a rendir peor". Auditar + allow-list docs/ANALYTICS.md. [paso posterior]

## Criterios de aceptación (testables con swift test)
- CA1: con la Config por defecto, `avgHrv` NO cambia el veredicto (dos días idénticos salvo avgHrv
  producen el mismo veredicto); pero sí aparece en `signals` con share 0.
- CA2: una noche de 359 min y una de 120 min NO votan idéntico si la necesidad/eficiencia difiere;
  el cliff de 6h ya no existe (test con dos duraciones sobre/bajo la necesidad).
- CA3: temp elevada SOLA (resp normal) no mete al eje térmico a "fuera"; temp+resp juntas sí.
- CA4: `cyclePhase = .lutealLean` no marca "fuera" una FC-reposo/temp que sin fase marcaría, dentro
  del corrimiento lúteo; `cyclePhase = nil` reproduce el comportamiento actual (parity).
- CA5: `nocturnalRMSSD` con `dense=false` no cambia el voto; con `dense=true` sí puede.
- CA6: los tests estructurales existentes que deben seguir válidos (histéresis, cold-start,
  night-anchoring) pasan o su cambio es intencional y re-firmado.
- CA7: entradas opcionales todas nil → el motor compila y corre; comportamiento documentado.

## Diferido a /arquitecto (necesita app-layer + datos on-device + validación del dueño)
- Repository: calcular nocturnalRestingHr (cuantil SWS), pasar cyclePhase (CyclePhaseEngine),
  densidad/RMSSD nocturno, y (si se decide) HRR. Todo off-main.
- Validación empírica de los cortes de 4 estados (no hay validación prospectiva — rotular aprox).
- HRR: nudge peso~0 con hedge (Cole 1999 es prueba clínica, no vida libre).

## Knobs nuevos (product-calibration, defaults documentados, los firma /cso)
wHRV=0 · wRHR=1 · wResp=0 · sleepNeedFloorMin=420 · sleepSlackMin=45 · sleepEffFloor=0.80 ·
lutealRHRShiftBpm≈2 · lutealTempShiftC≈0.3. Todos en `Config`, como los actuales.
