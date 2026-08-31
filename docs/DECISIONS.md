# Decisiones del dueño — no re-litigar

Registro versionado de las decisiones de producto y proceso ya tomadas por el dueño.
Regla: antes de proponer un cambio que toque uno de estos temas, lee su entrada; si la
propuesta la contradice, la conversación empieza por «quiero revertir la decisión X»,
no por re-abrirla como si fuera nueva. Toda decisión nueva del dueño se **añade aquí en
el mismo PR** que la implementa (una línea basta: fecha, decisión, por qué).

## Producto

- **2026-06 · Cero banda.** La banda WHOOP nunca existió para los usuarios de Cénit: la
  app es 100% Apple Health. Ningún copy, doc o feature nuevo la menciona como vigente
  (épico FER-1003; axioma «mundo nuevo cero banda»).
- **2026-07 · Solo iOS.** Las demás plataformas se retiraron; el app target es `Cenit`.
- **2026-07 · Veredicto v4.** Las 7 decisiones del plan del veredicto quedaron fijadas
  (ver memoria «plan-veredicto-v4-handoff»); el umbral del héroe por ejes NUNCA usa |z|≤1.
- **2026-08 · Hoy.** Tema por hora RETIRADO (FER-398). Cosmos APAGADO (2026-08-06).
  Las 8 decisiones de la auditoría de Hoy (2026-08-16, FER-73…80) y las 7 previas
  (2026-08-13) no se re-abren.
- **2026-08 · Sheets Liquid.** Las 5 excepciones del dueño al rediseño de sheets (FER-29)
  no se tocan.
- **2026-08-22 · Preparación.** «Tus tres señales» PROHIBIDO como título; el ámbar de
  identidad = ámbar de juicio (doradoTemp); `.combine` por ítem (FER-129).
- **2026-08-24 · Entrenar post-épico.** Biblioteca, tope de descanso 3:00 y Guía quedan
  en statu quo; QUEDABAN (FER-147), renombres (FER-148/150) y Progreso % con gates
  CSO+CDO (FER-149) ya ejecutados.
