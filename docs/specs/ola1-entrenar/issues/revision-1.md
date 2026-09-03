# Revisión adversarial 1 · issues ola 1 (contrato de implementación)

Base: `00-epico.md` + `01`–`14`; manda `../CONSOLIDACION-v5.md` sobre v4→v1; decisiones D-Q del épico; código solo-lectura en `/Users/fer.iracheta/code/noop/.claude/worktrees/new-session-ac9284`.

---

## H1 · BLOQUEANTE · issue 00 / 02 / 03

**Qué falla:** El contrato de «¿se pregunta con reloj?» queda en dos reglas opuestas. El épico D-Q13 y `03` mandan preguntar **siempre** (también con cobertura ≥ 0.8). `02` cita enmienda **E17** y el bloque C de v4, que tachan «siempre» y dicen **no preguntar** cuando `strainSource = 'hr'` (cobertura ≥ 0.8). Un agente que lea solo consolidación + E17 shippea sin pregunta; uno que lea solo D-Q13/E3 shippea con pregunta. No hay enmienda en v5 que retire E17 tras el CSO/`D-Q13`.

**Evidencia:**
- `00-epico.md` D-Q13: «Se pregunta … SIEMPRE al cerrar fuerza, también con reloj.»
- `03-carga-pantallas.md` §Comportamiento 5 + A4: «Con reloj: misma pregunta».
- `02-carga-motor.md` Contexto: cita `E17` (v2–v4).
- `../CONSOLIDACION-v3.md` N8/E17; `../CONSOLIDACION-v4.md` §C fila «arq-A · regla por sesión»: «No se pregunta con `strainSource = 'hr'` (cobertura ≥ 0,8) (E17).»
- `../cso-session-rpe-reloj.md` §3(a): preguntar siempre (base de D-Q13).
- `../CONSOLIDACION-v5.md`: no toca E17/N8.

**Propuesta mínima:** En `00-epico.md` y en `02`/`03`, añadir bloque canónico:

> **D-Q13 manda sobre E17/N8/v4 §C.** Se pregunta siempre al cerrar fuerza (también con cobertura ≥ 0.8). E17 queda **retirada** para la pregunta UI. La regla de *fuente* de `02` se mantiene: si `sessionRpe != nil` → `'rpe'`; si no y cobertura ≥ 0.8 → `'hr'`.

Y en `02` Contexto: sustituir «enmiendas E7/E8/E17/E22» por «enmiendas E7/E8/E22; **E17 retirada por D-Q13**».

---

## H2 · BLOQUEANTE · issue 00

**Qué falla:** La ruta del taller que el épico ordena leer **no existe** (`…/scratchpad/ola1/ola1/`). Hasta que E1 copie a `docs/specs/ola1-entrenar/`, un agente que siga el épico al pie no encuentra `CONSOLIDACION-v5.md` ni los specs.

**Evidencia:** `00-epico.md` línea de Fuentes: `…/scratchpad/ola1/ola1/`. `ls` de esa ruta → `No such file or directory`. Los specs viven en `…/scratchpad/ola1/` (un nivel arriba de `issues/`, no `ola1/ola1/`).

**Propuesta mínima:** En `00-epico.md`, cambiar la ruta a:

> `…/scratchpad/ola1/` (carpeta padre de `issues/`; **no** `ola1/ola1/`).

---

## H3 · BLOQUEANTE · issue 00 / 08

**Qué falla:** El orden en oleadas pone **E8 en paralelo con E2**, pero E8 llama APIs que E2 crea (`SessionRPE.prefill`, `SessionRPELoad`). Un worktree C que solo tenga E8 no compila / inventa el motor.

**Evidencia:**
- `00-epico.md` §Orden wave 2: `A = E2+E4 · B = E6+E10 · C = E8`.
- `08-import-lector.md` Persistencia: `sessionRpe = SessionRPE.prefill(sets)`, `strain = SessionRPELoad` … `strainSource = 'rpe'`.
- `02-carga-motor.md`: esos tipos nacen en E2 (`SessionRPELoad.swift`, `SessionRPE.swift`).

**Propuesta mínima:** En `00-epico.md` §Orden, reemplazar la wave 2 por:

