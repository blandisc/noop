# UX · Ola 1 · piezas ① «carga sin FC» y ② «RPE gobierna la progresión»

## Inventario (lo que se reutiliza)
1. `RPESheet` + `EntrenarFilaEsfuerzo` (Cenit/Screens/LiveStrengthSheets.swift:20-153; StrandDesign EntrenarFilaEsfuerzo.swift): escala 6·7·8·9·9,5·10 con descriptores localizados. La pregunta de sesión es ESTA fila.
2. Recibo `summaryPhase` / `receiptHero` (LiveStrengthSheet.swift:1406-1585): ya degrada Esfuerzo→Duración vía `SessionEffortDisplay.resolve`; el bloque estimado sustituye el caso `.durationOnly`/`.durationWithHR`.
3. Glifo «estimado» `~N` (docs/design-system/LENGUAJE.md §5.6) y chip «Estimated» (WorkoutHistoryScreen.swift:1923-1946, WorkoutDetailScreen.swift:307-312).
4. `EntrenarHubHeroe.raiseLine` (EntrenarView.swift:371-383; copy `raiseText` 832-850 y «la subida espera» 852) y `ProgressionSetupScreen` filas + `SegmentedPillControl` (ProgressionSetupScreen.swift:110-141).
5. `ProgressionChip.summary` (RoutineSheetLiveLogic.swift:892-898); persistencia anti-crash FER-798 (AppModel+Strength.swift:226-332).

**Hallazgo de vocabulario (bloqueante para copy):** en la app la escala 0–21 se llama «Esfuerzo» (LENGUAJE §6; recibo `Effort`, Historial `Effort /21`) y «Carga» es el ratio ACWR (`TrainingLoadSheet` titula «Load»). La pieza ① produce un **Esfuerzo estimado (0–21)** que alimenta la Carga. El copy nunca dice «carga estimada» en el recibo: dice «Esfuerzo ~N /21 · estimado». El RPE por serie sigue llamándose «RPE» (FER-930).

## Flujo — «¿Qué tan duro estuvo?»
Vive en el recibo (`summaryPhase`), no en hoja previa ni posterior. Sin FC, el héroe del recibo (hoy «Duración») se vuelve el bloque de pregunta. Un solo foco: el numeral.
1. «Terminar» → «Guardar entrenamiento» (LiveStrengthSheet.swift:477-489). Se guarda igual que hoy; si ≥1 serie de trabajo trae RPE, se persiste ya el esfuerzo estimado con el promedio redondeado al escalón de la escala (prellenado = dato del usuario).
2. Recibo: cabecera «Sesión guardada» → titular → bloque héroe:
   - Sin FC, con prellenado: overline «ESFUERZO · ESTIMADO», numeral `~11,4` + «/21», pregunta «¿Qué tan duro estuvo?» con la fila de 6 celdas y la celda 8 marcada; caption «De 52 min a esfuerzo 8 · promedio de tus series».
   - Sin FC, sin prellenado: overline «ESFUERZO», numeral `—`, pregunta + fila sin marcar, caption «Sin respuesta no se estima. Un toque y entra a tu carga.»
   - Tocar una celda: numeral cambia en vivo, se escribe de inmediato (no espera a «Listo»), háptico de selección. La última gana.
3. Saltar = no tocar nada y dar «Listo». No hay botón «Omitir».
4. Cierro la app a la mitad del recibo: la sesión ya está guardada; el recibo no vuelve; con prellenado ya tiene estimado; sin prellenado queda «sin estimar» y se corrige desde el detalle. No se reabre la pregunta.
5. Corregir después: en el detalle (WorkoutHistoryScreen.swift:1778-1797) el héroe estimado es tocable y «···» gana «Calificar esfuerzo…» → `RPESheet` con cabecera «¿Qué tan duro estuvo?» · «Sesión · 52 min». Solo sesiones sin FC.
6. Sesión con Apple Watch: `strain` medido → héroe «Esfuerzo 13,8 /21» como hoy; NO se pregunta. Sí se pregunta cuando hubo reloj pero fue demasiado corta para puntuar (`.durationWithHR`) o la cobertura de FC fue insuficiente (umbral lo fija /estadistico).

