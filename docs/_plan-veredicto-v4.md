# PLAN DE IMPLEMENTACIÓN — Veredicto de preparación v4

> **Para una sesión nueva:** este documento es autosuficiente. No necesitas la conversación que lo
> originó. Lee «Estado actual» y «Cómo trabajar cada fase», y arranca por la fase que toque.
> Última actualización: 2026-08-01 · Rama base: `blandisc/verdict-v3-engine` (pusheada, **NO mergeada**).
>
> ## ⚠️ Estructura del documento — léela antes de codear
> Este plan pasó una revisión adversarial (Grok) que lo dividió en dos partes con distinto nivel de
> madurez. **Respeta la división:**
> - **PARTE A — EJECUTABLE.** Fases 1a, 1b y 2. Decisiones cerradas, contratos de API, criterios
>   de aceptación numéricos. Un agente puede implementarlas desde aquí sin preguntar.
> - **PARTE B — HOJA DE RUTA, NO CODEAR.** Fases 3, 4, 5 y 6. Están justificadas y priorizadas,
>   pero **NO tienen el detalle suficiente para implementarse desde este doc**. Cada una necesita su
>   propia spec hija (y la 6, además, `/pm` + `/ux`). Si intentas codearlas desde aquí, inventarás.
>
> ## Bootstrap de sesión (haz esto primero)
> ```bash
> cd ~/code/noop && git fetch origin
> git checkout blandisc/verdict-v3-engine && git pull --ff-only
> cat docs/_plan-veredicto-v4.md          # este documento
> cd Packages/StrandAnalytics && swift build && swift test   # línea base verde antes de tocar nada
> ```
> **Convenciones — leer completo, hay una excepción explícita a `CLAUDE.md`:**
> - **Worktree vs canónico (EXCEPCIÓN CONSCIENTE).** `CLAUDE.md` manda trabajar en un worktree por
>   rama y **nunca** en el checkout principal. Esta rama se construyó en el canónico `~/code/noop` y
>   ahí viven sus commits. Continúa ahí **o** abre un worktree desde `blandisc/verdict-v3-engine` —
>   pero **no mezcles**: media rama en cada sitio es cómo se pierden commits. Si abres worktree,
>   recuerda que el build del iPhone sale del canónico.
> - **ANTES de codear: issue de Linear.** `CLAUDE.md` exige `/pm` → issue con criterios de aceptación
>   y campo **`Carril`**. Este trabajo es **carril PESADO** (analítica + datos on-device): lleva
>   `/arquitecto` si toca plomería, gate `/cso` (ciencia) + `/estadistico` (números) y `/qa`
>   independiente antes del merge. **Hoy NO existe issue — créalo antes de la primera fase.**
> - **PR:** etiqueta **`ci-app` OBLIGATORIA** en cualquier PR que toque `Cenit/**` (la fase 2 lo hace).
>   Referencia el issue (`Closes FER-NN`). Entrada de **CHANGELOG** si el cambio es visible al usuario.
>   Si el cambio mueve la arquitectura, actualiza **`docs/ARCHITECTURE.md`** en el mismo PR.
> - **Un commit por fase**; **nunca merges sin que el dueño valide en su iPhone**.
> - **Si Grok no está disponible** para la revisión adversarial: usa el subagente `qa` (escéptico), o
>   `cso`/`estadistico` según el eje. Lo que **no** es opcional es que alguien que no escribió el plan
>   lo ataque **ejecutando los criterios, no leyéndolos**: esta ronda encontró tres criterios
>   numéricamente falsos justo porque el auditor construyó un arnés y los corrió.
> - Antes de cualquier fase, checklist de 15 min de la **deuda de docs** (sección «Deuda pendiente») —
>   no bloquea código.

---

## 0 · Contexto en una página

**Qué es el veredicto.** `Preparedness` (paquete puro `StrandAnalytics`) responde cada mañana
«¿empujo o me cuido hoy?» con **4 estados categóricos** (`full` / `caution` / `easy` / `lowSignal`),
**nunca un score 0–100**. Es consenso por EJE, no por señal (FER-1010: una mala noche mueve varias
señales a la vez y no debe contarse tres veces).

**Qué se hizo antes de este plan (v3, ya implementado en la rama).** Una investigación científica
profunda (dos auditores independientes, citas verificadas) concluyó que el motor se apoyaba en la
señal más débil que Apple da. v3 corrigió:
- El **SDNN all-day de Apple sale del voto** (`wHRV=0`). O'Grady 2024 (*Sensors* 24(19):6220): MAPE
  28.88 %, sesgo −8.31 ms, LoA −53.8/+37.2 ms. ⚠️ **Corrección pendiente de doc:** el header de
  `Preparedness.swift` dice que O'Grady midió «all day»; midió **5 min supino matutino**. La
  conclusión se sostiene (un promedio de fondo es peor), el locator del método no.
- **Espinazo = FC en reposo** (`wRHR=1`), la señal densa y fiel de Apple (MAE 3.73 bpm / MAPE 5.91 %).
- **Sueño graduado** vs necesidad (piso 420 min, holgura 45) + eficiencia (<0.80), fuera el cliff de
  6 h (Van Dongen 2003: la deuda es un gradiente, no un escalón).
- **Centinela de enfermedad**: temp **y** respiración deben corroborar; una sola ya no vota
  (Mishra 2020; Apple Vitals usa el mismo «2+ fuera»).
- **Fase lútea**: allowance de FC (+2 bpm, Shilaih 2017) y temp (+0.3 °C, Maijala 2019) **solo en el
  día evaluado, jamás en el histórico** (contaminar la serie movería la base y rompería la histéresis).
- **RMSSD nocturno** re-entra solo en noches densas, peso 0.5, y **nunca vota sin FC-reposo**.
- **Cold-start en 3 tramos**: `lowSignal` → `provisional` → pleno.
- **Dos defectos cazados por la auditoría y ya arreglados** (commit `db11e148`):
  1. *Mezcla de constructos*: solo 14 noches tenían FC nocturna y el resto caía a la despierta de
     Apple; con `halfLifeB=14` la base quedaba permanentemente mitad y mitad. Como la nocturna es
     más baja, el z se corría a positivo → **sesgo optimista**. Ahora la serie nocturna se usa
     **entera o nada** (gate `Baselines.minNightsSeed` + la noche asOf debe ser nocturna).
  2. *La promesa de sueño profundo no se ejecutaba*: el cableado pasaba `deep: false` siempre. Ahora
     se decodifica `stagesJSON` y se marca cada muestra. ⚠️ Puede ser **inerte en la práctica** — ver
     la nota de la fase 1b: el subconjunto profundo rara vez llega a las 20 muestras que exige.
  3. *(Tercer defecto, cazado por la revisión escéptica)* **El veredicto cambiaba de constructo dentro
     de la misma mañana**: en el primer pintado `nocturnalRestingHr` viene vacío → se puntuaba la FC
     **despierta**; segundos después, en el refresh completo, la **nocturna**. El héroe podía decir una
     cosa y desdecirse. **Arreglado:** el veredicto ahora **solo se publica en el refresh completo**
     (`inputs.full`); en el primer pintado queda `nil`. Se rechazó marcarlo «preliminar» con un número
     que luego se contradice: eso entrena desconfianza. Es la misma disciplina que el archivo ya aplica
     a todo lo derivado de `days` que persiste («keep waiting for `fullyLoaded`»); el veredicto se
     había escapado de ella.

