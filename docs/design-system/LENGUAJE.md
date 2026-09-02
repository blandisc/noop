# Lenguaje — voz, escritura y contenido

> Compañero de [`DESIGN.md`](DESIGN.md). Donde `DESIGN.md` define **cómo se ve** el sistema
> (**Liquid Glass · El Eje**: vidrio teñido sobre lienzo blanco, dos regímenes mosaico/sobrio),
> este documento define **cómo suena**: la voz, las reglas de escritura, el microcopy por
> componente y el glosario canónico de términos. Es es-MX y describe lo que la app **ya hace** —
> no inventa una voz nueva.
>
> «Instrumento diurno / papel cálido» es la **generación anterior** del ADN (absorbida · en
> migración; inventario en `DESIGN.md` §8) — su punto de vista (instrumento de precisión, un
> dato dominante, color con significado) vive ahora dentro de Liquid Glass · El Eje.
>
> Todos los ejemplos son copy real del String Catalog (`Cenit/Resources/Localizable.xcstrings`).
> La sección de voz visual (tipografía de la voz) vive en `DESIGN.md` §8.7 (inventario en
> migración); aquí está el contenido.

---

## 1. La voz en una frase

**Un instrumento de precisión (Liquid Glass · El Eje) que habla como un coach tranquilo en
primera persona, te tutea, y nunca inventa un número.** Mide, no sentencia. Sugiere con
evidencia, no diagnostica.

Tres rasgos que la definen:

1. **Honesta antes que optimista.** Si no hay dato, lo dice y explica por qué. El numeral nunca
   miente (§5.6). Nada de datos falsos para «llenar» la pantalla.
2. **En primera persona, contigo en segunda.** El coach dice «tengo / necesito / no encuentro / lo
   detectaré» y se dirige a ti como «tú» y a «tu cuerpo / tu ritmo / tus señales».
3. **Con reservas, siempre.** El cuerpo es ruidoso. La voz cubre sus afirmaciones: «apunta a»,
   «señal de», «asociación, no causa», «contexto, no una predicción». Los números cargan su origen
   (`n=…`, «calculado a partir del esfuerzo de tu banda»).

La promesa de marca recurre como firma: **«todo se queda en tu iPhone · sin cuenta · sin servidor ·
sin nube».** El éxito, cuando aplica, dobla como tranquilidad de privacidad («en tu iPhone, cifrado
del sistema»).

---

## 2. Principios de voz

| Principio | Qué significa | En vez de |
|---|---|---|
| **Mide, no juzga** | Reporta la señal y su contexto. | «Dormiste mal» → «Tu sueño quedó por debajo de tu base». |
| **La culpa es del sistema, no tuya** | Los errores son impersonales: «No se pudo…». | «Escribiste mal el archivo» → «Uno de los ejercicios no tiene nombre. Revisa el archivo». |
| **Nunca inventes un número** | Sin dato → glifo honesto (`—`, `··`, `~N`), no un cero falso. | Mostrar «0%» cuando en realidad no hay lectura. |
| **Cubre lo que no sabes** | Hedge obligatorio en copy de cuerpo/dato. | «Esto te va a lesionar» → «Contexto para tu recuperación, no una predicción de lesiones». |
| **Breve y cálido** | Confirmaciones de 1–3 palabras; sin relleno. | «La operación se completó con éxito» → «Todo listo». |
| **No supongas quién eres** | Construcciones neutras de género (§7). | «Estás cansado» → «Baja el ritmo y dale a tu cuerpo tiempo de recuperarse». |

---

## 3. Tono por contexto

La voz base es una; el **tono** se ajusta al momento del usuario.

| Contexto | Tono | Ejemplo real (es-MX) |
|---|---|---|
| **Onboarding / privacidad** | Directo, confiado, sin jerga | «Cénit calcula por sí mismo tu recuperación, esfuerzo y sueño, en el dispositivo, sin nube.» |
| **Éxito / confirmación** | Corto, cálido | «Todo listo.» · «¡Copiado!» · «Todo guardado en tu iPhone» |
| **Error** | Tranquilo, impersonal, con salida | «No se pudo guardar el entrenamiento. Inténtalo de nuevo.» |
| **Estado vacío** | Honesto + alentador, explica el porqué | «Aún no encuentro un hábito con efecto claro en tus números. Sigue registrando tu día y lo detectaré.» |
| **Coach / insight** | Primera persona, con datos y reservas | «La HRV cayó muy por debajo de tu base, lo que apunta a estrés o fatiga elevados. Baja el ritmo…» |
| **Sin señal / calibrando** | Fáctico, sin drama | «SIN SEÑAL DE BANDA» · «En vivo. Tus puntuaciones se están construyendo.» |

---

