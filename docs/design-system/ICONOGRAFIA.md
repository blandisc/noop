# Iconografía

> Compañero de [`DESIGN.md`](DESIGN.md) (**Liquid Glass · El Eje** — marco canónico; «Instrumento
> diurno» = generación anterior absorbida · en migración). Define cómo se eligen, nombran y usan
> los iconos en Cénit: el catálogo `StrandIcon`, los glifos dibujados a mano, el tamaño ligado a
> la rejilla, la accesibilidad y qué reservar. Aterrizado en el uso real (76 nombres SF distintos,
> `chevron.right` solo = 52 usos).

---

## 1. Principio: nombra por propósito, no por forma

Un icono se nombra por **lo que hace**, no por cómo se ve (misma regla que el copy en
[`LENGUAJE.md §4`](LENGUAJE.md)). El triángulo de reproducir es `play`, no `triangle`. Esto evita que
dos pantallas usen iconos distintos para la misma acción, o el mismo icono para cosas distintas.

## 2. Catálogo `StrandIcon`

El set de alta frecuencia + semántico vive en `StrandIcon` (`Packages/StrandDesign/Sources/StrandDesign/StrandIcon.swift`).
Úsalo con `StrandIcon.disclosure.image` en vez de `Image(systemName: "chevron.right")`.

| Caso | SF Symbol | Propósito |
|---|---|---|
| `disclosure` | `chevron.right` | Abrir/entrar a un detalle (afordancia de fila). **52 usos hoy.** |
| `back` | `chevron.left` | Volver |
| `close` | `xmark` | Cerrar hoja/modal |
| `confirm` | `checkmark` | Confirmar / hecho |
| `add` | `plus` | Agregar (serie, entrenamiento…) |
| `more` | `ellipsis` | Más acciones |
| `info` | `info.circle` | Información / explicación |
| `warning` | `exclamationmark.triangle.fill` | Alerta / atención |
| `search` | `magnifyingglass` | Buscar |
| `up` | `arrow.up` | Sube / mejora |
| `down` | `chevron.down` | Colapsar / bajar |
| `heart` | `heart.fill` | Frecuencia cardíaca |
| `sleep` | `moon.zzz` | Sueño |
| `flame` | `flame` | Esfuerzo / calorías |
| `experiment` | `flask` | Experimento N-of-1 |
| `clock` | `clock` | Tiempo / duración |
| `calendar` | `calendar` | Fecha / calendario |

El resto de símbolos SF (cola larga de usos únicos) puede seguir inline; si uno empieza a repetirse
(≥3 veces) o es una acción común, se promueve al catálogo — misma regla que los componentes.

## 3. Iconos reservados

Estos representan acciones comunes y **no deben usarse para otra cosa**:
`disclosure` (navegar a detalle) · `close` (cerrar) · `confirm` (confirmar) · `add` (agregar) ·
`back` (volver). Reservarlos hace la app predecible.

## 4. Glifos dibujados a mano (custom)

Cuando ningún SF Symbol dice lo que necesitamos, dibujamos el glifo (CoreGraphics/Path) en
`StrandDesign`. Los que existen:

| Glifo | Uso |
|---|---|
| `DialTabGlyph` | Icono de la pestaña «Hoy» (dial 24h) |
| `PatronesGlyph` | Pestaña «Patrones» / Coach |
| `TendenciasGlyph` | Pestaña «Tendencias» |
| `InsightGlyph` | Marcador de insight |
| `BarcodeGlyph`, `ThermalDialGlyph` | Recibo térmico (skeuomorfo) |

Los cuatro primeros forman el set de la barra de pestañas; se envuelven en `AuthoredGlyph`. Un glifo
custom se justifica solo cuando la familia SF no cubre el significado con el estilo del sistema.

## 5. Estilo y tamaño

- **Estilo:** SF Symbols en su estilo por defecto; los glifos custom son de **línea** (coherentes
  con el instrumento de precisión del ADN Liquid Glass · El Eje). No mezclar filled/outlined al
  azar en una misma superficie.
- **Tamaño ligado a texto/rejilla:** usa `StrandFont.GlyphSize` (chevron/inline/lead/empty) y
  `StrandFont.glyph(_:)` para que el icono case con el texto y el grid (no `.font(.system(size:))`
  suelto). Un icono pareado a texto vive en su caja para alinear con la línea base.

## 6. Accesibilidad

- **Con significado → nombre hablado.** Si el icono comunica o es accionable, dale
  `accessibilityLabel` con ese significado. Ver [`ACCESIBILIDAD.md §3`](ACCESIBILIDAD.md).
- **Decorativo → oculto.** `accessibilityHidden(true)` en glifos puramente estéticos (ya es el patrón
  consistente en `StatePill`, `ThermalTicket`, estados vacíos…).
- Los glifos custom (`PatronesGlyph`, etc.) deben traer label si actúan como control (p. ej. tab).

## 6.5 Sellos de métrica de Hoy (`SelloMetrica`)

La Matriz de Hoy NO usa SF Symbols: usa **sellos dibujados** que retratan cada métrica. Son la
única familia de iconografía propia del sistema, y no se escriben a mano — los **genera**
`Tools/sellos-hoy/forge.py` y los vuelca en `SelloMetricaPaths.swift`.

| Regla | Por qué |
|---|---|
| No editar `SelloMetricaPaths.swift` | Es generado. Cambia el forjador y vuelve a correrlo. |
| El dibujo llena su lado | Traen su margen por dentro (tinta en [2,22] del viewBox 24). `LiquidIconDrop` encoge su glifo porque los símbolos de sistema ya traen el suyo: aplicar las dos reglas los rompe. |
| 20 pt en la Matriz, 28 en cabecera de hoja | Los mínimos (remates, ranuras, aires) están verificados a 20 pt. Por debajo, se borran. |
| El Guardián no lleva sello dibujado | Su sello es `SelloGuardianVivo`: el movimiento ES el dato (estado del par). |
| Identidad, no veredicto | La aguja del medidor de estrés va vertical a propósito: un sello de identidad no puede afirmar «estrés medio-alto» todos los días. |

El forjador verifica al emitir lo que el ojo no alcanza a esa escala: simetría de espejo, área
segura, y que ningún rasgo caiga bajo el pixel a 20 pt. `SelloMetricaTests` ancla el lado Swift.

## 7. Gobernanza

| Regla | Estado |
|---|---|
| Set frecuente en `StrandIcon`, nombrado por propósito | **Token** (este release) |
| Nombrar por propósito, reservados, custom vs SF | **Convención** (este doc) |
| Sin `Image(systemName:)` crudo en pantallas | **Fase 2** (posible regla de lint incremental, como las actuales) |

---

### Ver también
- [`DESIGN.md`](DESIGN.md) — sistema visual.
- [`ACCESIBILIDAD.md`](ACCESIBILIDAD.md) §3 — labels de VoiceOver.
- [`LENGUAJE.md`](LENGUAJE.md) §4 — nombrar por propósito (mismo principio que el copy).
