# Ronda 4 · revisor adversarial (cierre N9–N12 + H19 + hallazgos nuevos)

Base: `CONSOLIDACION-v4.md` manda sobre v3/v2/v1/specs. Enmiendas E (v2/v3/v4) y bloque C de v4 no se re-reportan como hallazgos; sí se audita si v4 cierra de verdad y qué huecos nuevos abre (sobre todo lo que v4 introduce).

## Cierre de la ronda 3

| Id | Veredicto | Una línea |
|---|---|---|
| N9 | **CERRADO** | E21: tecla «máx» en techo de reps + toggle «Última serie AMRAP» en «···»; `mode` en `workSetsAreEqual` / «Igualar todas»; mapa Trabajo/Calentamiento/AMRAP; keypad del editor **sí** tiene celda de techo (`EditorCell.Field.repsTop` → `repsRangeTop`, `HojaFilaSerieTapZones.onRepsTop`). |
| N10 | **CERRADO** | E22 sustituye A·H9: estimado → overlay ACWR + presencia en acta; **sin votante**; carga no voltea veredicto (`Preparedness.swift:677-681` verificado); Q12. |
| N11 | **CERRADO** | Bloque C canónico de CA sustituidos (B1/B2/B11/B14/C8/C10/edge12/A13/interruptor/A2/arq-A CA4+pregunta/arq-B semana+descarga+deload). Huecos de copy fuera de esa lista → hallazgos nuevos. |
| N12 | **CERRADO** | E23: «Ajustes › Datos y fuentes › Importar». |
| H19 | **CERRADO** | E24: al cerrar (o morir la app) persiste la selección en pantalla; deseleccionar → `nil`; test prefill 8 → deseleccionar → cerrar → `sessionRpe = nil`. |

## Hallazgos nuevos

## N13 · MEDIA · pieza ① / ④ · Q12 copy residual
- Qué falla: v4/N10 deja claro que **ninguna carga cambia el veredicto** en ola 1, pero el copy de círculo ④ (y un edge de ①) sigue prometiendo que sí. El bloque C sustituye C10 (el conteo N) y **no** tacha esas frases de veredicto.
- Evidencia (dónde corregir):
  1. `ux-C.md` **Paso 4 · Listo** (≈L24): «12 sesiones recientes entran a tu carga. **Tu veredicto de mañana puede cambiar.**»
  2. `ux-C.md` **Relación con ①** (≈L45): «Si cae en los últimos 28 días, **el veredicto de mañana puede moverse**; Listo lo anuncia con número.»
  3. `ux-A.md` edge **9** (≈L63): «Cambiar respuesta días después: **Carga y veredicto recalculan solos.**» (la Carga sí; el veredicto no por el eje de carga).
  - No está en bloque C; Q12 lo nombra como la promesa rota; ronda-1 H9 ya citaba el string de Listo.
- Por qué importa: Listo es la superficie que celebra el import; shippear «puede cambiar» cuando `Preparedness.load` «never flips the verdict» es la misma clase de mentira sobre el cuerpo que H9/N10 cerraron en el motor.
- Propuesta mínima: enmienda/bloque C — (1) Listo: solo el copy de N6/C10 («N sesiones… entran a tu carga» / alterno N=0), **sin** frase de veredicto; (2) Relación con ①: «entran a Carga/ACWR etiquetadas; el veredicto no cambia hasta que la carga vote (/cso, Q12)»; (3) ux-A edge 9: «Carga recalcula; el veredicto solo si otros ejes cambian» (o «Carga recalcula sola»).

## N14 · MEDIA · transversal · Q11 vs Q12
- Qué falla: v4 §D deja **Q11 sin cambio** (rec. «sí mueve el veredicto de mañana… con los candados de A·H9») y a la vez introduce **Q12** (la carga no vota; rec. **no** meter el voto en ola 1). N10/E22 ya sustituyeron A·H9. El dueño recibe dos recomendaciones opuestas sobre el mismo eje.
- Evidencia: `CONSOLIDACION-v2.md` F·Q11; `CONSOLIDACION-v4.md` D («Q1–Q4, Q6–Q11 sin cambio» + Q12); E22 «Sustituye A·H9 de v2 y v3».
- Por qué importa: Q12 se declara «la más importante»; dejar Q11 viva con la rec. vieja invita a reabrir el votante o a cablear copy de acta «carga: estimada» como si moviera `allowsRaise`.
- Propuesta mínima: en D, marcar Q11 **retirada / absorbida por Q12** (o reescribir Q11 a «solo Tendencias/ACWR en ola 1; voto de carga = issue ola 1b»).

## N15 · MEDIA · pieza ③ / E21 incompleto en superficies vecinas
- Qué falla: E21 exige `mode` en `workSetsAreEqual` y en `equalizeAll`, y «con modos mezclados la receta se abre en renglones». Quedan dos caminos del editor que hoy tratan la receta **sin** `mode` y v4 no los nombra: (1) `mirrorAcrossRoundsIfSuperset` / `roundsAreEven` solo copian/comparan `weightKg`/`reps`/`repsRangeTop` — AMRAP por «máx» en una ronda de superserie no se espeja y `roundsAreEven` puede dar true con modos distintos; (2) `recetaCount` clave `"peso-reps-techo"` sin `mode` → con solo modo distinto, `setsAreEqual` abre filas pero el chip dice «1 recipes».
- Evidencia: `CONSOLIDACION-v4` A·N9 / E21; `RoutineSheetKeypad.swift:41-68` (mirror / roundsAreEven); `RoutineSheetLogic.swift:296-329` (`recetaCount` / `equalizeAll`); `HojaPlegada.swift:19-20`.
- Por qué importa: v4 cerró el agujero de «Igualar todas» y dejó el espejo de superserie (flujo real post-agrupar) y el contador de recetas con la misma clase de silencio que N9 reportó.
- Propuesta mínima: ampliar E21 — `mirrorAcrossRoundsIfSuperset` y `roundsAreEven` incluyen `mode`; `recetaCount` (y cualquier clave de igualdad de receta) incluye `mode`; tests: AMRAP en última serie → receta abierta **y** label ≠ «1» si solo difiere el modo; espejo de superserie propaga `mode`.

## N16 · BAJA · pieza ③ / tecla «máx» sin anclar al API del keypad
- Qué falla: E21 dice que el keypad gana «máx» al editar el techo, pero no fija el hueco UI. En el editor `SessionKeypad` monta `confirmSetEnabled: false` (esquina ✓ Serie apagada) — es el slot natural; sin decirlo, un implementador puede inventar tecla quinta o meter «máx» en la barra de accesorios.
- Evidencia: E21; `RoutineSheetKeypad.swift:154-173`; `SessionKeypad.swift` rejilla 4×4 con `.confirmSet` (L247-278).
- Por qué importa: detalle de implementación, no bloquea el diseño; sí evita un rediseño accidental del pad.
- Propuesta mínima: una línea en E21 — «máx» reusa la tecla de acción inferior-derecha (`confirmSet`) solo con `field == .repsTop` y serie `.work`; en piso/peso sigue oculta/deshabilitada.

## Resumen

- Ronda 3: **CERRADO 5** (N9–N12, H19) · **PARCIAL 0** · **ABIERTO 0**
- Nuevos por severidad: **BLOQUEANTE 0** · **ALTA 0** · **MEDIA 3** · **BAJA 1** (total nuevos: 4)
- No quedan solo cosas BAJA: N13–N15 son MEDIA (copy Q12, Q11×Q12, mode en mirror/recetaCount).

HALLAZGOS NUEVOS: 4

CONVERGE: no
