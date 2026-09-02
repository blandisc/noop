# Auditoría C — El sistema por dentro (CenitDesign)

> **Solo reporte.** Cero cambios a Swift/CI/linter/docs existentes.  
> **Issue:** FER-279 · **rama:** `grok/fer-279c-sistema-1788281605-68973-8231`  
> **Fecha del censo:** 2026-09-01 · **worktree** de esta corrida.  
> **Alcance:** `CenitDesign` como sistema (tokens, recetas, API pública), no pantallas.

## Método (greps corridos)

Árbol **APP** = `Cenit/` + `CenitApp/` + `CenitWidgets/` + `CenitWatch/`.  
Árbol **PKG** = `Packages/CenitDesign/Sources/CenitDesign/`.

Conteos con `rg --glob '*.swift'` (hits / archivos distintos). Formato reportado: `N hits / F files`.

Familias censadas: `LiquidColor.`, `StrandPalette.`, `InstrumentoTheme`, `theme.(paper|ink|…)`, `CenitColor.`, `LiquidSpace.`, `CenitMetrics.`, `LiquidRadius.`, `LiquidChip.`, `LiquidControl.`, `LiquidElevation.`, `liquidShadow(`, `StrandElevation.`, `strandElevation(`, `LiquidType.`, `StrandFont.`, `InstrumentoType.`, `LiquidMotion.`, `StrandMotion.`, `LiquidHaptica`, `EntrenarHaptic`, `ChartHaptics`, `CenitOpacity.`, `WidgetMetrics.`, `HomeWidgetMetrics.`, `WatchMetrics.`, más ~110 componentes/APIs (`liquidGlass(`, `LiquidMenu`, `StatTile`, …) y miembros sueltos de `LiquidSpace` / `CenitMetrics` / `StrandMotion` / `LiquidMotion` / `LiquidElevation`.

**Tamaño del paquete:** 207 archivos `.swift` · ~48.8k LOC · ~338 tipos `public` (enum/struct/class/…) en 196 archivos.

**Decisiones ya cerradas (no se re-litigan):** FER-229 «Un solo vidrio · Liquid Glass · El Eje» (`docs/DECISIONS.md:103–113`); lienzo blanco + `InstrumentoTheme.paper` vivo solo para tarjetas/hojas (`:114–118`); `CenitMetrics.cardGap` + `LiquidElevation.tarjeta` como par único de tarjeta (`:119–121`); `LiquidSpace` nombrada por valor se queda (`CONTRATO.md:14–18`); componentes de papel se borran al migrar su último consumidor (`DECISIONS.md:110–111`); Watch OLED carve-out (`CONTRATO.md:82–83`).

---

## 1 · El mapa de las dos eras

Leyenda de **ruta**: **fusionar** (alias → un nombre) · **renombrar** · **dejar morir** (0 consumidores → borrar) · **`/migracion`** (pantalla/call-site, no el token) · **decidido** (dueño ya pinó).

