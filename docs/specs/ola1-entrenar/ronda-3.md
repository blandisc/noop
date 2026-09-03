# Ronda 3 · revisor adversarial (cierre N1–N8 + H9/H19 + hallazgos nuevos)

Base: `CONSOLIDACION-v3.md` manda sobre v2/v1/specs. Enmiendas E1–E20 no se re-reportan como hallazgos; sí se audita si v3 cierra de verdad y qué huecos nuevos abre.

## Cierre de la ronda 2

| Id | Veredicto | Una línea |
|---|---|---|
| N1 | **CERRADO** | Bifurcación editor (selector en plan por serie, long-press = borrar) vs sesión (long-press + chip 44 pt + VO); E15 sustituye E2 en editor. |
| N2 | **CERRADO** | Tres al límite consecutivas cuentan como estándar; CA `[met@10×3]`, n=2, `deferRaise=false` → `.readyToAdvance` (o `.deferred` si veredicto difiere); copy E16. |
| N3 | **CERRADO** | Cita reformulada «inspirado en session-RPE (Foster 2001), no literal»; pares con `sessionRpeSource`; no se exige `answered` (E17). |
| N4 | **CERRADO** | Drops nunca se promueven; huérfano en pos. 0 conserva `mode=drop`, solo volumen, pinta «↳ drop»; E18. |
| N5 | **CERRADO** | Default no importar en «Posibles duplicados»; toggle = forzar; copy Listo de excluidos (E19). Alinea con C8. |
| N6 | **CERRADO** | N = sesiones que el overlay fusiona; copy N=0 honesto (E19). |
| N7 | **CERRADO** | Motor ≤8 / ≥9,5 intacto; subtítulo nombra Q y 9,5 + tope de tres (E16). Keypad sigue sin emitir 9,5 (aceptable: hoja RPE sí). |
| N8 | **CERRADO** | Strike «se pregunta siempre»: no con `strainSource=hr` y cobertura ≥0,8; sí si cobertura &lt;0,8 (E17). |
| H9 | **CERRADO** | Sin votante nuevo; estimado entra por la vía de carga ya existente; etiquetas A·H9; nota a `/implement` sobre acta. |
| H19 | **PARCIAL** | Deselección declara «sin calificar», pero el mismo párrafo dice que cerrar/matar **acepta el prefill**; tras deseleccionar + cerrar no está definido si gana `nil` o `prefill`. |

## Hallazgos nuevos

## N9 · MEDIA · pieza ③ / editor
- Qué falla: v3/N1 afirma que el tipo se elige en «la hoja de plan por serie **que ya existe** (FER-492)» con selector «Trabajo · Calentamiento · AMRAP». FER-492 existe como tabla inline de reps/peso (`HojaTarjetaEjercicio` + keypad), **no** como hoja con selector de tipo. Hoy el calentamiento nace del «···» (`addWarmups` / rampa 40·60·80), no por tipo por fila; `RoutineSet.mode` aún no existe en modelo vivo. Además `equalizeAll` (`RoutineSheetLogic.swift:322-329`) solo copia `weightKg`/`reps`/`repsRangeTop` entre `.work` y `workSetsAreEqual` no compara `kind`/`mode`: al aterrizar AMRAP, «Igualar todas» puede dejar modos mezclados o fingir receta única.
- Evidencia: CONSOLIDACION-v3 A·N1 / E15; `Training.swift:115-140` (FER-492 = reps/peso; comentario histórico «kind always .work»); `HojaTarjetaEjercicio.swift:127-168` (tap → peso/reps, long-press → borrar; sin selector); `RoutineSetEditing.workSetsAreEqual` / `equalizeAll`.
- Por qué importa: un implementador busca un control que no está y o inventa una segunda puerta o deja el selector a medias; «Igualar todas» (flujo real de pirámides) borra la semántica nueva en silencio.
- Propuesta mínima: E15 debe decir «**agregar** selector de tipo a la fila/plan de serie (no existe hoy)» y fijar: (1) «Igualar todas» copia también `kind`+`mode` (o se deshabilita si hay modos distintos); (2) `workSetsAreEqual` incluye `mode`; (3) mapa explícito Trabajo=`work`+`standard`, Calentamiento=`warmup`, AMRAP=`work`+`amrap` (DROP sigue solo en sesión, como arq-B).

