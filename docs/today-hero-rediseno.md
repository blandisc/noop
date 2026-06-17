# Today — Hero / Veredicto: mapa de estados para el rediseño

> Documento de trabajo. Captura el **estado actual** del área *hero* de la pantalla
> Today (la tarjeta grande de arriba) como punto de partida para retrabajarla en el
> nuevo rediseño ("Instrumento diurno" / dial de 24h). No es la documentación
> canónica — esa vive en [`docs/SCREENS.md`](SCREENS.md) y
> [`docs/screen-map.html`](screen-map.html); este doc es el insumo del rediseño.
>
> Fuente: `Cenit/Screens/TodayView.swift`. Última revisión: 2026-06-16 (post FER-106).
> **Decisión de diseño añadida 2026-06-16** (ver §6): el hero se rediseña como un
> **instrumento único de estado adaptable**, variante **V1** (numeral a la izquierda +
> dial de 24h compañero). El resto del doc (§1–§5) es el diagnóstico que la sustenta.

---

## 1. Qué es el "hero"

El **hero** es el elemento más grande y prominente de la parte de arriba de Today
— el que "da la cara" y comunica el mensaje principal del día. Es **un solo
espacio** en pantalla: según tu situación, se renderiza **uno de 6 estados**. En el
código cada variante se nombra con sufijo `Hero` (`emptyHero`,
`importedBaselineHero`) o `Card`/`Section` (`CalibrationProgressCard`,
`verdictSection`, `heroSection`).

## 2. La decisión raíz

Todo el árbol cuelga de una sola pregunta:

```
¿Hay número de Recuperación?  (repo.today?.recovery)
├─ NO (== nil)  → rama PRE-VEREDICTO  → estados 1–4
└─ SÍ (!= nil)  → verdictSection      → estado 5 (o 6 como fallback)
```

Dentro de la rama pre-veredicto, el orden de prioridad es:

```swift
if hasImportedBaseline {                                  // estado 2
    importedBaselineHero
} else if strapSeen && ownNights < minNightsSeed {        // estado 3
    CalibrationProgressCard
} else {                                                  // estados 1 y 4
    emptyHero
}
```

Señales que deciden (todas de **solo lectura**, sin tocar el motor):

| Señal | Significado | Definición |
|-------|-------------|------------|
| `recovery` | El puntaje de recuperación de hoy | `repo.today?.recovery` (nil = sin veredicto) |
| `strapSeen` | Se ha visto la banda alguna vez | `live.lastSyncedAt != nil \|\| liveBpm != nil` |
| `ownNights` | Noches PROPIAS con HRV válida (banda) | cuenta sobre `repo.days` no-Apple |
| `seededNights` | Noches con HRV válida en TODA la base (Apple + banda) | cuenta sobre `repo.days` |
| `hasImportedBaseline` | La base la sembró Apple Health, no la banda | `seededNights ≥ 4 && ownNights < 4` (FER-106) |
| `minNightsSeed` = **4** | Noches para "sembrar" la base | `Baselines.minNightsSeed` |
| `minNightsTrust` = **14** | Noches para una base "de confianza" | `Baselines.minNightsTrust` |

---

## 3. Los 6 estados

### Estado 1 — Vacío, sin banda
- **Componente:** `emptyHero` (rama `strapSeen == false`)
- **Trigger:** nunca se vio banda, sin base importada.
- **Muestra:** overline "Veredicto de hoy" · título **"Aún sin lectura"** · cuerpo
  *"Conecta tu banda WHOOP para ver tu disposición, recuperación y ritmo cardiaco
  de la mañana."* · botón primario **"Buscar banda"** (dispara `model.scan()`).
- **Rol en el journey:** primer arranque, sin nada todavía.

### Estado 2 — Base lista (Apple Health)  · NUEVO (FER-106)
- **Componente:** `importedBaselineHero`
- **Trigger:** `hasImportedBaseline` — ≥4 noches de HRV de Apple Health **y** <4
  noches propias de banda, sin lectura de hoy.
- **Muestra:** título **"Tu base ya está lista"** · chip **`Base · Apple Health`**
  (en `metricCyan`) · cuerpo *"Usa tu banda para sumar lo único que Apple Health no
  puede darte: la lectura de hoy."* · **pie adaptable**: si no se ha visto banda →
  botón "Buscar banda"; si ya → fila de latido en vivo (`LiveHeartbeatRow`).
