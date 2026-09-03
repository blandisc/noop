## Contexto
Con el modelo de E10: crear un programa desde Tu Plan, la tira de semanas, la semana ligera en el héroe, prender/apagar y el import desde tu IA. Fuente: `ux-B.md §⑤` con E3/E4 (v2), el artefacto del dueño `artefactos/ola1-pantallas.html` §5 y su regla de selectores (en la carpeta del taller; E1 lo copia a `docs/specs/ola1-entrenar/artefactos/`); D-Q2/D-Q3/D-Q4/D-Q8/D-Q10; FER-251 (Crear plan archivada), v18 (sin estado nuevo del héroe).

## Objetivo
Programas visibles y controlables sin reabrir pantallas archivadas ni el héroe: fila en `CrearPlanChip`, convertir la semana, tira de semanas, semana ligera como kicker, terminar programa, y el prompt de IA enseñando los campos nuevos.

**Carril:** pesado por alcance (varias pantallas), pero cada pieza es UI sobre lo existente. Preview HTML/canvas con el dueño.

## Comportamiento esperado
- **Crear** (`CrearPlanChip` en Tu Plan y hoja de plantillas): fila «Programa · 4 a 6 semanas» → `StarterTemplatesSheet` en modo programa con 4 motores («Lineal para empezar», «Empuje · Tirón · Pierna · 6 días · intermedio», «Superior / Inferior · 4 días», «Cuerpo completo · 3 días»), subtítulo «N rutinas · 5 semanas · semana ligera en la 5». Pantalla de 3 pasos (solo la primera vez con guía, después compacta): **Semanas** (riel segmentado 4 · 5 · 6; solo el import desde IA acepta hasta 8) · **Semana ligera** (lista con palomita: «Menos series · la mitad, mismo peso» ✓ / «Menos series y menos peso · la mitad, y −7.5 %» / «Sin semana ligera») · **Al terminar** (lista: «Repetir el ciclo · vuelve a la semana 1 con tus pesos» ✓ / «Un solo ciclo · regresas a tu semana normal»). Línea fija: «La última semana es de descanso activo: la ves marcada desde hoy.» CTA «Empezar programa». Si ya hay programa: «Ya tienes un programa en la semana 3 de 5. Empezar otro lo termina.» [Seguir con el mío] [Empezar el nuevo]. First-run: los 3 chips no cambian (D-Q8).
- **Convertir**: en Tu Plan, fila «Convertir en programa ›» (si ≥1 día asignado y sin programa) → misma pantalla de 3 pasos + «Empieza: Esta semana · El lunes».
- **Tu Plan con programa**: línea «Semana 3 de 5 · semana ligera en 2 semanas» + tira (hecha / hoy / futura / ligera con marca «LIGERA»); fila «Al terminar la semana ligera · Repetir ciclo ›». Semana sin sesiones: «Semana 3 de 5 · la semana pasada no contó, sigues en la 3». Tras la ligera: «Ciclo nuevo · semana 1 de 5 · pesos: los que te ganaste» (hasta la primera sesión). «···» gana «Terminar programa» con confirm «¿Terminar el programa? Tus rutinas y tu semana se quedan; solo se va el conteo de semanas.»
- **Hub en semana ligera**: mismo estado «día de rutina»; kicker «Semana ligera · 5 de 5», meta con series reducidas, línea (en el slot de `raiseLine`): «La mitad de las series, el mismo peso. Mismo gym, menos desgaste. La próxima semana arrancas el ciclo con los pesos que te ganaste.» En la sesión, cada fila lleva «· ligera» en el playhead («La última vez: 80 × 8 · hoy 2 series»). El usuario puede agregar series o subir peso.
- **Estancado dentro de un programa**: chip de progresión como hoy («Estancado 3 sesiones · baja 7.5 %») + «la semana ligera llega en la N».
- **Import desde tu IA** (`WorkoutPrompt.es/en`, `WorkoutImportView`): el JSON de ejemplo y dos viñetas explican `semanas`, `semana_ligera`, `al_terminar` y `dia` por rutina (prompt sigue bajo ~40 líneas, FER-825). Pie en captura: «Si tu plan tiene semanas o una semana ligera, tu IA ya sabe ponerlas: el prompt lo pide.» Confirmación: fila «Programa de 5 semanas · semana ligera en la 5» o toggle apagado «Convertirlo en programa de 5 semanas»; si `weeksDiffer`: aviso «Este plan cambia entre semanas; Cénit usará la semana 1 para todas y la última como ligera.» Archivos viejos: sin cambio.

## Accesibilidad
Tira = un solo elemento: «Programa, semana 3 de 5, semana ligera en 2 semanas». Celdas de numeral fijo (FER-394); desde AX1 la tira baja debajo de la línea; nunca trunca. Listas con palomita anuncian estado seleccionado.

## Alcance técnico
`Cenit/Screens/CrearPlanChip.swift`, `StarterTemplatesSheet.swift:276-293`, `WeeklyPlanEditorView.swift` (línea + tira + filas), `Cenit/Screens/Entrenar/EntrenarHubSemana.swift` (tokens), `EntrenarView.swift` (kicker/meta/línea; sin estado nuevo), `Hoja/RoutineSheetLiveTarjeta.swift` (playhead), `Cenit/Data/WorkoutPrompt.swift`, `WorkoutImportView.swift:708-739` (escribir calendario + program), StrandDesign: componente de tira de semanas y lista con palomita (con #Preview; agente `componente`).

## Fuera de alcance
Modelo (E10). Ondas entre semanas. First-run.

## Criterios de aceptación
- [ ] P1 `CrearPlanChip` ofrece «Programa · 4 a 6 semanas» con 4 motores; «Empezar programa» arma semana + programa y muestra «Programa listo · semana 1 de N». P2 First-run idéntico a hoy.
- [ ] P3 Selectores según la regla: Semanas = riel; Semana ligera y Al terminar = lista con palomita; ninguna opción en dos líneas.
- [ ] P4 Tu Plan con programa muestra línea + tira + fila «Al terminar…»; sin programa, «Convertir en programa ›». P5 Terminar programa conserva rutinas y semana.
- [ ] P6 Semana N: kicker «Semana ligera · N de N», meta reducida, sesión sirve series ×0.5 (mín 1), editable; el héroe no cambia de forma (mismo `EntrenarHubHeroe`).
- [ ] P7 Semana en blanco → «la semana pasada no contó»; tras la ligera (repeat) → «Ciclo nuevo…»; (single) → programa terminado con aviso.
- [ ] P8 Estancado en semana 2 muestra «baja 7.5 %» + «la semana ligera llega en la N».
- [ ] P9 Prompt de IA incluye los 4 campos; confirmación muestra fila/toggle/aviso según el archivo; archivo viejo importa igual.
- [ ] P10 VoiceOver y AX5 según arriba. P11 Nada requiere red, cuenta ni reloj.

## Definition of Done
- [ ] Preview aprobado; `Tools/verify.sh app` verde; /qa PASS; claves `es` + `en` (nunca `es-MX`); CHANGELOG.
