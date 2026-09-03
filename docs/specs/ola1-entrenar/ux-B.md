# UX · Ola 1 · piezas ③ (AMRAP / drop / al fallo) y ⑤ (programas con descarga)

Corrección al brief: `CrearPlanScreen.swift` y `RoutineEditorScreen.swift` ya no existen. «Crear plan» es un chip con `LiquidMenu` de dos filas (CrearPlanChip.swift:24-27, montado en WeeklyPlanEditorView.swift:489); el first-run son 3 chips + «Desde cero» + «Importar» (EntrenarView.swift:1146-1252). El editor de rutina es `Hoja/RoutineSheet*.swift`.

## Inventario
1. Fila de serie `HojaFilaSerie` (StrandDesign; label VO :307-320) e instancia viva RoutineSheetLiveTarjeta.swift:224-289 con `TapZonesSesion` (peso/reps) + ✓. La marca «C» de calentamiento (:235) es el molde de AMRAP/drop.
2. Keypad `SessionKeypad` (fila QUEDABAN 0·1·2·3·4+ → RPE = 10 − RIR, :67-74; «✓ Serie»/«Saltar ›» :51-54). «Al fallo» ya existe como QUEDABAN «0».
3. `StrengthSessionModel`: «sin descanso» = `.fixed 0` (:609-615), `addSet` clona la última (:815-823), `insertWarmup` (:827-834), `removeSet` (:837-843), `setRPE` (:635-639).
4. Menús `LiquidMenu` por ejercicio (RoutineSheetLiveLogic.swift:779-851; RoutineSheetLogic.swift:552-598) y `CrearPlanChip`; tira semanal `EntrenarHubSemana` (Cenit/Screens/Entrenar/EntrenarHubSemana.swift, labels VO :114-123); héroe `EntrenarHubHeroe` (kicker, `raiseLine`); `PlanAppliedToast`; `StarterTemplatesSheet.applyTemplateGroup` (:276-293).
5. Import `WorkoutPrompt.es/en` + `WorkoutProgram` (ignora campos desconocidos, WorkoutProgram.swift:16-18) + `WorkoutImportView`. PlateMath para redondear −20 % y −10 %.

## ③ en la sesión viva
**El numeral de la serie es la puerta.** Tocar el numeral abre un `LiquidMenu` de serie (editor y sesión). El «···» del ejercicio no gana filas.
| Fila | Símbolo | Efecto |
|---|---|---|
| «Serie de trabajo» / «Calentamiento» | flame | radio |
| «AMRAP · las que puedas» | infinity | radio |
| «Agregar drop · −20 %» | arrow.down.right | solo en sesión, solo en trabajo/AMRAP; inserta sub-serie |
| «Al fallo · esfuerzo 10» | bolt.fill | toggle; ✓ si RPE == 10 |
| «Quitar serie» | trash | = removeSet |
Editor de rutina: mismo menú sin «Agregar drop» ni «Al fallo». Fila drop: solo «Quitar drop». Fila hecha: menú disponible.

**Fila y keypad con «máx»:** fila AMRAP: número «3», marca «AMRAP» en el slot de «C», reps = «máx» en tinta, playhead «ANT 80 × 11 · Q1». Keypad: celda vacía con placeholder «máx»; «✓ Serie» con reps vacías NO registra: la fila se sacude y el placeholder dice «¿cuántas salieron?». Hecha: «11 · Q1» + marca AMRAP. AMRAP solo en tipos con reps; en time/distance la fila aparece atenuada «solo en series por reps».

**Drop:** numeral → «Agregar drop · −20 %». Sub-fila debajo, numeral «↳», marca «DROP», indentada; pertenece a la madre por adyacencia. Peso = madre × 0.8 redondeado a discos (PlateMath; sin inventario, al paso `weightStepKg`); reps = de la madre. Palomear la madre con drop pendiente NO arranca descanso; el descanso arranca al palomear el último drop. Encadenar: máximo 3 escalones. Deshacer: «Quitar drop» o swipe. Quitar madre con drops hechos: «Esta serie tiene 2 drops registrados. Quitarla también los borra.» · [Conservar] [Quitar serie y drops].

**«Al fallo»:** ya existe como QUEDABAN «0» = RPE 10. Se agrega legibilidad: segmento «0» gana subtítulo «fallo»; fila hecha con RPE 10 dice «· fallo» en vez de «· Q0»; en la hoja de RPE el 10 lleva «al fallo». La fila del menú hace `setRPE(10)`. No es tipo.

