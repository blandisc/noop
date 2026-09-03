# Consolidación v1 · Ola 1 · decisiones del director sobre los cinco specs (2026-09-02)

Los specs son: ux-A.md (①②), ux-B.md (③⑤), ux-C.md (④), arq-A.md (①②④), arq-B.md (③⑤). Este archivo resuelve sus conflictos y fija lo que se ataca. Donde dos specs chocan, aquí está la regla que manda.

## Conflictos resueltos
R1 **¿Preguntar «¿qué tan duro estuvo?» también con reloj?** arq-A pedía sí (para calibrar k); ux-A pedía no (fricción). **Regla:** NO se pregunta cuando hay FC suficiente. Los pares de calibración salen de sesiones con FC que además traen RPE por serie (el prellenado `SessionRPE.prefill` existe sin pregunta). Si un usuario nunca captura RPE por serie, k se queda en el default y se dice así.
R2 **Escala de la pregunta.** Se reutiliza la fila existente 6·7·8·9·9,5·10 (ux-A). Del CSV se aceptan RPE 5–10 (arq-A `rpeMin = 5`); por debajo de 5 → `sessionRpe = nil`, sin estimar (gana ux-A edge 11 sobre ux-C edge 12: nunca clampear hacia arriba). El mapeo RPE→CR-10 de Foster lo absorbe k; /cso valida o pide mapeo explícito.
R3 **Modelo de serie.** Se adopta `SetMode {standard, amrap, drop}` ortogonal a `SetKind` (arq-B), no un `SetKind` de 4 casos. El copy de ux-B no cambia. ④ mapea Hevy `dropset` → `mode = .drop`, `failure` → RPE 10.
R4 **Migraciones.** Un solo PR-esquema previo con **v42** (strengthSession: strainSource, sessionRpe, source, title, programWeek, deload · routineExercise: progressionUseRPE · routineSet.mode · setEntry.mode) y **v43** (tabla `program`). Ninguna pieza abre su propia migración.
R5 **Semana del programa.** Gana la regla de ux-B (avanza solo en semanas con ≥1 sesión) pero implementada pura (arq-B): `ProgramCalendar.position(startTs:, trainedWeekStarts: Set<Int>, now:, weeks:)`, sin columna «semana actual». Decisión #2 del dueño sigue abierta con esta recomendación.
R6 **Import desde tu IA y calendario.** El prompt gana `semanas`, `descarga` y `dia` por rutina; si falta `dia`, se asignan días libres en orden L→D como hacen las plantillas (StarterTemplatesSheet:285-292). Sin esto un programa importado no tendría calendario (hallazgo arq-B).

## Decisiones de diseño que se mantienen (y por qué)
- ① **Overlay en lectura** sobre `days` (arq-A), nunca persistido en `dailyMetric`; por día `max(medido Apple, Σ sesiones en TRIMP)`; una sesión sin strain convierte un falso `rest(0)` en `nil`. Hoy (día en curso) queda fuera del ACWR hasta mañana. Etiqueta «Esfuerzo ~N /21 · estimado» (vocabulario de ux-A: «Esfuerzo» = escala 0–21; «Carga» = ACWR).
- ① **Una fuente por sesión**: FC suficiente → medido; si no, RPE → estimado; si no, `nil`. Nunca suma. Umbral de «FC suficiente» lo fija /estadistico.
- ② `useRPE` por ejercicio (columna `progressionUseRPE`, default 1); cómodo ≤ 8 → sube en 1; al límite ≥ 9,5 → invisible al conteo de cumplidas (no rompe ni suma); el veredicto sigue encima (FER-85).
- ③ Drop = `SetEntry` propio con `mode = .drop` y `position` siguiente; sin FK. Reglas 3×4 en `SetMode.counts(for:)`. «Al fallo» = RPE 10, no es tipo.
- ⑤ Tabla `program` singleton; descarga aplicada solo a la semilla en memoria; sesión guardada con `deload = 1` = frontera para la progresión (no cuenta como hit/miss, reinicia estancamiento) y excluida de «la última vez». En semanas 1…N−1 el `.deloading` reactivo no se propone: se informa «Estancado · la descarga llega en la semana N». Regla de descarga: series ×0.6 (mín 1), peso ×0.9 a discos (decisión #3 del dueño: recomendación).
- ④ Ids deterministas `source-startTs`; lote en un solo write; PRs con ts original; reconciliación con el componente extraído de WorkoutImportView.

## Hallazgos colaterales que entran al alcance
H1 (arq-A) Hoy un día de fuerza sin Watch con pocos pasos se cuenta como **descanso (0)** en el ACWR (AppleLoadEstimator.swift:99-104 + HealthKitBridge notOurs :803-808). ① lo corrige; se registra como defecto.
H2 (arq-B) FER-85 vive en código (EntrenarView.swift:892-897) pero no en docs/DECISIONS.md; ARCHITECTURE.md:311 dice v41. Se corrige en el PR-esquema.
H3 (arq-A) docs/DATA_MODEL.md documenta migraciones solo hasta v26. Issue de docs aparte.

## Preguntas al dueño (acumuladas; el subagente `criterio` infiere respuesta probable)
Q1 Subida acelerada en 1 sesión cuando llegaste cómodo (≤ 8). Rec: sí.
Q2 Contador de semanas: solo semanas con ≥1 sesión. Rec: sí.
Q3 Forma de la descarga: series −40 % y peso −10 %. Rec: sí.
Q4 Cuatro motores de dominio público, sin biblioteca de coaches. Rec: sí.
Q5 Volver a mostrar «la subida espera» en el héroe solo para el caso conflicto de ② (FER-171 la quitó). Rec: sí.
Q6 Interruptor «Usar mi esfuerzo» por ejercicio (columna) y no global. Rec: por ejercicio.
Q7 Celda de reps de AMRAP vacía («máx»), no prellenada. Rec: vacía.
Q8 «Programa» solo desde Tu Plan y Crear plan, no en el first-run. Rec: sí.
Q9 Import CSV: ¿ofrecer crear rutinas a partir de los nombres de entreno importados? Rec: no en esta ola.

## Fuera de alcance explícito
Que el veredicto baje series (FER-85); Watch que registra solo (ola 3); leer entrenos de otras apps desde Apple Health; récords por ejercicio como pantalla (ola 2); catálogo con imágenes.