| Familia | Liquid (canónico) | Instrumento / neutral compartido | APP Liquid | APP otro | Ruta de consolidación |
|---|---|---|---|---|---|
| **Color** | `LiquidColor` (`LiquidColor.swift:15`) | `InstrumentoTheme` roles (`Instrumento.swift:28`) + `theme.*` vía env; `StrandPalette` residual (`Palette.swift:36`); `CenitColor.pantalla` (`PantallaFondo.swift:12`) | `LiquidColor` **843/56** | `theme.*` **1005/55**; `InstrumentoTheme` **127/49**; `StrandPalette` **3/3**; `CenitColor` **4/4** | **Liquid gana** para pantallas nuevas. `InstrumentoTheme` vive hasta `/migracion` del último consumidor (decidido). `StrandPalette` → dejar morir (3 call-sites). Escalas recovery/strain/HR de `StrandPalette` aún alimentan charts Instrumento en PKG (**51/14**) — fusionar lectura hacia `LiquidColor` / tonos de dato cuando migre el chart. |
| **Espacio** | `LiquidSpace` (`LiquidLayout.swift:8`) + roles FER-273/275 | `CenitMetrics` (`Components.swift:10`) — escala «Instrumento» + medidas compartidas (`cardGap`, `tileHeight`, …) | `LiquidSpace` **660/66** | `CenitMetrics` **577/51** | **Dos dialectos vivos con valores iguales.** Fusionar por alias valor-neutral (Fase 1 CONTRATO) los pares exactos; roles solo-Liquid (`topeScroll`, `handoff14`, …) se quedan; `cardGap` **decidido** en `CenitMetrics` — no mover sin dueño. |
| **Radio** | `LiquidRadius` (`LiquidLayout.swift:175`) + `LiquidChip` / `LiquidControl` | `CenitMetrics.controlRadius/chipRadius/tileRadius/ctaRadius/insetRadius/cardRadius` | `LiquidRadius` **25/18**; `LiquidChip` **4/2**; `LiquidControl` **4/2** | radios vía `CenitMetrics.*Radius` (suma ~**58** hits APP) | Fusionar iguales (`control`↔`controlRadius`=12, `chip`↔`chipRadius`=8). `cardRadius`16 ≠ `tarjeta`18 y `tileRadius`17 — **no** envolver; van a `/migracion` o decisión de dueño (pixel). `LiquidRadius.pastilla`=999: **0** usos directos APP (se usa `Capsule` / receta `.pastilla`) — documentar, no borrar. |
| **Tipo** | `LiquidType` (`LiquidType.swift:14`) | `StrandFont` SF (`Typography.swift:19`); `InstrumentoType` + grotesk (`Instrumento.swift:415`) | `LiquidType` **348/33** | `StrandFont` **511/46**; `InstrumentoType` **130/31** | Tres voces. Liquid gana display/valores; SF cuerpo puede vivir como subconjunto de `LiquidType` o `StrandFont` marcado «solo body». `InstrumentoType.grotesk*` es el motor real de Space Grotesk — **fusionar** la puerta pública hacia `LiquidType` (ya lo envuelve) y dejar de enseñar `InstrumentoType` en docs. |
| **Sombra** | `LiquidElevation` + `liquidShadow` (`LiquidLayout.swift:231`, `:290`) | `StrandElevation` + `strandElevation` (`Elevation.swift:6`, `:44`) | `LiquidElevation` **3/1**; `liquidShadow(` **4/3** | `StrandElevation` / `strandElevation(` **0/0** APP | **Liquid gana.** `StrandElevation` es cadáver (solo PKG definición + 3–4 previews). Dejar morir. `LiquidElevation.tarjeta` **decidido** (`DECISIONS.md:120`). |
| **Motion** | `LiquidMotion` (`LiquidMotion.swift:21`) + recetas press/entrada/sheet | `StrandMotion` (`Motion.swift:18`) + keyframes `rec*` en el mismo archivo | `LiquidMotion` **82/36** | `StrandMotion` **59/25** | **Liquid gana** para features nuevas (gate `no-motion-literal` ya empuja tokens). Fusionar springs/duraciones solapadas vía typealias; `StrandMotion.interactive/gentle/fade` aún calientes en APP — migrar call-sites luego borrar. Ambientales (`drift`/`flow`) solo PKG: OK. |
| **Hápticos** | `LiquidHaptica` (`LiquidHaptica.swift:20`) | `EntrenarHaptic` (sesión); `ChartHaptics` (scrub) | `LiquidHaptica` **8/4** | `EntrenarHaptic` **11/5**; `ChartHaptics` **1/1** APP (+ **12/9** PKG) | **Tres catálogos con rol distinto — decidido en comentarios del propio código** (`LiquidHaptica.swift:14–16`). No fusionar; sí documentar el mapa en CATALOGO. |
| **Opacidad** | (vidrio en `LiquidColor.vidrio*`) | `CenitOpacity` (`Palette.swift:200`) — compartido | — | `CenitOpacity` **15/9** APP / **19/9** PKG | Neutral compartido útil. Se queda. Corregir docs que hablan de `opacity.disabled` → el token real es `CenitOpacity.dim` (`:208`). |
| **Z-index** | — | *(capa z-index huérfana — archivo ya ausente del árbol)* | **0/0** | **0/0** | **Ya muerto** — no reintroducir. |
| **Widgets / Watch** | — | `WidgetMetrics`, `HomeWidgetMetrics`, `WatchMetrics` (`Components.swift:66+`) | `WidgetMetrics` vía typealias en Live Activity; `HomeWidgetMetrics` vía `typealias M` en home widgets; `WatchMetrics` **13/2** | carve-out CONTRATO | **Decidido:** fuera de varios gates. No mezclar con `LiquidSpace`. |
| **Superficie** | `liquidGlass(_:)` / `liquidGlass(tono:regimen:)` (`LiquidGlassRecipes.swift:18`, `:132`) | `.instrumentoCard` (`InstrumentoCard.swift:68`); Paper* residual | `liquidGlass(` **33/17** APP (+ **61/40** PKG) | `instrumentoCard(` **0** APP (solo PKG); `LiquidMenu` reemplaza a `PaperMenu` (FER-283) | Vidrio Liquid gana. `InstrumentoTheme` en `/migracion`. `instrumentoCard` ya sin consumidor APP → candidato a borrar tras quitar previews. |