## 4. Guía de escritura (house style es-MX)

Reglas duras del español de la app. Varias están **verificadas por CI** (§8).

1. **Tuteo siempre. Nunca «usted».** Cero ocurrencias de «usted» en el catálogo. Imperativos en
   forma tú: *Inténtalo, Revisa, Conecta, Usa tu banda, Baja el ritmo, Pregunta, Sigue registrando*.
   Posesivos: *tu / tus*.
2. **Botones = imperativo desnudo, 1–3 palabras.** *Empezar · Guardar · Agregar serie · Buscar mi
   banda · Conectar Apple Salud · Continuar · Ver tu plan · Listo*. «Add X» siempre es **«Agregar X»**
   (nunca «Añadir»).
3. **Sin em-dash (—) en el copy.** Usa coma, dos puntos o «·». *«Falló la verificación, intenta
   resincronizar.»* · *«…en este momento: se reintentará.»* (Verificado por CI, regla
   `no-emdash-string`.) El glifo suelto **«—»** para «sin dato» **sí** se permite: es un símbolo, no
   texto.
4. **«·» (punto medio) es el separador de meta/listas.** *«sin cuenta · sin servidor»* · *«mín %@ ·
   máx %@ bpm»*.
5. **Hedge obligatorio en copy de cuerpo/dato.** Nada de causalidad ni diagnóstico: *«apunta a»,
   «señal de», «tendencia, no causa», «asociación, no causa», «no una predicción de lesiones»*.
6. **Los números cargan su origen.** Muestra la muestra y la fuente: *«n=%lld»*, *«Calculado a
   partir del esfuerzo de tu banda»*.
7. **El éxito reafirma la privacidad** cuando puede: *«%lld noches guardadas · en tu iPhone, cifrado
   del sistema»*.
8. **Errores con el marco fijo «No se pudo… + reintento».** *«No se pudo verificar. Inténtalo de
   nuevo.»* La culpa nunca es «tú».
9. **Marca:** «Cénit» es el nombre de producto; «WHOOP» → siempre **«banda»** en cuerpo («Buscar mi
   banda», nunca «correa»). **«Apple Health» → «Apple Salud»** siempre.
10. **El signo apertura sí se usa** donde aplica: *«¡Copiado!»*.

---

## 5. Microcopy por componente

### 5.1 Botón / CTA
Imperativo tú, 1–3 palabras, sin punto final. Verbo primero.
`Empezar` · `Guardar` · `Agregar entrenamiento` · `Activar alarma inteligente` · `Ver patrón →`

### 5.2 Error
Marco **«No se pudo [verbo]. [Salida].»** Impersonal, con reintento, sin culpar.
`No se pudo guardar el entrenamiento. Inténtalo de nuevo.` ·
`Falló la verificación, intenta resincronizar.`

### 5.3 Estado vacío
Explica **por qué** no hay nada + **qué hacer**. El coach promete notar.
`Aún no encuentro un hábito con efecto claro en tus números. Sigue registrando tu día y lo detectaré.` ·
`Usa la banda unas cuantas noches y tu lectura de preparación aparecerá aquí.`

### 5.4 Confirmación / éxito
1–3 palabras, cálida. Si aplica, reafirma privacidad.
`Todo listo.` · `¡Copiado!` · `Todo guardado en tu iPhone`

### 5.5 Coach / insight
Primera persona, dato + reserva. Nunca diagnostica.
`Por encima de tu base, listo para un día fuerte.` ·
`Necesito al menos 3 señales para calcularla sin adivinar. Llevas %lld.`

### 5.6 El numeral nunca miente (regla más importante del sistema)
El héroe usa glifos honestos, no números inventados (ver `DESIGN.md §8.7.1`):

| Estado | Glifo | Significado |
|---|---|---|
| Calibrando | `··` | Aún no hay lectura suficiente |
| Sin dato / en espera | `—` | No hay señal |
| Estimado de Apple | `~N` | Recuperación aproximada, no de la banda |
| Lectura lista | `N` en **color de nivel** | Dato confiable |

Invariante: **color de nivel = lectura lista; tinta / `—` = en espera.**

---

## 6. Glosario canónico

El término de la izquierda es el **único** que debe aparecer en pantalla para ese concepto.