**Veredicto de la re-investigación «¿v3 es el techo?»** No, pero el techo **no está en más señales**.
Se rechazaron con evidencia: la hora del nadir (regla de marketing de Oura, sin publicación),
arquitectura de sueño como voto (Apple acierta N3 el 50.66 %, κ=0.53 — Schyvens 2025), SpO₂ (apagado
por litigio + no mide preparación), fase circadiana (cosinor yerra ~4.5 h sin luxómetro),
Kalman/bayesiano (un EWMA ya es un Kalman escalar; peor auditabilidad), y copiar el conteo «2+» de
Vitals (nuestro consenso por eje es superior: no cuenta tres veces lo mismo).

**El techo duro no es el sensor: es que no hay desenlace contra el cual calibrar.** Doherty/Altini
2025 (doi 10.1515/teb-2025-0001) revisó 14 scores compuestos de 10 fabricantes: **ninguno tiene
validación independiente revisada por pares**. Ungaro 2026 (*Sensors* 26(4):1325) encontró que
sentirse «con energía» se asocia **negativamente** con la HRV. ⚠️ **Si un requerimiento pide «que el
veredicto prediga cómo me irá», regrésalo a `/pm`: no es verificable con estos datos.**

---

## 1 · Estado actual (verificado)

**Rama:** `blandisc/verdict-v3-engine`, pusheada a origin, **sin PR y sin mergear** (el dueño valida
en su iPhone antes de producción). Commits, del más viejo al más nuevo:

| Commit | Qué trae |
|---|---|
| `b6df2c24` | Núcleo v3 (SDNN fuera, espinazo FC-reposo, sueño graduado, centinela, `provisional`) |
| `5ae2f3e3` | `NocturnalRestingHR` (carril A) |
| `71f08ccb` | Entradas v3 en `Input` (carril B) |
| `9312dc78` | Cableado en `Repository` (carril C) |
| `db11e148` | Los dos primeros defectos de la auditoría (mezcla de constructos · `deep`) |
| `f04cf751` | Este plan (primer checkpoint) |
| `86d8f79c` | Tercer defecto (el veredicto solo se publica en refresh completo) + las 7 decisiones arbitradas |

**Verificación al cierre (2026-08-01, tras `86d8f79c` — el commit que hace opcional el veredicto):**
`swift test` del paquete → 1030 tests,
0 fallas; `xcodebuild … -jobs 4` → BUILD SUCCEEDED. ⚠️ **Los conteos y las fechas se pudren: no los
cites, re-córrelos.** Ojo: `swift test` del paquete **no compila `Cenit/Data/Repository.swift`** — si
tocas la capa app, el `xcodebuild` es obligatorio, no opcional.
```bash
cd ~/code/noop/Packages/StrandAnalytics && swift test          # línea base del paquete
swift test --filter Preparedness && swift test --filter NocturnalRestingHR
```

**Suites de test del veredicto** (no editar las tres primeras salvo re-gate intencional):
`PreparednessTests` (14, estructura) · `PreparednessSignalReadParityTests` (8) ·
`PreparednessV3Tests` (8, el re-gate v3) · `PreparednessV3InputsTests` (7, entradas + regresión de
mezcla) · `NocturnalRestingHRTests` (6).

**Archivos load-bearing (rutas relativas a la raíz del repo):**
- `Packages/StrandAnalytics/Sources/StrandAnalytics/Preparedness.swift` — el motor.
- `Packages/StrandAnalytics/Sources/StrandAnalytics/NocturnalRestingHR.swift` — cuantil nocturno.
- `Packages/StrandAnalytics/Sources/StrandAnalytics/Baselines.swift` — `prefixStates`, `metricCfg`
  (`resting_hr`: `halfLifeB=14`), `minNightsSeed=4`, `minNightsTrust=14`, `confidence(nValid)`.
- `Packages/StrandAnalytics/Sources/StrandAnalytics/NocturnalHRV.swift` — gates de densidad
  (`minCleanBeats=60`, `minSuccessivePairs=30`), `NightResult{rmssdMs, nClean, nPairs}`.
- `Packages/StrandAnalytics/Sources/StrandAnalytics/AutonomicTrend.swift` — `Read{direction,
  confidence, nightsUsable, **nightsToTrend**, recentDenseNights, z7d, spark, asOfWasDense}` (8
  campos). **`spark` = z por-noche (past-only), oldest→newest. ⚠️ `spark == []` salvo que
  `confidence == .solid`, y `spark.last` es el z de la noche asOf SOLO si `asOfWasDense == true`** —
  si no, es el de la última noche densa anterior. `z7d` es OTRO constructo (media de 7 d): no
  confundirlos.
- `Packages/StrandAnalytics/Sources/StrandAnalytics/NightAutonomicShape.swift` — **ya existe y ya
  está cableado** en `SleepDetailScreen` (nadirHour, dipPct, fractionBelowRHR). Es descriptivo y
  **debe seguir siéndolo**: promoverlo al veredicto sería sobreafirmar.
- `Packages/StrandAnalytics/Sources/StrandAnalytics/CyclePhaseEngine.swift` — `NightSample`, `Phase`,
  `estimate(_:asOf:)`.
- `Cenit/Data/Repository.swift` — `performRefresh(windowDays:full:)` hace las LECTURAS (tiene
  `store`); `assembleDashboard(_:)` es `nonisolated async` y hace el cómputo PURO fuera del main
  actor; ahí vive la llamada a `Preparedness.evaluate`.