## Estados por superficie (copy es-MX)
| Estado | Recibo | Detalle | Tendencias › Carga | Hub |
|---|---|---|---|---|
| Con reloj | «ESFUERZO» · `13,8` /21 (sin etiqueta) | como hoy; chip «Medido en el dispositivo» | curva como hoy; pie «Con FC de tu reloj» | `13,8` |
| Sin reloj, con respuesta | «ESFUERZO · ESTIMADO» · `~11,4` /21 · caption «De 52 min a esfuerzo 8» | `~11,4`, caption «Estimado de 52 min a esfuerzo 8. Toca para cambiarlo.»; chip «Estimado» | entra; pie «Incluye 3 sesiones con esfuerzo estimado» | `~11,4` |
| Sin reloj, sin respuesta | «ESFUERZO» · `—` · pregunta abierta | «Duración» + «Esfuerzo sin calificar · Calificar ›» | no cuenta; pie «1 sesión sin esfuerzo: no entra a la carga» | `—` |
| Importada con RPE | n/a | `~N`, caption «Estimado de tu historial importado»; chip «Estimado» | entra | `~N` |
| Importada sin RPE / manual sin respuesta | n/a | «Esfuerzo sin calificar · Calificar ›» | no cuenta | `—` |
| Manual (`ManualWorkoutSheet`) | campo opcional «¿Qué tan duro estuvo?» bajo «Duración» | igual | igual | igual |
| Error de guardado | numeral no cambia; toast `saveErrorToast` | idem | — | — |
Regla: «estimado» aparece una vez por superficie (overline o chip), nunca en el numeral ni dos veces.

## Pieza ② — héroe del hub y interruptor
Línea 2 nueva solo cuando el esfuerzo cambió algo (casos 1, 3, 5):
| Caso | Línea 1 | Línea 2 |
|---|---|---|
| Cómodo (todas ≤ 8) → sube en 1 | «Hoy subes: Press banca · 62,5 kg» | «Llegaste a las reps con esfuerzo 7. Una sesión bastó.» |
| Normal (8,5–9) | como hoy («1 de 2 para subir») | — |
| Al límite (alguna ≥ 9,5) → mantiene | «Hoy mantienes: Sentadilla · 100 kg» | «Llegaste, pero al límite (9,5). Una sesión más holgada y subes.» |
| Sin RPE | como hoy («2 de 2 · sin RPE») | — |
| Esfuerzo dice sube, veredicto dice mantén | «Hoy mantienes: Press banca · 60 kg · la subida espera» (EntrenarView.swift:852) | «Te la ganaste con esfuerzo 7; hoy tu cuerpo pide no subir. La tomas con un toque en la sesión.» |
Más de un ejercicio: línea 2 nombra al primero y termina «y 1 más».

**Interruptor «Usar mi esfuerzo (RPE)»**: `ProgressionSetupScreen`, fila después de «Subes cuando», `SegmentedPillControl` [Sí · No], encendido por defecto, deshabilitado si «Progresión automática» está apagada. Subtítulo: «cómodo (8 o menos) sube en 1 · al límite (9,5 o más) espera». Bloque consecuencia: «Con este plan: 4×8 con 60 kg dos sesiones seguidas → la próxima entrenas con 62,5. Con esfuerzo 8 o menos, con una basta.» Editor de rutina por slot (`ProgressionChip.summary`): «+2,5 kg cada 2 · con RPE ✓».

## Accesibilidad
- VoiceOver fila de esfuerzo: un solo elemento ajustable (patrón EntrenarStepperSegundos.swift:42-44): label «Esfuerzo de la sesión», value «8 de 10, esfuerzo duro, quedaban unas 2 reps», swipe recorre 6→10. Sin respuesta: «sin calificar». Numeral héroe: «Esfuerzo estimado, 11,4 de 21».
- Dynamic Type: línea 2 sin lineLimit; fila de 6 celdas pasa a 2 renglones de 3 desde AX1; celdas ≥ 44 pt.
- Háptico: selección al tocar; ninguno al prellenar. Reduce Motion: sin animación de numeral.