- **Rol:** mata la contradicción "0 de 4" para el usuario recién importado. Es el
  hermano pre-veredicto de la barra "Se afina con tu banda · N de 14" (FER-105).

### Estado 3 — Calibrando 0→4 (sin import)
- **Componente:** `CalibrationProgressCard`
- **Trigger:** banda vista, `ownNights < 4`, **sin** base importada.
- **Muestra:** ícono `sparkles` · **3 copys según la noche**:
  - noche 0 → "Tu primera noche cuenta" / *"Ponte la banda esta noche — la primera
    de las 4 noches que tu propia base necesita."*
  - noches 1–3 → "Tus puntuaciones se están construyendo" / *"Tu propia base se
    afina cada noche — ya llevas N."*
  - noche 4 (computando) → "Casi listo" / *"Las 4 noches están listas — calculando
    tu primer veredicto."*
  - puntos-noche (●●○○) + "N de 4 noches" · **atajo Apple Health** (*"¿Tienes
    historial en Apple Health? Conéctalo y tu base se adelanta."* → abre Data
    Sources) · fila de latido en vivo.
- **Rol:** calibración clásica para quien no importó nada.

### Estado 4 — Base propia lista, sin lectura de hoy
- **Componente:** `emptyHero` (rama `strapSeen == true`)
- **Trigger:** ≥4 noches **propias** ya sembraron la base, pero hoy aún no llega la
  lectura (cae al `else`, no es calibración ni import).
- **Muestra:** título **"Aún sin lectura de hoy"** · cuerpo *"Tu base está lista.
  Usa la banda toda la noche y la recuperación, el esfuerzo y el sueño de esta
  mañana llegan al sincronizar."* · fila de latido en vivo.
- **Rol:** usuario establecido que simplemente no tiene el dato de hoy todavía.

### Estado 5 — Veredicto ("dos verdades")
- **Componente:** `verdictSection` (cuando `recovery != nil` y `level != insufficient`)
- **Trigger:** hay puntaje de recuperación y suficiente contexto para una palabra.
- **Muestra:** dos cajas lado a lado — **Veredicto** (palabra + culpable, en el
  color del nivel) y **Recuperación** (`92/100` + estado, en su propio color de
  banda). **4 niveles / colores**:

  | Nivel | Palabra (es) | Color (`StrandPalette`) |
  |-------|--------------|--------------------------|
  | `primed` | Listo | `statusPrimed` (menta) |
  | `balanced` | Equilibrado | `statusPositive` (verde) |
  | `strained` | Tensionado | `statusWarning` (ámbar) |
  | `rundown` | Agotado | `metricRose` (rosa) |

- **Modificadores que se apilan** (opcionales):
  - **frase puente** (`Readiness.bridge`) — reconcilia veredicto vs recuperación.
  - **aviso de noche corta** (si `confidenceLow`) — triángulo ámbar + nota.
  - **barra de calibración** "Se afina con tu banda · N de 14" — solo si
    `1 ≤ ownNights < 14`; añade *"Tu base viene de Apple Health"* si la base es
    importada; **desaparece a ≥14 noches**.
  - enlace "¿Por qué {veredicto}?" → `WhyVerdictSheet`.
  - fila de latido en vivo.
- **Rol:** el estado-objetivo, la razón de ser de la pantalla.

### Estado 6 — Fallback raro (anillo)
- **Componente:** `heroSection` ("Síntesis de hoy")
- **Trigger:** `recovery != nil` **pero** `level == insufficient` (hay puntaje, no
  hay contexto para una palabra de veredicto).
- **Muestra:** layout VIEJO de dos tarjetas — **`RecoveryRing`** (anillo 0–100 con
  el número al centro) + **`InsightCard`** (categoría "Recuperación" + palabra de
  síntesis + detalle), bajo el encabezado "Síntesis de hoy / De un vistazo".
- **Nota:** el **mismo** `heroSection` también pinta el anillo con overlay "Sin
  datos" o "Calibrando · N de 4 noches" cuando `recovery == nil`, pero ese camino
  pertenece al layout viejo de síntesis, no al flujo veredicto-primero actual.
- **Rol:** resto del diseño anterior. Inconsistente con los estados 1–5.

---

## 4. Modificadores transversales (sobre varios estados)