**Knobs actuales en `Preparedness.Config`** (product-calibration, firmados por `/cso`):
`wHRV=0` · `wRHR=1` · `wResp=0` · `wNocturnalRMSSD=0.5` · `autonomicOutZ=-1.0` · `respBadZ=1.5` ·
`thermalOutC=0.8` · `hysteresisDays=2` · `sleepNeedFloorMin=420` · `sleepSlackMin=45` ·
`sleepEffFloor=0.80` · `lutealRHRAllowanceBpm=2.0` · `lutealTempAllowanceC=0.3` · `sdnnCfgKey="sdnn"`.

---

## ⚠️ DECISIÓN DEL DUEÑO (2026-08-01): la VFC queda FUERA por ahora

La **fase 2 (VFC nocturna a co-protagonista) queda DIFERIDA** por decisión de producto. No es un
rechazo técnico —su análisis sigue siendo válido y está escrito abajo—, es una decisión de alcance:
la VFC de Apple solo se vuelve señal de primera si el usuario **densifica el muestreo**, y esa
palanca tiene costos que el dueño no quiere pedir hoy:
- **AFib History** multiplica el muestreo nocturno (de ~cada 4 h a ~cada 15 min), pero **apaga las
  notificaciones de ritmo irregular** (pasan a resumen semanal) y **Apple pide confirmar un
  diagnóstico de fibrilación auricular** para activarlo. No se sugiere proactivamente; vive solo en
  ajustes avanzados con el intercambio explicado.
- **Polar H10** (~USD 80) da VFC a grado ECG y **reusa la plomería BLE que el repo ya tiene**, pero
  es hardware extra: sería su propia fase, pequeña y opcional.

**Orden vigente sin la fase 2:** **1b** (tramo estable) → **1a** (capacidad de suavizado) → **3**
(residuo condicional). La fase 3 **NO depende de la 2** (su modelo predice la FC, no la VFC), así que
diferir la VFC no le cuesta nada.

⚠️ **Hueco que la spec hija de la fase 3 DEBE resolver:** la fase 3 depende de la 1a, pero la 1a
quedó con `rhrSmoothingNights = 1` (apagada) hasta que `/cso` firme un valor con evidencia. Si nadie
lo firma, **la fase 3 correría sobre señal sin suavizar** — justo lo que su dependencia buscaba
evitar. Decidir: (a) firmar N antes de la 3, (b) que la 3 haga su propio suavizado interno, o (c)
aceptar explícitamente que corre sin él y documentarlo.

---

## PARTE A · FASES EJECUTABLES

Tres rankings distintos salieron de la investigación (sofisticación, impacto/esfuerzo, y el de Grok).
El plan no sigue a ninguno: sigue **qué necesita qué**.

```
Fase 1a (suavizado del pulso)  ──→ Fase 2   (dependencia de ARCHIVO: ambas editan Preparedness.swift)
Fase 1b (segmento estable)     ──   independiente de la 2
```
⚠️ **La flecha 1b → 2 NO existe.** Tras la decisión D5 (la fase 2 no toca la ventana de medición del
RMSSD), la fase 2 **no consume** el tramo estable: ese aplica solo a la FC nocturna. Lo único que ata
la 2 a la 1a es que **ambas editan `Preparedness.swift`** — colisión de archivo, no de símbolo.

**Orden por IMPACTO real** (distinto del de dependencia): **1b** (arregla el constructo) → **2** (la
VFC sube a co-protagonista) → **1a** (capacidad/instrumentación). Si hay que elegir una sola fase,
empieza por **1b**.
⚠️ **No es contradicción con la tabla de carriles:** la 2 va «después de la 1a» por **colisión de
archivo** (`Preparedness.swift`), no por valor. Si priorizas por impacto y haces la 2 antes que la 1a,
es válido — solo asegúrate de no correrlas **a la vez** sobre el mismo archivo.
**Corrección del DAG (Grok):** la fase 3 (residuo) depende de **1a + 1b**, NO de la 2 — su modelo
predice la FC, no la VFC. Solo dependería de la 2 si más adelante se extiende el residuo al compuesto
autonómico completo. Las fases 4, 5 y 6 son independientes entre sí.

### Carriles y dueños de archivo (para paralelizar sin colisión)

| Fase | Dueño exclusivo de |
|---|---|
| 1a | `Preparedness.swift` + `Tests/…/PreparednessV4SmoothingTests.swift` (nuevo) |
| 1b | `NightStableSegment.swift` (nuevo) + `Tests/…/NightStableSegmentTests.swift` (nuevo) **+ `NocturnalRestingHR.swift`** (cambiar el orden de preferencia: segmento → deep → ventana completa) |
| 2 | `Preparedness.swift`, `Repository.swift` **+ `Baselines.swift`** (alta de la clave `"rmssd_verdict"` + su test hermano, molde: `testSdnnBaselineConfig_existsAndIdentical`) — **secuencial, después de 1a** (colisión en `Preparedness.swift`) |

1a y 1b **pueden correr en paralelo** (archivos disjuntos: `Preparedness.swift` vs
`NightStableSegment.swift`+`NocturnalRestingHR.swift`). La 2 va después de la **1a** porque comparten
`Preparedness.swift`; **no** depende de la 1b.

---

### FASE 1a · Suavizado multi-noche del espinazo

**Problema.** El veredicto z-scorea **una sola noche** y compensa el ruido con histéresis de 2 días.
La histéresis es un filtro de *decisión*: no reduce el ruido de la *medición*. Plews et al. 2013
(*Sports Med* 43(9):773–781) — la tendencia multi-día tiene mejor validez que el valor de un día. El
repo **ya cree esto** (`AutonomicTrend` cita a Plews) pero solo para el RMSSD… que ya no vota.

**Decisión cerrada (no adivinar).** El suavizado se aplica **a la serie UNA vez**, y esa serie
suavizada se usa **en todo**: el fold del baseline (`prefixStates`) **y** el valor de cada día. Igual
disciplina que el fix de constructos: *una serie, un constructo, en todas partes*. Suavizar solo el
día contra un baseline crudo desalinearía la varianza y volvería el z inservible.

```swift
// En Config:
/// Noches (incluida la propia) promediadas para el valor de FC-reposo que se z-scorea.
/// 1 = comportamiento pre-v4, bit-idéntico. Media SIMPLE, solo hacia el pasado (nunca mira al futuro).
public var rhrSmoothingNights: Int = 1   // ⚠️ DEFAULT 1 A PROPÓSITO — ver abajo
```

