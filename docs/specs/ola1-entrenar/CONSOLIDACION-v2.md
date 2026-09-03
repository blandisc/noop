# Consolidación v2 · Ola 1 · tras ronda 1 (Grok 24 · biomecánico 8 · estadístico 10 · criterio) · 2026-09-02

**Este archivo manda sobre CONSOLIDACION-v1, ux-A/B/C y arq-A/B.** Donde un spec diga otra cosa, vale la enmienda de aquí (sección E). Todo lo demás de los specs sigue vigente.

## A · Decisiones por hallazgo de Grok (ronda 1)
| Grok | Decisión |
|---|---|
| H1 k nunca calibra | Se calibra con pares (sesión medida con cobertura ≥ 0,8 **y** RPE por serie → prefill persistido como `sessionRpe` con `sessionRpeSource = 'prefill'`). No se pregunta con reloj. Sin pares, k es **constante de producto** con banda de prueba publicada (no «no validado» a secas). Ver B1–B4. |
| H2 max sub-cuenta cardio+fuerza | Regla por día: **suma en TRIMP** cuando el intervalo de la sesión Cénit no traslapa ningún HKWorkout usado por el strain de Apple; **máximo** cuando traslapa. El snapshot carga los intervalos de HKWorkout del rango (ya se leen para FER-883). Test `testDisjointWorkoutsAddInTrimp`. |
| H3 escala 6–10 vs CR-10 | Mapeo afín explícito `cr10 = 1.5·rpe − 5` (6→4, 8→7, 9→8,5, 9,5→9,25, 10→10), constante nombrada, test, cita. /cso confirma anclas; la matemática exige mapeo afín, no identidad. Método se cita como «session-RPE (Foster 2001) con escala RIR mapeada». |
| H4 arq-B calendario puro | Enmienda E5: firma única `ProgramCalendar.position(startTs:trainedWeekStarts:now:weeks:)`; `n` = semanas entrenadas estrictamente anteriores a la semana actual desde el inicio; `week = (n mod weeks) + 1`; `cycle = n / weeks`. Tests reescritos. |
| H5 optedOut vs frontera | Enmienda E3: la sesión de semana ligera lleva `deload = 1` = frontera (no hit/miss, rompe racha de fallos, invisible a «la última vez»). `optedOut` no se usa. Criterio B14bis: `[miss, miss, deload, miss] → .stalled(1)`. |
| H6 AMRAP sin reps en `Int` | Requisito: `WorkingSet.reps: Int?` y `SetSnapshot.reps: Int?` (nil = AMRAP pendiente); ✓ bloqueado si nil; test de snapshot ida y vuelta con AMRAP vacío. |
| H7 `useRPE` default encendido | Migración: `DEFAULT 0` (cero cambio silencioso en rutinas existentes). Plantillas nuevas: encendido en slots de barra/compuestos; **apagado** en aislamiento y en el motor «Lineal para empezar» (biomecánico #3, #4). |
| H8 al límite = congelado eterno | Tope: tras 3 sesiones consecutivas cumplidas-al-límite (reutiliza `deloadStallThreshold`), la sesión cuenta como estándar (avanza el ciclo) y el ejercicio muestra «Tres al límite: subes igual, o apaga Q». Nunca baja peso por RPE solo (Helms 2016). Test `[met@10, met@10, met@10]` con n=2 → no `.inCycle(0, of: 2)`. |
| H9 estimado mueve veredicto | Entra al ACWR y al veredicto (es la brecha #1; excluirlo re-rompe el círculo), con tres candados: k como constante de producto con banda publicada + mapeo citado; etiqueta «estimado» en recibo, detalle, Carga **y** en el acta del veredicto cuando la carga del día proviene de estimación; el «costo de mañana» del recibo dice «estimado». |
| H10 dedupe ±30 min | Dedupe estricto solo `source + startTs`. Traslapes entre orígenes a ±30 min aparecen en Revisar como «Posibles duplicados · N · revisar» con toggle por fila, **default importar**. Nunca omisión silenciosa. |
| H11 CSV propio sin lector | Dialecto `cenit` obligatorio en ④ con test de ida y vuelta (export → import) incluyendo `set_mode`, `rpe`, `source`. |
| H12 tres inventarios de migración | Tabla canónica única en sección C. Los conteos de arq-A/arq-B quedan invalidados. |
| H13/H22 numeral como puerta | Enmienda E2: el numeral es solo lectura. La puerta del menú de serie es **pulsación larga sobre la fila** (con tooltip una sola vez) y, cuando existe marca (AMRAP/DROP/C), la marca es un chip tocable de 44 pt. VoiceOver: acciones personalizadas en la fila (rotor), no un hint sobre el índice. Sin rediseño de HojaMetrics. |
| H14 RPE < 6 importado | Rango único 6–10 en todo (serie, sesión, import). Serie importada con RPE < 6 → `rpe = nil`; prefill ignora nil; nunca clampear. |
| H15 hoy fuera del ACWR | Copy honesto en recibo y detalle: «Cuenta en tu carga desde mañana». Sin tile parcial en esta ola. |
| H16 k viejo vs nuevo | Se persiste `trimpPerAU` por sesión. Al recalibrar (solo al duplicarse los pares: 5, 10, 20, 40, con histéresis 15 %), se **recomputan** todas las sesiones `.rpe` en un solo write: la curva usa una sola k. Tendencias muestra «Escala recalibrada el D» una vez. |
| H17 drop sin FK | Sin FK. Invariante de store al guardar: renormaliza adyacencia (un drop siempre sigue a una no-drop del mismo ejercicio; huérfano → se reetiqueta `standard`). Test de reorder y de import fuera de orden. |
| H18 dos descargas | Una sola familia: peso usa **`deloadFraction` (7,5 %)** también en la semana ligera; volumen usa `ligeraSeriesFactor = 0.5` (mín 1). Default `volumeOnly` (series ×0,5, peso igual: lo más alineado a Bell 2023). `volumeAndLoad` como opción. Q3 al dueño cambia (ver F). |
| H19 prefill persistido antes de confirmar | El estimado se persiste al tocar una celda **o** al cerrar el recibo (cerrar = aceptar el prefill, `sessionRpeSource = 'prefill'`). Sin prefill: botón terciario «Sin calificar» visible; cerrar sin tocar = sin estimar. Matar la app en el recibo con prefill = prefill aceptado y etiquetado. |
| H20 fixtures «a verificar» | Criterio bloqueante: fixtures reales en repo (Hevy kg, Hevy lb, Strong actual, Strong legacy) con tests verdes antes de merge. Valor desconocido de `set_type`/`Set Order` → serie omitida con conteo en Revisar, nunca adivinar. |
| H21 hub vacío tras importar | Pantalla Listo: CTA «Arma tu semana» (plantillas) siempre que no haya plan, con copy «Tu historial ya está; tu plan lo armas en un minuto». Crear rutinas desde nombres importados sigue fuera (ola 2). |
| H23 docs desfasadas | El PR-esquema no mergea sin ARCHITECTURE §7 (v42/v43, migrator v43) y DATA_MODEL al menos con v42/v43 y una nota de que v27–v41 están pendientes (issue aparte). |
| H24 AMRAP y 1RM tope 12 | Pie en detalle de ejercicio: «El 1RM estimado usa máximo 12 reps». |

## B · Decisiones del gate estadístico (①)
B1 **Medido ⇔** `hasEnoughData` ∧ cobertura de FC ≥ 0,8 de `elapsedSeconds` (huecos plausibles < 300 s). Por debajo → `.rpe` y se pregunta. Los pares de calibración exigen lo mismo. Knob `minHRCoverage = 0.8`.
B2 Mapeo afín (A·H3). B3 Estimador de k = **mediana de razones** trimp/au (Theil–Sen por el origen), ≥ 5 pares, clamp [0,05, 1,0]. B4 Refit solo al duplicarse pares + histéresis 15 % (A·H16).
B5 Default k = **0,29** con mapeo (50 min × RPE 8 → cr10 7 → 350 AU → TRIMP 100 → strain 10,9). Rotulado «calibration default, /estadistico owns», banda de test 10–12.
B6 Overlay retroactivo: sintetiza filas **solo desde la primera fila base** con strain no-nil o, sin base, dentro de `[hoy − 56, hoy)`. El historial anterior alimenta récords, 1RM, volumen y mapa muscular; **no** el ACWR. Test: 5 años importados + 28 días Apple → ACWR ±0,05 del caso sin import. Copy de Listo: «N sesiones de las últimas 8 semanas entran a tu carga».
B7 Tolerancia relativa 0,3 % en el test de ida y vuelta (redondeo a 2 dp). B8 Tope `maxDurationS = 3 h` para estimar; sesión que cruza medianoche → día de inicio. B9 A9 de ux-A (conteo de estimadas y sin calificar en el pie de Carga) es obligatorio.

## C · Esquema canónico (único PR-esquema, antes de A/B/C)
**v42** (todo por `addColumnIfMissing`):
- `strengthSession`: `strainSource TEXT` ('hr'|'rpe'; NULL con strain = legado hr) · `sessionRpe REAL` · `sessionRpeSource TEXT` ('answered'|'prefill') · `trimpPerAU REAL` · `source TEXT` ('strong'|'hevy'|'cenit-csv'; NULL = Cénit) · `title TEXT` · `programWeek INTEGER` · `deload INTEGER`.
- `routineExercise.progressionUseRPE INTEGER NOT NULL DEFAULT 0`.
- `routineSet.mode TEXT` · `setEntry.mode TEXT` (NULL = standard).
**v43**: tabla `program` (`id` PK 'active', `name`, `weeks`, `startTs`, `deloadRule`, `templateId`, `createdTs`), guardada con `tableExists`.
MigrationTests: append-only + idempotente para v42 y v43; decodificación de `mode` NULL/standard/amrap/drop; snapshot pre-v42 decodifica. ARCHITECTURE §7 y DATA_MODEL en el mismo PR (A·H23). FER-85 entra a DECISIONS.md transcribiendo la orden original del dueño (buscar la cita en memoria; si no aparece textual, se le pide al dueño la frase).

## D · Decisiones del gate biomecánico (②③⑤)
D1 El deload reactivo (−7,5 % tras 3 estancadas) **sigue vivo por ejercicio dentro de un programa**; la semana ligera sigue siendo frontera y no propone subida. Se retira «en semanas 1…N−1 no se propone». Copy: «Estancado 3 sesiones · baja 7,5 %» como hoy; en semanas previas a la ligera, añade «la semana ligera llega en la N». Test: `[miss,miss,miss]` en semana 2 de 5 → `.deloading`.
D2 Tope de «al límite» (A·H8). D3 Motor lineal novato: `progressionUseRPE = 0` y `deloadRule = .none` por default; sube cada sesión solo en slots de barra; mancuerna/aislamiento con n = 2. D4 Aislamiento en plantillas: `progressionUseRPE = 0`. Backlog ola 2: campo `mechanic` en el catálogo.
D5 Citas en código: Bell 2023 (DOI 10.1186/s40798-023-00633-0), Bell 2024 (PMC10948666), Helms 2016 (DOI 10.1519/SSC.0000000000000218), Zourdos 2016, Steele 2017, Foster 2001. Se retira «Helms 2019» sin locator. Constantes rotuladas «convención de gimnasio, no ley».
D6 Vocabulario: «descarga/descargar» ya significa bajar medios en la app → la semana se llama **«Semana ligera»** en todo el copy (tira, héroe, hoja, prompt de IA usa `semana_ligera`). D7 Copy ux-A: «Una sesión más holgada y **cuenta** para subir». D8 PPL 6 días se etiqueta «intermedio». D9 AMRAP/1RM/drop/al fallo: sin cambio (sólido).

## E · Enmiendas a los specs (texto que sustituye)
E1 **ux-A §②, caso conflicto:** NO vuelve «la subida espera» al héroe (reabriría FER-171). El conflicto «Q dice sube, el cuerpo dice mantén» se muestra en la fila del ejercicio y en el bloque SUBIDAS LISTAS con la razón al lado; el héroe queda v18. Q5 se retira.
E2 **ux-B §③ puerta del menú:** pulsación larga en la fila + chip de marca tocable (A·H13). Se retira «el numeral es la puerta». VoiceOver: acciones personalizadas.
E3 **ux-B §⑤ descarga vs deload:** sustituir por D1 + frontera `deload` (A·H5). Se retira `optedOut`.
E4 **ux-B §⑤ nombre y héroe:** «Semana ligera» (D6). El hub **no gana un estado de héroe nuevo** (v17/v18 no se re-litiga): en semana ligera el estado sigue siendo «día de rutina»; cambia solo el kicker («Semana ligera · 5 de 5») y la meta refleja las series reducidas; la línea explicativa va en el lugar de `raiseLine` solo si el dueño lo aprueba (Q10). La fila «Programa · 4 a 6 semanas» vive en `CrearPlanChip` (Tu Plan) y en la hoja de plantillas; la pantalla «Crear plan» está archivada (FER-251) y no se revive.
E5 **arq-B §⑤ semana:** firma con `trainedWeekStarts` (A·H4). Tests: start martes sin sesiones → semana 1; 3 semanas entrenadas → semana 4; una semana en blanco no avanza; 5 entrenadas con weeks=5 → ciclo 2 semana 1.
E6 **arq-B §⑤ regla ligera:** `ProgramDeload` usa `ligeraSeriesFactor = 0.5` y `deloadFraction = 0.075` (A·H18); default `volumeOnly`.
E7 **arq-A §① motor:** escala 6–10 + mapeo afín + k = 0,29 + mediana de razones + refit por duplicación + `trimpPerAU` persistido + recomputo al refit + cobertura 0,8 + tope 3 h + overlay desde la primera fila base (B1–B8). Se retira `rpeMin = 5`.
E8 **arq-A §① regla por día:** suma/máximo por traslape de intervalos (A·H2).
E9 **arq-A §②:** `progressionUseRPE DEFAULT 0` (A·H7) + tope de al límite (A·H8).
E10 **arq-A §④:** dialecto `cenit` + fixtures reales bloqueantes + dedupe estricto + posibles duplicados con toggle (A·H10, H11, H20).
E11 **ux-A §① flujo:** persistencia del estimado al tocar o al cerrar; «Sin calificar» terciario; copy «Cuenta en tu carga desde mañana» (A·H15, H19).
E12 **ux-C:** RPE < 6 → nil (A·H14); Listo con CTA «Arma tu semana» (A·H21); «N sesiones de las últimas 8 semanas entran a tu carga» (B6).
E13 **Nombre del interruptor:** no «Usar mi esfuerzo» (Esfuerzo = escala 0–21). Nombre: **«Subir según Q (lo que te quedaba)»**, subtítulo «con Q 2 o más, sube en 1 · con Q 0, espera». (La escala visible sigue siendo la fila 6–10 con descriptores; Q es el vocabulario del keypad.)
E14 **Carril:** migraciones v42/v43 y motores (①②③⑤ en paquetes) los implementa Claude (carril pesado-delicado, DECISIONS 2026-08-31); Grok teclea ④ lector CSV y pantallas ligeras, y revisa.

## F · Preguntas al dueño (actualizadas; el criterio infirió respuesta probable)
Q1 Subida en 1 sesión con Q ≥ 2 (RPE ≤ 8): rec. sí (confianza media; gate /cso).
Q2 Contador solo con semanas entrenadas: rec. sí (media).
Q3 **Semana ligera = solo volumen (series ×0,5, peso igual)** como default; la opción con peso usa el mismo 7,5 % del deload reactivo. Rec. sí (baja: quiere UNA regla).
Q4 Cuatro motores = las plantillas existentes con semanas, sin coaches: rec. sí (alta).
Q5 Retirada (E1).
Q6 Interruptor por ejercicio, apagado por default en rutinas existentes: rec. sí (media-alta).
Q7 Celda AMRAP vacía: rec. sí (media; se ve con él en /inject).
Q8 «Programa» fuera del first-run, en Tu Plan (CrearPlanChip) y plantillas: rec. sí (alta).
Q9 Sin rutinas desde nombres importados: rec. sí (alta).
Q10 **Nuevo:** ¿la semana ligera cambia el kicker y la meta del héroe existente (sin estado nuevo)? Rec. sí, es copy dentro del estado «día de rutina»; lo contrario (estado nuevo) reabre v18.
Q11 **Nuevo:** ¿el esfuerzo estimado mueve el veredicto de mañana en ola 1 (con etiqueta en el acta) o solo Tendencias? Rec. sí mueve (es la brecha #1), con los tres candados de A·H9.

## G · Fuera de alcance (sin cambio)
Veredicto que baja series (FER-85); Watch standalone (ola 3); leer entrenos de otras apps desde Apple Health; pantalla de récords (ola 2); catálogo con imágenes; campo `mechanic` (ola 2); tile «hoy parcial» de carga.