> **2a** A = E2+E4 · B = E6+E10 (paralelo). **2b** C = E8 (después de merge de E2, o con E2 ya en la rama base del worktree).  
> En `08`: Dependencias explícitas: «Requiere E1 + E2 mergeados (tipos `SessionRPE` / `SessionRPELoad`).»

---

## H4 · ALTA · issue 02

**Qué falla:** El diagnóstico de contexto cita archivo:línea que **no respaldan** el claim (ruta inexistente / fuera de rango / tema distinto). Un agente que abra esas líneas no ve el bug descrito y puede «arreglar» el sitio equivocado.

**Evidencia (worktree `new-session-ac9284`):**
- `AppleLoadEstimator.swift` tiene **99** líneas; `:99-104` está fuera de rango. En `:77-78` el código dice lo contrario del claim: *«NEVER downgrade a known-workout day to `.rest`»*; `:97` solo marca `.rest` si **no** hay workout conocido y pasos/kcal bajos.
- `HealthKitBridge` **no** está en `Cenit/Data/HealthKitBridge.swift` (MISSING). Está en `CenitApp/Health/HealthKitBridge.swift`. `:803-808` es el predicado `notOurs` de lecturas HK (`HKSource.default()`), **no** la clasificación descanso/fuerza.
- `AppModel+Strength.swift:140-200` (citado «decidir fuente al guardar») es el fin de sesión desde Watch / `endStrengthSession`; el strain actual por FC está en `:191-198` y solo hace `StrainScorer.strain(hrSamples…)` — no hay decisión `sessionRpe`/`strainSource` ahí todavía.

**Propuesta mínima:** En `02` Contexto, sustituir la cita por evidencia verificable, p. ej.:

> Hoy `AppModel+Strength.endStrengthSession` (`:191-198`) solo escribe `strain` desde FC si `hrSamples.count >= 2`; sin FC la sesión queda sin strain. `AppleLoadEstimator.classify` (`:86-97`) marca `.rest` cuando no hay workout conocido y actividad baja — una sesión Cénit sin Watch no aporta HR de workout a ese día. Corregir glue en `AppModel+Strength.endStrengthSession` / `attemptStrengthSave` (no en `:140-200` del bridge Watch). Quitar la cita a `HealthKitBridge notOurs :803-808`.

Y en Alcance: `AppModel+Strength.swift` → anclar a `endStrengthSession` / save path reales, no `:140-200`.

---

## H5 · ALTA · issue 10 / 11

**Qué falla:** Rango de semanas y `endMode` no son un solo contrato. (a) Dentro de `10`, un CA clampa 4…8 y otro **erra** con `semanas: 9`. (b) UI de `11` solo ofrece 4·5·6; el modelo/import de `10` acepta hasta 8. (c) `endMode` aparece en E1/E10/E11 pero **no** en la tabla canónica v2 §C ni en v5 — drift sin enmienda.

**Evidencia:**
- `10` Reglas: import `semanas: Int?` (4…8; fuera → `unsupportedSemanas`); CA `ProgramCalendarTests`: «weeks fuera de 4…8 se **clampa**»; CA `WorkoutProgramTests`: «`semanas: 9` → **error**».
- `11` Crear: riel «4 · 5 · 6»; copy «Programa · 4 a 6 semanas».
- `../CONSOLIDACION-v2.md` §C `program`: sin columna `endMode`; `arq-B.md` igual. Solo issues la añaden.

**Propuesta mínima:** Unificar en `10` y `11`:

> **Semanas de producto (UI):** 4…6. **Import IA:** 4…8 (7–8 válidos; `semanas` fuera de 4…8 → `unsupportedSemanas`, no clamp silencioso). `ProgramCalendar` no clampa: recibe `weeks` ya validado.  
> Añadir a `01`/`10`: «`endMode` es pulido post-taller (D-Q implícito en E11 Al terminar); no está en v2 §C — forma parte del esquema v43 de este épico.»

Y corregir el CA de `ProgramCalendarTests` borrando «weeks fuera de 4…8 se clampa».

---

## H6 · ALTA · issue 00 / 04 / 10

