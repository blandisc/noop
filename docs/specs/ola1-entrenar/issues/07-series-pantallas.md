## Contexto
Con el modelo de E6, la sesión viva y el editor necesitan sus puertas sin gestos que choquen (la pulsación larga en el editor ya arma el borrado; el numeral es solo lectura). Fuente: `ux-B.md §③` con E2/E15/E21/E26 (v2–v5), el artefacto del dueño `artefactos/ola1-pantallas.html` §③ (en la carpeta del taller; E1 lo copia a `docs/specs/ola1-entrenar/artefactos/`), D-Q7.

## Objetivo
En sesión: pulsación larga o chip abren el menú de serie (las que puedas · bajar y seguir · llegué al fallo · quitar); en el editor: tecla «máx» en el techo de reps y atajo «Última serie: las que puedas»; recibo, detalle, Live Activity y Watch muestran los tipos sin campos nuevos.

**Carril:** pesado (sesión viva; se pule JUNTO con el dueño en /inject, orden 2026-09-01).

## Comportamiento esperado
- **Sesión viva** (`RoutineSheetLiveTarjeta`, `RoutineSheetLiveLogic`): pulsación larga sobre la fila de serie → `LiquidMenu`: «Las que puedas» (radio, marca AMRAP) · «Bajar y seguir · −20 %» (solo trabajo/AMRAP; inserta sub-fila «↳» con marca «bajar y seguir», peso a discos, sin descanso) · «Llegué al fallo» (= RPE 10; ✓ si ya) · «Quitar serie» (destructiva). En una sub-fila drop: solo «Quitar». Quitar madre con drops hechos: «Esta serie tiene 2 “bajar y seguir” registradas. Quitarla también las borra.» [Conservar] [Quitar serie y drops]. Cuando existe marca (AMRAP/DROP/C), la marca es un chip tocable de 44 pt que abre el mismo menú. La marca del tipo va en una línea propia bajo la fila, no dentro del numeral.
- AMRAP: celda de reps vacía con placeholder «máx»; «✓ Serie» con reps vacías no registra: la fila se sacude y el placeholder dice «¿cuántas salieron?» (Reduce Motion: solo texto). Referencia bajo la fila: «La última vez: 80 × 11 · te quedaba 1». Solo en tipos con reps; en tiempo/distancia la opción aparece atenuada «solo en series por reps».
- **Editor** (`RoutineSheetKeypad`): al editar el techo de reps de una serie de trabajo, la tecla de acción inferior-derecha (`confirmSet`) dice «máx» → `repsRangeTop = nil`, `mode = .amrap`; celda muestra «8 a máx». El «···» del ejercicio gana el toggle «Última serie: las que puedas». Sin gesto nuevo; la pulsación larga sigue armando el borrado.
- **Recibo/detalle**: «Press banca · 80 kg · 8 · 8 · 11 máx»; «↳ bajar y seguir 64 kg · 9»; «· 1 al fallo» al final si aplica; récord por AMRAP en récords. Pie en detalle de ejercicio: «El 1RM estimado usa máximo 12 reps».
- **Live Activity / Watch**: `returnDetail` preformateado → «80 kg × máx», «↳ 64 kg × 9»; drops cuentan en «N/M series». Sin campos nuevos.

## Accesibilidad
Fila: «Serie 3, las que puedas, 80 kilos, máximo de reps, pendiente» → «…, 11 reps, al fallo»; drop: «Bajar y seguir de la serie 3, 64 kilos, 9 reps». Acciones personalizadas de VoiceOver en la fila (rotor) con las cuatro opciones del menú. Placeholder «máx» → «reps, máximo, escribe las que salieron». Chip de marca ≥ 44 pt. Dynamic Type AX3+: la fila apila (contrato de `HojaFilaSerie`).

## Alcance técnico
`Cenit/Screens/Hoja/RoutineSheetLiveTarjeta.swift` (fila de serie, `TapZonesSesion`), `Hoja/RoutineSheetLiveLogic.swift` (NUEVO `setMenuItems(ei:si:)`; el menú existente en `exerciseMenuItems` ~:779 es el del EJERCICIO y no se toca para esto), `Hoja/RoutineSheetKeypad.swift` (~:154-173, montaje del keypad), `SessionKeypad.swift` (solo la tecla `confirmSet` contextual → «máx»; las etiquetas de reps en reserva son de E5), `Hoja/RoutineSheetLogic.swift:552-598` («···»), `LiveStrengthSheet.swift` (recibo), `WorkoutDetailScreen.swift`, `ExerciseDetailScreen.swift` (pie 1RM), `CenitWidgets/Shared/RestActivityAttributes.swift:49-52`, StrandDesign: `HojaFilaSerie` gana la sub-línea de tipo y el chip (con #Preview; agente `componente`).

## Fuera de alcance
Modelo y SQL (E6). Vocabulario del glosario y tips (E12). Cadenas del teclado de reps en reserva («REPS EN RESERVA», «· al fallo»): E5.

## Criterios de aceptación
- [ ] B1 Pulsación larga en una serie (sesión) abre el menú de 4; el numeral no reacciona al toque; el chip de marca abre el mismo menú.
- [ ] B2 En el editor no hay menú de serie; «máx» aparece solo al editar el techo de una serie de trabajo; «Última serie: las que puedas» marca solo la última.
- [ ] B3 AMRAP no se palomea sin reps; nunca guarda 0; tras matar la app se restaura como pendiente.
- [ ] B4 «Bajar y seguir» inserta «↳» con −20 % a discos y reps de la madre; palomear la madre no inicia descanso; palomear el último drop sí; máximo 3 escalones.
- [ ] B5 Quitar madre con drops hechos pide confirmación con el conteo exacto.
- [ ] B6 «Llegué al fallo» escribe RPE 10 (igual que reps en reserva 0 en el teclado); el tipo no cambia.
- [ ] B7 Recibo y detalle con la gramática exacta; Live Activity y Watch muestran «× máx» / «↳ 64 kg × 9».
- [ ] B8 Ninguna marca desborda la fila a AX5; la línea de tipo va bajo la fila.
- [ ] B9 VoiceOver lee tipo, peso, reps y «al fallo»; acciones personalizadas presentes.
- [ ] B10 «Igualar todas» con modos mezclados abre la receta en renglones.

## Definition of Done
- [ ] Pulido en /inject con el dueño; `Tools/verify.sh app` verde; /qa PASS; claves `es` + `en` en el catálogo (nunca `es-MX`; gate i18n).