> ### ⚠️ DECISIÓN CERRADA (auditoría ejecutada + arbitraje): el default es **1**, y esta fase entrega
> una **capacidad, no un cambio de comportamiento**.
>
> Un auditor construyó un arnés y **ejecutó** los criterios en vez de leerlos. Dos hallazgos:
> 1. Con 20 noches planas la dispersión cae al piso (`floorSpread = 2.0` bpm), así que con `N=5` una
>    **sola** noche de +20 bpm ya cruza el corte: `(55·4+75)/5 = 59`, `z = (59−55)/2 = 2.0` → orientado
>    `−2.0 ≤ −1.0` → `.low`. Para que una noche aislada NO mueva el eje harían falta **N ≳ 8**.
> 2. Peor: el suavizado tiene **latencia SIMÉTRICA**. Con `N=5` se rompe
>    `testHysteresisVerdictSequence_frozen` (`PreparednessTests.swift:117-131`): tras bad·bad·good·good
>    el cuarto día debe volver a `full` y devuelve `caution`. Yo solo había admitido la latencia de
>    subida; la de bajada **retrasa el reconocimiento de que ya te recuperaste**.
>
> **Resolución (criterio de desempate: lo que el repo ya firmó gana sobre un criterio de plan que la
> aritmética desmiente):** se implementa el mecanismo con **default `1`** — comportamiento actual
> bit-idéntico, test congelado intacto, cero re-gate. El valor operativo lo firma `/cso` **con
> evidencia sobre datos reales**, no con un número elegido en un plan.
> **Rechazado explícitamente:** suavizado **asimétrico** (rápido a la baja, lento a la alza) — es
> hackear el filtro para pasar un test, y rompe la simetría que la histéresis bidireccional de 2 días
> ya firmó; y `N=2–3`, que ni arregla el ruido ni evita la latencia.
> **Entregable honesto de la fase:** el knob + los tests + la medición que le permita a `/cso` elegir
> N. Si eso te parece poco, es porque el hallazgo fue que el cambio "obvio" no era gratis.
- Media **simple past-only**: `mean(rhrSeries[max(0, i-N+1)...i])`, ignorando `nil`.
- Si en la ventana hay **menos de 2 valores** no-nil, usa el valor crudo del día (sin inventar).
- Se aplica a **todos** los días, incluidos los del pase histórico de `rawVerdictAt`/`hysteresed`.
- **`hysteresisDays` se queda en 2** hasta que `/cso` decida; reducirla es una pregunta abierta, NO
  parte de esta fase (no apiles cambios de comportamiento en un mismo gate).

**Criterios de aceptación (numéricos y testeables).**
- **CA1 (paridad):** `rhrSmoothingNights = 1` produce `verdict`, `drivers` y `signals` **idénticos**
  a los actuales. ⚠️ `PreparednessTests.baseline()` es `private` dentro de esa clase: **duplica la
  fixture** en tu archivo nuevo (20 noches: `hrv 52+i%5`, `rhr 54+i%3`, `resp 13+i%3`,
  `sleep 440+(i%4)*5`, `temp 0`) en vez de abrir el acceso del test existente.
- **CA2 (corregido — el original era numéricamente falso):** el efecto del suavizado es
  **monótono**: con 20 noches planas y una sola noche de +20 bpm, el z orientado del día crece (menos
  negativo) conforme sube N, y existe un `N*` a partir del cual el eje deja de ser `.low`.
  **Determina `N*` ejecutándolo, no a mano.** Medido: **`N* = 8` con 20 noches planas** y **`N* = 9`
  con la fixture `baseline()`** — no las confundas, y fija en el test el de la fixture que uses. Con `N=5` el eje SÍ queda `.low`: no lo escribas al revés.
- **CA2b:** con `N=1` una noche mala deja el eje `.low` y con `N = N*` no — la misma serie, dos
  configuraciones, resultados distintos: eso prueba que el knob hace algo.
- **CA3 (independencia del centinela) — ⚠️ TERCERA redacción; las dos anteriores pasaban por
  vacuidad. Lee esto antes de escribirlo.**
  El centinela **no es observable** desde `Read`: `sentinelOut` es local en `rawVerdictAt`, `Axis` no
  tiene caso para él, y el driver `.thermal` que sí se publica es **solo temperatura**. Por eso:
  - ❌ Asertar sobre `.thermal` → pasa por vacuidad (no toca el centinela).
  - ❌ Asertar `verdict(N=1) == verdict(N=8)` sobre una **serie plana** → **también** es vacuo: sobre
    una serie plana el suavizado es la **identidad**, así que el `Input` completo es bit-idéntico
    entre N y la aserción es una tautología. Pasaría **incluso si** alguien cableara el centinela a
    leer la serie suavizada — que es justo el bug que este criterio dice cazar.
  - ✅ **Redacción correcta (verificada por ejecución):** usa una fixture donde `N` **sí muerde** —
    20 noches planas + **pico de +20 bpm hoy** — **y** temp/resp elevadas hoy. Entonces:
    ```
    N=1 → verdict == .easy      (eje autonómico .low + centinela  = 2 votos)
    N=8 → verdict == .caution   (eje autonómico .inRange + centinela = 1 voto)
    ```
    **La prueba está en que N=8 da `.caution` y NO `.full`:** el suavizado apagó el eje autonómico,
    y aun así quedó un voto — el del centinela. Si el suavizado lo hubiera silenciado también, N=8
    daría `.full`. Este test **puede fallar**, que es lo que lo hace un test.
  *(El test fuerte —asertar el centinela directamente— exige exponerlo en `Read`/`Axis`: es un cambio
  de API que este plan NO autoriza. Decídelo aparte si lo quieres.)*
  **Lección transferible:** un criterio sobre *independencia* nunca se prueba con una fixture donde la
  variable no varía.
- **CA4 (no regresión):** con el **default 1**, las suites del veredicto siguen verdes **sin
  editarlas** — incluido `testHysteresisVerdictSequence_frozen`, que es el que rompería cualquier
  N>1. Si tocas ese test, te saliste de la decisión de arriba. Lista exacta y cómo
  contarlas (el número se pudre; usa el comando):
  ```bash
  cd ~/code/noop/Packages/StrandAnalytics && swift test --filter Preparedness   # PreparednessTests,
  # PreparednessSignalReadParityTests, PreparednessV3Tests, PreparednessV3InputsTests
  swift test --filter NocturnalRestingHR
  ```
  **Política de re-gate:** si una de esas suites falla, es **bug tuyo** salvo que el cambio sea un
  re-gate deliberado; en ese caso documenta en el commit qué invariante cambió y por qué, y actualiza
  `testSignedKnobs_lockedByCSO`.

**Riesgo admitido.** Latencia: una elevación real tarda ~N noches en expresarse del todo en el eje.
Esto es deliberado (tendencia sobre instantánea) y **el camino agudo no depende de este eje**: la
enfermedad la cubre el centinela (temp+resp), que es independiente.

