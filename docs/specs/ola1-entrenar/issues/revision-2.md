# Revisión adversarial 2 · issues ola 1 (post-aplicación H1–H17)

Base: texto actual de `00-epico.md` + `01`–`14`; manda `../CONSOLIDACION-v5.md`; artefactos del dueño en `../artefactos/`; código solo-lectura en `/Users/fer.iracheta/code/noop/.claude/worktrees/new-session-ac9284`.

---

## Cierre H1–H17

- **H1** · CERRADO — `00` D-Q13 manda sobre E17/N8/v4 §C; `02` marca E17 retirada y separa pregunta vs fuente; `03` alinea «siempre».
- **H2** · CERRADO — ruta del taller = carpeta padre de `issues/` (ya no `ola1/ola1/`); `artefactos/` citado.
- **H3** · CERRADO — wave **2a** (E2+E4 ∥ E6+E10) y **2b** E8 tras merge E2; `08` declara dependencia E1+E2.
- **H4** · CERRADO — `02` ancla `endStrengthSession` `:191-198`, `AppleLoadEstimator.classify` `:86-97`, `attemptStrengthSave`; sin HealthKitBridge/`notOurs`.
- **H5** · CERRADO — UI 4…6 / import IA 4…8; `ProgramCalendar` no clampa; `unsupportedSemanas` sin clamp; `endMode` documentado en `01`/`10`; `11` riel 4·5·6.
- **H6** · PARCIAL — `StarterTemplates` solo en E10 y E4 ya no lo toca; **hueco:** `ProgressionState` + `ProgressionPlanner` siguen en E4∥E10 (wave 2a). Ver N1.
- **H7** · CERRADO — citas a `artefactos/ola1-pantallas.html` (§3b/§③/§4/§5); archivo presente en `../artefactos/`.
- **H8** · CERRADO — `07` ancla `setMenuItems` nuevo y aclara `exerciseMenuItems` ~:779; `00` reparte `SessionKeypad` (E5 labels / E7 `confirmSet`).
- **H9** · CERRADO — anclas por símbolo (`workSetHistory` ~:720, `lastWorkSets` ~:689, PRs ~:918/:935, `make` ~:1303); CA = censo de 4 call sites, no `grep "\.mode"`.
- **H10** · PARCIAL — A11 verificable (pliegue de puertas, estados del hub); Objetivo lista 4 superficies; **hueco:** A6 y la tabla siguen en 3, y «costo de mañana» no es superficie de «estimado». Ver N2.
- **H11** · CERRADO — teclado RIR = E5; `confirmSet`/menú = E7; E12 no reescribe esas cadenas.
- **H12** · CERRADO — cobertura = suma de intervalos Δt &lt; 300 s / elapsed (tiempo con FC plausible).
- **H13** · CERRADO — `endMode` amplía v2 §C; CA idempotente = 11 columnas listadas; tests `:1401-1445`.
- **H14** · CERRADO — tabla TipKit 6×(título·cuerpo) en `12`; E1 crea `tips-es.md`.
- **H15** · CERRADO — DoD de `03`/`05`/`09`/`11` con «nunca `es-MX`» (queda eco en `07` → N5).
- **H16** · CERRADO — `PastSession` `:52-59`, `classify` `:105-153`.
- **H17** · CERRADO — `08` expone `startTs`/`source`/`title` para el copy «Posibles duplicados · N · fuera» de `09`.

---

## N1 · ALTA · issue 00 / 04 / 10

**Qué falla:** La corrección de H6 sacó `StarterTemplates` de E4, pero en wave **2a** el worktree A (E4) y el B (E10) siguen editando los **mismos** archivos de progresión: `ProgressionState.swift` (`PastSession` gana `workSetRPE` en E4 y `deload` en E10; ambos tocan `classify`) y `ProgressionPlanner.swift` (`pastSessions`/`evaluate` vs exclusiones de deload / `raise = nil` en ligera). Dos ramas = conflicto de merge / tests `ProgressionStateTests` que se pisan.

**Evidencia:**
- `00` §Orden 2a: A = E2+E4 · B = E6+E10 en paralelo; solo reparte `StarterTemplates` y `AppModel+Strength`, no `ProgressionState`/`ProgressionPlanner`.
- `04` Alcance: `ProgressionState.swift` + `ProgressionPlanner.swift`.
- `10` Alcance: mismos dos + frontera `PastSession.deload`.

**Propuesta mínima:** En `00` §Orden 2a, añadir:

> E4 posee `ProgressionState`/`ProgressionPlanner` para `useRPE`/`workSetRPE`. E10 **no** edita esos archivos en 2a: la frontera `PastSession.deload` y `raise = nil` en semana ligera van en una **2c** (o al final de 2a en el mismo worktree que E4 tras merge), o E10 solo añade el campo `deload` vía patch rebaseado sobre E4.

Y en `10` Alcance: sustituir el toque a `ProgressionState`/`ProgressionPlanner` por «tras merge de E4» o mover esos hunks fuera del paralelo con E4.

---

## N2 · MEDIA · issue 03

