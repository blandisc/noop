# Ronda 1 · hallazgos

## H1 · BLOQUEANTE · pieza ①
- Qué falla: usuario con Apple Watch que sí marca RPE por serie. CONSOLIDACION R1 prohíbe la pregunta de sesión cuando hay FC; arq-A exige pares `(AU, TRIMP)` con `strainSource == .hr` **y** `sessionRpe` contestado para calibrar `k`. Sin pregunta y sin regla explícita de persistir el prefill como `sessionRpe`, **k nunca sale del default 0.25**. Quien sí tiene TRIMP real (reloj) no calibra; quien no tiene reloj estima con una constante inventada.
- Evidencia: CONSOLIDACION-v1.md R1; arq-A.md §① motor (`fitTrimpPerAU`, `minCalibrationPairs = 5`, pares hr+sessionRpe) y «La pregunta se hace siempre»; ux-A.md A4 (no preguntar con strain medido).
- Por qué importa: la app cita Foster y etiqueta «estimado» mientras la escala al 0–21 descansa en un default confesado como no validado.
- Propuesta: fijar una sola regla: o (a) persistir `sessionRpe = SessionRPE.prefill` en silencio en sesiones hr cuando hay RPE de series (y documentar que no es «contestado»), o (b) pedir confirmación mínima solo la primera N veces con FC, o (c) matar la calibración en ola 1 y tratar `k` como constante de producto con banda de prueba publicada.

## H2 · BLOQUEANTE · pieza ①
- Qué falla: día con carrera/caminata medida por Apple (strain 14) y pesas en Cénit sin reloj (estimado 11). Overlay hace `max(Apple, Σ sesiones)` → 14. Las pesas **no entran** a la carga del día. El copy de ①/④ dice que la sesión estimada «entra a tu carga».
- Evidencia: CONSOLIDACION-v1.md «por día `max(medido Apple, Σ sesiones en TRIMP)`» y arq-A.md §Regla por día puntos 3–4 (admite «Sub-cuenta un día carrera+pesas»); ux-A.md tabla «Sin reloj, con respuesta → entra»; ux-C.md «Estas entran a tu carga como estimada».
- Por qué importa: miente sobre el cuerpo del híbrido cardio+fuerza, el usuario típico de Cénit+Health.
- Propuesta: `combined = trimpToStrain(strainToTrimp(base) + Σ strainToTrimp(sesiones_Cénit))` cuando las sesiones Cénit no tienen espejo HK propio; reservar `max` solo si `deviceId`/HKWorkout propio del mismo intervalo indica solape (el caso Watch Workout que motivó el max).

## H3 · BLOQUEANTE · pieza ① / transversal
- Qué falla: la pregunta/prefill usa la fila 6·7·8·9·9,5·10 (RIR/RPE de serie). Foster session-RPE es CR-10 (anclas desde ~5). arq-A dice `rpeMin = 5`, «se usan directo, sin mapear; gate /cso». BRIEF pide pregunta 5–10. CONSOLIDACION R2 reutiliza la fila 6–10 y deja el mapeo a /cso. Se puede shippear ① calculando AU = min × 6…10 como si fuera CR-10.
- Evidencia: BRIEF.md pieza ①; LiveStrengthSheets.swift:28-30 (`scale = [6,7,8,9,9.5,10]`); SetEntry documenta RPE 6–10 (Training.swift:333-334); arq-A.md §① «Escala: la pregunta del recibo (5–10) es CR-10»; CONSOLIDACION-v1.md R2.
- Por qué importa: matemática citada que no implementa la escala del paper = claim falso con barniz académico.
- Propuesta: o mapear explícito `(rpeSerie → CR10)` con constante nombrada + test + cita, o renombrar el método a «session-RPE adaptado a escala 6–10 (no Foster literal)» y no citar Foster 2001 como identidad.