## N10 · MEDIA · pieza ① / H9 residual de ruta
- Qué falla: v3 cierra H9 diciendo que el estimado «entra por la misma vía que la carga medida (banda de carga del ACWR)» y pide verificar si esa banda vota en `Preparedness`. En código, el eje `load` de Preparedness **nunca voltea el veredicto** (solo `inRange`/`noData` por presencia de strain; comentario explícito «OUT logic is deferred… never flips the verdict»). El ACWR/`loadBand` vive en `ReadinessEngine`, distinto del oráculo de `allowsRaise` (`TrainingRegulation` ← veredicto Preparedness). La prosa de v3 mezcla dos motores.
- Evidencia: CONSOLIDACION-v3 A·H9; `Preparedness.swift:678-681`; `ReadinessEngine.swift:162-163,385-387`; `ProgressionPlanner.swift:77` (`deferRaise` ← `!allowsRaise(advice)`).
- Por qué importa: un implementador «obediente» puede cablear la banda ACWR como votante nuevo en Preparedness — justo lo que H9 prohíbe — o etiquetar «carga: estimada» en un acta que no usa esa banda.
- Propuesta mínima: enmendar H9/E a «el estimado alimenta `strainByDay` / overlay ACWR como el medido; **Preparedness.load hoy no vota**; no añadir votante; etiqueta «estimado» en recibo/detalle/Carga/costo de mañana; si en el futuro `/cso` enciende OUT de carga, entonces sí «carga: estimada» en el acta».

## N11 · MEDIA · transversal / criterios de aceptación
- Qué falla: varios CA de los specs quedan imposibles o contradichos por enmiendas vigentes (v2+v3) y nadie los invalidó en la lista E. Un QA que marque el checklist del spec falla el PR o exige el comportamiento viejo.
- Evidencia (contradicción → enmienda que manda):
  - **B1** «Tocar el numeral abre el menú» → E2/E15 (numeral solo lectura; editor = selector; sesión = long-press + chip).
  - **B2** menú editor Trabajo/Calentamiento/AMRAP/Quitar en numeral → E15 (selector en plan; quitar = long-press armado).
  - **B11** series −40 % y peso −10 % → E6 (`ligeraSeriesFactor=0.5`, `deloadFraction=0.075`).
  - **B14** «en semanas 1…N−1 no se muestra `.deloading`» → D1 (deload reactivo **sigue vivo** por ejercicio).
  - **C10** «Listo dice cuántas sesiones de los **últimos 28 días** entraron a la carga» → N6/E19 (N = fusión real del overlay; ventana ≠ «28 días» de ux-C).
  - (Ya cubiertos por E y no se reabren: edge 12 de ux-C clampear RPE&lt;6 → E12 nil; «pregunta siempre» arq-A → E17; huérfano→`standard` → E18; default importar A·H10 → E19.)
- Por qué importa: checklists de ux-B/ux-C son el contrato de QA; dejarlos vivos junto a E es la misma clase de defecto que N8 (texto no tachado).
- Propuesta mínima: bloque «CA invalidados» en consolidación (o strikes en ux-B/ux-C) con el reemplazo de una línea por cada ítem de arriba; C10 → copy de N6.

## N12 · BAJA · pieza ④ / copy
- Qué falla: el resumen de Listo (N5) dice «revísalos en **Ajustes › Importar**». La entrada real del spec es **Ajustes › Datos y fuentes › Importar** (ux-C flujo).
- Evidencia: CONSOLIDACION-v3 A·N5; ux-C.md «Ajustes › Datos y fuentes › Importar».
- Por qué importa: deep-link de copy incompleto; el usuario no encuentra la sección al primer intento.
- Propuesta mínima: alinear el string a «Ajustes › Datos y fuentes › Importar» (o al nombre localizado vigente de esa fila).

## Resumen

- Ronda 2: **CERRADO 9** (N1–N8, H9) · **PARCIAL 1** (H19) · **ABIERTO 0**
- Nuevos por severidad: **BLOQUEANTE 0** · **ALTA 0** · **MEDIA 3** · **BAJA 1** (total nuevos: 4)
- Hueco PARCIAL ≥ MEDIA que suma al contador: H19 (MEDIA→ALTA por contradicción deseleccionar vs cerrar; se cuenta como ≥ MEDIA)

HALLAZGOS NUEVOS: 5

CONVERGE: no