**Recibo / detalle / Live Activity / Watch:** recibo «Press banca · 80 kg · 8 · 8 · 11 máx»; drops «↳ drop 64 kg · 9»; «· 1 al fallo» al final. Detalle misma gramática. Live Activity y Watch: `returnDetail` (RestActivityAttributes.swift:49-52) es texto preformateado → «80 kg × máx», «↳ 64 kg × 9»; drops cuentan en «N/M series». Sin marca gráfica nueva.

## ⑤ Programas con descarga
**Modelo mental:** «Tu semana» × N (4–6) con la última marcada de descarga desde el día uno. El contador avanza por semanas del calendario en las que entrenaste al menos una vez; una semana en blanco no cuenta. Al terminar la descarga vuelve solo a la semana 1 con los pesos ganados.

**Flujo A · Crear plan:** `CrearPlanChip` gana tercera fila «Programa · 4 a 6 semanas» → `StarterTemplatesSheet` en modo programa: «Lineal para empezar», «Empuje · Tirón · Pierna · 6 días», «Superior / Inferior · 4 días», «Cuerpo completo · 3 días», subtítulo «N rutinas · 5 semanas · descarga en la 5». Preview + selector «Semanas: 4 · 5 · 6» (default 5) + línea «La última semana es de descarga: menos series y un poco menos de peso. La ves marcada desde hoy.» CTA «Empezar programa» → crea rutinas, arma la semana (`applyTemplateGroup`), crea programa con inicio = lunes de esta semana. Toast «Programa listo · semana 1 de 5 · edítalo cuando quieras». Si ya hay programa: «Ya tienes un programa en la semana 3 de 5. Empezar otro lo termina.» · [Seguir con el mío] [Empezar el nuevo]. First-run: los 3 chips no cambian.

**Flujo B · Convertir:** en Tu Plan, fila «Convertir en programa ›» (si ≥1 día asignado y sin programa). Hoja: «Tu semana, por ciclos», «Semanas: 4 · 5 · 6», «Empieza: Esta semana · El lunes», línea de descarga, CTA «Empezar programa».

**Tira de semanas en Tu Plan:** línea «Semana 3 de 5 · descarga en 2 semanas» + tira de celdas (hecha / hoy / futura / descarga con marca «descarga»). Semana 5: «Semana de descarga · 5 de 5». Después: «Ciclo nuevo · semana 1 de 5 · pesos: los que te ganaste» (hasta la primera sesión). Semana sin sesiones: «Semana 3 de 5 · la semana pasada no contó, sigues en la 3». «···» gana «Terminar programa»: «¿Terminar el programa? Tus rutinas y tu semana se quedan; solo se va el conteo de semanas.»

**Héroe del hub en descarga:** kicker «Semana de descarga · 5 de 5»; meta «5 ejercicios · 9 series · ~35 min» ya con −40 %; línea «Menos series y el peso al 90 %. Mismo gym, menos desgaste. La próxima semana arrancas el ciclo con los pesos que te ganaste.» CTA «Empezar». En sesión cada fila lleva «· descarga» en el playhead («ANT 80 × 8 · hoy 72»); el usuario puede agregar series o subir peso.

**Regla de cierre y calendario:** termina la semana 5 (llega lunes y hubo ≥1 sesión en la 5) → vuelve a 1 solo, sin pregunta. Semana saltada: no cuenta, no avanza. Empezar a mitad de semana: esta semana calendario es la 1 («Semana 1 de 5 · empezó esta semana»). Cambiar rutina a media semana: el programa no se entera; la descarga se aplica al servir la sesión, nunca edita la rutina guardada.

**Descarga programada vs deload reactivo:** dentro de un programa, en semanas 1–4 la propuesta `.deloading` no se muestra; el ejercicio estancado dice «Estancado 3 sesiones · la descarga llega en la semana 5». En la semana 5 el motor recibe historia cortada en el inicio de la descarga (contadores reinician) y la sesión marca `optedOut` (ProgressionState.swift:55-56). Semana 1 del ciclo nuevo: peso = último peso de trabajo antes de la descarga. Sin programa, deload reactivo como hoy. `ProgressionSetupScreen` fila «Si te estancas 3 sesiones»: subtítulo «con programa, espera a la semana de descarga».

## Import desde tu IA
`WorkoutPrompt.es/en`: el JSON de ejemplo gana `"semanas":0, "descarga":false` al nivel de `programa` + dos viñetas. Pie en captura: «Si tu plan tiene semanas o una semana de descarga, tu IA ya sabe ponerlas: el prompt lo pide.» Confirmación: si `semanas ≥ 4`, fila «Programa de 5 semanas · descarga en la 5»; si no, toggle apagado «Convertirlo en programa de 5 semanas». Archivos v1 viejos: sin cambio.