**Qué falla:** Wave 2 pone en paralelo A (E4) y B (E10) tocando los **mismos** archivos de modelo (`StarterTemplates.swift`, `ProgressionState.swift`, y E10 además `ProgressionPlanner` / `AppModel+Strength` que E2 también toca). Dos worktrees = merge conflict / tests que se pisan (`testTemplatesTurnRPEOnForCompoundsOnly` vs motores `linear-novice`).

**Evidencia:**
- `04` Alcance + CA: `StarterTemplates.swift`, `ProgressionState.swift`, `testTemplatesTurnRPEOnForCompoundsOnly`.
- `10` Alcance + CA: mismos + `ProgramTemplate.materialize`, `linear-novice` con RPE off.
- `00` wave 2: A = E2+E4 · B = E6+E10 en paralelo.

**Propuesta mínima:** En `00` §Orden:

> E4 **no** edita `StarterTemplates` en wave 2; solo el motor `useRPE`. Flags de plantillas / `ProgramTemplate` / `materialize` van **solo en E10**.  
> En `04`: quitar `StarterTemplates.swift` del alcance y el CA `StarterTemplatesTests`; añadir «Plantillas: las marca E10; este issue solo consume `progressionUseRPE` ya persistido.»

---

## H7 · ALTA · issue 05 / 07 / 11 / 12

**Qué falla:** Varios issues citan el artefacto **«Ola 1 en pantalla»** (§3b/§3/§4/§5) como fuente de layout/copy, pero **no está** en la carpeta del taller ni en `docs/specs/`. Un agente no puede construir UI «según el artefacto».

**Evidencia:** Citas en `05`, `07`, `11`, `12`. Búsqueda bajo el scratchpad `ola1/` y `docs/specs` del worktree: no hay archivo con ese nombre. Los specs presentes son `ux-A/B/C.md`, consolidaciones, gates.

**Propuesta mínima:** O bien (preferido) copiar/adjuntar el artefacto a `docs/specs/ola1-entrenar/` en E1 y citar ruta estable; o bien en cada issue sustituir la cita por el spec que sí existe, p. ej. en `05`:

> Fuente: `ux-A.md §②` + E1/E13/E16 + D-Q1/D-Q6 (**sin** depender de «Ola 1 en pantalla»).

Y listar en el issue el wireframe mínimo (controles visibles / Ritmo / Ajustes finos) que ya está en el cuerpo — suficiente para codear.

---

## H8 · ALTA · issue 07

**Qué falla:** La cita de alcance `RoutineSheetLiveLogic.swift:779-851` **no** es el menú de tipo de serie. Hoy `:779` abre `exerciseMenuItems` (Mover arriba/abajo, estructura). El agente ancla el menú AMRAP/drop en el sitio equivocado. Además E5 y E7 tocan ambos `SessionKeypad` en la misma wave de pantallas.

**Evidencia:** Worktree: `RoutineSheetLiveLogic.swift:779` = `func exerciseMenuItems(ei:…)`. `07` Alcance lista `:779-851` junto a LiveTarjeta para el menú de serie. `05` y `07` ambos listan `SessionKeypad.swift` (labels «REPS EN RESERVA» / tecla `confirmSet` «máx»).

**Propuesta mínima:** En `07` Alcance, reemplazar la cita LiveLogic por el punto de extensión real (o «nuevo: `setMenuItems(ei:si:)` en LiveLogic + long-press en `HojaFilaSerie` / LiveTarjeta fila») y quitar `:779-851` como ancla del menú de serie. En `00` wave pantallas: «E5 posee labels RIR del teclado; E7 posee tecla `confirmSet`→«máx» y menú de serie — no editar el mismo hunk.»

---

## H9 · ALTA · issue 06

**Qué falla:** Varias anclas archivo:línea están desplazadas respecto al worktree actual; el CA `grep "\.mode"` es inverificable (demasiados falsos positivos tras implementar bindings).

**Evidencia (worktree):**
- `StrengthStore.workSetHistory` = **`:720`**, no `:729`.
- `lastWorkSets` = **`:689`**, no `:698`.
- `updatePersonalRecords` = **`:918`**, `recomputePR` = **`:935`** (no 919/937).
- `StrengthSessionModel.make` = **`:1303`**, no `:1315`.
- CA: `grep -rn "\.mode" Cenit` «solo en …» — tras el cambio, `.mode` aparecerá en modelos, SwiftUI, tests, widgets; el grep fallará o se «cumplirá» a mano.

