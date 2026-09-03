# Revisión adversarial 3 · issues ola 1 (post-aplicación N1–N4)

Base: texto actual de `00-epico.md` + `01`–`14`; manda `../CONSOLIDACION-v5.md`; artefactos del dueño en `../artefactos/`; código solo-lectura en `/Users/fer.iracheta/code/noop/.claude/worktrees/new-session-ac9284`.

---

## Cierre N1–N4 y parciales H6/H10

- **N1** · CERRADO — `00` mueve E10 a **2b** tras merge de A; E4 posee `ProgressionState`/`ProgressionPlanner` en 2a; `10` declara dependencia E1+E4 y hunks rebaseados; `StarterTemplates` solo E10.
- **N2** · CERRADO — `03` Objetivo unifica a **tres** superficies con «estimado»; caption/costo cardiovascular sin la palabra; A6 y la tabla alineados. Eco residual «cuatro» en Contexto → N5 (BAJA).
- **N3** · CERRADO — `00` wave 3 reparte `EntrenarView` / `RoutineSheetLiveTarjeta` / `SessionKeypad` por hunk y fija merge E3→E5→E7→E9→E11→E12.
- **N4** · CERRADO — `07` DoD: claves `es` + `en` (nunca `es-MX`; gate i18n).
- **H6** · CERRADO — vía N1: ya no hay E4∥E10 sobre progresión/`StarterTemplates`.
- **H10** · CERRADO — vía N2: tres superficies + A11 verificable (pliegue de puertas / estados del hub); el eco de Contexto es N5.

---

## N5 · BAJA · issue 03

**Qué falla:** El Contexto sigue diciendo «etiqueta «estimado» en **cuatro** superficies» mientras Objetivo, tabla y A6 mandan **tres**. Un agente que lea solo el párrafo de apertura puede reintroducir la 4.ª.

**Evidencia:** `03` l.2 «cuatro superficies» vs Objetivo «exactamente tres superficies» + A6 «(recibo, detalle, Carga)».

**Propuesta mínima:** En `03` Contexto, sustituir «cuatro» por «tres».

---

## N6 · MEDIA · issue 00 / 10

**Qué falla:** La wave **2b** arranca «**Tras mergear A**» (E2+E4). E10 (en 2b) usa `PlateMath.snap`, que **nace en E6** (worktree **B** de 2a) y no existe hoy en el worktree (`PlateMath` solo tiene `perSide`/`achievedKg`). Si /orquesta abre E10 con solo A mergeado, o reimplementa `snap` (duplicado) o no compila. Además E10 reescribe exclusiones en `StrengthStore`/`lastWorkSets` sobre la base que E6 acaba de tocar (drop/adyacencia).

**Evidencia:**
- `00` §Orden 2b: «Tras mergear A: ⑤ modelo (E10) … en paralelo, ④ lector (E8)».
- `06` Alcance: `PlateMath.swift (+snap)`; firma canónica en reglas.
- `10` Reglas: `volumeAndLoad` → peso × (1 − `deloadFraction`) «redondeado con `PlateMath.snap`»; depende solo de «E1 y E4», no de E6.
- Worktree: no hay `func snap` en `PlateMath.swift`.

**Propuesta mínima:** En `00` 2b:

> **Tras mergear A y B** (cierre de 2a): E10 rebaseado sobre E4 **y** E6 (`PlateMath.snap` + SQL de series); E8 en paralelo tras E2.

Y en `10`: «Depende de E1 + E4 + E6 mergeados».

---

## N7 · MEDIA · issue 00 / 02 / 06 / 08 / 10

**Qué falla:** `StrengthStore.swift` (~1000 líneas) queda sin dueño en los dos paralelos de paquetes. En **2a**, A (E2: `strengthCalibrationPairs` / `recomputeEstimatedStrain`) y B (E6: SQL de los 4 puntos, `workSetHistory`/`lastWorkSets`, invariante drop) editan el mismo archivo. En **2b**, E8 (`saveSessions` / `existingSessionIds`) y E10 (program CRUD + exclusiones `deload`) vuelven a pisarlo. Mismo modo de fallo que N1/N3: merge conflict o tests `StrengthStoreTests` que se pisan.

**Evidencia:** Alcances de `02`, `06`, `08`, `10` listan `StrengthStore`; `00` solo reparte `ProgressionState`/`Planner`, `StarterTemplates` y `AppModel+Strength` (E2 vs E10).

**Propuesta mínima:** En `00` 2a/2b, añadir:

> `StrengthStore`: en 2a, E6 posee SQL de series/`workSetHistory`/`lastWorkSets`/adyacencia; E2 solo métodos nuevos de calibración/recompute (hunk distinto). En 2b, E8 posee `saveSessions`/`existingSessionIds`; E10 posee program CRUD y exclusiones `deload` — no editar el mismo hunk; E10 rebaseado sobre E6.

---

## Resumen

| Severidad | Conteo (hallazgos N de esta ronda) |
|---|---|
| BLOQUEANTE | 0 |
| ALTA | 0 |
| MEDIA | 2 |
| BAJA | 1 |
| **Total N** | **3** |

| Cierre N1–N4 + H6/H10 | Conteo |
|---|---|
| CERRADO | 6 |
| PARCIAL | 0 |
| ABIERTO | 0 |

HALLAZGOS NUEVOS: 2

CONVERGE: no

### Notas (sin hallazgo nuevo ≥ MEDIA aparte de N6/N7)
- Oleadas 2a/2b y wave 3 con merge ordenado: el contrato de progresión/UI compartida quedó sólido tras N1/N3; lo que falta es el cierre de 2a (A+B) y el dueño de `StrengthStore`.
- Copy D-Q12 intacto: Listo/recibo/tips hablan de **carga**, no prometen cambio de veredicto; tip de reps en reserva («la app decide si subes») es progresión, no acta.
- Regla i18n `es` (nunca `es-MX`) cubierta en DoD de pantallas tras N4; encabezados «copy es-MX exacto» = idioma del copy, no la llave del catálogo.
- `06` lista `ProgressionState.swift (sin cambio de fórmula)` en paralelo con E4: ruido — quitarlo del Alcance al aplicar N7; los CA de AMRAP no exigen editar ese archivo (`metGoal` ya basta).
- Anclas spot-check OK: `PastSession` `:52`, `classify` `:105`, `mondayFirst` `:35`, `MigrationTests` 1445 líneas, `strainToLoad` `:637`, `returnDetail` en `RestActivityAttributes` `:52`.
- Fuera de N5–N7 solo queda BAJA (eco «cuatro»). No inflar: el bloqueo de converge es N6+N7 (MEDIA).
