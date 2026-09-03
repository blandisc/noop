## Contexto
La pantalla de progresión tiene seis controles del mismo tamaño; con E4 tendría siete. El dueño pidió dos pasadas de UX manteniendo funcionalidad, el nombre «reps en reserva» (no «Q»), y la regla de selectores (lista con palomita para opciones con explicación). Fuente: `ux-A.md §②` con E1/E13/E16, D-Q1/D-Q6, y el artefacto del dueño `artefactos/ola1-pantallas.html` §3b (en la carpeta del taller; E1 lo copia a `docs/specs/ola1-entrenar/artefactos/`). El wireframe mínimo está en este issue.

## Objetivo
Progresión por ejercicio con una frase-resumen arriba, tres controles visibles, un selector «Ritmo» de tres opciones en lista con palomita, y ajustes finos plegados; el hub explica el porqué con una línea cuando las reps en reserva cambiaron algo.

**Carril:** ligero (UI/copy sobre pantallas existentes). Preview en canvas/inject con el dueño.

## Comportamiento esperado
- `ProgressionSetupScreen`: (1) tarjeta verde arriba con la frase «Subes **2.5 kg** cuando cumples **8 reps** con ritmo **constante**. Si te estancas tres veces, bajas 7.5 %.» (se recalcula al cambiar cualquier control); (2) visibles: «Progresión automática» (toggle), «Reps objetivo», «Paso de carga · de tus discos»; (3) «Ritmo» = lista con palomita: **Constante** «subes tras 2 sesiones cumplidas» · **Rápido** «subes tras 1» · **Según reps en reserva** «1 si te sobraron 2 · espera si llegaste al fallo»; (4) «Ajustes finos ▾» plegado: «Si te estancas 3 sesiones» (Bajar 7.5 % / Solo avisar) y «Cuando tu cuerpo dice mantén» (Esperar / Subir igual) (renombra «Días fuera de rango»).
- Mapeo: Constante = `sessions 2, useRPE false`; Rápido = `sessions 1, useRPE false`; Reps en reserva = `useRPE true` (sessions se conserva para el caso no-cómodo). Rutinas existentes muestran su estado real (2 → Constante, 1 → Rápido).
- Chip del ejercicio en el editor (`ProgressionChip.summary`): «+2.5 kg · constante» / «+2.5 kg · rápido» / «+2.5 kg · reps en reserva».
- Hub (héroe v18, `raiseLine`): línea 2 solo en casos cómodo / al límite / tope: «Llegaste a las reps y te sobraban 3. Una sesión bastó.» · «Llegaste, pero al fallo. Una sesión más holgada y cuenta para subir.» · «Tres veces al fallo y con las reps: subes, o cambia el ritmo.» El caso «reps dicen sube, el cuerpo dice mantén» NO vuelve al héroe: se muestra en la fila del ejercicio (subtítulo) y en SUBIDAS LISTAS con la razón (E1; no reabrir FER-171).
- Teclado de sesión: la fila «QUEDABAN 0·1·2·3·4+» se renombra «REPS EN RESERVA» (mismo control), y la fila hecha con 0 en reserva lee «· al fallo» en vez de «· Q0».

## Alcance técnico
`Cenit/Screens/ProgressionSetupScreen.swift`, `EntrenarView.swift:371-383, 832-852`, `Hoja/RoutineSheetLiveLogic.swift:892-898`, `SessionKeypad.swift:67-74` (labels), `Hoja/RoutineSheetLiveTarjeta.swift` (sufijo). Solo tokens StrandDesign; la lista con palomita usa el componente de opciones existente o se crea uno en StrandDesign con #Preview (agente `componente`).

## Fuera de alcance
La regla (E4). El vocabulario del resto de la app (E12), salvo el teclado, que va aquí porque esta pantalla lo explica.

## Criterios de aceptación
- [ ] La frase-resumen refleja cada cambio de control (reps, paso, ritmo, deload) en vivo.
- [ ] «Ritmo» es lista con palomita (título + subtítulo); no hay ningún control segmentado con más de una palabra por opción.
- [ ] Rutina existente con `sessions=2, useRPE=0` abre en Constante; guardar sin cambios no altera columnas.
- [ ] Elegir «Según reps en reserva» persiste `progressionUseRPE = 1`; el chip del editor dice «reps en reserva».
- [ ] Hub: los tres copys de línea 2 aparecen solo en sus casos; en «normal» y «sin RPE» el héroe es idéntico a hoy; «la subida espera» no vuelve al héroe.
- [ ] Teclado: «REPS EN RESERVA» y «· al fallo»; ninguna cadena visible dice «Q» ni «Quedaban».
- [ ] Dynamic Type AX5: nada se trunca; VoiceOver lee la lista de ritmo con estado seleccionado.

## Definition of Done
- [ ] Preview aprobado por el dueño; `Tools/verify.sh app` verde; claves `es` + `en` (nunca `es-MX`); sin `/qa` (carril ligero) pero con checklist de arriba en el PR. Este issue es el dueño de las cadenas visibles del teclado de reps en reserva.