## Edge cases
1. Reloj se apaga a la mitad: FC «suficiente» = cobertura mínima de la duración activa (umbral /estadistico); por debajo se trata como sin FC y se pregunta; recibo «FC parcial: el esfuerzo se estima con tu respuesta».
2. Sesión corta con reloj: se pregunta; caption «FC promedio 128 bpm · demasiado corta para puntuar con FC».
3. RPE solo en algunas series: promedio de las que sí; calentamiento nunca; con ③ AMRAP cuenta, drop no.
4. Todo a RPE 10 por costumbre: se explica en línea 2; interruptor existe; no se corrige en silencio.
5. Cierre de app en recibo: cubierto.
6. Fin desde el Watch con teléfono bloqueado (FER-799): recibo en el siguiente foreground con el mismo bloque.
7. Pausas: duración activa (`elapsedSeconds`, FER-823); el caption enseña el número.
8. Sesión olvidada abierta (3 h): caption hace visible el error; si /estadistico pone tope, copy «duración limitada a N min para estimar».
9. Cambiar respuesta días después: Carga y veredicto recalculan solos.
10. Dos sesiones el mismo día (una con FC, otra sin): agregación la decide /estadistico; «estimado» solo en la sesión estimada.
11. RPE importado fuera de 6–10: no se estima; «sin calificar».
12. Un solo `MetricFormat.forMetric(.strain)` para medido y estimado.
13. Progresión apagada o interruptor en No: prellenado de ① sigue; héroe sin líneas de ②.
14. Veredicto pendiente: línea 2 no se pinta.

## Criterios de aceptación UX (A1–A18)
A1 Sesión sin FC con RPE → recibo abre con celda marcada y `~N` visible sin toque.
A2 Sin FC y sin RPE → `—`, pregunta, ninguna celda; «Listo» no genera estimado.
A3 Tocar celda cambia numeral en el acto y sobrevive a matar la app.
A4 Sesión con strain medido no muestra la pregunta en ninguna superficie.
A5 Con reloj sin puntuación (`.durationWithHR`) sí muestra la pregunta con caption de FC promedio.
A6 Detalle de sesión estimada: tocar héroe o «Calificar esfuerzo…» abre la escala; guardar cambia numeral y curva de Carga.
A7 Detalle de sesión medida: no existe «Calificar esfuerzo…».
A8 «estimado» aparece exactamente una vez por superficie en estados estimados; cero en medidos.
A9 Tendencias › Carga muestra procedencia con conteo de estimadas y sin esfuerzo.
A10 `ManualWorkoutSheet` muestra fila opcional; sin tocarla queda «sin calificar».
A11 Interruptor Sí + reps cumplidas + todas ≤ 8 → «Hoy subes…» + «Llegaste a las reps con esfuerzo N. Una sesión bastó.»
A12 Alguna ≥ 9,5 + reps cumplidas → «Hoy mantienes…» + «Llegaste, pero al límite (N)…»
A13 Raise ganada por esfuerzo + veredicto leve/recupera → «…la subida espera» + línea del cuerpo; sesión abre con peso anterior y subida a un toque.
A14 Interruptor No → comportamiento idéntico a antes de ②.
A15 VoiceOver lee la fila como un elemento ajustable con valor «N de 10, descriptor».
A16 AX5: héroe no trunca; fila de 6 en 2 renglones.
A17 Háptico de selección al tocar; ninguno al prellenar.
A18 «Otra forma ›» idéntico en los 8 estados (FER-85, EntrenarView.swift:893-898).

## Preguntas al dueño
1. ¿Preguntar también con reloj? Recomiendo no.
2. ¿Volver a mostrar la subida retenida en el héroe (FER-171 la quitó del v18, EntrenarView.swift:1456-1462)? Recomiendo sí, solo para el caso conflicto de ②.
3. ¿Interruptor por ejercicio o global? Recomiendo por ejercicio en ProgressionSetupScreen (columna en `routineExercise`, append-only) → ② deja de ser «sin migración».
