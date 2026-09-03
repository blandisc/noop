## Contexto
E2 aporta el motor; esta pieza es lo que el usuario ve: la pregunta al cerrar, la etiqueta «estimado» en tres superficies y la procedencia en Tendencias › Carga. Fuente: `ux-A.md §①` con enmiendas E11/E20/E24/E25 (v2–v5) y D-Q13 (manda sobre E17: se pregunta siempre, también con reloj); vocabulario: «Esfuerzo» = escala 0–21; «Carga» = ACWR.

## Objetivo
Al cerrar cualquier sesión de fuerza, el recibo pregunta «¿Qué tan duro estuvo?» con un toque; el esfuerzo estimado se muestra una vez por superficie con la palabra «estimado» (exactamente tres superficies: héroe del recibo, detalle de sesión, Tendencias › Carga; el caption «Cuenta en tu carga desde mañana» y el bloque «Costo cardiovascular» NO llevan «estimado») y nunca promete cambiar el veredicto.

**Carril:** pesado (toca el cierre de sesión y el guardado). Preview HTML/canvas con el dueño antes de codear la UI.

## Comportamiento esperado
1. «Terminar» → «Guardar entrenamiento» (como hoy). Se guarda la sesión con `sessionRpe = prefill` y `sessionRpeSource = 'prefill'` si hay prefill.
2. El recibo abre con el bloque héroe: overline «ESFUERZO · ESTIMADO», numeral `~11.4 /21`, pregunta «¿Qué tan duro estuvo?» y la fila `EntrenarFilaEsfuerzo` (6·7·8·9·9.5·10). Con prefill la celda aparece **sugerida** (estilo punteado, no seleccionada como respuesta); caption «Sugerido por tus series. Toca para confirmar o cambiar.». Sin prefill: numeral `—`, caption «Sin respuesta no se estima.»
3. Tocar una celda → `answered`, numeral cambia en vivo (numericText, sin count-up), háptico de selección, se persiste de inmediato. Tocar la celda seleccionada otra vez → deselecciona («sin calificar», `sessionRpe = nil`). Botón terciario «Sin calificar» visible solo sin prefill.
4. Cerrar el recibo (o morir la app) persiste **lo que está seleccionado en pantalla**: sugerida aún marcada → `prefill`; tocada → `answered`; ninguna → `nil`.
5. Con reloj: misma pregunta. El bloque muestra además «Costo cardiovascular · Ligero/Moderado/Alto» (existente) y FC media. Con reloj de cobertura ≥ 0.8 y sin respuesta, el héroe muestra el esfuerzo medido sin etiqueta «estimado».
6. Corregir después: en el detalle de la sesión, el héroe estimado es tocable y «···» gana «Calificar esfuerzo…» (abre `RPESheet` con cabecera «¿Qué tan duro estuvo?» · «Sesión · 52 min»). Cambiarlo recalcula Carga; copy «La Carga recalcula sola».
7. `ManualWorkoutSheet` gana la fila opcional «¿Qué tan duro estuvo?» bajo Duración.

## Estados (copy es-MX exacto)
| Estado | Recibo | Detalle | Tendencias › Carga |
|---|---|---|---|
| Esfuerzo por RPE (con o sin reloj) | «ESFUERZO · ESTIMADO» `~11.4` /21 · «De 52 min a esfuerzo 8» · «Cuenta en tu carga desde mañana» | `~11.4` + chip «Estimado» + «Toca para cambiarlo» | entra; pie «Incluye 3 sesiones con esfuerzo estimado» |
| Reloj suficiente, sin respuesta | «ESFUERZO» `13.8` /21 (sin etiqueta) + pregunta abierta | chip «Medido en el dispositivo» | curva como hoy |
| Sin reloj, sin respuesta | `—` + pregunta + «Sin calificar» | «Esfuerzo sin calificar · Calificar ›» | no cuenta; pie «1 sesión sin esfuerzo: no entra a la carga» |
| Importada con RPE | n/a | `~N` + «Estimado de tu historial importado» | entra, marca «estimada · importada» |
| Error de guardado | numeral no cambia; toast existente | idem | — |
Regla: la palabra «estimado» aparece exactamente una vez por superficie en estados estimados y cero en medidos. Ninguna superficie dice que una sesión cambia el veredicto.

## Accesibilidad
Fila de esfuerzo = un solo elemento ajustable (patrón `EntrenarStepperSegundos`): label «Esfuerzo de la sesión», value «8 de 10, esfuerzo duro, te sobraban unas 2 reps», swipe recorre 6→10; sin respuesta «sin calificar». Numeral «Esfuerzo estimado, 11.4 de 21». Dynamic Type: desde AX1 la fila de 6 pasa a 2 renglones de 3; celdas ≥ 44 pt. Reduce Motion: sin animación del numeral.

## Alcance técnico
`Cenit/Screens/LiveStrengthSheet.swift` (summaryPhase/receiptHero :1406-1585), `LiveStrengthSheets.swift` (RPESheet/EntrenarFilaEsfuerzo :20-153; añadir estilo «sugerido» a `EntrenarFilaEsfuerzo` en StrandDesign con #Preview), `WorkoutDetailScreen.swift`, `WorkoutHistoryScreen.swift:1778-1797`, `TrainingLoadSheet.swift` (pie de procedencia con `strengthEstimatedDays`), `ManualWorkoutSheet.swift`, `Cenit/App/AppModel+Strength.swift` (persistir sessionRpe/source al guardar y al cerrar el recibo). Solo tokens StrandDesign.

## Fuera de alcance
El motor y el overlay (E2). Tile «hoy parcial».

## Criterios de aceptación
- [ ] A1 Sesión con RPE por serie → recibo abre con celda sugerida (punteada) y `~N` visible sin toque; cerrar sin tocar guarda `sessionRpeSource == 'prefill'`.
- [ ] A2 Sin RPE por serie → `—`, pregunta, «Sin calificar»; cerrar sin tocar → `sessionRpe IS NULL`.
- [ ] A3 Tocar 9 → numeral cambia y `answered`; matar la app → persiste 9. Tocar 9 de nuevo → deselecciona → cerrar → NULL.
- [ ] A4 Con reloj de cobertura ≥ 0.8 la pregunta aparece igual; sin respuesta el héroe no muestra «estimado».
- [ ] A5 Detalle de sesión estimada: «Calificar esfuerzo…» existe; en sesión medida (hr sin respuesta) no existe.
- [ ] A6 «estimado» exactamente una vez por superficie (recibo, detalle, Carga) en estados estimados; cero en medidos (test de snapshot de accesibilidad o UI test).
- [ ] A7 Tendencias › Carga muestra el pie con conteo de estimadas y sin calificar.
- [ ] A8 `ManualWorkoutSheet` fila opcional; sin tocar → sin calificar.
- [ ] A9 VoiceOver: fila ajustable con el value especificado; AX5 sin truncar.
- [ ] A10 `grep` del catálogo de strings de Entrenar: ninguna clave nueva contiene «veredicto».
- [ ] A11 «Otra forma ›» permanece visible con el mismo pliegue de cuatro puertas en todos los estados del hub tocados por esta ola (día de rutina con/sin estimado, semana ligera vía E11); no se oculta ni lee el veredicto (FER-85, `EntrenarView.swift` «Otra forma ›»).

## Definition of Done
- [ ] Preview aprobado por el dueño (canvas/inject o HTML). `Tools/verify.sh app` verde. Claves `es` + `en` en el catálogo (nunca `es-MX`; gate i18n). /qa PASS.