### Pares numéricos exactos (espacio/radio) — candidatos a alias

| Valor | Liquid | CenitMetrics / otro | ¿Igualdad exacta? |
|---|---|---|---|
| 4 | `LiquidSpace.s100` (`LiquidLayout.swift:18`) | `CenitMetrics.space1` (`Components.swift:32`) | sí |
| 8 | `s200` (`:24`) | `space2` (`:33`) | sí |
| 12 | `s300` (`:31`) | `gap` (`:13`) | sí |
| 16 | `s400` (`:33`) | `cardPadding` (`:12`) / `sectionGapCompact` (`:34`) | sí (padding); sectionGapCompact es otro rol |
| 24 | `s600` (`:38`) | `screenPadding` (`:16`) | sí |
| 12 | `LiquidRadius.control` (`:185`) | `CenitMetrics.controlRadius` (`:35`) | sí |
| 8 | `LiquidRadius.chip` (`:183`) | `CenitMetrics.chipRadius` (`:36`) | sí |
| 44 | `LiquidControl.hitTarget` / `md` (`:204–208`) | `CenitMetrics.touchTarget` (`:40`) | sí |
| 10 | `seccionCanto` / `filaRespiro` (`:97–103`) | `rowVPad` (`:41`) | sí en cifra; **roles distintos a propósito** (CONTRATO / comentario FER-273) — **decidido, no se toca** |
| 16 | — | `cardRadius` (`:11`) | ≠ `LiquidRadius.tarjeta` 18 |
| 17 | — | `tileRadius` (`:37`) | ≠ 18 |

### Motion lado a lado (quién gana)

| Necesidad | Liquid | Strand | Veredicto |
|---|---|---|---|
| Interacción corta | `instant` 120 ms / `press` (`LiquidMotion.swift:26`, `:107`) | `interactive` spring 0.28 (`Motion.swift:23`) | Liquid para press; Strand spring aún en APP (**16** hits) → migrar |
| Cambio de valor | `gentle` 420 ms (`:30`) | `gentle` spring 0.5 (`:27`) | Nombres iguales, curvas distintas — **trampa de API**. Renombrar o documentar; Liquid gana en pantallas Liquid |
| Fade | `fadeTransition` (`:135`) | `fade` (`:57`) | Ambos vivos (Liquid **10** APP transitions; Strand fade **20** APP) |
| Ambient loop | `drift*` / `flow*` (PKG) | `breathe` / `bob` / `livePulse` | Liquid para Hoy; Strand residual sesión/loading |

---

## 2 · Duplicidades y solapes

### 2.1 `StrandElevation` vs `LiquidElevation`

| | Strand | Liquid |
|---|---|---|
| API | `Elevation.swift:6–47` · `.strandElevation(_:ink:)` | `LiquidLayout.swift:231–323` · `.liquidShadow(_:)` |
| APP | **0** | **3** + **4** `liquidShadow` |
| PKG | definición + preview | recetas de vidrio + módulos |

**Gana Liquid.** Costo de matar Strand: borrar un archivo + quitar del «entry points» de DESIGN (`DESIGN.md:26`) + baseline si aplica. Riesgo de pixel: nulo en APP.

### 2.2 `StrandMotion` vs `LiquidMotion`

