# Consolidación v4 · Ola 1 · tras ronda 3 (Grok: 9 cerrados, 1 parcial, 4 nuevos, 0 bloqueantes) · 2026-09-02

**Manda sobre v3, v2, v1 y los specs.** Solo agrega decisiones sobre N9–N12 y cierra H19; incluye dos verificaciones propias del director en código.

## A · Decisiones ronda 3
| Id | Decisión |
|---|---|
| N9 editor sin «hoja por serie» (verificado por el director: el editor edita cada serie en línea con el keypad, FER-166/492; no hay hoja) | **Sustituye E15.** En el editor el AMRAP se declara de dos formas, ambas sin gesto nuevo: (a) el keypad del editor, al editar el techo de reps de una serie de trabajo, gana la tecla **«máx»** → `repsRangeTop = nil`, `mode = .amrap`; (b) el «···» del ejercicio gana el toggle **«Última serie AMRAP»** (el caso de programa más común). Calentamiento sigue naciendo del «···» (rampa) como hoy. Mapa: Trabajo = `work`+`standard` · Calentamiento = `warmup` · AMRAP = `work`+`amrap` · DROP solo en sesión. `workSetsAreEqual` compara también `mode`; «Igualar todas» copia `mode`; con modos mezclados la receta se abre en renglones («series distintas») como ya hace con reps distintas. Tests: `RoutineSetEditingTests` con AMRAP en la última serie → receta abierta; `equalizeAll` propaga `mode`. |
| N10 prosa mezcla dos motores (verificado por el director: `Preparedness.swift:677-681`: el eje `load` solo marca presencia, «never flips the verdict»; el ACWR vive en `ReadinessEngine`) | **Sustituye A·H9 de v2 y v3.** El esfuerzo estimado alimenta (1) el overlay de `days` → ACWR/monotonía → Tendencias › Carga, y (2) `strainByDay` del día → el eje de carga del acta marca presencia (contexto), como hoy con un entreno de Apple. **No se añade ningún votante.** Etiqueta «estimado» en recibo, detalle, Carga y costo de mañana. **Consecuencia honesta:** en la ola 1 la sesión de fuerza sin reloj se ve en tu carga y en tu acta, pero **no cambia el veredicto de mañana**, porque hoy ninguna carga lo cambia (la lógica OUT del eje de carga está diferida a /cso). Ver Q12. |
| N11 CA invalidados por enmiendas | Bloque C de este archivo: lista canónica de criterios sustituidos. Un QA usa los specs **más** este bloque. |
| N12 ruta de copy | «Ajustes › Datos y fuentes › Importar». |
| H19 parcial (deseleccionar vs cerrar) | Regla única: **al cerrar el recibo (o si la app muere) se persiste lo que está seleccionado en pantalla en ese momento**: celda prellenada aún seleccionada → `prefill`; celda tocada → `answered`; ninguna (deseleccionada o sin prefill) → `nil`. Test: prefill 8 → deseleccionar → cerrar → `sessionRpe = nil`. |

## B · Enmiendas (nuevas)
E21 **ux-B §③ editor (sustituye E15):** tecla «máx» en techo de reps + toggle «Última serie AMRAP» en «···»; sin selector nuevo; `mode` en «Igualar todas» y en `workSetsAreEqual`.
E22 **ux-A / arq-A §① H9 (sustituye A·H9 v2 y v3):** texto de N10.
E23 **ux-C Listo:** ruta «Ajustes › Datos y fuentes › Importar».
E24 **ux-A §① recibo:** regla de persistencia al cerrar (H19).

