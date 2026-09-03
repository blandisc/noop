## Contexto
Entrenar se está volviendo complejo (5 descansos, 3 tipos de serie, reps en reserva, semana ligera, programas). El dueño no sabe qué es AMRAP; el usuario no técnico tampoco. Mejor práctica (HIG Onboarding, TipKit iOS 17 — nuestro mínimo es 17.0): enseñar en contexto, una vez, sin tour. Fuente: el artefacto del dueño `artefactos/ola1-pantallas.html` §4 (en la carpeta del taller; E1 lo copia a `docs/specs/ola1-entrenar/artefactos/` y crea `tips-es.md` con la tabla de abajo), vocabulario final del épico.

## Objetivo
Un vocabulario en palabras en toda la app y cuatro capas de enseñanza: nombres, consejos contextuales de una sola vez (TipKit), glosario en el «?» y guía de 3 pasos al crear el primer programa.

**Carril:** ligero (copy + componentes de ayuda), pero transversal: se ejecuta al cierre de la wave de pantallas.

## Comportamiento esperado
- **Capa 1 · Nombres** (barrido del catálogo de strings de Entrenar; NO reescribe las cadenas que E5 y E7 ya cambiaron en el teclado y la sesión, solo verifica y completa el resto): «reps en reserva» (RIR chico donde quepa) en teclado, setup, hub y hojas; «las que puedas» (AMRAP), «bajar y seguir» (drop), «llegué al fallo»; «semana ligera» (nunca «descarga» en Entrenar); «esfuerzo estimado». Ninguna cadena visible dice «Q», «Quedaban», «AMRAP» solo, «drop» solo ni «descarga» en Entrenar.
- **Capa 2 · Consejos (TipKit)**: un `Tip` por concepto, con regla de aparición (la primera vez que el concepto aparece en la pantalla del usuario), máximo uno por pantalla, se cierra con «Entendido» y no vuelve; estilo tinta sobre vidrio (StrandDesign, componente `LiquidConsejo` con #Preview). Conceptos: las que puedas, bajar y seguir, reps en reserva (en el teclado, la primera vez que se registra una serie), esfuerzo estimado (primer recibo con la pregunta), semana ligera (primera vez que Tu Plan la muestra), ritmo (primera vez en setup). Copy es-MX final (título · cuerpo), sin género, sin claims:
  | Concepto | Título | Cuerpo |
  |---|---|---|
  | Las que puedas | Serie «las que puedas» | Haz todas las reps que puedas con buena forma y anota cuántas salieron. Cuenta para tus récords y para subir. |
  | Bajar y seguir | «Bajar y seguir» | Al terminar la serie, baja el peso y sigue sin descansar. Suma volumen; no cuenta para subir ni para récords. |
  | Reps en reserva | Reps en reserva | Cuántas reps más podías hacer al terminar. 0 = llegaste al fallo. Con esto la app decide si subes. |
  | Esfuerzo estimado | ¿Qué tan duro estuvo? | Un toque al cerrar. Con minutos y esfuerzo, tu sesión entra a tu carga aunque no traigas reloj. |
  | Semana ligera | Semana ligera | La última del ciclo: la mitad de las series, el mismo peso. Descansas sin dejar de entrenar. |
  | Ritmo | Ritmo de subida | Constante sube tras 2 sesiones cumplidas; rápido tras 1; por reps en reserva, 1 si te sobraron 2 y espera si llegaste al fallo. |
- **Capa 3 · Glosario**: `WorkshopTricksScreen` (el «?») gana la sección «Palabras del gym» con tarjetas: las que puedas · bajar y seguir · reps en reserva · semana ligera · esfuerzo estimado · descansos (5 formas) · programa · 1RM estimado. Cada una: qué es, cuándo usarla, qué hace la app con el dato (una línea cada una).
- **Capa 4 · Guía de 3 pasos**: la pantalla de crear programa (E11) muestra, solo la primera vez, una línea de porqué por paso y el enlace terciario «¿Qué es una semana ligera?» al glosario.
- Reglas: nunca un modal que bloquee; todo lo avanzado nace escondido (serie normal, descanso fijo, sin programa).

## Alcance técnico
`Cenit/Screens/WorkshopTricksScreen.swift`, catálogo `.xcstrings` (es bajo «es», nunca «es-MX»), StrandDesign `LiquidConsejo` (TipKit `TipView` estilizado o vista propia con `Tips.showTipsForTesting`), reglas de tips en `Cenit/System/EntrenarTips.swift` (nuevo). Gate i18n; gate anti-literales.

## Fuera de alcance
Un onboarding/tour de Entrenar. Videos o imágenes del catálogo.

## Criterios de aceptación
- [ ] `grep` del catálogo de strings (claves de Entrenar) no encuentra «Quedaban», «Q0»/«Q1», «AMRAP» sin «las que puedas», «descarga» en Entrenar.
- [ ] Cada consejo aparece exactamente una vez en un dispositivo limpio y en el lugar del concepto; «Entendido» lo cierra; con `Tips.resetDatastore` vuelve a aparecer (test de UI).
- [ ] Nunca dos consejos a la vez en una pantalla.
- [ ] «Palabras del gym» lista los 8 términos con las tres líneas cada uno; accesible desde el «?» de Entrenar.
- [ ] La guía de 3 pasos aparece solo la primera vez que se crea un programa.
- [ ] Reduce Motion: los consejos aparecen sin animación; VoiceOver los lee como alerta no modal.

## Definition of Done
- [ ] `Tools/verify.sh app` verde; gate i18n verde; preview con el dueño de dos consejos y el glosario.