| Concepto (EN) | Canónico es-MX | Notas |
|---|---|---|
| Recovery | **Recuperación** | — |
| Strain / Effort | **Esfuerzo** | **Nunca «tensión».** Strain y Effort colapsan en una sola palabra. |
| Sleep | **Sueño** | — |
| HRV | **HRV** | Se mantiene la sigla. |
| Baseline | **base** (cotidiano) / **línea base** (formal) | «tu base» en copy corto; «línea base» en explicaciones. |
| Readiness | **Preparación** | No «disposición» (string viejo, no canónico). |
| Signals | **Señales** | — |
| Session | **Sesión** | — |
| Band / strap | **banda** | Nunca «correa». |
| Today | **Hoy** | Tab. |
| Train | **Entrenar** | Tab. «Add Workout» → «Agregar entrenamiento». |
| Trends | **Tendencias** | Tab. |
| Patterns | **Patrones** | «SIN PATRÓN CLARO», «Ver patrón →». |
| Coach / Loop | **Coach** (tab) / **el Bucle** (pantalla) | Ver `docs/SCREENS.md`. |
| Apple Health | **Apple Salud** | Siempre localizado. |

**Verdictos / niveles:** `Primed`→**A punto**, `Balanced`→**Equilibrado**, `Strained`→**Exigido**,
`Run down`→**Desgastado**, `Recovering`→**Recuperándote**, `Optimal`→**Óptimo**,
`Low/Moderate/High`→**Bajo / Moderado / Alto**, `Depleted`→**AGOTADO**, `Learning`→**APRENDIENDO**.

**Etiquetas de tiempo:** `Today`→**Hoy**, `Yesterday`→**Ayer**, `Tomorrow`→**Mañana**,
`Last night`→**Anoche**, `Tonight`→**Esta noche**. Relativas: **«hace %lld min / hace %lld h»**.

---

## 7. Género y neutralidad

**Principio:** el copy no supone el género de quien lee. Se logra con las herramientas que el
español ya da:

- **Segunda persona «tú» + gerundios:** `Recuperándote` (neutro), en vez de un adjetivo con género.
- **Dirígete al cuerpo, no a la persona:** «dale a **tu cuerpo** tiempo de recuperarse», «**tu
  ritmo**», «**tus señales**» — esquiva la concordancia de adjetivo.
- **Términos clínicos neutros** en temas sensibles: «No te dice qué día empieza tu siguiente
  periodo» (fáctico, sin suponer).

> **Deuda conocida (limpieza pendiente).** Este principio se cumple **a medias**: varios verdictos
> siguen en masculino por defecto — **«Equilibrado», «Exigido», «Desgastado», «listo para un día
> fuerte», «%lld de %lld hechos»**. Formalizar la neutralidad al 100% requiere una pasada de copy
> sobre esas cadenas (candidato a issue propio). Hasta entonces, este documento describe la
> **aspiración** y el estado real.

---

## 8. Formato de números y unidades

El formato es parte del lenguaje visual; las pantallas consumen los helpers, no redeclaran
`NumberFormatter` (`Packages/CenitDesign/Sources/CenitDesign/CenitFormat.swift`).

- **Enteros agrupados:** `CenitFormat.groupedInt` → `12,345` (sin decimales).
- **Numerales tabulares siempre** (`font-variant-numeric: tabular-nums` / SF Mono) para que las
  columnas de dígitos alineen.
- **Unidades con espacio:** `%lld h`, `%lld min`, `bpm` (se mantiene en inglés), `pts`, `kcal`.
- **Temperatura:** signo + valor + `°C` sin espacio → `+1.2°C`.
- **Deltas con el signo menos real** `−` (U+2212), no guion: `−%lld pts`.
- **Abreviaturas:** `mín / máx / reposo` → «mín %@ · máx %@ · reposo %@ bpm».
- **Estadística:** `±` para variación, `σ` (o «DE») para desviación → «±tu variación».

---

## 9. Gobernanza — qué está verificado vs. qué es convención

| Regla | Estado |
|---|---|
| Sin em-dash en copy | **Verificado por CI** — `Tools/check-design-drift.py --rules no-emdash-string`, `.github/workflows/design-lint.yml` |
| Strings de UI son claves en inglés con traducción `es` (nada de español hardcodeado) | **Verificado por CI** — `Tools/check-hardcoded-strings.py`, `.github/workflows/i18n-guard.yml` |
| El numeral nunca miente (glifos honestos) | **Con test** — invariante en `RecoveryRules` (`testNumeralEqualsVisibleSumAcrossStates`) |
| Glosario canónico, tuteo, marcos de microcopy, neutralidad de género | **Convención de revisión** (este documento) — no tooled todavía |

---

### Ver también
- [`DESIGN.md`](DESIGN.md) — sistema visual; §8.7 voz tipográfica.
- [`ACCESIBILIDAD.md`](ACCESIBILIDAD.md) — contraste, Dynamic Type, VoiceOver, reduce-motion.
- [`I18N.md`](I18N.md) — mecánica de traducción, locales, plurales.
- [`../SCREENS.md`](../SCREENS.md) — decisiones de copy por pantalla.
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — «el sistema de diseño es la ley».