- **Línea de sincronización** (arriba, `syncMeta`): *"Sincronizado hace X · banda
  Y%"* / *"Sincronizando el historial de la banda…"* (cuando `live.backfilling`) /
  *"Última sync — nunca"*.
- **Fila de latido en vivo** (`LiveHeartbeatRow`): "Míralo latido a latido" + bpm en
  vivo (punto rosa) o "Sin lectura" → abre el monitor (`LiveView`). Aparece al pie
  de los estados 2, 3, 4 y 5 (los que ya vieron banda).
- **Debajo del hero** (NO cambian con el estado): fila de síntesis
  (Recuperación · HRV · Sueño) + **Métricas clave** (Esfuerzo, Sueño, HRV,
  Frecuencia cardiaca, FC en reposo, SpO₂, Pasos…).

---

## 5. Qué retrabajar (recomendaciones para el rediseño)

> POV: el hero no tiene problema de *contenido*, sino de **fragmentación** — 6
> layouts para responder, en el fondo, una sola pregunta: *"¿ya tengo tu lectura de
> hoy?"*. El rediseño debe **reducir, no agregar**.

1. **Colapsar los 4 estados pre-veredicto en UN solo "modo de espera" adaptable.**
   Los 4 son la misma idea con distinto vestido. Un componente que diga: *qué
   tienes* (base Apple Health / propia / ninguna) + *qué falta* (la noche de hoy) +
   *la única acción* (conectar banda / usarla esta noche / conectar Apple Health).
   FER-106 ya unificó la **narrativa**; falta unificar la **forma** (hoy unos son
   "tarjeta" y otros "hero").

2. **Eliminar el estado 6 (anillo / `heroSection`).** Es el único resto del layout
   viejo, rompe la consistencia visual y su disparador es contradictorio. Fundirlo
   al modelo de tarjeta-veredicto como un veredicto "tenue". **Un solo paradigma.**

3. **Anclar el hero al "dial diurno".** Si el rediseño gira en torno al dial de 24h
   con un dato al centro, el hero deja de ser "6 tarjetas" y pasa a ser **un objeto
   permanente (el dial) con un centro que se adapta**: con veredicto → número/palabra
   al centro; sin lectura de hoy → "falta la noche de hoy"; calibrando → "N de 4".
   Resuelve la fragmentación de raíz: estados-de-un-mismo-objeto, no estados-pantalla.

4. **Quitar la duplicación de la síntesis.** Recuperación · HRV · Sueño aparece en
   "—" arriba **y otra vez** en Métricas clave. Decidir UNA casa por dato.

5. **No agregar más estados.** Cada caso borde sumó una pantalla a la medida — así se
   llegó a 6. El rediseño debe ir al revés.

---

## 6. Decisión de diseño — el hero se rediseña como instrumento único (2026-06-16)

> Esta sección **cierra** el rediseño del hero. Sustituye la pregunta "¿qué tarjeta
> toca hoy?" por "¿qué valor lleva el numeral y de qué color?". Validada con el
> usuario por previews HTML fieles a `InstrumentoTheme.base`.

### 6.1 El principio

**Un solo instrumento permanente, no 6 tarjetas.** El hero deja de ser un layout por
estado y pasa a ser **un objeto fijo cuyo centro se adapta** (lleva al final la
recomendación §5.1 + §5.2 + §5.3):

- **El `DiurnalDial` (FER-134) siempre está.** Nunca desaparece ni cambia de forma;
  da contexto "ahora / tu noche / tu día" en todos los estados, así que la pantalla
  nunca se siente rota o vacía.
- **Un solo numeral dominante** (regla "un solo elemento dominante" del lenguaje
  Instrumento). Lo único que cambia entre estados es **qué valor lleva y de qué
  color es**.

### 6.2 El invariante que colapsa los 6 estados — *color = listo / tinta = en espera*

Se usa la regla "color solo en el dato" como **lenguaje de estado**, sin crear ningún
token nuevo:

> **Numeral con color de banda (verde/ámbar/rosa) = tu lectura de hoy está lista.**
> **Numeral en tinta (`ink`/`inkTertiary`) o em-dash `—` = sigues en espera / sin
> contexto.**

El usuario lee su situación por el **color del número**, antes que el copy. Esto mata
la fragmentación de raíz: los 6 estados son ahora el mismo esqueleto con distinto
relleno (ver §7).