## H4 · BLOQUEANTE · pieza ⑤
- Qué falla: CONSOLIDACION R5 manda `ProgramCalendar.position(..., trainedWeekStarts:)` (avanza solo semanas con ≥1 sesión). arq-B sigue especificando `week = (Δsemanas mod weeks) + 1` **sin** `trainedWeekStarts` y sus tests (start martes, +4 ⇒ deload) asumen calendario puro. Un implementador que lea arq-B shippea el contador que ux-B y R5 rechazaron: vacaciones adelantan la descarga.
- Evidencia: CONSOLIDACION-v1.md R5; arq-B.md §Semana N sin job y `ProgramCalendarTests`; ux-B.md modelo mental + B13.
- Por qué importa: contradicción entre specs que CONSOLIDACION «resolvió» en el papel pero no reescribió en el diseño que se va a codear.
- Propuesta: reescribir arq-B §⑤ y sus tests CA para la firma con `trainedWeekStarts`; borrar la fórmula mod-calendario como comportamiento de producto.

## H5 · BLOQUEANTE · pieza ⑤
- Qué falla: en semana de descarga, ux-B marca la sesión `optedOut` (invisible). arq-B/CONSOLIDACION exigen `deload = 1` frontera (rompe failRun, no es invisible). Si alguien implementa el copy de ux-B, tres misses + descarga + miss → `.deloading` reactivo o estancamiento que atraviesa la descarga: exactamente el bug que arq-B descartó.
- Evidencia: ux-B.md §Descarga programada vs deload reactivo (`optedOut`, ProgressionState.swift:55-56); arq-B.md §Interacción con ProgressionMath («NO reutilizar optedOut»); CONSOLIDACION-v1.md «`deload = 1` = frontera»; ProgressionState.swift:108 (`filter { !$0.optedOut }`).
- Por qué importa: CONSOLIDACION no listó este choque en «Conflictos resueltos»; el texto de UX sigue mandando la semántica incorrecta.
- Propuesta: enmendar ux-B: tachar `optedOut`; exigir `deload`/frontera y un criterio B14bis verificable ([miss,miss,deload,miss] → stalled(1)).

## H6 · BLOQUEANTE · pieza ③
- Qué falla: AMRAP deja la celda de reps vacía («máx»). `WorkingSet.reps` y `SetSnapshot.reps` son `Int` no opcional. No hay valor legal para «aún no escribió» (0 está prohibido por B3/edge 1). Crash a mitad de AMRAP (FER-798) no puede serializar el estado vacío sin mentir un número.
- Evidencia: ux-B.md «celda vacía con placeholder máx», B3, Q1/CONSOLIDACION Q7; StrengthSessionModel.swift:123-126 (`var reps: Int`); Training.swift:358-386 (`SetSnapshot.reps: Int`); SetEntry.reps sí es `Int?` (Training.swift:325).
- Por qué importa: la pieza ③ no es usable con el modelo vivo/snapshot actual; el agujero no está en arq-B.
- Propuesta: exigir en requerimiento `WorkingSet.reps: Int?` + `SetSnapshot.reps: Int?` (nil = pendiente AMRAP), ✓ bloqueado si nil, y test de snapshot ida y vuelta con AMRAP vacío.

## H7 · ALTA · pieza ②
- Qué falla: `progressionUseRPE` default `1` (encendido). Usuario actual que ya loguea RPE 7–8 por costumbre, sin haber pedido progresión por esfuerzo, de pronto sube en 1 sesión. Cinco sesiones/semana × varios lifts = saltos de peso no pedidos.
- Evidencia: CONSOLIDACION-v1.md «default 1»; arq-A.md columna `DEFAULT 1`; ux-A.md interruptor «encendido por defecto»; ProgressionPlanner hoy **tira** el RPE (arq-A supuesto; StrengthStore workSetHistory ya expone `rpe`).
- Por qué importa: cambio de comportamiento silencioso en datos viejos; un entrenador no enciende doble progresión sin acuerdo.
- Propuesta: default `0` en migración + interruptor off hasta que el usuario lo encienda en ProgressionSetup (o onboarding de una vez por rutina).

