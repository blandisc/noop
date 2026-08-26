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

## Proceso

- **2026-07-11 · Orquestación:** preview solo frena en pantalla nueva/rediseño;
  auto-merge a iOS salvo riesgo; el alcance por corrida lo fija el dueño al invocar.
- **2026-08-25 · Contrato de flujo:** topes de vueltas adversariales (2 ligero / 3
  pesado, excepción: datos corruptos o copy que miente sobre el cuerpo); lotes, no gotas;
  en vivo por default para retoques visuales; verificación proporcional; `/orquesta`
  default para trabajo multi-paso con Fable/Opus orquestando, Sonnet implementando,
  DeepSeek en lo mecánico y Grok SOLO revisando; tablero obligatorio en toda corrida.
- **2026-08-26 · Build del iPhone:** sigue siendo manual y al ritmo del dueño — no se
  agenda ni se automatiza.
- **DNA:** «Instrumento diurno» es canónico; el sistema oscuro es legacy (mantener, no
  extender).

## Cómo revertir una decisión

Se puede — son decisiones, no leyes físicas. El camino: el dueño lo pide explícitamente,
se anota aquí la reversión con fecha y razón, y recién entonces se implementa.