- **2026-08 · Anomalías vitales:** solo FC en reposo (FER-48).
- **Señales:** temperatura de piel reemplaza a SpO₂.
- **2026-08-28 · Foco gestos (FER-187).** Además del «⤢» y el grabber-tap: (a) tap del cromo
  sin celdas de la tarjeta activa (thumb + nombre; no las filas/TapZones de peso-reps) entra
  a foco; (b) arrastre del grabber ⌄ hacia abajo sale. El DragGesture vive SOLO en el
  grabber de `FocoCabecera`, nunca sobre el ScrollView de Foco.
  **Reversión parcial 2026-08-29 (orden del dueño, #1356):** el punto (a) queda DEROGADO — el tap
  del cromo (thumb + nombre) de la tarjeta activa YA NO entra a foco; **abre el DETALLE del
  ejercicio** (`detailExercise`). El foco queda SOLO en el «⤢» y en el «Enfoque» del «···».
  El punto (b) del grabber sigue vigente.
- **2026-08-30 · CTA de arranque = una sola voz** (FER-249). Verde de marca vía
  `LiquidGlassButton(.primary)` en TODOS los contextos, incluido día de descanso. El ámbar
  `dataStrain` queda como excepción nombrada SOLO en el pill «+ Serie». «Hoy subes» habla en
  `verdeCarga` (identidad de carga), nunca `verdePrimario`.

## Proceso

- **2026-08-28 · Cerrar es parte de entregar.** El issue se pasa a `done` en el **mismo
  paso** que se borra la rama, no como trámite posterior; y todo cierre (de issue en
  `/implement`, de corrida en `/orquesta`) corre `Tools/cleanup.sh --apply`. Origen: la
  retro del 2026-08-28 encontró 3 issues verdes-pero-mentirosos (hasta 26 días) y 7.9 GB
  en 22 worktrees fósiles. La receta de poda que ya existía era **ciega por diseño**:
  detectaba ramas entregadas con `merge-base --is-ancestor`, que el squash-merge —el
  único modo de merge del repo— invalida siempre. La señal buena es «la rama tuvo
  upstream y ya no está en `origin`» (FER-194).
- **2026-07-11 · Orquestación:** preview solo frena en pantalla nueva/rediseño;
  auto-merge a iOS salvo riesgo; el alcance por corrida lo fija el dueño al invocar.
- **2026-08-25 · Contrato de flujo:** topes de vueltas adversariales (2 ligero / 3
  pesado, excepción: datos corruptos o copy que miente sobre el cuerpo); lotes, no gotas;
  en vivo por default para retoques visuales; verificación proporcional; `/orquesta`
  default para trabajo multi-paso con Fable/Opus orquestando, Sonnet implementando,
  DeepSeek en lo mecánico y Grok SOLO revisando; tablero obligatorio en toda corrida.
- **2026-08-27 · Reversión parcial del reparto de modelos (orden del dueño):** Grok
  VUELVE al carril de implementación — «para ir más rápido, paralelizar y ahorrar
  tokens» — SOLO para lotes bien especificados (componentes contra mock, wiring,
  trabajo de paquete con spec de 5 partes cerrado) y SOLO vía `grok-lane.sh`
  (worktree determinista + permisos que sí escriben + prohibido compilar; la
  verificación la corre el director). Lo delicado (migraciones, motores, BLE,
  concurrencia) sigue en Claude, y cuando Grok teclea, la revisión adversarial la
  hace OTRA familia — Grok nunca se auto-revisa. Revierte parcialmente el punto
  «Grok SOLO revisando» del contrato 2026-08-25; la falla de agosto tenía causa
  raíz de tooling (hook-discovery + acceptEdits), resuelta por el wrapper.
- **2026-08-26 · Build del iPhone:** sigue siendo manual y al ritmo del dueño — no se
  agenda ni se automatiza.
- **2026-08-30 · El build del iPhone es OPCIONAL, no un paso del flujo (aclara 2026-08-26).**
  El flujo termina en «mergeado a `origin/iOS` + sincronizado a `~/code/noop`». Compilar e
  instalar en el iPhone desde Xcode es cosa del dueño, cuando él quiera: nunca es un gate,
  nunca cierra ni «completa» un cambio, nunca se agenda ni automatiza. Ningún flujo, skill ni
  rutina lo añade como último paso ni trata un cambio como inconcluso hasta estar en el teléfono.
- **DNA:** «Instrumento diurno» es canónico; el sistema oscuro es legacy (mantener, no
  extender). **Superseded 2026-08-29** por «Un solo vidrio: unificar en Liquid Glass · El Eje»
  (abajo); el sistema oscuro sigue retirado.
- **2026-08-29 · Un solo vidrio: unificar en Liquid Glass · El Eje** (épico FER-229). Un solo
  lenguaje de ADN: la receta de vidrio teñido de El Eje bajo el nombre «Liquid Glass». Lienzo
  blanco (ya decidido el mismo día). Dos regímenes, una receta: **Mosaico** (muchos módulos /
  Entrenar: cada tesela se tiñe con su identidad) y **Sobrio** (default; un dato dominante — el
  color vive en el número y su gota, superficie clara). Cuatro colores que no se mezclan:
  identidad de señal · identidad de módulo · juicio (verde/ámbar/rojo del veredicto) · voz de
  marca (verde CTA); `verdeCarga` ≠ verde del veredicto (`verdePrimario`). «Instrumento diurno /
  papel cálido» queda muerto como marco y en migración (punto de vista absorbido; pantallas de
  papel migran; componentes de papel se borran al migrar su último consumidor). Watch OLED es la
  única excepción viva del sistema oscuro retirado. Nombre fundido en API: `liquidGlass` +
  `LiquidTono`.
- **2026-08-29 · Fondo de pantalla blanco (revierte parcialmente el «papel cálido» del DNA):**
  el lienzo de TODAS las secciones (Hoy, Tendencias, Entrenar, Ajustes) pasa de papel cálido a
  blanco, vía el componente compartido `pantallaFondo` (`CenitColor.pantalla`). El papel cálido
  (`InstrumentoTheme.paper`) sigue vivo para tarjetas, hojas y toolbars; Hoy conserva sus
  partículas (`LiquidAtmosfera`) sobre el mismo blanco. Orden del dueño en sesión /inject.
- **2026-08-29 · Distancia y sombra de tarjeta unificadas a un token cada una:** todo elemento tipo
  tarjeta usa `CenitMetrics.cardGap` para su separación y `LiquidElevation.tarjeta` para su sombra
  (las tarjetas teñidas conservan su sombra de color). Un solo lugar por cada cosa. Orden del dueño.
- **2026-08-29 · La consola de la sesión viva vuelve a ocultarse (revierte FER-167 R19):** el keypad
  de la sesión de fuerza gana la tecla ⌄ para bajarlo y ver la tabla completa; se reabre tocando
  cualquier celda de peso/reps (`beginEditing`). Orden del dueño en sesión /inject.

## Cómo revertir una decisión

Se puede — son decisiones, no leyes físicas. El camino: el dueño lo pide explícitamente,
se anota aquí la reversión con fecha y razón, y recién entonces se implementa.

## 2026-08-29 · Entrenar — terminar a medias y descanso sin reloj (FER-250, lote E)

Tres decisiones del dueño para el rediseño del cierre de sesión y el descanso sin Apple Watch:

1. **Sesión parcial = entrenamiento normal.** Si el usuario termina a la mitad y elige «guardar lo hecho», el entrenamiento parcial **cuenta igual** que uno completo: entra al historial, suma volumen y mantiene la racha/constancia. Lo que hiciste es trabajo real (paridad con Hevy). No se marca como «incompleto».
2. **Avisos de sesión ON por defecto durante un entrenamiento activo.** Sin reloj, al terminar el descanso la app **avisa (sonido + vibración) y mantiene la pantalla encendida**, aunque hoy ambos vienen apagados de fábrica. Fuera de una sesión activa, nada cambia. El Watch es una mejora, no un requisito.
3. **Descanso de respaldo = el de la rutina.** Cuando una rutina pide «descanso por pulso» pero no hay reloj, se cae al **tiempo objetivo que ya define la rutina**; si no define ninguno, a un default sensato (90 s). No un fijo global.

Contexto: la 2.ª auditoría de Entrenar (revisión Grok UX) encontró que hoy no hay salida honesta a media sesión (la única es minimizar, que descarta todo) y que el descanso sin reloj castiga al caso más común. Carril pesado: toca `StrengthSessionModel`, la Hoja, la píldora de minimizar y el Watch.