Dos contratos completos. El comentario en `Motion.swift:8–16` aún habla de «two languages, one catalog» — eso **choca** con FER-229 (un solo dialecto).  
**Gana LiquidMotion** para código nuevo. Costo de matar StrandMotion: ~**59** call-sites APP + **30** PKG + keyframes `rec*` del detalle de tendencias (mismo archivo, otro rol). Plan: (1) aliases Strand→Liquid donde la curva sea sustituible sin pixel-shift, (2) `/migracion` de springs restantes, (3) borrar enum.

### 2.3 `CenitMetrics` vs `LiquidSpace` / `LiquidRadius`

El dolor #1 del sistema. Misma cifra, dos nombres; agentes y humanos eligen al azar → clase FER-119.  
**Gana LiquidSpace/Radius** como DNA (`CONTRATO.md:15–16`). `CenitMetrics` conserva lo que no tiene gemelo Liquid (`cardGap` **decidido**, `tileHeight`, `chartHeight`, `liveSheetHeight`, `receiptPadding`, `screenTop`, …) hasta reubicarlos con rol propio.

### 2.4 `StrandFont` vs `LiquidType` vs `InstrumentoType`

- `StrandFont`: APP **511/46** — sigue siendo la tipografía por defecto de pantallas no migradas y mucho chrome SF.  
- `LiquidType`: APP **348/33** — voz Liquid.  
- `InstrumentoType`: APP **130/31** — grotesk + helpers; `LiquidType` ya depende de grotesk empaquetado.

Solape: Space Grotesk expuesto por dos puertas. **Gana `LiquidType` como puerta**; `InstrumentoType.grotesk*` puede quedar `internal`/`package` después de reexportar.

### 2.5 `StrandPalette` vs `LiquidColor` vs `InstrumentoTheme`

- `LiquidColor` es el diccionario vivo (CATALOGO).  
- `InstrumentoTheme` sigue siendo el **mayor consumidor de color en APP** (`theme.*` **1005** hits) — no es duplicado gratuito: es el tema inyectable por hora (FER-132). **Decidido:** vive hasta migrar pantallas.  
- `StrandPalette`: **3** APP (`RootTabView` tint, 2× `disabledOpacity`) — matable ya.

### 2.6 `StatTile` vs `LiquidMetricTile` vs átomos

Ambos solo en **previews PKG** (`StatTile.swift:99+`, `LiquidMetricTile.swift:101+`). APP **0** construcciones. Apple Health **evita** `LiquidMetricTile` porque exige `delta` (`AppleHealthView.swift:436–437`) y compone átomos a mano — señal de API incompleta (ver §4).

### 2.7 `Hypnogram` vs `LiquidHipnograma` · `Calendario90` vs `LiquidCalendario90`

| Legacy | APP | Liquid | APP |
|---|---|---|---|
| `Hypnogram` | 0 | `LiquidHipnograma` | **8/1** |
| `YearHeatStrip` / `Calendario90` | 0 | `LiquidCalendario90` | **31/5** |

Legacy solo PKG (rollback / tests). Candidatos a borrar cuando el dueño acepte perder el rollback (DESIGN §8 aún los lista como conservados — alinear doc).

### 2.8 `Metodo` / `PieMetodo` vs `LiquidMetodo`

`LiquidMetodo` APP **15/12**. `PieMetodo` ya **no existe** como símbolo (solo mención en comentario `TendenciasDetalle.swift:6`). `Metodo` genérico sigue en `TendenciasDetalle.swift:72` y como nested types en hojas Liquid. Limpiar naming en un lote de docs+API.

### 2.9 `EntrenarTono` vs `LiquidTono`

**Ya fusionado:** `LiquidTono` vive en `EntrenarVidrio.swift:20`. El inventario `INVENTARIO-UN-SOLO-VIDRIO.md:36` está desactualizado.

---

## 3 · Huérfanos

Criterio: **0 consumidores en APP**. Se subdividen.

### 3.1 Muertos totales (APP 0 · PKG solo definición/preview → borrar seguro)