**Propuesta mínima:** Actualizar anclas a las líneas actuales (o anclar por nombre de símbolo: `func workSetHistory`, `static func make`). Sustituir el CA grep por:

> Test/censo: los **cuatro** call sites de regla (`volume`/`progression`/`records`/`oneRepMax`) pasan por `SetMode.counts` / `SetEntry.counts(for:)`; ningún filtro nuevo `kind == .work` se edita (censo documentado en el PR).

---

## H10 · MEDIA · issue 03

**Qué falla:** (a) Objetivo habla de «**cuatro** superficies» con «estimado»; la tabla de estados solo lista tres (Recibo / Detalle / Tendencias › Carga). (b) A11 exige «Otra forma › idéntico en los **8 estados** (FER-85)» sin enumerar esos 8 estados — no es verificable.

**Evidencia:** `03` Objetivo vs tabla §Estados. A11 sin lista. FER-85 en código es el pliegue de puertas (`EntrenarView` «Otra forma ›»), no un enum de 8 estados de esfuerzo.

**Propuesta mínima:**
> Superficies con «estimado»: (1) recibo (2) detalle (3) Tendencias › Carga (4) **costo de mañana / caption del recibo** si aplica — o borrar «cuatro» y decir tres.  
> A11: ««Otra forma ›» permanece visible y con el mismo pliegue de puertas en todos los estados del hub de Entrenar tocados por esta ola (día de rutina, semana ligera vía E11, con/sin estimado); no se oculta ni se liga al veredicto (FER-85).»

---

## H11 · MEDIA · issue 05 / 07 / 12

**Qué falla:** Tres issues mezclan el mismo concern de vocabulario del teclado («REPS EN RESERVA», «· al fallo», tips TipKit del teclado). Riesgo de copy divergente y de doble PR sobre `SessionKeypad`.

**Evidencia:** `05` Fuera de alcance dice que el teclado va aquí; `07` §Comportamiento también redefine subtítulo «fallo» / «· al fallo»; `12` Capa 1+2 vuelve a barrer teclado y tip de reps en reserva.

**Propuesta mínima:** En `07`, borrar el párrafo del teclado RIR (dejar solo menú/máx/recibo/LA/Watch). En `12`, «Capa 1 teclado: **no reescribe** strings ya cambiados por E5; solo tips + glosario». En `05` DoD: «owner de las cadenas visibles del teclado RIR».

---

## H12 · MEDIA · issue 02

**Qué falla:** La fórmula de cobertura está escrita de forma ambigua («Σ huecos plausibles / elapsed»). Un agente puede implementar *fracción de huecos* en vez de *tiempo cubierto por intervalos inter-muestra &lt; 300 s*, pese a que el gate trae tests ancla.

**Evidencia:** `02` Reglas; `../gate-estadistico-1.md` H1: mismo wording + test «50 min con 12 min de FC → `.rpe`; con 41 min → `.hr`».

**Propuesta mínima:** En `02`, reemplazar la frase de cobertura por:

> `coverage = (suma de intervalos entre muestras consecutivas con Δt &lt; 300 s) / elapsedSeconds` (tiempo con FC plausible, no la fracción de agujeros). Medido ⇔ `hasEnoughData` ∧ `coverage ≥ minHRCoverage (0.8)`. Tests del gate H1 son la ancla.

---

## H13 · MEDIA · issue 01

**Qué falla:** `endMode` en v43 y la nota «12 columnas» del CA idempotente no cuadran con la tabla canónica v2 que el issue dice seguir; el patrón de tests cita `:1401-1449` pero `MigrationTests.swift` tiene **1445** líneas (OOB menor). Un agente que re-lea solo v2 §C omitirá `endMode`.

**Evidencia:** `01` v43 incluye `endMode`; `../CONSOLIDACION-v2.md` §C no. CA `testV42IsIdempotentWhenColumnsAlreadyExist` («12 columnas»). `MigrationTests.swift` wc = 1445.