### 6.3 La composición elegida — variante **V1** ("compañía equilibrada")

Se evaluaron 4 composiciones (bake-off con previews). **Gana V1.**

| Variante | Qué es | Veredicto |
|----------|--------|-----------|
| **V1 · numeral-izquierda + dial compañero (~110px)** | Número soberano a la izq, dial de 24h a la derecha, centrados en vertical | **ELEGIDA** — equilibra dominancia del dato y firma visual; escala limpio a estados vacíos; compacta (no empuja Métricas clave) |
| **B · dato-dentro-del-dial** | Número 0–100 al centro del aro | Descartada — **colisión semántica**: un número 0–100 dentro de un aro se lee como gauge de progreso, pero el aro es un reloj de 24h → engañoso. Además invierte la jerarquía (contexto > dato) |
| **V2 · editorial apilado** | Zona "veredicto" sobre zona "contexto", separadas por espacio | Descartada — la más pura conceptualmente, pero **demasiado alta**: empuja las Métricas clave hacia abajo en el *glance* matutino |
| **V3 · número soberano (dial medallón ~66px)** | Número enorme, dial reducido a glyph esquinero | Descartada — el dial se vuelve **adorno** (pierde función y firma); la pantalla se ve genérica (número + glyph) |

**Geometría:** dial **~110px** (`DiurnalDial`), numeral hero a la izquierda
(`InstrumentoType.hero`, color de banda o tinta según §6.2), palabra de veredicto con
su color de readiness + **«i»** pegada (abre el porqué; ver §6.5), y al pie la fila de
latido / CTA / atajo. Tema por hora (FER-132) aplica por encima sin cambiar la
estructura.

### 6.5 Acceso al porqué del veredicto — «i» pegada (decisión 2026-06-16)

El acceso a `WhyVerdictSheet` se mueve del **renglón aparte** "¿Por qué {veredicto}?"
(lo que shipeó FER-113) a una **«i» pegada a la palabra de veredicto**, y **toda la
palabra de veredicto es tocable** (no solo el blanco de ~17px de la «i»).

Razón: el temor de FER-113 ("los copys largos rompen el layout") era por el **texto
del enlace**, no por la palabra de veredicto — que es corta y acotada (máx.
"Equilibrado"). Al colgar la «i» de la palabra, ese riesgo desaparece y se ahorra un
renglón (el hero respira, las Métricas suben). El sheet en sí (`WhyVerdictSheet`,
señales + leyenda de niveles) **no cambia**; solo cambia su disparador. Validado con
preview en el estado más exigente ("Tensionado" + frase puente).

### 6.4 Lo que muere

- **El estado 6 (anillo / `heroSection`) desaparece como layout.** Pasa a ser "el
  mismo héroe con el numeral en tinta y sin palabra de veredicto" (§7, estado 4).
- **Los 4 estados pre-veredicto colapsan** a "numeral en tinta/`—` + una línea de
  qué falta + una acción".

---

## 7. El árbol de estados consolidado (un solo esqueleto)

Mismo layout V1 en todos; **solo cambian numeral, color y pie**. Validado con preview
en los 7 casos:

| # | Situación | Numeral | Color | Pie / modificador |
|---|-----------|---------|-------|-------------------|
| 1 | Veredicto `primed`/`balanced` | `82` | verde `dataRecovery` `#0C8F62` | frase puente · latido |
| 2 | Veredicto `strained` | `54` | ámbar `warning` `#9C5E10` | + aviso noche corta (si `confidenceLow`) · latido |
| 3 | Veredicto `rundown` | `38` | rojo `critical` `#BC3A34` | + barra "se afina · N de 14" (si aplica) · latido |
| 4 | `recovery != nil` pero `insufficient` (ex-estado 6) | `71` | **tinta** `ink` | "aún sin contexto suficiente" · latido. **«i» es clave aquí** |
| 5 | Calibrando 0→4 (sin import) | `2/4` | **tinta** | puntos-noche · atajo Apple Health · latido |
| 6 | Base lista (Apple Health), falta hoy | `—` | **tinta** `inkTertiary` | chip `Base · Apple Health` · "Falta la lectura de hoy" · pie adaptable |
| 7 | Sin banda, primer arranque | `—` | **tinta** | "Aún sin lectura" · botón **Buscar banda** |