## H8 · ALTA · pieza ②
- Qué falla: series cumplidas con alguna ≥ 9,5 son «invisibles» al metRun: no suman ni rompen. Atleta que siempre llega a las reps al límite se queda eterno en «1 de 2» / «hoy mantienes» sin subir y **sin** disparar deload (el deload solo mira misses de reps). Grinding infinito.
- Evidencia: BRIEF.md pieza ②; arq-A.md classify `atLimit` invisible; ux-A.md caso «Al límite → mantiene»; ProgressionState.swift:116-149 (failRun solo si `!metGoal`).
- Por qué importa: regla que un entrenador rechaza: RPE alto sostenido debería bajar carga o cortar ciclo, no congelar el contador.
- Propuesta: `atLimit` cuenta como miss suave para deload tras N, o como met que no acelera pero sí ocupa slot de la racha (rompe «cómodo» sin ser invisible), con copy explícito.

## H9 · ALTA · pieza ① / reglas del repo
- Qué falla: strain estimado con `k` default no validado alimenta ACWR → veredicto de mañana → `allowsRaise` / héroe «la subida espera», y también `SessionRecoveryCost` / `costTomorrowPct` del recibo. Import CSV anuncia «Tu veredicto de mañana puede cambiar» sobre números fabricados.
- Evidencia: arq-A.md `defaultTrimpPerAU = 0.25` «no validado»; ux-C.md paso Listo; AppModel+Strength.swift:455-465 (RecoveryForecast + SessionRecoveryCost desde `record.strain`); CLAUDE.md «No clinical claims» + math cited+tested.
- Por qué importa: claims de cuerpo/recuperación sin método cerrado = rompe la regla dura del repo.
- Propuesta: hasta validar k/banda, el estimado entra a Tendencias etiquetado pero **no** al veredicto ni a SessionRecoveryCost (o gate explícito «esfuerzo estimado no mueve el veredicto» en ola 1).

## H10 · ALTA · pieza ④
- Qué falla: reimport / traslape Strong↔Hevy: inicio a ±30 min = «ya estaba». Dos sesiones reales el mismo día (AM force + PM hipertrofia) a 25 min de diferencia se colapsan; el interruptor «importar de todos modos» es fácil de no ver en Revisar.
- Evidencia: ux-C.md edge Strong/Hevy traslapadas + C8; arq-A.md idempotencia `source-startTs` (otra llave) vs UX ±30 min cross-origin.
- Por qué importa: historial y volumen mentidos; PRs/1RM pueden perder una sesión entera.
- Propuesta: dedupe estricto solo `source + startTs` (o título+startTs); el ±30 min cross-origin como sugerencia revisable fila a fila, nunca omisión por defecto silenciosa.

## H11 · ALTA · pieza ④ / consistencia de datos
- Qué falla: ux-C acepta el CSV **propio** de Cénit. arq-A solo define dialectos `strong|hevy`. Hoy solo hay export (`StrengthCSV.header` sin `set_mode`; DataSourcesView export-only). Tras ola 1 el export gana `set_mode` pero no hay lector → export→import ida y vuelta roto; drops/AMRAP salen y no vuelven.
- Evidencia: ux-C.md paso 1 «el CSV propio de Cénit también se acepta»; arq-A.md `enum Dialect { strong, hevy }`; StrengthCSV.swift:10-11; DataSourcesView.swift importSection solo Apple Health (:177-181) + strengthCSVBlock export (:845+).
- Por qué importa: backup parcial / migración entre teléfonos por CSV queda coja justo cuando ③ añade semántica nueva.
- Propuesta: dialecto `cenit` obligatorio en ④ con round-trip test (incl. `set_mode`, `source`, RPE) o sacar «CSV propio» del alcance de ola 1 explícitamente.

