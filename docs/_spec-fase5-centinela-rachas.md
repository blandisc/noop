# SPEC HIJA v2 — FASE 5 · El centinela pasa de HOY a RACHAS

> Estado: **v2 — cerrada tras 2 rondas adversariales (2 escépticos + Grok + /cso).** Todos los ejes en
> check. Aterrizada en firmas reales (`~/code/noop`, 2026-08-01).

## 0 · La bifurcación — RESUELTA (confirmada sólida por los 4 adversarios)
**(A) Extender el centinela existente (temp ∧ resp) a un estado con memoria** ← ELEGIDO.
**(B) FSM estilo NightSignal sobre la FC-reposo nocturna** ← RECHAZADO: la FC-reposo **ya vota** en el
eje autonómico (`wRHR=1`, verificado `:236`) → una FSM sobre ella la **cuenta dos veces** (FER-1010).
`/cso` verificó además que Alavi validó la persistencia **sobre RHR, no sobre temp∧resp** — otra razón
para no importar su mecanismo tal cual. **Fase 5 = memoria de rachas del centinela que YA existe.**

## 1 · Qué hace HOY (verificado byte a byte)
`Preparedness.swift:580-584`, en `rawVerdictAt` (un día, **sin memoria**):
```
tempHigh   = adjustedTempDev >= thermalOutC (0.8 °C ABSOLUTOS, solo lado alto)   // NO es z
respHigh   = -respZ >= respBadZ (1.5)                                             // sí es z
sentinelOut = tempHigh && respHigh          // AND — mata el cuarto caliente
out = a.isOut + s.isOut + sentinelOut        // sentinelOut = UN voto
```
`sentinelOut` es `let` local y se **descarta**; no está en `Read`. La pasada forward ya recorre toda la
historia (`hysteresed` corre `rawVerdictAt` por día, `:598-602`; **único llamador** — verificado).
Ajuste luteal **solo en `isAsOf`** (`:564-565`).

## 2 · Alcance cerrado
1. **Exponer el centinela en `Read`** (hoy se descarta) — campo `sentinel: SentinelRead?`.
2. **Racha del centinela** en la pasada forward, misma definición corroborada (temp ∧ resp).
3. **El voto NO cambia.** `.corroborated` del asOf = 1 voto (idéntico). La racha **no añade votos** → no
   re-gatea los tests congelados. Maneja **copy**, no votos, no momento de detección.

## 3 · Refactor de `rawVerdictAt` (F5-min — verificado de 1 línea)
```swift
private struct RawDay { let verdict: Verdict; let tempOut: Bool; let respOut: Bool }
private static func rawVerdictAt(...) -> RawDay      // cambia el tipo de retorno
```
`hysteresed` (único llamador, `:599`) usa `.verdict`. `tempOut`/`respOut` salen del **mismo** cálculo
que el voto → cero drift con el gating luteal/`isAsOf`.

## 4 · API cerrada
```swift
public enum SentinelState: String, Equatable, Sendable {   // sin Codable (Read no es Codable)
    case quiet, watchingOneSignal, corroborated
}
public enum SentinelSignal: String, Equatable, Sendable { case temp, resp }
public struct SentinelRead: Equatable, Sendable {
    public let state: SentinelState
    public let streakNights: Int
    public let watchingSignal: SentinelSignal?
    public let tempOut: Bool
    public let respOut: Bool
    public init(state: SentinelState, streakNights: Int, watchingSignal: SentinelSignal?,
                tempOut: Bool, respOut: Bool)
}
```
**En `Preparedness.Read` (`:140-186`):** `public let sentinel: SentinelRead?` **con default `= nil` al
FINAL del init** (F5-D2). Verificado: el init ya mezcla un default no-trailing (`signals = []`), Swift
lo permite, y los 6 sitios externos (`LiquidHoyBuilder.swift:624` y `:762`;
`LiquidHoyBuilderTests.swift:22,433,448,472`) **compilan sin tocarse** porque terminan en `trend:`.

## 5 · Regla ÚNICA de racha (resuelve F5-D1 + H1 + H2)
> `streakNights` = número de noches **de calendario contiguas** (cada una exactamente 1 día civil
> después de la anterior, comparando `ordered[i].day`), terminando en la asOf, cuyo estado es **igual**
> al de la asOf; y si es `.watchingOneSignal`, además con la **misma señal** (`watchingSignal`).
> **Rompen la racha:** (a) una noche `quiet`, (b) un cambio de estado, (c) un flip de señal, (d) un
> **hueco de calendario** — una fila AUSENTE o un salto de fecha > 1 día. **Si el estado de la asOf es
> `.quiet`, `streakNights = 0`** (H1).

⚠️ **Contigüidad por FECHA, no por índice (H2):** `Input.days` **no se rellena por calendario**
(`SourceFusion.mergeDaily:34-44` solo incluye fechas con fuente), así que una noche sin reloj es una
**fila ausente**, no una fila con `nil`. `ordered[i-1]` y `ordered[i]` pueden estar a días de
distancia. La racha DEBE comparar `day` civil, no posición en el array — o contaría «3 noches juntas»
a través de un hueco de una semana.

Casos zanjados (CA por cada uno, §7):
- corroborated·corroborated·**watching(temp)**=asOf → estado ≠ → `streak = 1`.
- watching(temp)·**watching(resp)**=asOf → flip → `streak = 1`.
- corroborated·corroborated·corroborated (contiguas) = asOf → `streak = 3`.
- corroborated·**[hueco de 2 días]**·corroborated=asOf → hueco rompe → `streak = 1`.

