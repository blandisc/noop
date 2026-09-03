# Ronda 2 · revisor adversarial (cierre H1–H24 + hallazgos nuevos)

Base: `CONSOLIDACION-v2.md` manda; enmiendas E1–E14 no se re-reportan. Gates biomecánico y estadístico integrados en v2.

## Cierre de la ronda 1

| Id | Veredicto | Una línea |
|---|---|---|
| H1 | **CERRADO** | Pares = cobertura ≥ 0,8 + RPE de series → `sessionRpe` prefill; sin pares, k constante de producto con banda (B1–B5). |
| H2 | **CERRADO** | Suma en TRIMP si no traslapa HKWorkout; máximo si traslapa; test `testDisjointWorkoutsAddInTrimp` (A·H2, E8). |
| H3 | **CERRADO** | Mapeo afín `cr10 = 1.5·rpe − 5`, constante, test, cita «Foster 2001 con escala RIR mapeada» (A·H3, E7). |
| H4 | **CERRADO** | Firma única con `trainedWeekStarts`; tests reescritos (E5). |
| H5 | **CERRADO** | `deload = 1` frontera; `optedOut` retirado; B14bis (E3). |
| H6 | **CERRADO** | `WorkingSet.reps` / `SetSnapshot.reps: Int?`; ✓ bloqueado si nil; test ida y vuelta. |
| H7 | **CERRADO** | Migración `DEFAULT 0`; plantillas nuevas encienden solo barra/compuestos (A·H7, E9, D3–D4). |
| H8 | **CERRADO** | Tope 3 al límite → cuenta estándar + copy; nunca baja peso solo por RPE; test del gate (A·H8, D2). |
| H9 | **PARCIAL** | v2 elige que el estimado mueva veredicto (Q11) con tres candados de etiqueta; el hueco: hasta tener ≥ 5 pares, k = 0,29 default sigue moviendo `allowsRaise` / costo de mañana como oráculo de cuerpo. |
| H10 | **CERRADO** | Dedupe estricto `source+startTs`; ±30 min → «Posibles duplicados» con toggle, default importar, sin omisión silenciosa (E10). |
| H11 | **CERRADO** | Dialecto `cenit` + test export→import con `set_mode`/`rpe`/`source` (E10). |
| H12 | **CERRADO** | Tabla canónica única en §C; conteos viejos de arq-A/B invalidados. |
| H13 | **CERRADO** | Numeral solo lectura; puerta = pulsación larga + chip de marca 44 pt (E2). |
| H14 | **CERRADO** | Rango 6–10; RPE importado &lt; 6 → `nil`; nunca clampear (E12). |
| H15 | **CERRADO** | Copy «Cuenta en tu carga desde mañana»; tile parcial fuera (E11, G). |
| H16 | **CERRADO** | `trimpPerAU` por sesión; refit por duplicación + histéresis 15 %; recomputo de todas las `.rpe` en un write (B3–B4, E7). |
| H17 | **CERRADO** | Sin FK; invariante de store renormaliza adyacencia; huérfano → `standard`; tests reorder/import (A·H17). |
| H18 | **CERRADO** | Familia única: `ligeraSeriesFactor = 0.5`, `deloadFraction = 0.075`; default `volumeOnly` (E6, D5). |
| H19 | **PARCIAL** | Cerrar = aceptar prefill; «Sin calificar» solo sin prefill; el hueco: con prefill no hay rechazo explícito y matar la app acepta el promedio de series como session-RPE. |
| H20 | **CERRADO** | Fixtures reales bloqueantes; `set_type` desconocido → omitir con conteo, no adivinar (E10). |
| H21 | **CERRADO** | Listo → CTA «Arma tu semana» si no hay plan; rutinas desde nombres siguen en ola 2 (E12). |
| H22 | **CERRADO** | VoiceOver: acciones personalizadas en la fila; sin rediseño de HojaMetrics (E2). |
| H23 | **CERRADO** | PR-esquema no mergea sin ARCHITECTURE §7 y DATA_MODEL v42/v43 (A·H23, §C). |
| H24 | **CERRADO** | Pie en detalle: «El 1RM estimado usa máximo 12 reps». |

## Hallazgos nuevos