## H12 · ALTA · pieza transversal (migraciones)
- Qué falla: CONSOLIDACION R4 fija v42 con strainSource/sessionRpe/source/title/programWeek/deload/progressionUseRPE/mode y v43 `program`. arq-A CA #4 habla de «5 columnas» sin mode/programWeek/deload. arq-B pone mode en v42 y programWeek/deload en v43. Tres inventarios distintos para el mismo PR-esquema.
- Evidencia: CONSOLIDACION-v1.md R4; arq-A.md §Migración + CA 4; arq-B.md §Migraciones v42/v43.
- Por qué importa: dos worktrees chocan o dejan columnas huérfanas; viola la disciplina append-only de un solo migrator limpio.
- Propuesta: una tabla canónica de columnas por versión en CONSOLIDACION (única); invalidar los conteos viejos de arq-A/B.

## H13 · ALTA · pieza ③ / UX vs competencia
- Qué falla: el numeral de serie (hoy tipografía ~11 pt, columna estrecha) pasa a ser puerta de `LiquidMenu`. En sesión, el tap de la fila confirma/palomea (`confirmOrToggleSet`); las tap-zones cubren peso/reps, no el número (`TapZonesSesion`, marca sin hit testing). Robar el numeral pelea con el gesto de ✓ y es peor que Strong/Hevy (badge W/D/F o `set_type` junto al peso, no el índice).
- Evidencia: ux-B.md «El numeral de la serie es la puerta», B1, AX numeral 44 pt; RoutineSheetLiveTarjeta.swift:245-275; HojaMetrics.numeroSize = 11 (HojaMetrics.swift:44); Hevy/Strong (paridad citada en BRIEF/arq-A).
- Por qué importa: fricción cada serie, 5×/semana; gesto nuevo no descubrible; accesibilidad 44 pt pelea con la geometría StrandDesign de la fila.
- Propuesta: puerta en marca tipo (chip AMRAP/DROP / «···» de serie) o long-press de fila; numeral solo lectura; target 44 pt en el chip, no en el índice.

## H14 · ALTA · pieza ④
- Qué falla: ux-C edge 12 clampea RPE Hevy &lt; 6 a 6 «con nota». CONSOLIDACION R2 / ux-A edge 11: por debajo de 5 → `sessionRpe = nil`, nunca clampear arriba. RPE 1–4 de Hevy y el hueco 5.0–5.9 quedan en limbo; clampear a 6 inventa esfuerzo y mete carga falsa.
- Evidencia: ux-C.md edge 12 + CONFLICTO declarado; CONSOLIDACION-v1.md R2; ux-A.md edge 11.
- Por qué importa: conflicto marcado y no cerrado del todo para el import de series (solo se habló de session RPE).
- Propuesta: serie con RPE &lt; 6 → `rpe = nil` (se guarda la serie, sin esfuerzo); session prefill ignora nil; nunca clampear.

## H15 · MEDIA · pieza ①
- Qué falla: overlay solo días cerrados (`day < today`). Usuario entrena a las 19:00; Tendencias/ACWR/veredicto no ven el esfuerzo estimado hasta mañana. Cinco sesiones/semana = cinco veces que «entra a tu carga» es mentira el día que importa.
- Evidencia: arq-A.md Regla por día punto 1; CONSOLIDACION-v1.md «Hoy queda fuera del ACWR hasta mañana»; AppleLoadEstimator.isCompletedDay (day &lt; today).
- Por qué importa: paridad emocional con Watch (el strain medido tampoco cierra el día — OK) pero el copy de recibo/hub habla como si ya contara.
- Propuesta: copy honesto «cuenta desde mañana en tu carga» en recibo/detalle; o tile separado «hoy (parcial)» sin meter EWMA.

## H16 · MEDIA · pieza ①
- Qué falla: strain RPE se persiste y **no** se recalcula al cambiar `k`. Tras 5 pares, k salta; sesiones viejas quedan en escala vieja, nuevas en nueva; Tendencias mezcla dos calibraciones sin etiqueta.
- Evidencia: arq-A.md Persistencia «no se recalcula al recalibrar»; Alternativas descarta recálculo.
- Por qué importa: la curva de carga miente en el tiempo sin decir «k cambió».
- Propuesta: persistir `(au, kUsada)` o `trimpPerAU` por sesión y mostrar en pie de Tendencias cuando k vigente ≠ k histórica; o versionar estimados.

