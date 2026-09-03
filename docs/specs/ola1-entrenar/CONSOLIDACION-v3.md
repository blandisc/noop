# Consolidación v3 · Ola 1 · tras ronda 2 (Grok: 22 cerrados, 2 parciales, 8 nuevos) · 2026-09-02

**Manda sobre v2, v1 y los specs.** v2 sigue vigente en todo lo que aquí no se toque. Esta v3 solo agrega decisiones sobre N1–N8 y cierra H9/H19.

## A · Decisiones ronda 2
| Id | Decisión |
|---|---|
| N1 pulsación larga vs borrar en editor | **Bifurcación explícita (sustituye E2):** en el **editor de rutina** no hay gesto nuevo: el tipo de serie se elige en la hoja de plan por serie que ya existe (FER-492, reps/peso por serie) con un selector «Trabajo · Calentamiento · AMRAP»; la pulsación larga sigue armando el borrado. En la **sesión viva** (sin long-press hoy) la puerta es pulsación larga sobre la fila + chip de marca tocable (AMRAP/DROP/C, 44 pt) + acciones personalizadas de VoiceOver. |
| N2 tope «al límite» ambiguo | Regla única: tras 3 sesiones consecutivas cumplidas-al-límite, **las tres cuentan como estándar** en la racha. Con n = 2 → `.readyToAdvance` (o `.deferred` si el veredicto difiere). Copy del ejercicio: «Tres veces al límite y con las reps: subes, o apaga Q». Test CA: `[met@10, met@10, met@10]`, n = 2, `deferRaise = false` → `.readyToAdvance`. |
| N3 calibra con otro instrumento | Se cita el método como **«carga por esfuerzo: minutos × RPE medio de las series de trabajo (escala RIR mapeada a CR-10), calibrada contra el TRIMP de FC; inspirado en session-RPE (Foster 2001), no literal»**. Los pares registran su fuente (`sessionRpeSource`) y el test lo documenta. No se exige `answered` para calibrar. |
| N4 huérfano promovido | Los drops **nunca se promueven**. La invariante solo reordena un drop para que siga a la no-drop anterior de su ejercicio; si no existe (drop en posición 0), conserva `mode = drop`, cuenta solo a volumen y se pinta «↳ drop». Nada se borra. |
| N5 duplicados default importar | Default **no importar** en «Posibles duplicados» (visibles, toggle = forzar). El resumen de Listo dice «N posibles duplicados se dejaron fuera; revísalos en Ajustes › Importar». |
| N6 «N de las últimas 8 semanas» | N = sesiones que el overlay realmente fusiona (día ≥ primera fila base ∧ dentro de la ventana). Si N = 0: «Tu historia ya alimenta récords y 1RM. Tu carga arranca con tu reloj o con tus próximas sesiones». |
| N7 Q vs 9,5 | Umbrales del motor sin cambio (≤ 8 / ≥ 9,5). Subtítulo alineado: «Q 2 o más: sube en 1 · Q 0 o 9,5: espera · tres al límite: subes o apaga». El keypad emite RIR enteros; la hoja de RPE conserva 9,5. |
| N8 arq-A «se pregunta siempre» | Strike literal en E7/E11: **no se pregunta cuando `strainSource = 'hr'` (cobertura ≥ 0,8)**; con cobertura < 0,8 sí se pregunta (B1). |
| H9 parcial (k default mueve el veredicto) | Cierre: el esfuerzo estimado **no añade ningún votante** al veredicto; entra por la misma vía que la carga medida entra hoy (banda de carga del ACWR). Las etiquetas «estimado» de A·H9 se mantienen. /implement verifica en `Preparedness` si la banda de carga vota; si vota, el acta muestra «carga: estimada» ese día. |
| H19 parcial (prefill sin rechazo explícito) | Con prefill: la celda prellenada aparece seleccionada y tocarla otra vez la **deselecciona** («sin calificar»); tocar otra celda la cambia. Cerrar el recibo o matar la app acepta el prefill etiquetado `prefill`; el detalle permite corregir. Sin prefill: «Sin calificar» terciario (v2). |

## B · Enmiendas nuevas a los specs
E15 **ux-B §③ editor:** selector de tipo en la hoja de plan por serie; sin long-press nuevo en editor (N1).
E16 **ux-A §② copy del ejercicio:** «Tres veces al límite y con las reps: subes, o apaga Q» (N2). Subtítulo del interruptor según N7.
E17 **arq-A §① cabecera del motor:** cita según N3; **strike** de «la pregunta se hace siempre» (N8).
E18 **arq-B §③ invariante de adyacencia:** sin promoción de drops (N4).
E19 **ux-C §Revisar y Listo:** duplicados default fuera; copy de N según overlay (N5, N6).
E20 **ux-A §① recibo:** deselección de la celda prellenada (H19).

## C · Estado
Bloqueantes abiertos: 0. Preguntas al dueño: F de v2 (Q1–Q4, Q6–Q11) sin cambio.