---

### FASE 1b · Segmento nocturno estable, detectado desde la señal

**Problema.** El nadir real vive en el tramo estable de la noche, pero **no podemos confiar en la
etiqueta «deep» de Apple**: Schyvens 2025 (*SLEEP Adv* 6(2):zpaf021) mide sensibilidad N3 de
**50.66 %** y κ=0.53 en Apple Watch S8. Hoy `NocturnalRestingHR` prefiere el subconjunto `deep`, que
viene de esa etiqueta.

**Motivación (no equivalencia).** Herzig 2018 (*Front Physiol* 8:1100) reporta que la HRV es más
reproducible en SWS (ICC 0.84) y que **un algoritmo basado en HRV localizó SWS el 87 % de las veces
sin PSG**. ⚠️ **No afirmamos reproducir ese 87 %**: nuestro detector es más simple (FC baja + varianza
baja) y su desempeño **no está medido**. Herzig justifica *por qué* buscar el tramo estable, no *qué
tan bien* lo encontramos. El copy debe llamarle **«tramo estable»**, nunca «sueño profundo».

**API cerrada.**
```swift
public enum NightStableSegment {
    public struct Sample: Sendable, Equatable {
        public let ts: Int; public let bpm: Double
        public init(ts: Int, bpm: Double)
    }
    /// Ventana mínima para considerarse un tramo (segundos). 20 min: por debajo el cuantil
    /// no tiene muestras suficientes para ser robusto. Product-calibration, no un valor publicado.
    public static let minDurationSec: Int = 1200
    /// Ancho de la media móvil con la que se suaviza la serie antes de buscar el tramo (segundos).
    public static let smoothWindowSec: Int = 300
    /// Devuelve [inicio, fin] (unix s) del tramo estable más largo, o nil si no hay ninguno.
    public static func find(_ samples: [Sample]) -> (start: Int, end: Int)?
}
```
**Algoritmo cerrado (no adivinar).**
1. Ordenar por `ts`; descartar `bpm < 30 || bpm > 120` (artefactos PPG, mismo filtro que
   `NocturnalRestingHR`).
2. Suavizar con media móvil de `smoothWindowSec`.
3. Calcular la **mediana** de la serie suavizada y su **MAD** (desviación absoluta mediana).
4. Marcar «tranquila» toda muestra suavizada con `bpm <= mediana` **y** cuya variación local
   (|bpm − bpm previo|) sea `<= MAD`.
5. Devolver la **racha contigua más larga** de muestras tranquilas cuya duración total sea
   `>= minDurationSec`. Si ninguna llega, devolver `nil`.

**Orden de preferencia resultante en `NocturnalRestingHR`** (cámbialo explícitamente en esta fase):
`segmento estable` → si `nil`, `deep` de Apple → si tampoco, **toda la ventana**. La etiqueta de Apple
baja a segunda opción, no desaparece.

⚠️ **Sospecha a zanjar con datos ANTES de confiar en el fix #2:** la preferencia por `deep` exige que
el subconjunto profundo llegue solo a `minSamples = 20`. Apple muestrea FC durante el sueño ~cada
5 min, así que 1–1.5 h de profundo da ~12–18 muestras: **la rama `deep` podría no activarse nunca** y
caer siempre a la ventana completa — es decir, el fix #2 estaría cableado pero sin efecto medible.
**Mídelo:** cuenta muestras `deep` por noche en datos reales antes de dar por bueno ese arreglo.
⚠️ **DECISIÓN CERRADA (arbitrada): NO bajes el umbral «para que `deep` dispare».** Aflojar el gate
para forzar una rama es exactamente cómo se cuela ruido con etiqueta de precisión (y la etiqueta de
Apple ya trae κ≈0.53). Acepta el fallback a la ventana completa y **retira la promesa del copy y de
los docs**: «preferimos el sueño profundo cuando hay ≥20 muestras; en la práctica suele ser la noche
entera». **El arreglo de constructo es la fase 1b (tramo estable), no aflojar `deep`.**

**Criterios de aceptación (numéricos).**
- **CA1:** noche sintética de 8 h con un tramo de 2 h a 50±1 bpm y el resto a 70±8 bpm → `find`
  devuelve un rango contenido en el tramo de 50 bpm, con duración ≥ `minDurationSec`.
- **CA2:** serie uniformemente agitada (70±15 bpm sin tramo tranquilo de 20 min) → `nil`.
- **CA3 (independencia de la etiqueta):** `find` **no recibe** `stagesJSON` ni etiquetas; el test pasa
  la misma serie dos veces con hipnogramas contradictorios y el resultado es idéntico.
- **CA4:** puro y determinista (Foundation only, sin `Date()`, sin I/O). Mismo input → mismo output.
- **CA5:** la ruta de `NocturnalRestingHR` con `find == nil` reproduce **exactamente** el
  comportamiento actual (paridad).

**Recompute histórico.** ⚠️ **Ojo con la premisa:** `Repository` NO lee todas las noches — hoy calcula
la FC nocturna solo para las **14 más recientes** y **solo en refresh completo**
(`Repository.swift:436-437`, `prefix(14)` dentro de `if full`). El segmento debe calcularse para el
mismo conjunto de noches que alimente la serie nocturna, sea cual sea; si ese conjunto se amplía,
amplíalo **a la vez** para base y día, o vuelves a mezclar constructos. El costo de lectura es real
(la propia función lo advierte): ampliarlo es una decisión con presupuesto, no un detalle.

---

### FASE 2 · La VFC nocturna sube a co-protagonista

**El reencuadre que importa.** La premisa «la HRV de un wearable no sirve» es **falsa**; lo que no
sirve es **el SDNN que Apple publica**. Dial 2025 (*Physiol Rep* 13(16):e70527, 536 noches vs ECG)
mide RMSSD nocturno de Oura en CCC 0.99 / MAPE 5.96 % y de WHOOP en 0.94 / 8.17 %.
⚠️ **Dial EXCLUYÓ al Apple Watch. NO extrapolamos esos números a Cénit.** Lo que sí es nuestro:
`NocturnalHRV` calcula RMSSD desde los **R-R crudos** (`HKHeartbeatSeriesSample`), no desde el SDNN de
Apple, con gates propios de densidad — así que la señal es **de otra clase que el SDNN**, y su calidad
en Apple **no está medida por nadie**. Esa es la afirmación honesta. Refuerzo del enfoque nocturno:
Nuuttila 2024 (*Sports Med Open* 10:120) — bajo sobrecarga, las medidas nocturnas respondieron con más
sensibilidad que las matutinas.