## Accesibilidad
- VO fila de serie: «Serie 3, AMRAP, 80 kilos, máximo de reps, pendiente» → «Serie 3, AMRAP, 80 kilos, 11 reps, al fallo». Drop: «Drop de la serie 3, 64 kilos, 9 reps». Numeral: hint «Cambia el tipo de serie».
- VO keypad: placeholder «máx» → «reps, máximo, escribe las que salieron»; segmento «0» → «Reps en reserva: 0, al fallo».
- VO tira: un solo elemento «Programa, semana 3 de 5, descarga en 2 semanas».
- Dynamic Type: celdas fijas (FER-394), línea escala; desde AX1 la tira baja debajo (ViewThatFits); nunca trunca. Numeral de serie con 44 pt de toque. Reduce Motion: sub-fila sin animación; sacudida sustituida por texto.

## Edge cases (13)
1. AMRAP palomeado sin reps → no registra; «¿cuántas salieron?». Nunca 0.
2. Drop con peso 0 → fila atenuada «solo con peso».
3. −20 % por debajo de barra vacía o paso mínimo → mínimo construible, «mínimo de tus discos».
4. Quitar madre con drops hechos → confirm; con drops pendientes se quita sin preguntar.
5. Reordenar/sustituir con drops → viajan con la madre.
6. Superserie + drop → salto al siguiente miembro después del último drop.
7. Snapshot tras crash → `SetSnapshot` guarda el tipo.
8. Sesión ad-hoc → todo ③, nada de ⑤.
9. Programa con rutina borrada en un día → descanso honesto; contador intacto.
10. Semana 5 sin sesiones → no avanza; sigue en descarga; «la semana pasada no contó».
11. Zona horaria / firstWeekday → mismo calendario que Tu Plan.
12. Bajar de 6 a 4 semanas estando en la 5 → la actual se vuelve descarga; en la 6 termina y reinicia con aviso.
13. Descarga −40 % sobre 1 serie → 1; sobre 2 → 1. «1 serie · descarga».

## Criterios de aceptación UX (B1–B18)
B1 Tocar el numeral abre el menú de serie; «···» del ejercicio no gana filas.
B2 Editor: Trabajo/Calentamiento/AMRAP/Quitar; sesión suma Drop y Al fallo; drop solo Quitar drop.
B3 AMRAP muestra «máx» y no se palomea sin reps; nunca 0.
B4 «Agregar drop» inserta «↳ DROP» con −20 % a discos y reps de la madre; madre no inicia descanso; último drop sí.
B5 Drop se quita con «Quitar drop» o swipe; madre con drops hechos pide confirmación con conteo.
B6 QUEDABAN «0» y «Al fallo» escriben RPE 10; fila hecha lee «· fallo»; tipo no cambia.
B7 Recibo y detalle «11 máx» y «↳ drop 64 kg · 9» con la misma gramática; récord por AMRAP aparece.
B8 Live Activity y Watch «× máx» / «↳ 64 kg × 9» en `returnDetail`; drops cuentan en «N/M».
B9 Crear plan ofrece «Programa · 4 a 6 semanas» con 4 motores; toast «Programa listo · semana 1 de N».
B10 Tu Plan con programa: línea + tira; sin programa: «Convertir en programa ›».
B11 Semana N: hub «Semana de descarga · N de N»; sesión sirve series −40 % (mín 1) y peso −10 % a discos, editable.
B12 Semana siguiente a la descarga (con ≥1 sesión en ella): contador a 1 sin diálogo; «Ciclo nuevo…» hasta la primera sesión.
B13 Semana sin sesiones no avanza; «la semana pasada no contó».
B14 Con programa, semanas 1–N−1 no muestran `.deloading`; «Estancado · la descarga llega en la semana N». Sin programa, idéntico a hoy.
B15 Prompt incluye «semanas» y «descarga»; confirmación muestra fila o toggle; archivo sin campos importa igual.
B16 VO lee tipo, peso, reps y «al fallo»; la tira es un solo elemento.
B17 AX5 nada se trunca; numeral 44 pt.
B18 Nada requiere red, cuenta ni Watch.

## Preguntas al dueño
1. ¿Celda de reps de AMRAP vacía («máx») o prellenada? Recomiendo vacía.
2. ¿Contador por calendario puro o por «semanas con al menos una sesión»? Recomiendo con sesión.
3. ¿«Programa» también en first-run? Recomiendo solo desde Tu Plan y Crear plan.

## Fuera de alcance
Qué es exactamente cada «motor» es contenido de /pm + /biomecanico; la plantilla PPL existente tiene 3 rutinas, «6 días» las asigna dos veces.