## 6 · Semántica de señal faltante
- `tempOut`/`respOut` usan `?? false` (`:581-582`): una señal `nil` **no está fuera**.
- `sentinel == nil` para la asOf **solo si temp ∧ resp ambas nil**. Si una está presente, el estado
  refleja lo presente.
- Una noche con **una** señal `nil` (fila presente) NO es corroborable → cae a `watching`/`quiet` →
  rompe una racha corroborada por la regla de igualdad-de-estado (§5). El hueco de **calendario** (fila
  ausente) lo rompe la cláusula (d).

## 7 · Criterios de aceptación (numéricos y testeables)
- **CA1 (paridad de voto + BUILD):** para cualquier serie, `verdict` **bit-idéntico** a hoy; suites
  congeladas (`testHysteresisVerdictSequence_frozen`, `PreparednessV3Tests`) verdes **sin editarse**;
  **y el target `Cenit` compila** (`xcodebuild`, no solo `swift test`).
- **CA2 (racha corroborada contigua):** 3 noches de fechas contiguas temp∧resp fuera → `.corroborated`,
  `streakNights == 3`.
- **CA3 (watching NO vota, fixture numérico):** `skinTempDevC = 0.9` (≥0.8) en 3 noches contiguas,
  `respRateBpm` en baseline → `.watchingOneSignal`, `watchingSignal == .temp`, `streakNights == 3`.
  Sanity: el `verdict` no cambia.
- **CA4 (transición corroborated→watching):** corroborated·corroborated·watching(temp)=asOf →
  `streakNights == 1`, `.watchingOneSignal`.
- **CA5 (flip de señal):** watching(temp)·watching(resp)=asOf → `streakNights == 1`.
- **CA6 (hueco de CALENDARIO rompe — H2):** filas de `2026-06-21` corroborated y `2026-06-24`
  corroborated=asOf, **sin filas 22/23** → `streakNights == 1` (no 2). Este CA prueba la contigüidad
  por fecha; sin ella daría 2.
- **CA7 (quiet → 0):** asOf en estado `quiet` → `streakNights == 0`.
- **CA8 (reset por quiet):** tras racha corroborada terminando en noche `quiet`, la siguiente
  corroborada arranca en `1`.
- **CA9 (independencia):** calcular la racha no altera `drivers`, `signals`, ni el eje autonómico.
- **CA10 (pureza):** determinista; mismo `Input.days` → mismo `sentinel`.

## 8 · Copy (gate `/cso` — PASS condicionado; estos guards son obligatorios)
- **NUNCA** «enfermedad» ni diagnóstico. Rectora: «algo se salió de tu patrón, hoy ve leve».
- **Prohibido el léxico de detección/predicción** (`detectar`, `detección`, `temprana`, `antes de`,
  `incubando`, `vas a`, `podrías estar`): el `verdict` es bit-idéntico → **no hay lead-time nuevo que
  prometer**; usarlo importaría el claim de Alavi que esta spec declara no portable.
- `.corroborated`, `streakNights==1`: «Tu temperatura y tu respiración se salieron **juntas** de tu
  patrón.» (aprobado tal cual por `/cso`).
- `.corroborated`, `streakNights>=2`: «…llevan **N noches** saliéndose juntas de tu patrón.» — número
  **factual, sin adjetivos de gravedad**. ⚠️ **La salience de la franja NO crece con N** (color solo
  cuando ambas se salen, no proporcional a la racha — DNA «color solo en el dato», plan padre L651).
- `.watchingOneSignal`: teñir solo esa señal (ámbar), **el veredicto NO cambia**.
- **Provenance resp:** evitar «tu respiración **ahora/en este momento**» — es promedio de sueño de
  Apple, no puntual. «tu respiración» a secas es correcto.
- **Rótulos de honestidad OBLIGATORIOS en la franja/detalle** (faltaban; paridad con plan padre L659):
  - «Cénit **describe** tu patrón; no detecta ni predice enfermedad.»
  - «Estos cortes **no tienen validación prospectiva**.»
  - «La evidencia de que una racha adelanta una infección es de **FC-reposo** (Alavi 2022), no de
    temp∧resp; aquí la racha **describe**.»
- **Cold-start:** `respZ` es `nil` hasta que hay baseline de resp → las primeras noches nunca alcanzan
  `.corroborated` (la racha está topada por construcción); `watching(temp)` sí puede aparecer antes. El
  copy no debe prometer rachas que la historia temprana no puede dar.

## 9 · Dueño de archivos
| Archivo | Rol |
|---|---|
| `Preparedness.swift` | `RawDay`, `SentinelState/Signal/Read`, racha (contigüidad por fecha) en la pasada forward, exponer en `Read` |
| `Cenit/Screens/Hoy/LiquidHoyBuilder.swift` | 2 sitios que construyen `Read` (`:624`, `:762`) — usan el default |
| `CenitUnitTests/LiquidHoyBuilderTests.swift` | 4 sitios de construcción de `Read` — usan el default |
| `Tests/.../PreparednessSentinelStreakTests.swift` (**nuevo**) | CAs |

La UI (franja «VIGILANDO/JUNTAS», plan padre L640-652) ya tiene dueño en la deuda de UI — esta spec le
da el dato (`sentinel.state` + `streakNights` + `watchingSignal`). Todo cambio de copy pasa por
`/ux`+`/ui`.

## 10 · Gates + rechazado explícito
Gates: `/cso` (Alavi no portable, «nunca enfermedad», rótulos de honestidad), `/qa`, `ci-app` (CA1
exige compilar el target). **Rechazado (no reabrir):** FSM sobre RHR (doble conteo §0); gate de
persistencia que retrasa el voto (latencia aguda); citar Alavi como desempeño de Cénit; votos por
longitud de racha; salience proporcional a N.
