# Revisión adversarial 4 · issues ola 1 (post-aplicación N5–N7)

Base: texto actual de `00-epico.md` + `01`–`14`; manda `../CONSOLIDACION-v5.md`; artefactos del dueño en `../artefactos/`; código solo-lectura en `/Users/fer.iracheta/code/noop/.claude/worktrees/new-session-ac9284`.

---

## Cierre N5–N7

- **N5** · CERRADO — `03` Contexto ya dice «etiqueta «estimado» en **tres** superficies»; alineado con Objetivo, A6 y la tabla.
- **N6** · CERRADO — `00` 2b arranca «**Tras mergear A y B**»; E10 rebaseado sobre E4 **y** E6 (`PlateMath.snap` + SQL); `10` declara «Depende de E1, E4 y E6 mergeados».
- **N7** · CERRADO — `00` reparte `StrengthStore` en 2a (E6 SQL/series vs E2 calibración/recompute) y 2b (E8 `saveSessions` vs E10 program/deload); `06` saca `ProgressionState` del Alcance (E4 dueña).

---

## N8 · BAJA · issue 03

**Qué falla:** La fila de accesibilidad del esfuerzo prescribe el value «quedaban unas 2 reps», que choca con el vocabulario del épico (nunca «Quedaban») y con el CA de E12/`05` que grepea esa forma.

**Evidencia:** `03` Accesibilidad l.29 vs `00` vocabulario + `12` CA («Quedaban»).

**Propuesta mínima:** Sustituir por algo como «te sobraban unas 2 reps» / «2 reps en reserva».

---

## Resumen

| Severidad | Conteo (hallazgos N de esta ronda) |
|---|---|
| BLOQUEANTE | 0 |
| ALTA | 0 |
| MEDIA | 0 |
| BAJA | 1 |
| **Total N** | **1** |

| Cierre N5–N7 | Conteo |
|---|---|
| CERRADO | 3 |
| PARCIAL | 0 |
| ABIERTO | 0 |

HALLAZGOS NUEVOS: 0

CONVERGE: sí

### Notas (sin hallazgo ≥ MEDIA)
- Dependencias 2a/2b y wave 3: A∥B → merge A+B → E10/E8; pantallas con dueños de hunk + merge E3→E5→E7→E9→E11→E12. Contratos de `PlateMath.snap`, `ProgressionState`/`Planner` y `StrengthStore` cerrados.
- Copy D-Q12/N13 intacto: recibo («Cuenta en tu carga…»), Listo («N sesiones entran a tu carga»), tip de esfuerzo y edge «La Carga recalcula sola» — ninguno promete cambio de veredicto.
- Regla i18n `es` (nunca `es-MX`) en DoD de pantallas; encabezados «copy es-MX exacto» = idioma del copy, no llave del catálogo.
- Anclas spot-check OK: `PastSession` `:52`, `classify` `:105`, `mondayFirst` `:35`, `MigrationTests` 1445 líneas, `strainToLoad` `:637`, `returnDetail` `:52`, `workSetHistory` `:720`, `lastWorkSets` `:689`; `PlateMath.snap` aún ausente (lo entrega E6).
- Fuera de N8 solo queda ruido operativo (p. ej. `LiveStrengthSheet`/`WorkoutDetail` tocados por E3 y E7 bajo merge ordenado). No inflar: cero ≥ MEDIA.

## Veredicto final

El contrato de la ola 1 está sólido para `/orquesta`: waves, dependencias (E10←E4+E6, E8←E2), propiedad de archivos compartidos y copy D-Q12 cierran sin contradicción ≥ MEDIA. CONSOLIDACION-v5 manda; N5–N7 aplicados. Riesgo residual mayor al ejecutar: reintroducir un votante de carga o un copy que prometa veredicto, o pisar hunks de `StrengthStore`/`LiveStrengthSheet` si un lane ignora el orden de merge — no un hueco del papel. N8 (BAJA, «quedaban» en VO) se puede corregir en el spec de E3 o al teclear.