**Qué falla:** H10 pidió alinear «cuatro superficies» con lo verificable. El Objetivo ahora enumera cuatro (recibo, detalle, Tendencias › Carga, «costo de mañana» del recibo), pero A6 solo exige tres y la tabla §Estados tiene tres columnas. Además el artefacto muestra «Costo cardiovascular» / caption «Cuenta en tu carga desde mañana» **sin** la palabra «estimado» — la 4.ª «superficie» es caption del recibo (ya contado) o un bloque distinto; un agente puede etiquetar «estimado» el costo cardiovascular o fallar A6 vs Objetivo.

**Evidencia:**
- `03` Objetivo: cuatro superficies incluyendo «costo de mañana».
- `03` A6: «(recibo, detalle, Carga)» — tres.
- `../artefactos/ola1-pantallas.html`: kicker «Esfuerzo · estimado» en el héroe; bloque aparte «Costo cardiovascular» sin «estimado».

**Propuesta mínima:** En `03`, unificar a tres superficies con «estimado» y borrar la 4.ª:

> Superficies con la palabra «estimado»: (1) recibo héroe (2) detalle (3) Tendencias › Carga. El caption «Cuenta en tu carga desde mañana» y el bloque «Costo cardiovascular» **no** llevan «estimado».

Y dejar A6 como está (tres). Alternativa: si el dueño quiere cuatro, enumerar la 4.ª con copy exacto que sí diga «estimado» y ampliar A6 + la tabla.

---

## N3 · MEDIA · issue 00 / 05 / 07 / 11

**Qué falla:** Tras H8, `00` reparte `SessionKeypad`, pero la wave 3 sigue en paralelo sin dueño de otros archivos compartidos. `EntrenarView` lo tocan E5 (`raiseLine` / hub RIR) y E11 (kicker/meta semana ligera). `RoutineSheetLiveTarjeta` lo tocan E5 (sufijo «· al fallo»), E7 (menú/chip/línea de tipo) y E11 (playhead «· ligera»). Tres worktrees sobre el mismo SwiftUI = conflicto o copy/gestos que se pisan.

**Evidencia:**
- `00` wave 3: propiedad explícita solo de `SessionKeypad` / tips.
- `05` Alcance: `EntrenarView.swift:371-383, 832-852`, `RoutineSheetLiveTarjeta` (sufijo).
- `07` Alcance: `RoutineSheetLiveTarjeta` (fila, `TapZonesSesion`).
- `11` Alcance: `EntrenarView` (kicker/meta/línea), `RoutineSheetLiveTarjeta` (playhead).

**Propuesta mínima:** En `00` wave 3, añadir:

> Propiedad adicional: E5 posee `EntrenarView` líneas de `raiseLine`/héroe RIR; E11 posee kicker/meta/línea de semana ligera (hunk distinto, no reescribir el de E5). E7 posee `RoutineSheetLiveTarjeta` (menú/chip/línea de tipo); E5 solo el sufijo «· al fallo» en la fila hecha; E11 solo el playhead «· ligera» — no editar el mismo hunk.

---

## N4 · BAJA · issue 07

**Qué falla:** H15 cerró `03`/`05`/`09`/`11`, pero `07` DoD sigue en «claves es/en» sin la regla del repo (`es`, nunca `es-MX`).

**Evidencia:** `07` Definition of Done: «claves es/en.» Contrastar `05`/`09`/`11`/`12`.

**Propuesta mínima:** En `07` DoD, sustituir por:

> claves `es` + `en` en el catálogo (nunca `es-MX`; gate i18n).

---

## Resumen

| Severidad | Conteo (hallazgos N de esta ronda) |
|---|---|
| BLOQUEANTE | 0 |
| ALTA | 1 |
| MEDIA | 2 |
| BAJA | 1 |
| **Total N** | **4** |

| Cierre H1–H17 | Conteo |
|---|---|
| CERRADO | 15 |
| PARCIAL | 2 (H6, H10) |
| ABIERTO | 0 |

HALLAZGOS NUEVOS: 4

CONVERGE: no

### Notas (sin hallazgo nuevo ≥ MEDIA)
- Anclas verificadas OK en worktree: `endStrengthSession` `:191-198`, `AppleLoadEstimator` `:86-97`, `addColumnIfMissing` `:941`, `MigrationTests` `:1401-1445` (wc 1445), `PastSession`/`classify`, `workSetHistory`/`lastWorkSets`/PRs/`make`, `exerciseMenuItems` `:779`, `ReadinessEngine.strainToLoad` `:637`, `RestActivityAttributes.returnDetail` ~`:49-52`, `Preparedness` load «never flips» `:677-681`.
- `TrainingWeeks.mondayFirst` está en `:35` (issue `10` cita `:36`) — ruido off-by-one, no elevado.
- `09` `DataSourcesView:177-217` + `:701-723` (extender `ImportTarget` / `handleImportResult`) cuadra con el código.
- Copy TipKit / Listo / recibo: no prometen cambio de veredicto; D-Q12 intacto.
- Lo que queda fuera de N1–N3 es BAJA (N4 + off-by-one). No inflar: el bloqueo real de converge es N1 (ALTA) + N2/N3 (MEDIA).