## C · Criterios de aceptación de los specs que quedan SUSTITUIDOS (el QA lee esto encima del spec)
| Spec · CA | Texto viejo | Sustituto |
|---|---|---|
| ux-B · B1 | Tocar el numeral abre el menú de serie | Sesión: pulsación larga en la fila o chip de marca abren el menú; el numeral es solo lectura. Editor: sin menú de serie (E21). |
| ux-B · B2 | Editor ofrece Trabajo/Calentamiento/AMRAP/Quitar en el numeral | Editor: AMRAP por tecla «máx» o «Última serie AMRAP»; calentamiento por «···»; quitar por pulsación larga armada (como hoy). Sesión: menú con AMRAP · Agregar drop · Al fallo · Quitar. |
| ux-B · B11 | Series −40 % y peso −10 % | Semana ligera default: series ×0,5 (mín 1), peso igual; opción con peso usa −7,5 % (`deloadFraction`). |
| ux-B · B14 | En semanas 1…N−1 no se muestra `.deloading` | El deload reactivo sigue vivo por ejercicio dentro del programa; la semana ligera es frontera y no propone subida; copy añade «la semana ligera llega en la N». |
| ux-B · copy «descarga» | «Semana de descarga», «descarga en 2 semanas» | «Semana ligera», «semana ligera en 2 semanas» (D6). |
| ux-B · héroe de descarga | Estado nuevo del héroe | Sin estado nuevo: cambia kicker y meta del estado «día de rutina» (E4, Q10). |
| ux-C · C8 | Otro origen a ±30 min se omite por defecto | Se lista en «Posibles duplicados», default fuera, toggle = forzar (N5). |
| ux-C · C10 | Listo dice cuántas de los últimos 28 días entraron | N = sesiones que el overlay fusiona; copy alterno si N = 0 (N6). |
| ux-C · edge 12 | RPE < 6 se guarda como 6 | RPE < 6 → `nil` (E12). |
| ux-A · A13 | Héroe muestra «…la subida espera» + línea del cuerpo | El conflicto Q-sube / cuerpo-mantén se muestra en la fila del ejercicio y en SUBIDAS LISTAS; el héroe queda v18 (E1). |
| ux-A · interruptor | «Usar mi esfuerzo (RPE)» | «Subir según Q (lo que te quedaba)» con subtítulo N7 (E13). |
| ux-A · A2 | «Listo» sin tocar no genera estimado | Sigue válido; se añade: con prefill, cerrar acepta el prefill salvo que se deseleccione (H19). |
| arq-A · CA 4 | «5 columnas» en v42 | Tabla canónica §C de v2 (12 columnas en v42 + tabla `program` en v43). |
| arq-A · regla por sesión | «La pregunta se hace siempre» | No se pregunta con `strainSource = 'hr'` (cobertura ≥ 0,8) (E17). |
| arq-B · semana | `week = (Δsemanas mod weeks) + 1` | `trainedWeekStarts` (E5). |
| arq-B · descarga | series ×0,6, peso ×0,9 | ×0,5 y `deloadFraction` (E6). |
| arq-B · deload en programa | «en semana de descarga `evaluate` no propone nada» | Sigue: no propone subida; el deload reactivo sí se propone en semanas 1…N−1 (D1). |

## D · Preguntas al dueño (F de v2 + nuevas)
Q1–Q4, Q6–Q11 sin cambio.
**Q12 (nueva, la más importante):** hoy ninguna carga cambia el veredicto (el eje de carga del acta es solo contexto; la lógica OUT está diferida a /cso). La ola 1 hace que la fuerza sin reloj **se vea** en Carga y en el acta, pero la promesa «tu sesión de hoy cambia tu veredicto de mañana» no se cumple hasta que la banda de carga vote. Recomendación: **no meterlo en la ola 1** (es un cambio de ciencia con gate /cso y afecta a Hoy entero), y abrir de inmediato un issue propio «la carga vota en el veredicto» como primera pieza de la ola 1b. Alternativa: incluirlo en la ola 1 y aceptar que Hoy cambia de comportamiento para todos.

## E · Estado
Bloqueantes: 0. Altas: 0. Pendiente solo la confirmación de Grok en ronda 4.