**Propuesta mínima:** En `01` Reglas v43, añadir: «`endMode` amplía v2 §C (pulido de programa; ver E10/E11).» Corregir ancla de tests a `:1401-1445` (patrón `testV40AddsRestTakenS…`). Listar explícitamente las 11 columnas v42 + tabla v43 para el CA idempotente.

---

## H14 · MEDIA · issue 12

**Qué falla:** Los tips TipKit piden copy de dos líneas pero solo dan **un** ejemplo («las que puedas»). El resto de conceptos (drop, RIR, esfuerzo estimado, semana ligera, ritmo) quedan sin copy exacto — el agente inventará o preguntará.

**Evidencia:** `12` Capa 2: lista 6 conceptos; un solo ejemplo de copy.

**Propuesta mínima:** Pegar en `12` la tabla de 6×2 líneas (es-MX final) o citar archivo de copy en el taller / `docs/specs/ola1-entrenar/tips-es.md` creado en E1. Sin eso, el issue no es autocontenido.

---

## H15 · BAJA · issue 03 / 05 / 09 / 11

**Qué falla:** DoD dice «claves es/en» sin recordar la regla del repo: traducciones bajo la llave **`es`**, nunca `es-MX` (gate i18n). `12` sí lo dice; los de pantallas no.

**Evidencia:** `Tools/check-xcstrings-es.py` / `i18n-keys-baseline.txt`: «SIEMPRE bajo la llave «es», nunca «es-MX»». `12` Alcance lo cita; `03`/`05`/`09`/`11` DoD solo «claves es/en».

**Propuesta mínima:** En cada DoD de pantallas: «claves `es` + `en` en el catálogo (nunca `es-MX`)».

---

## H16 · BAJA · issue 04

**Qué falla:** Ancla `ProgressionState.swift:48-60` presenta `PastSession`, pero en el worktree `:48` es `deloadFraction` y `PastSession` empieza en `:52`. Ruido menor para el agente.

**Evidencia:** Archivo actual `:48-60` mezclado constante + struct.

**Propuesta mínima:** Citar `PastSession` / `classify` por símbolo, o `:52-59` y `:105-153`.

---

## H17 · BAJA · issue 08 / 09

**Qué falla:** E8 y E9 están alineados en duplicados (default fuera, N5), pero E8 no nombra el copy exacto de Revisar que E9 exige («Posibles duplicados · N · fuera»). Riesgo de strings distintos entre capa datos y UI.

**Evidencia:** `08` Reglas dedupe; `09` Paso 2 copy literal.

**Propuesta mínima:** En `08`: «La lista de posibles duplicados expone `startTs`/`source`/`title` para que E9 pinte el copy de `09` Paso 2 sin inventar campos.»

---

## Resumen

| Severidad | Conteo |
|---|---|
| BLOQUEANTE | 3 |
| ALTA | 6 |
| MEDIA | 5 |
| BAJA | 3 |
| **Total** | **17** |

HALLAZGOS NUEVOS: 17

CONVERGE: no

### Notas de pasada (sin hallazgo nuevo)
- **E2 vs E3 fuente por sesión:** con D-Q13 resuelto (H1), la cascada `sessionRpe` → else HR → else nil es coherente entre motor y pantallas; A5 (sin «Calificar» en medido) es producto deliberado, no contradicción interna.
- **E4 vs E5 ritmo:** mapeo Constante/Rápido/Según RIR ↔ `sessions`+`useRPE` alineado a D-Q1/D-Q6.
- **E6 vs E7 gestos:** modelo (E6) vs puertas UI (E7) bien partidos; el problema es ancla/citas (H8/H9), no la bifurcación editor/sesión (N9/E21/E26).
- **E8 vs E9 duplicados:** ambos default fuera (N5) — OK.
- **Copy veredicto (D-Q12):** no se encontró promesa de que una sesión cambie el veredicto en los issues; Listo/recibo hablan de **Carga**/ACWR. `13` backlog «la carga vota» está correctamente fuera de ola 1.
- **Offline / append-only / un oráculo / FER-85·171·251 / tokens:** E2 no añade votante; E11 no revive Crear plan (FER-251); E5 no reabre héroe (FER-171); migraciones E1 append-only. Sin violación adicional bloqueante más allá de lo listado.