| Símbolo | Evidencia |
|---|---|
| Capa z-index huérfana | Archivo ya ausente del árbol (0 usos) |
| `StrandElevation` (casi) | APP 0; PKG definición + previews (`Elevation.swift`) |
| `HeroInvertido` | 0 en todo el árbol (ya borrado; docs aún lo nombran `DESIGN.md:283`) |
| `StrandFontScaled` | 0 archivos |
| `CenitMetrics.liveSheetHeight` | 0 APP / 0 usos reales fuera de la definición (`Components.swift:26`) |
| `CenitMetrics.sourceGlyph` | 0/0 |
| `CenitMetrics.chartHeight` | 0 APP (PKG 0 usos de producto) |
| `LiquidSpace.chipHorizontal` / `seccionCanto` / `filaRespiro` | 0 APP / 0 PKG — **minteados FER-273 y aún sin aplicar** (`LiquidLayout.swift:78–103`). No son basura: esperan `/migracion`. Marcar «pieza lista, call-sites pendientes». |

### 3.2 Solo previews / rollback PKG (APP 0 · PKG 1–4 archivos)

Candidatos a **lote de poda** tras confirmación de que no hay wrapper APP oculto:

`EmptyStateView`, `LoadingStateView`, `ErrorStateView`, `InkButton`, `OutlineButton`, `InstrumentoScreenTitle`, `StatePill`, `ConnectionDot`, `BreathingDot`, `RecoveryZoneGauge`, `Hypnogram`, `YearHeatStrip`, `Calendario90`, `PoincareCloud`, `ECGWave`, `NumeroVivo`, `InfoAccordion`, `InputCard`, `DetailBlock`, `StepChart`, `StreakArc`, `ExperimentEffectChart`, `HeatLegend`, `OnFieldOpacity`, `SenalEnBanda`, `SelloConfianzaArco`, `TrendSparkline`, `SheetPaper`, `TileSurface`, `SeccionBloque`, `StatTile`, `instrumentoCard`, `HeatCalendarSection`, `AuthoredGlyph`, `BehaviorDumbbell`, `InsightGlyph`, `GroteskVoice`, `ReferenceRange` (helper puro aún referenciado por Sparkline PKG).

### 3.3 APP 0 pero pieza viva del pipeline Liquid (NO borrar)

Usadas por pantallas vía builders/compositores en PKG o como receta interna:

`LiquidHoyScreen` (referencia; APP usa `LiquidHoyContent` **2/1**), `LiquidCargaBar`, `LiquidSectionHeader`, `LiquidPlasta`, `LiquidAuroraEdge`, `liquidLift`, `liquidKicker` / `liquidMicro`, `LiquidElevation.e0/e3/dial/modulo/tarjeta` (embebidos en recetas), muchos miembros `LiquidMotion.*` solo consumidos dentro de modificadores (`.liquidEntrada`, `.liquidPress` sí tienen APP: **39** / **31**).

### 3.4 `StrandMotion` miembros APP 0 (dentro de un enum aún vivo)

`durationStandard`, `durationSlow`, `breathPeriod`, `drawIn`, `pulse`, `spin`, `bob`, `livePulse` — APP 0. `breathe` 1, `countUp` 1, `hero` 1. Poda interna posible sin tocar el enum entero.

### 3.5 Tokens FER-273/275 con APP>0 (no huérfanos — éxito del wrapping)

`topeScroll` 6, `ctaVertical` 6, `bloqueAjuste` 6, `handoff14` 3, `estadoVacioAire` 2, etc. (`LiquidLayout.swift:117–158`). CATALOGO ya lista parte FER-273; faltan roles FER-275 en la tabla generada si el generador no los emite — ver §5.

---

## 4 · Calidad de API

Dónde el sistema hace difícil lo correcto.

### 4.1 `LiquidMetricTile` exige `delta`

`LiquidMetricTile.swift:22–23` — `delta: String` obligatorio.  
`AppleHealthView.swift:436–466` documenta el workaround: componer átomos (`LiquidOverline`, gota, sparkline) porque la pantalla no tiene delta.  
**Propuesta:** overload / `delta: String? = nil` que oculte `LiquidDeltaCaption`, o variante `LiquidMetricTile.simple`. Criterio: Apple Health deja de tener `liquidStatTile` privado.

### 4.2 Dos puertas de vidrio sin guía en el call-site