**Dos cosas a vigilar en implementación (no bloquean la decisión):**

1. **Estados 1 vs 4** se distinguen *solo* por el color del numeral. El color por sí
   solo es frágil para daltónicos → el **copy de apoyo y la «i»** deben cargar su
   parte. No depender únicamente del verde-vs-tinta.
2. **El em-dash `—`** (estados 6, 7) es discreto; el peso recae en la línea "Falta la
   lectura / Aún sin lectura". Confirmar en device que no se sienta *demasiado* vacío
   junto al dial activo. Variante dentro del mismo lenguaje si se siente flojo:
   mostrar la **hora** en tinta en el numeral.

---

## 8. Casos de base importada (Apple Health) — el cruce más delicado

Usuario con **base sembrada por Apple Health (≥4, p. ej. 14 noches)** y **pocas
noches propias de banda**. El resultado depende de **si anoche usó la banda**, porque
el veredicto del día se calcula con la noche de la **banda** (Apple Health solo
siembra la *base* y alimenta gráficas de respaldo — ver FER-149 y
[[repo-days-feeds-baseline]]).

| | Anoche **sí** usó banda | Anoche **no** usó banda |
|---|---|---|
| `recovery` hoy | existe → **veredicto real** (estado 7.1) | `nil` → pre-veredicto |
| Numeral | `76` en **color** (dato listo) | `—` en **tinta** |
| Modificador | barra "se afina · 1 de 14" + nota *"Tu base viene de Apple Health"* | — |
| Dial | **con** banda de sueño (anoche registró) | **sin** banda de sueño |
| Pie | latido en vivo | "Sin lectura" (banda ya vista → no "Buscar banda") |
| Estado en el árbol | §7-1/2/3 con modificador | §7-6 (`importedBaselineHero`) |

**Por qué importa:** el caso "sí usó banda" da veredicto real **desde el día 1**
(la base la sembró Apple) — esto mata la vieja contradicción "0 de 4" (FER-106). La
barra "1 de 14" es un **modificador** que se cuelga del héroe de veredicto y
**desaparece sola** a las 14 noches propias, sin salto de layout.

**A confirmar en código al implementar:** que NOOP **no** calcula veredicto con solo
Apple Health (que el score sale de la banda). Es lo que indican los cambios de
FER-149, pero verificar en `Repository`/`IntelligenceEngine` antes de cerrar el copy:
si algún día se diera veredicto desde Apple Health, el estado §7-6 cambiaría a
"veredicto en tinta" en vez de em-dash.

---

## 9. Referencias

- **Código:** [`Cenit/Screens/TodayView.swift`](../Cenit/Screens/TodayView.swift)
  (`emptyHero`, `importedBaselineHero`, `CalibrationProgressCard`, `verdictSection`,
  `heroSection`, `readinessColor`).
- **Componentes del rediseño (ya en `iOS`):**
  [`DiurnalDial`](../Packages/StrandDesign/Sources/StrandDesign/DiurnalDial.swift)
  (dial 24h, FER-134), [`Instrumento`](../Packages/StrandDesign/Sources/StrandDesign/Instrumento.swift)
  (`InstrumentoTheme` + tipo, FER-131/147),
  [`InstrumentoThemeEngine`](../Packages/StrandDesign/Sources/StrandDesign/InstrumentoThemeEngine.swift)
  (tema por hora, FER-132), `Sparkline`/`ReferenceRange` (banda 14d, FER-155).
- **Motor (solo lectura):** `Packages/StrandAnalytics` — `ReadinessEngine.Level`,
  `RecoveryScorer.calibrationNights`, `Baselines.minNightsSeed/minNightsTrust`,
  `SolarClock`, `SleepWindowClock` (FER-133/154).
- **Tickets relacionados:** FER-105 (línea de confianza del veredicto), FER-106
  (narrativa por fuente de datos — este doc nace de ahí), FER-60 (calibrar con Apple
  Health), FER-61 (card de 4 puntos), y el rediseño "Instrumento diurno"
  (FER-131…136); el **ensamblaje de TodayView fue FER-135** (Done) y la
  **consolidación del hero en este doc es FER-160**.
- **Mapa canónico:** [`docs/SCREENS.md`](SCREENS.md) · [`docs/screen-map.html`](screen-map.html).
