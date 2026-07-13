# Cénit (Cénit)

Companion offline y on-device para straps WHOOP: captura biometría por BLE, la guarda local y computa recuperación/esfuerzo/HRV/sueño en el dispositivo. Este glosario cubre el lenguaje del dominio, empezando por el motor de coaching proactivo (en diseño).

## Language

### Coaching proactivo

**Check-in**:
Un contacto proactivo del coach — notificación local + tarjeta — que combina algo que decirte (insight, accountability) con algo que preguntarte (contexto, ánimo).
_Avoid_: alerta, recordatorio, push

**Gate de calidad**:
El umbral determinístico que un check-in debe superar para dispararse; si no hay nada que supere el umbral, silencio.
_Avoid_: filtro de spam

**Memoria del usuario**:
Lo que la app sabe de ti más allá de sensores: metas, hábitos comprometidos, eventos de vida, rutinas. Vive en el dispositivo, se llena por captura explícita + extracción conversacional. Distinta de la memoria de Claude (que vive en la Mac del dev, no en la app).
_Avoid_: perfil (eso es `Profile`: biométricos), contexto (demasiado genérico)

**Evento de vida**:
Un hecho no-sensor con rango temporal que explica tu estado: mudanza, proyecto intenso, enfermedad familiar, vacaciones. Capturado a mano o extraído por LLM de una respuesta libre.
_Avoid_: nota, journal entry (el journal es sí/no por día)

**Calendario semántico**:
Los eventos de EventKit categorizados por el LLM en clases comparables (tipo de junta, carga social, viaje) para que el motor estadístico pueda correlacionarlos. Evolución de FER-38, que hoy los trata como texto plano.

**Motor determinístico**:
La capa que decide QUÉ decir, CUÁNDO y A QUIÉN, reutilizando InsightEngine/ReadinessEngine + memoria del usuario. Puro, testeable con `swift test`, sin LLM.

**SemanticEngine (capa LLM)**:
Protocolo swappeable con cuatro trabajos: categorizar (calendario semántico), extraer (respuestas libres → hechos), redactar (voz del check-in) y proponer hipótesis. v1 = Apple FoundationModels; fallback templado siempre disponible.
_Avoid_: "el modelo", "la IA" (ambiguos entre motor y LLM)

**Hipótesis (del LLM)**:
Una corazonada de dónde buscar («¿noches fuera de casa × recuperación?») que el SemanticEngine propone leyendo la memoria del usuario; nunca se muestra al usuario — el motor determinístico la prueba contra los datos y solo sobrevive con significancia (o se ofrece como experimento N-of-1).
_Avoid_: insight (eso es un hallazgo ya validado), predicción

### Motor existente (referencia)

**Insight**:
Un hallazgo estadístico rankeado (p-value, effect size, FDR) de InsightEngine, con confianza `candidate` / `proven` / `medium`.

**Experimento N-of-1**:
Prueba de 7 días de un behavior × outcome; veredicto `sustained` promueve el insight a `proven`.

**Journal**:
Preguntas sí/no por día (alcohol, cafeína, pantalla en cama…). Binario; no captura texto libre.

**Meta (Goal)**:
Objetivo del usuario sobre recovery/sueño/HRV/FC en reposo (FER-311), con proyección de trayectoria.

**Pacto**:
Un hábito concreto que el usuario declara comprometerse a cumplir («no alcohol entre semana»), idealmente sugerido desde una palanca `proven`; el coach lo rastrea con datos reales y confronta con evidencia, no con regaños.
_Avoid_: hábito (genérico), reto, streak

## Relationships

- Un **Check-in** solo se dispara si pasa el **Gate de calidad**; su contenido lo decide el **Motor determinístico** y su redacción (opcional) el **SemanticEngine**.
- La **Memoria del usuario** contiene **Metas**, **Eventos de vida** y hábitos comprometidos; se alimenta de las respuestas a **Check-ins** (vía extracción del **SemanticEngine**) y de captura explícita.
- El **Calendario semántico** y los **Eventos de vida** amplían el espacio de correlación de **Insights**; un insight `candidate` puede convertirse en **Experimento N-of-1**.

## Example dialogue

> **Dev:** "¿El check-in de la mañana siempre llega?"
> **Domain expert:** "No — hay ventana matutina, pero solo dispara si el **motor determinístico** tiene algo que supere el **gate de calidad**. Un día plano es silencio, no un mensaje obvio."
> **Dev:** "¿Y el LLM decide qué es interesante?"
> **Domain expert:** "Nunca. El **SemanticEngine** categoriza, extrae y redacta; qué decir y cuándo es del motor determinístico. Sin Apple Intelligence, el mismo check-in sale con copy templado."

## Flagged ambiguities

- «memoria» se usaba para dos cosas: la memoria de Claude en la Mac del dev y la **Memoria del usuario** en la app — resuelto: la feature construye la segunda; la primera no existe en el iPhone.
- «modelo local» ≠ el cerebro: los hallazgos los produce el **Motor determinístico**; el LLM es capa semántica/voz/oídos — resuelto en diseño (candidato a ADR).
- «Clima» como fuente de contexto queda vetado: WeatherKit es llamada de red y el repo es offline absoluto.

## Decisiones de diseño del coaching proactivo (sesión 2026-07-04)

1. **Núcleo**: el check-in proactivo; conversación y motor son soporte.
2. **Memoria**: híbrida — setup explícito mínimo + extracción conversacional.
3. **Disparo**: ritmo (mañana post-sync, noche journal) + eventos, todo tras el gate de calidad; cap duro de frecuencia.
4. **Modelo**: Apple FoundationModels detrás de protocolo swappeable; el camino de la notificación en background es 100% determinístico + template (el LLM enriquece en foreground).
5. **Fuentes de contexto v1**: calendario semántico, eventos de vida, ánimo/energía subjetivos, estructura temporal (+ luz de día si está en HealthKit). Ubicación/Screen Time → v2+. Clima vetado (red).
6. **Superficie**: el check-in matutino ES el Daily Brief evolucionado (FER-612 es cimiento, no competidor): notificación → Hoy con el Brief expandido en sheet conversacional. Una sola voz matutina.
7. **Accountability**: pactos explícitos rastreados con datos + confrontación con evidencia; un solo tono (sin configurador de intensidad en v1).
8. **Memoria transparente**: vista «Lo que sé de ti» editable; el usuario puede corregir o borrar cualquier hecho.
9. **Anti-repetición**: registro de insights ya contados; el gate de calidad descuenta lo ya dicho.
10. **Fases**: F0 spike FoundationModels es-MX en device → F1 Memoria (schema GRDB + vista editable) → F2 Check-in (motor + gate + scheduler + notificaciones, copy templado, insights existentes) → F3 Pactos → F4 Calendario semántico → F5 Voz + extracción LLM → F6 Generador de hipótesis (LLM propone, motor valida) → F7 «Conexiones» en Tendencias. Carril pesado (ver docs/adr/0001). Épico FER-763 (F0..F7 = FER-765..772).
11. **Quinto trabajo del SemanticEngine** (sesión 2026-07-04, 2ª ronda): generador de hipótesis — el LLM lee la memoria del usuario y sugiere al motor DÓNDE buscar; la estadística decide QUÉ es verdad. Ninguna hipótesis llega al usuario sin validación.
12. **Superficie pull además del push** (3ª ronda): bloque «Conexiones» en Tendencias — el mapa explorable de relaciones confirmadas (solo lo que sobrevivió umbrales/FDR; las descartadas no se muestran). Los check-ins empujan lo urgente; Conexiones deja explorar a demanda.