**Hoy se desperdicia:** entra con peso fijo 0.5, solo el día asOf, sin serie histórica ni baseline
propio dentro del veredicto (usa la z de `AutonomicTrend`, que es un constructo distinto).

**Decisiones cerradas.**
1. **Fuente de datos (claves EXACTAS, verificadas).** El RMSSD por noche NO se calcula en el motor:
   lo calcula `CenitApp/Health/HealthKitBridge.swift` sobre los R-R crudos y lo persiste como
   **`apple_rmssd_night`** (que `Repository` ya lee en `nightRows`). La densidad vive en dos claves
   hermanas que **hoy nadie lee** salvo el bridge para su cursor: **`apple_rr_clean_night`** y
   **`apple_rr_pairs_night`** (`HealthKitBridge.swift:1024-1025`). Hay que agregar su
   `store.metricSeries(...)` en `performRefresh`. **No** reusar la z de `AutonomicTrend`: ese motor es
   la superficie de tendencia con su propio gate (`solid` = 21 noches); el veredicto necesita su
   propia z, disponible antes.
   ⚠️ **Rama muerta a sabiendas:** `apple_rmssd_night` **solo se escribe si la noche es densa**
   (`HealthKitBridge.swift:1021`), así que el tramo `peso = 0 si p < 30` de la rampa es inalcanzable
   con datos reales — es testeable en el motor pero nunca se ejercita en producción. Déjalo por
   robustez, pero no lo cuentes como cobertura.
2. **Baseline propio — CLAVE NUEVA, no `"hrv"`.** ⚠️ *(Corrección: el borrador decía «usa
   `metricCfg["hrv"]` bajo su propia clave», que es contradictorio — usar esa clave ES compartirla.)*
   Crea **`"rmssd_verdict"`** en `Baselines.metricCfg` como **copia** de la config log-domain de
   `"hrv"` (`floorSpread=0.08`, `halfLifeB=14`, `halfLifeS=21`). Es exactamente el patrón que el repo
   ya firmó con `"sdnn"` (clave propia, config idéntica, «so a future RMSSD retune can never silently
   move the SDNN baseline» — `Baselines.swift:154-160`), y su test hermano
   `testSdnnBaselineConfig_existsAndIdentical` es el molde del que debes escribir. Expón el knob
   análogo `rmssdCfgKey` en `Config`. Mismo `prefixStates`.
3. **Forma del `Input`** (reemplaza el `nocturnalRmssd: DenseRmssd?` actual):
   ```swift
   /// RMSSD nocturno por día ("yyyy-MM-dd" → ms) y densidad de esa noche.
   public let nocturnalRmssdMs: [String: Double]        // default [:]
   public let nocturnalRmssdPairs: [String: Int]        // default [:]  (nPairs de NocturnalHRV)
   ```
   `DenseRmssd` se retira (era un parche del día asOf). **Migrar sus tests.**
4. **Rampa de peso (fórmula cerrada).** Con `p = nocturnalRmssdPairs[día]`:
   ```
   peso(p) = 0                                    si p <  NocturnalHRV.minSuccessivePairs (30)
   peso(p) = wNocturnalRMSSD · (p − 30) / (120 − 30)   si 30 ≤ p < 120   (rampa lineal)
   peso(p) = wNocturnalRMSSD                      si p ≥ 120
   ```
   `wNocturnalRMSSD` se mantiene en `0.5` como **techo** (no como valor fijo). El `120` es
   product-calibration: aproxima una noche bien muestreada; **no es un umbral publicado** y lo firma
   `/cso`.
5. **Invariante que se conserva:** nunca vota sin FC-reposo presente (`rhrZ != nil`). Sin espinazo no
   hay veredicto.
6. ⚠️ **La fase 2 NO toca la ventana de medición del RMSSD.** *(Corrección: el borrador decía «medir
   sobre el segmento estable», y eso rompe su propio CA4.)* El RMSSD por noche se calcula en
   `CenitApp/Health/HealthKitBridge.swift` sobre la unión del sueño de la noche entera y se persiste
   bajo `apple_rmssd_night` — **la misma clave que lee `AutonomicTrend`**. Cambiar la ventana movería
   la superficie de tendencia Y mezclaría filas históricas (noche entera) con nuevas (segmento): el
   mismo defecto de constructos que `db11e148` acaba de cerrar en la FC.
   **Alcance cerrado de la fase 2:** serie histórica en `Input` + baseline propio + rampa de peso +
   cableado. **Nada más.** El segmento estable de la fase 1b aplica a la **FC nocturna**
   (`NocturnalRestingHR`), no al RMSSD. Medir el RMSSD sobre el segmento es una **fase futura** que
   exige clave nueva + recompute/backfill explícito, nunca reescribir `apple_rmssd_night` en sitio.
   Por eso `HealthKitBridge.swift` **no** está en la tabla de dueños de archivo de esta fase.

**Criterios de aceptación (numéricos).**
- **CA1:** `nPairs = 20` (< 30) → `peso == 0` exacto, y el veredicto es idéntico a no pasar RMSSD.
- **CA2 (corregido — el original era aritméticamente imposible):** con `wRHR=1`, techo
  `wNocturnalRMSSD=0.5` y `autonomicOutZ=−1.0`, el compuesto es `(1·zFC + 0.5·zRMSSD)/1.5`. Con
  `zFC=0` hace falta **`zRMSSD ≤ −3.0`** para cruzar el corte (con `−2.0` da `−0.667`, en rango).
  Escribe el CA con ese número. **Lo que esto significa, y hay que decirlo en el copy:** la VFC densa
  **no puede volcar el eje sola** salvo en valores extremos — su papel real es **corroborar los
  bordes**: empujar a `.low` un día en que la FC ya viene floja, o sostener `inRange` uno dudoso.
  Si alguien quiere que la VFC pueda decidir sola, eso es **subir el techo `wNocturnalRMSSD`**, y es
  una decisión de `/cso` con evidencia — no un ajuste para que pase un criterio.
- **CA3:** sin FC-reposo (`restingHr = nil`, sin nocturna) y con RMSSD denso → `verdict == .lowSignal`.
- **CA4:** el baseline del RMSSD del veredicto es independiente: cambiarlo no altera
  `AutonomicTrend.spark` ni `z7d` (test de no-interferencia).
- **CA5:** `peso(75) == wNocturnalRMSSD * 0.5` ± 1e-9 (la rampa es la fórmula, no una tabla al gusto).