## H17 · MEDIA · pieza ③
- Qué falla: drop sin FK, madre = «no-drop anterior por position». Reordenar, insertar serie entre madre y drop, o pegar sets del CSV fuera de orden huérfana drops (cuentan volumen, se pintan ↳ colgados, lastWorkSets/PR filters ayudan pero la UI miente).
- Evidencia: arq-B.md «SIN FK… relación implícita»; ux-B.md edge 5 «Reordenar/sustituir con drops → viajan con la madre» (solo app path).
- Por qué importa: un solo camino de edición roto deja datos inconsistentes permanentes.
- Propuesta: o FK `parentSetId` nullable, o invariante de store al guardar que reescribe adyacencia y test de reorder.

## H18 · MEDIA · pieza ⑤ / matemática de progresión
- Qué falla: descarga programa = series ×0.6 (−40 %) **y** peso ×0.9 (−10 %). Deload reactivo hoy es −7,5 % de peso sin tocar series (`deloadFraction = 0.075`). Misma palabra «descarga/deload», dosis distintas; apilar −40 % volumen y −10 % intensidad en la misma semana es agresivo para novatos del motor lineal y flojo/ raro para avanzados según escuela.
- Evidencia: CONSOLIDACION Q3/regla; arq-B ProgramDeload; ProgressionState.swift:47-48; ux-B B11.
- Por qué importa: entrenador ve dos oráculos de «bajar»; el usuario en programa nunca ve el deload 7,5 % (oculto) y de pronto come −40/−10.
- Propuesta: una sola familia de parámetros documentada (p.ej. solo volumen −40 % **o** peso −10 %, no ambos por default) y alinear copy «descarga» vs «deload reactivo».

## H19 · MEDIA · pieza ① / UX
- Qué falla: pregunta de esfuerzo vive en el recibo **después** de guardar. Saltar = no tocar + «Listo». Sin prefill el héroe muestra «—» y es fácil cerrar 5×/semana sin calificar; luego hay que ir al detalle. Con prefill ya se persistió estimado antes de confirmar la celda — tocar otra celda reescribe, pero matar la app en el recibo deja el promedio de series como «sesión» sin que el usuario lo haya validado como session-RPE.
- Evidencia: ux-A.md flujo pasos 1–4; BRIEF «saltable»; CONSOLIDACION R1 (prefill sin pregunta con FC).
- Por qué importa: Foster session-RPE es una pregunta **global** post-sesión; sustituirla por promedio de series sin confirmación es otro constructo.
- Propuesta: si hay prefill, no persistir strain estimado hasta toque o «Listo» explícito que confirma el prefill; si no hay prefill, un omitir visible (no solo «Listo»).

## H20 · MEDIA · pieza ④
- Qué falla: Hevy `dropset`/`failure`/`weight_lbs` y Strong `D` siguen «a verificar» en arq-A, pero ux-C/CONSOLIDACION ya mapean failure→RPE 10 y dropset→mode drop. Shippear el lector sin fixtures reales = silent data loss o series mal tipadas.
- Evidencia: arq-A.md formatos «a verificar»; CONSOLIDACION R3; ux-C.md RPE/set_type.
- Por qué importa: import es irreversible en percepción (aunque idempotente); basura tipada es peor que rechazo.
- Propuesta: CA bloqueante: fixtures reales en repo + tests verdes antes de merge; si no hay archivo, esas ramas `throw`/skip con conteo en Revisar, no adivinar.