`liquidGlass(_ recipe:)` vs `liquidGlass(tono:regimen:)` (`LiquidGlassRecipes.swift`). Correcto por diseño (FER-229), pero sin `#warning`/doc en el autocomplete del primer overload los agentes eligen receta de forma y olvidan el régimen.  
**Propuesta:** en CATALOGO + comment del overload de forma: «pantalla nueva con identidad → overload `tono:`; chrome neutro → receta».

### 4.3 Escala `LiquidSpace` con muchos sinónimos numéricos

`10` ×3 roles (`s250`, `seccionCanto`, `filaRespiro`), `14` ×3 (`handoff14`, `estadoVacioAire`, `bloqueAjuste`), `20` ×4 (`topeScroll`, `seccionAire`, `tarjetaAmplia`, `pastillaHorizontal`).  
**Decidido** por CONTRATO/FER-275 (rol ≠ valor). Dolor cognitivo real.  
**Propuesta:** tabla «cifra → roles» en CATALOGO (generada); linter no sugiere el gemelo equivocado.

### 4.4 Defaults que invitan al literal / al dialecto viejo

- `DESIGN.md:26` lista entry points **Strand\*** / `CenitMetrics` / `StrandElevation` — el agente lee eso primero y escribe Instrumento.  
- `DESIGN.md:152`: «The **one** spacing scale» = `CenitMetrics` — **falso** hoy.  
- `Motion.swift` y `StrandMotion.gentle` vs `LiquidMotion.gentle` — mismo nombre, distinta curva.

### 4.5 Recetas que piden componer a mano

- Hápticos: tres catálogos OK, pero sin índice único.  
- Charts: scrub compartido (`ChartScrubMath` / `ChartHaptics`) bien factorizado; la piel Liquid vs Instrumento aún duplica contenedores (`TrendChart` APP **5/2** vs `LiquidTrendChart` **1/1**).  
- Estados de pantalla Instrumento (`EmptyStateView` et al.) huérfanos mientras cada pantalla Liquid inventa su vacío — falta **un** empty Liquid en el catálogo.

### 4.6 `PaperMenu` → `LiquidMenu` (resuelto en FER-283)

Al censo, `no-legacy-api` incluía `PaperMenu` y APP tenía **26/10**. FER-281 entregó `LiquidMenu` (API espejo); FER-283 migró los call-sites de la app y retiró `PaperMenu` del paquete y del gate.

---

## 5 · Docs vs realidad

### 5.1 Lo que DESIGN / LIQUID-GLASS enseñan y ya no es cierto