**Honestidad de copy.** 60 s de R-R es **HRV ultra-corta**: Esco & Flatt 2014 (*J Sports Sci Med*
13(3):535–541) reporta validez aceptable a 60 s con degradación por debajo. Decirlo, no esconderlo.
**Nunca** afirmar paridad con Oura/WHOOP.

**Consecuencia de UI — bloqueante de producto, con dueño.** Aparece un **tercer orbe «VFC»** las
noches densas. **Dueño: `/ux` + `/ui` antes de mergear la fase 2.** Ver «Deuda pendiente» (deuda de UI): la pantalla
en producción todavía dice «3 SEÑALES» en el orbe autonómico, y con v3 vota una sola.

---

## PARTE B · HOJA DE RUTA — **NO CODEAR DESDE ESTE DOCUMENTO**

⚠️ Las fases siguientes están **justificadas y priorizadas, pero NO especificadas al nivel de la
Parte A**. La revisión adversarial las marcó como **no implementables de forma autónoma**: falta el
modelo completo (3), los criterios de aceptación numéricos (4 y 5) y el requerimiento de producto (6).
**Cada una necesita su propia spec hija**, escrita con el mismo rigor que la Parte A y pasada por
revisión adversarial, antes de que alguien escriba código. Lo que sigue es el *por qué* y el *qué*,
deliberadamente **no** el *cómo*.

---

### FASE 3 · Residuo condicional («¿está alto para lo que hiciste?») — *spec hija pendiente*

**Idea.** Hoy el veredicto pregunta «¿tu FC está alta vs tu normal?». El salto es «¿está más alta **de
lo que debería** dado lo que entrenaste ayer y lo que dormiste?». Si entrenaste duro y dormiste poco,
una FC alta es **costo esperado**; si tu carga fue baja, dormiste bien y aun así está alta, **eso sí**
es señal no explicada.

**Boceto de modelo** (on-device, personal, ventana ~28–60 noches):
`FC_esperada = β0 + β1·carga(d−1) + β2·(sueño vs necesidad) + β3·eficiencia + β4·1{lútea}`,
y el eje vota sobre `z(residuo)` en vez del z crudo **cuando el ajuste es confiable**, con fallback
explícito al z crudo. La carga deja de ser adorno y pasa a **predictor** (sigue visible como contexto).

**Depende de:** 1a + 1b (NO de la 2 — el modelo predice la FC, no la VFC). Un modelo entrenado sobre
señal ruidosa aprende ruido.

**Qué tiene que resolver su spec hija antes de codear:** familia de ajuste (Huber / Theil–Sen / EWLS)
y sus parámetros; umbral de «confiable» (¿R² mínimo? ¿n mínimo?); qué hace con noches faltantes; qué
expone el `Read` para ser auditable (`coefficients`, `r2`, `fallbackReason`); y CAs numéricos.

**Riesgo alto de copy.** Debe leerse como explicación, nunca como permiso ni regaño: «viene alta, pero
es lo esperado tras ayer», jamás «vas bien, entrénale». ⚠️ **Sin validación en Cénit**: nace como
interpretación condicional con fallback, no como verdad fisiológica.

---

### FASE 4 · Contraste por tercios de la noche — *spec hija pendiente*

**Qué.** FC media del **primer tercio** menos la del **último tercio**, contra tu propio normal.
Separa «ayer entrenaste fuerte o tomaste» (golpea el principio de la noche) de «tu línea base se
movió» (parejo toda la noche).

**Respaldo mecanístico.** El alcohol eleva la FC nocturna y altera el sueño de forma asimétrica entre
la primera y la segunda mitad; el ejercicio vespertino intenso **eleva la FC nocturna** (Myllymäki).
⚠️ **NO promover el timing del nadir:** no existe validación revisada por pares de «nadir temprano =
mejor recuperación» — es una afirmación de producto de Oura. `NightAutonomicShape` ya calcula
`nadirHour` y **se queda descriptivo**, en el detalle de sueño.

**Alcance explícito: NO VOTA.** Nace como lectura descriptiva en el detalle. Promoverla al veredicto
requeriría evidencia que hoy no existe. Costo bajo: la serie de FC ya se lee.

---

### FASE 5 · El centinela pasa de «hoy» a rachas — *spec hija pendiente*

**Qué.** Hoy el centinela mira si temp **y** respiración se salen **hoy**. Alavi et al. 2022
(*Nature Medicine* 28(1):175–184) publicó `NightSignal`: una máquina de estados finitos determinista
sobre la **FC-reposo nocturna**, con 80 % de sensibilidad, 87.7 % de especificidad y mediana de 3 días
antes de los síntomas, en su cohorte.

⚠️ **Matices que la spec hija DEBE respetar:** (a) esos números son **de su cohorte con su FSM**, no
una promesa reproducible aquí — no citarlos como desempeño esperado de Cénit; (b) el paper **no
compara contra un umbral/z simple**, así que no hay evidencia publicada de que le gane a lo que ya
tenemos; (c) los propios autores reportan que **estrés, alcohol y viaje** disparan alertas; (d)
`NightSignal` es una FSM sobre umbrales — **v3 ya es de la misma familia**, así que esto es una mejora
de detección de *rachas*, no un cambio de paradigma. **Nunca decir «enfermedad»**: «algo se salió de
tu patrón, hoy ve leve».

---

### FASE 6 · N-of-1: que tus propios datos juzguen al veredicto — *requiere `/pm` + `/ux` antes que código*

**Por qué es el salto real.** Ningún fabricante puede demostrar que su veredicto predice algo
(Doherty/Altini 2025). Cénit tiene lo que ninguno: **offline, años de historia del mismo cuerpo**, y
los motores `MannWhitney` / `ExperimentVerdict` ya construidos.

**Qué.** Contrastar los días que el motor llamó `full` vs `easy` contra un **desenlace propio del
usuario** (tag de sesión, RPE, o un tap de «¿cómo te fue?»). Salida descriptiva:
*«en tus últimas N semanas, tu FC nocturna sí separó tus días buenos de los malos; tu temperatura no»*
— o, con la misma honestidad, *«todavía no separa nada»*.

**Es la única fase que pide algo al usuario** (registrar cómo le fue) → es un requerimiento de
producto antes que de ingeniería. Convierte el veredicto de **afirmación** en **hipótesis auditada por
los propios datos**, que es la postura defendible dada la literatura.

---

## 3 · Cómo trabajar cada fase (método que ya funcionó)

1. **Spec ejecutable** de la fase, aterrizada en los tipos reales (lee el código, no asumas firmas).
2. **Revisión adversarial con Grok** ANTES de codear. Vara: implementabilidad autónoma — que cace
   cada hueco donde un implementador tendría que adivinar. **Es debate, no dictadura:** defiende
   donde Grok se pase, concede donde tenga razón, itera hasta acuerdo.