## N1 · BLOQUEANTE · pieza ③ / UX
- Qué falla: E2 fija la puerta del menú de serie en **pulsación larga sobre la fila**. En el editor, esa misma fila ya tiene `LongPressGesture(minimumDuration: 0.4)` que arma el borrado de serie (`armedDeleteSetId`). Dos productos distintos pelean el mismo gesto.
- Evidencia: CONSOLIDACION-v2 E2 / A·H13; `HojaTarjetaEjercicio.swift:165-168` (long-press → delete arm); ux-B exige el menú en editor **y** sesión.
- Por qué importa: shippear E2 sin resolver el gesto rompe el borrado armado (patrón actual) o hace indescubrible el menú AMRAP/DROP; no es un detalle de copy.
- Propuesta mínima: en editor, puerta del menú = solo chip de marca (o «···» de serie); reservar long-press al armado de borrado. En sesión viva (sin ese long-press hoy), long-press de fila puede quedar. Documentar la bifurcación en E2.

## N2 · ALTA · pieza ②
- Qué falla: el tope «tras 3 al límite la sesión cuenta como estándar» no dice **qué** cuenta ni **cuándo**. Con `n = 2`, el test solo exige «no `.inCycle(0, of: 2)`»: puede ser `inCycle(1)`, `readyToAdvance` o un estado nuevo. Si las tres se reescriben como `met`, un usuario que califica 10 por costumbre **sube** tras tres sesiones al fallo de esfuerzo; si solo la tercera suma, sigue un ciclo más sin copy de «1 de 2».
- Evidencia: A·H8 + D2; test `[met@10×3]` con n=2; `ProgressionState.classify` hoy no tiene rama `atLimit` (ProgressionState.swift:120-139).
- Por qué importa: ambigüedad de implementación = dos comportamientos de progresión incompatibles; el copy «subes igual, o apaga Q» implica subida, el test no la exige.
- Propuesta mínima: regla explícita + test: tras 3 al límite consecutivos, esas 3 cuentan como `standard` en la racha (con n=2 → `.readyToAdvance` o `.deferred` según veredicto) **o** solo la 3ª abre conteo en 1 — elegir una y fijar el CA.

## N3 · ALTA · pieza ①
- Qué falla: la calibración de k usa pares con `sessionRpeSource = 'prefill'` (media de RPE de series), sin pregunta de sesión cuando hay cobertura ≥ 0,8. Foster session-RPE es un constructo **global post-sesión** (gate estadístico → CSO: riesgo de sesgo hacia la última serie / distinto del CR-10 de sesión). v2 cierra H1 permitiendo calibrar, pero calibra con otro instrumento.
- Evidencia: A·H1; B3 (pares con el mismo umbral de cobertura); gate-estadistico-1.md «Para el CSO» bullet 2; SessionKeypad guarda RIR→RPE por serie, no session-RPE.
- Por qué importa: k «personal» hereda un sesgo sistemático; el método citado («Foster 2001 con escala RIR mapeada») sobreafirma si los pares nunca fueron session-RPE contestado.
- Propuesta mínima: (a) pares de calibración solo con `sessionRpeSource = 'answered'`, o (b) citar el método como «AU desde media de RPE de series mapeada, calibrada contra TRIMP-HR» y no como session-RPE Foster literal; en ambos casos, test que documente la fuente del par.

## N4 · MEDIA · pieza ③ / consistencia de datos
- Qué falla: huérfano de drop se reetiqueta `standard`. Al dejar de ser drop, la serie pasa a contar para progresión, récords y 1RM (reglas D9 / arq-B: drop fuera de esos caminos). Un reorder/import torcido **promueve** trabajo silencioso.
- Evidencia: A·H17; gate biomecánico #6 (drop fuera de progresión/PR); filtros `lastWorkSets` / mode drop.
- Por qué importa: invariante «arregla» adyacencia inventando series de trabajo; peor que omitir el huérfano en conteos.
- Propuesta mínima: huérfano → `standard` **solo para pintura/volumen**, o marcar `mode = standard` pero excluir de progresión/PR hasta confirmación; mejor: al renormalizar, si queda huérfano tras reorder, eliminarlo o exigir «Convertir en serie» en Revisar/editor.