## H21 · MEDIA · pieza ④ / alcance
- Qué falla: Q9/CONSOLIDACION: no crear rutinas desde nombres de Workout Name. El switcher Strong/Hevy importa 200 sesiones y el hub sigue vacío de plan: historial sí, «Empezar» no. Strong/Hevy/Boostcamp abren el último template; aquí la pieza ④ queda a medias para el job-to-be-done «seguir entrenando mañana».
- Evidencia: CONSOLIDACION-v1.md Q9 fuera; ux-C.md pregunta 2; fuera de alcance explícito.
- Por qué importa: usable ≠ importó filas; la ola promete paridad de entrada y deja el hueco.
- Propuesta: al menos «Crear rutinas desde los N nombres más frecuentes (apagado por default)» o CTA post-Listo a plantillas con copy que no prometa paridad total.

## H22 · MEDIA · accesibilidad / ③⑤
- Qué falla: tira de semanas como un solo elemento VO (bien) pero celdas fijas FER-394 + ViewThatFits desde AX1; numeral de serie a 44 pt pelea con `HojaFilaSerie` densa. Menú de 5 acciones en el índice sin custom rotor/action documentado más allá del hint.
- Evidencia: ux-B.md Accesibilidad + B16/B17; HojaFilaSerie VO actual arma «Set N» desde `numero` (HojaFilaSerie.swift:312-314).
- Por qué importa: AX5 «nada se trunca» + 44 pt en columna de índice = redesign de HojaMetrics no presupuestado en arq-B («copy/UX no forma parte de este spec»).
- Propuesta: CA de layout explícito en StrandDesign (ancho mínimo de puerta de tipo) o mover la puerta fuera del índice (H13).

## H23 · BAJA · transversal / docs
- Qué falla: ARCHITECTURE.md aún dice migrator v41; DATA_MODEL.md corta en v26. H2/H3 de CONSOLIDACION lo notan como issue aparte, pero el PR-esquema de ola 1 puede mergear sin tocar docs y dejar el desfase peor (v43).
- Evidencia: CONSOLIDACION-v1.md H2/H3; docs/ARCHITECTURE.md:311; docs/DATA_MODEL.md:110.
- Por qué importa: la regla del repo es que el migrator documentado coincide con Database.swift.
- Propuesta: el PR-esquema no mergea sin actualizar ARCHITECTURE §7 y DATA_MODEL al menos v42/v43.

## H24 · BAJA · pieza ③
- Qué falla: AMRAP cuenta a 1RM con clamp a 12 reps (`OneRepMax.maxReps`). Un AMRAP de 20 a 60 kg se estima como 12 reps — «under-count» honesto en código, pero el recibo celebrará PR de reps y el sparkline de 1RM casi no se mueve: dos verdades distintas sin copy.
- Evidencia: arq-B.md «tope 12 ya recorta»; OneRepMax.swift:47-55; ux-B B7 «récord por AMRAP aparece».
- Por qué importa: confusión menor pero real en detalle de ejercicio.
- Propuesta: en detalle, pie «1RM estimado usa máx. 12 reps»; el PR de reps sigue aparte.

## Resumen
- BLOQUEANTE: 6
- ALTA: 8
- MEDIA: 8
- BAJA: 2
- Total: 24

HALLAZGOS NUEVOS: 24

## Lo que aguanta
- Overlay en lectura (no persistir en `dailyMetric`) evita el COALESCE que pisa sueño/HRV — diagnóstico H1 de CONSOLIDACION es sólido (AppleLoadEstimator + notOurs).
- `SetMode` ortogonal a `SetKind` es la decisión correcta frente a crecer el enum (censo ~60 `kind == .work`).
- FER-85 queda intacto en ②: solo `deferRaise` / allowsRaise, sin reordenar «Otra forma» (EntrenarView.swift:883-897).
- Frontera `deload` ≠ `optedOut` (cuando se respete arq-B) es la semántica adecuada para reiniciar estancamiento.
- Vocabulario Esfuerzo 0–21 vs Carga ACWR (ux-A) evita el doble sentido del brief.
- Idempotencia por id determinista `source-startTs` + un `syncWrite` es el patrón correcto de store (saveSession upsert).
