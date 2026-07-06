# El coaching proactivo lo decide un motor determinístico; el LLM es solo capa semántica

---
status: accepted
---

Para el motor de coaching proactivo (check-ins, pactos, calendario semántico), QUÉ decir, CUÁNDO
y A QUIÉN lo decide un motor determinístico puro (reutiliza InsightEngine/ReadinessEngine + la
memoria del usuario), testeable con `swift test`. El LLM local (Apple FoundationModels detrás de
un protocolo `SemanticEngine` swappeable) hace exactamente cuatro trabajos: **categorizar**
(títulos de calendario → clases comparables), **extraer** (respuesta libre → hechos
estructurados vía guided generation), **redactar** (hechos ya validados → voz natural) y
**proponer hipótesis** (leer la memoria del usuario y sugerir al motor DÓNDE buscar; la
propuesta nunca se muestra — el motor la prueba estadísticamente y solo sobrevive con
significancia, o se ofrece como experimento N-of-1). Nunca razona sobre datos crudos ni decide
qué se le dice al usuario.

## Por qué

- Los hallazgos «mágicos» («cuando tienes esta junta, tu estrés sube») son correlaciones que
  requieren rigor estadístico (p-value, effect size, FDR) — un LLM de ~3B las alucina; el
  InsightEngine ya las computa bien. La regla del repo de matemática transparente aplica.
- El check-in matutino nace en un despertar BLE en background, donde iOS no da memoria/CPU para
  ningún LLM: el camino crítico de la notificación es determinístico + template por necesidad,
  con cualquier modelo. El LLM enriquece en foreground.
- Sin Apple Intelligence (device viejo, modelo apagado) la feature degrada a copy templado y
  chips — no desaparece. Mismo patrón de 3 niveles ya probado en Pregúntale (FER-308).

## Alternativas rechazadas

- **LLM como cerebro del razonamiento**: no testeable, alucina números, rompe transparencia, y
  muere en background y en devices sin Apple Intelligence.
- **Modelo embebido (Gemma/MLX) en v1**: +1.5–2 GB de app, integración y mantenimiento propios,
  y tampoco puede correr en el despertar de background — su única ventaja (cobertura de devices
  sin A17 Pro) no justifica el costo hoy. El protocolo `SemanticEngine` deja la puerta abierta
  si la calidad en español de FoundationModels decepciona (validar con spike F0).
- **Clima como fuente de contexto**: WeatherKit es llamada de red; el repo es offline absoluto.