## N5 · MEDIA · pieza ④
- Qué falla: «Posibles duplicados» trae toggle con **default importar**. Cierra la omisión silenciosa (H10) pero el sesgo por defecto es doble conteo de volumen, mapa y (si hay RPE) esfuerzo estimado hasta que el usuario revise la sección.
- Evidencia: A·H10; ux-C job de Revisar; import Strong→Hevy del mismo gym el mismo día es el caso típico.
- Por qué importa: el usuario que toca «Importar» de corrido (flujo feliz) hincha historial; deshacer es más caro que no importar de más.
- Propuesta mínima: default **no** importar en la sección «Posibles duplicados» (siguen visibles, toggle on = forzar); o exigir un paso «Revisaste N posibles» antes de Guardar si N &gt; 0.

## N6 · MEDIA · pieza ① / ④
- Qué falla: B6 limita el overlay del ACWR a partir de la **primera fila base** (o `[hoy−56, hoy)` sin base), pero el copy de Listo dice «N sesiones de las últimas 8 semanas entran a tu carga» sin definir N. Si N = sesiones con RPE en 56 días y la base Apple empezó hace 10 días, el copy cuenta sesiones que **no** entran al ACWR.
- Evidencia: B6 + E12; test «5 años + 28 días Apple → ACWR ±0,05»; ux-C Listo.
- Por qué importa: misma mentira de cobertura que motivó el gate H7, ahora en el recibo de import.
- Propuesta mínima: N = conteo de sesiones que el overlay realmente fusiona (día ≥ primera base ∧ dentro de ventana); copy alterno si N = 0: «Tu historia alimenta récords; la carga espera a tu reloj».

## N7 · MEDIA · pieza ② / UX
- Qué falla: E13 nombra el interruptor «Subir según Q» con subtítulo «con Q 2 o más, sube en 1 · con Q 0, espera». La regla de motor sigue siendo RPE ≤ 8 / 8,5–9 / ≥ 9,5. El keypad solo emite RIR enteros (0…4+ → RPE 10…6); **nunca 9,5**. El subtítulo omite la banda media y colapsa «al límite» a Q 0 (RPE 10), distinto del umbral 9,5 del sheet.
- Evidencia: E13; SessionKeypad.swift:67-74 (`rirLabels`, RPE = 10 − RIR); arq-A `rpeLimitMin = 9.5`; EntrenarFilaEsfuerzo incluye 9,5.
- Por qué importa: el dueño lee Q y cree que apagar/encender sigue la fila 6–10; novatos con sheet en 9,5 quedan «al límite» sin que el subtítulo lo diga.
- Propuesta mínima: subtítulo alineado a la regla real («≤ 8 (Q ≥ 2) sube en 1 · 9,5+ (Q 0) espera · tres al límite: subes o apaga») o bajar el umbral de motor a RPE ≥ 10 si Q es la UI canónica.

## N8 · MEDIA · transversal / specs
- Qué falla: E7 sustituye el motor de arq-A (escala, k, mediana, refit, cobertura, overlay…) pero **no** tacha la frase «La pregunta se hace **siempre** (también con FC…)». A·H1 manda lo contrario cuando hay strain medido. Un implementador que aplique solo E7 sobre arq-A reabre H1.
- Evidencia: arq-A.md §① «Regla por sesión» párrafo de la pregunta; CONSOLIDACION-v2 A·H1 + E7; ux-A A4 ya dice no preguntar con medido.
- Por qué importa: v2 «manda», pero E es la lista explícita de texto que sustituye; este renglón quedó fuera y es el conflicto original de calibración.
- Propuesta mínima: ampliar E7 (o E11) con strike literal: «no se pregunta cuando `strainSource = hr` medido; cobertura &lt; 0,8 sí pregunta (B1)».

## Resumen

- Ronda 1: **CERRADO 22** · **PARCIAL 2** (H9, H19) · **ABIERTO 0**
- Nuevos por severidad: **BLOQUEANTE 1** · **ALTA 2** · **MEDIA 5** · **BAJA 0** (total nuevos: 8)
- Huecos PARCIAL ≥ MEDIA que suman al contador: H9 (ALTA), H19 (MEDIA)

HALLAZGOS NUEVOS: 10

CONVERGE: no