| Afirmación | Dónde | Realidad |
|---|---|---|
| Entry points = `StrandPalette`, `StrandFont`, `StrandMotion`, `CenitMetrics`, `StrandElevation` | `DESIGN.md:26` | Canónicos reales: `LiquidColor`, `LiquidType`, `LiquidSpace`/`LiquidRadius`, `LiquidElevation`, `LiquidMotion`, `liquidGlass`. Varios Strand\* están muertos o residuales. |
| «Dark-only. … There is no light theme.» | `DESIGN.md:260` | Lienzo blanco + Liquid; dark retirado salvo Watch OLED (`DECISIONS.md:111–112`). |
| «The **one** spacing scale» = `CenitMetrics` | `DESIGN.md:152–155` | Convivencia 660 vs 577 hits. |
| Entrenar / Ajustes / Bucle / Dieta «siguen siendo canónicos» Instrumento; Entrenar consumidor vivo de papel | `DESIGN.md:281–286` | Entrenar es **mosaico Liquid** (`liquidGlass(tono:regimen:)`, `EntrenarModulo` APP **28/14`). Ajustes usa `LiquidColor` intensivo (p.ej. `AjustesView` en el censo de color). |
| Lista `HeroInvertido`, `TileSurface`, `SeccionBloque`, `PieMetodo` como componentes vivos | `DESIGN.md:283–284` | `HeroInvertido`/`PieMetodo` ya no existen; otros APP 0. |
| `dockBottom=14`, `ecosistemaAlto=324` | `LIQUID-GLASS.md:80–81` | Código: `dockBottom = -22` (`LiquidLayout.swift:74`), `ecosistemaAlto = 320` (`:50`). |
| «Cinco radios, ninguno más» | `LIQUID-GLASS.md:83–84` | Código añade `hairline` y `chip` (`LiquidLayout.swift:176–183`). |
| `flowPeriod` 9 s en prosa | `LIQUID-GLASS.md:157` / comentario cabecera Motion | `LiquidMotion.flowPeriod = 6` (`LiquidMotion.swift:49`) — drift doc/código. |
| `INVENTARIO-UN-SOLO-VIDRIO` aún propone fusionar `EntrenarTono` → `LiquidTono` | `INVENTARIO-…md:36` | Ya es `LiquidTono` en `EntrenarVidrio.swift:20`. |

### 5.2 Lo que el sistema real no enseña (causa clase FER-119)

1. **Mapa «¿qué token uso?»** Liquid vs CenitMetrics para la misma cifra.  
2. **Régimen mosaico/sobrio** como decisión de pantalla, no solo de Hoy/Entrenar.  
3. **`CenitOpacity`** como escala sancionada (DESIGN habla de `opacity.disabled` genérico).  
4. **Hápticos:** `LiquidHaptica` / `EntrenarHaptic` / `ChartHaptics`.  
5. **Roles FER-275** (`topeScroll`, `ctaVertical`, …) — en código con comentarios ricos; CATALOGO generado puede atrasarse si no re-corre `CenitDesignTokens`.  
6. **Huérfanos públicos** siguen en el índice mental (CATALOGO aún presenta `StatTile`, `Hypnogram`, … como opciones).  
7. Que `InstrumentoTheme` siga siendo el carrier de color de media app **no** implica que el DNA sea Instrumento — el doc de apertura lo dice; el §8 y los entry points lo contradicen.

### 5.3 CONTRATO vs instinto

Instinto: colapsar `seccionCanto`/`filaRespiro`/`rowVPad` en un solo `10`.  
**Decidido, no se toca** (`LiquidLayout.swift:91–103`, `CONTRATO.md` regla de roles + FER-273).  
Instinto: mover `cardGap` a `LiquidSpace`.  
**Decidido** en `CenitMetrics` (`DECISIONS.md:120`, `Components.swift:14`).

---

## 6 · Top-5 mejoras (dolor × costo)

Cada una es un issue proponible. **Sin implementar aquí.**

### 1 — Verdad de docs + entry points Liquid (dolor alto × costo bajo)

**Problema:** DESIGN enseña el dialecto muerto; es la mecha de FER-119.  
**Issue:** «DESIGN/LIQUID-GLASS: entry points Liquid; matar Dark-only; alinear §8 Entrenar; corregir dockBottom/ecosistemaAlto/radios/flowPeriod».  
**Criterios verificables:**

1. `DESIGN.md` lista entry points `LiquidColor|LiquidType|LiquidSpace|LiquidRadius|LiquidElevation|LiquidMotion|liquidGlass` y relega Strand\*/CenitMetrics a «legado en migración».  
2. No queda la frase «Dark-only» / «no light theme».  
3. §8 no afirma que Entrenar sea canónico Instrumento.  
4. `LIQUID-GLASS.md` cifras = `LiquidLayout.swift` / `LiquidMotion.swift` (tabla de 4 valores citados arriba).  
5. Diff solo `docs/**` (y regeneración CATALOGO si aplica).

### 2 — Puente valor-neutral `CenitMetrics` → `LiquidSpace`/`LiquidRadius` (dolor alto × costo medio)

**Problema:** 577+660 call-sites en dos nombres.  
**Issue:** «Aliases / typealiases de igualdad exacta + lote wrapping; sin cambio de pixel».  
**Criterios:**

1. Pares de §1 con igualdad exacta tienen un solo nombre canónico Liquid; el viejo es `typealias` o wrapper documentado `=`.  
2. Checklist Fase 1 de `CONTRATO.md:87–96` (diff mecánico + `DesignDriftTokenTests`).  
3. `cardGap` y radios no exactos **no** se tocan.  
4. Grep APP: nuevos call-sites de `CenitMetrics.space1|space2|gap` en pantallas Liquid = 0 (gate o censo).

### 3 — Un dialecto de motion (`LiquidMotion` gana) (dolor alto × costo medio)

**Problema:** `gentle` significa dos cosas; StrandMotion **59** APP.  
**Issue:** «Deprecar StrandMotion; migrar interactive/gentle/fade; poda miembros APP0».  
**Criterios:**

1. Pantallas nuevas / diff de feature no introducen `StrandMotion.` (extender `no-legacy-api` o regla hermana — **alta legal de baseline** si sube conteo).  
2. Miembros APP0 de StrandMotion borrados o `internal`.  
3. Comentario `Motion.swift:8` deja de decir «two languages».  
4. Tests de motion existentes verdes; Reduce Motion sin regresión en Hoy (smoke de `liquidEntrada` / press).

### 4 — Lote de poda de huérfanos públicos (dolor medio × costo bajo–medio)

**Problema:** ~40 símbolos públicos APP0 ensucian CATALOGO y el autocomplete.  
**Issue:** «Poda capa z-index huérfana + StrandElevation + componentes APP0 solo-preview; regenerar CATALOGO/CENSO».  
**Criterios:**

1. Lista §3.1 + subset acordado de §3.2 eliminados del target.  
2. `swift test` del paquete CenitDesign verde.  
3. CATALOGO ya no indexa los borrados.  
4. No borrar §3.3 (pipeline Liquid).  
5. `HeroInvertido`/`PieMetodo` quitados también de DESIGN prosa.

### 5 — API `LiquidMetricTile` + empty Liquid + menú Liquid (dolor medio × costo medio)

**Problema:** call-sites reinventan tiles sin delta; empties huérfanos; menú Paper eterno (menú resuelto en FER-281/283 → `LiquidMenu`).  
**Issue:** «Completar piezas: tile sin delta; `LiquidEmptyState`» (menú ya migrado).  
**Criterios:**

1. `LiquidMetricTile` usable sin delta (API + Preview + test).  
2. Apple Health puede llamar la pieza pública (o issue hijo de migración).  
3. Un empty/loading/error Liquid en CATALOGO con Preview; estados Instrumento marcados legacy o borrados.  
4. ~~Diseño de menú Liquid + migración PaperMenu~~ — hecho (FER-281 pieza, FER-283 adopción/retiro).

---

## Apéndice A — Tabla compacta de uso (APP / PKG)

| Símbolo | APP hits/files | PKG hits/files |
|---|---|---|
| `LiquidColor.` | 843/56 | 1248/104 |
| `theme.(paper\|ink\|…)` | 1005/55 | 361/61 |
| `InstrumentoTheme` | 127/49 | 339/81 |
| `StrandPalette.` | 3/3 | 51/14 |
| `LiquidSpace.` | 660/66 | 627/83 |
| `CenitMetrics.` | 577/51 | 116/30 |
| `LiquidType.` | 348/33 | 298/72 |
| `StrandFont.` | 511/46 | 201/53 |
| `InstrumentoType.` | 130/31 | 153/37 |
| `LiquidMotion.` | 82/36 | 70/32 |
| `StrandMotion.` | 59/25 | 30/24 |
| `liquidGlass(` | 33/17 | 61/40 |
| `LiquidGlassButton` | 48/17 | 7/3 |
| `LiquidMenu` (ex-`PaperMenu`, FER-283) | migrado | definición en PKG |
| `InstrumentoSectionBand` | 15/4 | 9/2 |
| `LiquidElevation.` | 3/1 | 12/6 |
| `StrandElevation.` / `strandElevation(` | 0/0 | 1/1 · 4/3 |
| `CenitOpacity.` | 15/9 | 19/9 |
| `.instrumentoTheme` | 76 inyecciones | — |
| `liquidEntrada` / `liquidPress` | 39/12 · 31/17 | 7/5 · 33/21 |

## Apéndice B — Orden sugerido de issues (no implementado)

1. Docs truth (mejora §6.1) — desbloquea a todos los agentes.  
2. Poda huérfanos seguros (§6.4 subset Elevation + docs fantasmas).  
3. Puente espacio (§6.2).  
4. Motion (§6.3).  
5. Piezas API (§6.5) en paralelo a `/migracion` de Paper/InstrumentoTheme.

---

*Fin del reporte. El director verifica y mergea. Ningún Swift fue modificado en esta corrida.*