3. **Implementación en carriles paralelos** con **dueño único de archivos** por carril y contratos de
   API fijados por adelantado (así codean sin esperarse). Los carriles que dependen de símbolos de
   otro van **secuenciales**.
4. **Verificación propia** (nunca el reporte del agente):
   ```bash
   cd ~/code/noop/Packages/StrandAnalytics && swift build && swift test
   cd ~/code/noop && xcodebuild -project Cenit.xcodeproj -scheme Cenit \
       -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -jobs 4 build
   ```
5. **Gates** antes de tocar producción: `/cso` (ciencia, si mueve umbrales o claims), `/estadistico`
   (si mueve fórmulas), `/qa` (verificador independiente), `/ux`+`/ui` si toca pantalla.
6. **Commit por fase**, push, y **NUNCA merge sin la validación del dueño en su iPhone**.

### Trampas conocidas (no re-descubrir)
- **Grok CLI headless:** `--permission-mode acceptEdits` es **no-op** para ediciones — usa
  `--allow 'Edit(**)' --allow 'Write(**)'` o el agente reportará trabajo hecho **sin haber escrito
  nada**. Verifica siempre el diff, no el reporte.
- **Un build a la vez**, siempre `-jobs 4`. Dos `xcodebuild` simultáneos revientan la RAM de la Mac.
- **`Localizable.xcstrings`:** el build de Xcode lo reformatea entero (~32k líneas) sin perder
  traducciones. Es ruido: descártalo (`git checkout --`).
- **Claves de día de una noche:** `localDayKey(endTs)` — el día en que **despiertas**. Convención ya
  establecida (`mergeSleep`, `apple_rmssd_night`).
- **`Repository.hrSamples(from:to:)` hardcodea el `deviceId` de la BANDA** (vacío en Apple-only). Para
  datos de Apple usa `store.hrSamples(deviceId: "apple-health", …)`.
- **`spark.last` ≠ `z7d`.** El primero es el z de esa noche; el segundo, el de la media de 7 días.
  Y `spark.last` solo es «la noche de hoy» si `asOfWasDense == true` y `confidence == .solid`; si no,
  `spark` está vacío o su último elemento es de otra noche.

---

## 4 · Deuda pendiente que este plan hereda

- **Doc:** el header de `Preparedness.swift` describe a O'Grady 2024 como «all day»; fue **5 min
  supino matutino**. Corregir la frase (la conclusión se sostiene).
- **Doc:** `docs/ANALYTICS.md` marca `NocturnalDC` y `ThermalStabilityEngine` como *library-only*,
  pero **ambos están cableados** (`SleepDetailScreen`, `SkinTempDetailScreen`). Tabla stale.
- **Doc:** `docs/_spec-veredicto-v3.md` sigue describiendo el diferido como pendiente; ya aterrizó.
- **Doc:** el header de `Preparedness.swift` sigue diciendo «deferred to the Repository wiring» /
  «Still outside the engine: the Repository wiring» — quedó stale con `9312dc78`.
- **UI — BLOQUEANTE DE MERGE, con dueño.** La pantalla Hoy en producción muestra el orbe autonómico
  con «3 SEÑALES»; con v3 **vota una sola**. Quedan **dos orbes** (En reposo · Sueño) + el tercero
  condicional que introduce la fase 2. **Dueño: `/ux` + `/ui`.** ⚠️ **La rama v3 no debe mergearse
  hasta que esta pasada exista**, o la pantalla afirmará algo que el motor ya no hace. Es la única
  deuda que bloquea; las de docs no.
- **Copy:** las 4 cadenas del veredicto deben quedar **descriptivas, nunca predictivas** («tus señales
  en reposo vs tu normal», jamás «vas a rendir peor»). *(Su alta en la allow-list de
  `docs/ANALYTICS.md` YA está hecha — verificado; no es deuda.)*
- **Validación:** los cortes de los 4 estados **no tienen validación prospectiva**. Rotular como
  aproximación; la fase 6 es la respuesta honesta a esto.

---

## 5 · Citas verificadas (para no re-verificar)

| Fuente | Qué sostiene |
|---|---|
| O'Grady 2024, *Sensors* 24(19):6220 | FC-reposo Apple MAE 3.73 bpm/MAPE 5.91 %; **SDNN** MAPE 28.88 %, sesgo −8.31 ms. **Protocolo: 5 min supino matutino.** |
| Dial 2025, *Physiol Rep* 13(16):e70527 | 536 noches vs ECG. RMSSD nocturno: Oura CCC 0.99/MAPE 5.96 %, WHOOP 0.94/8.17 %. FC nocturna MAE 0.98–1.78 bpm. **Apple Watch excluido.** |
| Herzig 2018, *Front Physiol* 8:1100 | RMSSD/HF ICC 0.84 en SWS; menor varianza entre segmentos; **algoritmo por HRV localiza SWS 87 % sin PSG**. |
| Schyvens 2025, *SLEEP Adv* 6(2):zpaf021 | Apple Watch S8: sensibilidad N3 **50.66 %**, REM 68.57 %, κ=0.53. |
| Alavi 2022, *Nat Med* 28(1):175–184 | `NightSignal` FSM sobre FC nocturna: 80 % sens., 87.7 % espec., 3 días pre-síntoma. |
| Nuuttila 2024, *Sports Med Open* 10:120 | Medidas nocturnas más sensibles a la carga que las matutinas; no intercambiables. |
| Doherty/Altini 2025, doi 10.1515/teb-2025-0001 | 14 scores de 10 fabricantes; **ninguno validado independientemente**. |
| Ungaro 2026, *Sensors* 26(4):1325 | Sentirse «con energía» se asocia **negativamente** con HRV (p<0.01). |
| Plews 2013, *Sports Med* 43(9):773–781 | Tendencia multi-día > valor de un día. *(La afirmación exacta se confirmó en fuentes secundarias.)* |
| Windred 2024, *Sleep* 47(1):zsad253 | Regularidad de sueño predice mortalidad mejor que duración. **Crónico, no agudo** → fuera del voto diario. |
| Esco & Flatt 2014, *J Sports Sci Med* 13(3):535–541 | HRV ultra-corta: validez aceptable a 60 s, degrada por debajo. |

**NO verificadas — no citar como hechos:** «el nadir temprano indica mejor recuperación» (regla de
producto de Oura, sin publicación); «en sueño profundo la FC cae 20–30 %» (solo blogs); el score
Nightly Recharge de Polar (método corroborado, score sin validación publicada).
