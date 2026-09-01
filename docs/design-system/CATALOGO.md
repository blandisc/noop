# Catálogo Liquid Glass

<!-- GENERADO por `swift run StrandDesignTokens` desde `Packages/StrandDesign/Sources/StrandDesignTokens/main.swift` — no editar a mano. `rol`/`simbolo`/valores salen del código; `archivo`/`cuándo usarlo`/`cuándo no` son la tabla curada `catalogEntries` de ese mismo archivo. -->

Diccionario + índice del sistema **Liquid Glass · El Eje** (FER-229), leído directo del API
público de `StrandDesign` — mismo trato que `color.instrumento` en
[`tokens/design-tokens.json`](tokens/design-tokens.json): el código gana, este archivo solo
lo refleja.

## Diccionario

### Color (`LiquidColor`)

| Token | Valor | Uso |
|---|---|---|
| `tinta900` | `#221D16` | texto principal, iconos activos |
| `tinta700` | `#5C5648` | texto secundario, kickers de fecha |
| `tinta500` | `#6F6857` | labels, captions neutros, iconos inactivos |
| `tinta10` | `rgba(34,29,22,0.10)` | tracks de anillos, divisores de lista |
| `tinta7` | `rgba(34,29,22,0.07)` | segmentos de barra inactivos, chips de día vacíos |
| `papelAlto` | `#F8F6EF` | inicio del degradado de pantalla |
| `papelBajo` | `#F0EDE4` | fin del degradado de pantalla |
| `papelDock` | `rgba(251,249,242,0.38)` | relleno del vidrio/lente (dock) |
| `papelTarjeta` | `#FFFFFF` | tarjeta de HOJA — blanco puro |
| `fondoAlto` | `#FEFEFD` | fondo neutro — «El Tablero» |
| `fondoBajo` | `#F3F4F2` | fondo neutro — «El Tablero» |
| `papelMatriz` | `#F6F4EE` | papel plano del modo Matriz |
| `verdePrimario` | `#0C8F62` | CTA, énfasis, palabra destacada del hero, pulsos |
| `verdeProfundo` | `#00774B` | deltas positivos, texto quiet |
| `verdeAurora` | `#2EB27D` | solo halos/auroras de fondo (nunca texto) |
| `verdeOrbe` | `#50AF73` | orbes drift del fondo de Hoy |
| `verdeBotonAlto` | `#12A06E` | tope del degradado del botón primary |
| `tintaSobreVerde` | `#F4F1E8` | texto sobre el botón primary |
| `indigo` | `#5D5A9E` | sueño |
| `cian` | `#147C8C` | HRV |
| `rosa` | `#B85068` | FC en reposo |
| `ambar` | `#C4631F` | esfuerzo, temperatura de piel |
| `teal` | `#4C8998` | pasos |
| `azul` | `#3B6FA0` | respiración |
| `oro` | `#E8C24B` | amanecer / halos cálidos |
| `ambarClaro` | `#E29A50` | clima de atención |
| `doradoTemp` | `#8A6A2B` | identidad de temperatura de piel en Cosmos/Matriz |
| `verdeCarga` | `#3F7A5E` | identidad de carga |
| `estresMedio` | `#A9752F` | heatmap de estrés — nivel medio |
| `estresAlto` | `#9C5B2E` | heatmap de estrés — nivel alto |
| `celdaVacia` | `rgba(34,29,22,0.07)` | día sin lectura en un mosaico de calendario |
| `celdaVaciaPip` | `rgba(34,29,22,0.14)` | el mismo hueco a tamaño de pip en leyenda |
| `particulaVerde` | `#10694E` | partícula en rango/atención |
| `particulaRoja` | `#963426` | partícula en desgaste |
| `particulaAmbar` | `#96501A` | partícula en atención |
| `particulaNeutra` | `#737670` | partícula neutra — calibrando |
| `rojoClaro` | `#E06C56` | rojo claro del clima de alerta |
| `positivo` | `#00774B` | deltas a favor |
| `atencion` | `#C4631F` | fuera de rango |
| `negativo` | `#B3402A` | deltas en contra |
| `atencionTexto` | `#8F4712` | atención para texto chico (AA) |
| `vidrioEspecular` | `rgba(255,255,255,0.92)` | highlight especular |
| `vidrioBordeFuerte` | `rgba(255,255,255,0.90)` | borde de esfera / gota |
| `vidrioBorde` | `rgba(255,255,255,0.85)` | bordes de vidrio |
| `vidrioBordePastilla` | `rgba(255,255,255,0.80)` | borde de pastilla + inner-highlights |
| `vidrioBordeSuperficie` | `rgba(255,255,255,0.72)` | borde de superficie (tiles) |
| `vidrioStreak` | `rgba(255,255,255,0.55)` | streak especular del dock |
| `vidrioLente` | `rgba(255,255,255,0.38)` | relleno lente/dial |
| `vidrioRealcePastilla` | `rgba(255,255,255,0.35)` | realce especular de la pastilla del selector del dock |
| `vidrioPastilla` | `rgba(255,255,255,0.46)` | relleno pastilla |
| `vidrioSuperficie` | `rgba(255,255,255,0.46)` | relleno superficie tile |
| `vidrioStep` | `rgba(255,255,255,0.70)` | relleno de los steppers circulares del enfoque |
| `vidrioCanto` | `rgba(34,29,22,0.08)` | canto exterior hairline de un módulo |
| `vidrioAtmosfera` | `rgba(255,255,255,0.30)` | relleno del módulo de vidrio sobre la atmósfera |
| `vidrioAtmosferaSolida` | `rgba(255,255,255,0.45)` | plan B opaco de la receta de atmósfera |

### Espaciado (`LiquidSpace` / mixtos de `LiquidLayout`)

| Token | Valor | Uso |
|---|---|---|
| `s025` | 1pt | micro-gap — rótulo ↔ dato dentro de una columna |
| `s050` | 2pt | gaps de segmentos de barra |
| `s075` | 3pt | respiro exterior de la pastilla táctil |
| `s100` | 4pt | — |
| `s125` | 5pt | gap rótulo ↔ ratio / diámetro |
| `s150` | 6pt | gota ↔ label |
| `s200` | 8pt | gap del grid de tiles |
| `s225` | 9pt | padding vertical interior de la pastilla táctil |
| `s250` | 10pt | gap entre módulos de «El Tablero» |
| `s300` | 12pt | padding H de tile, separación entre bloques chicos |
| `s400` | 16pt | padding H de pastilla / interior horizontal de módulo |
| `s550` | 22pt | margen horizontal de pantalla (legacy Liquid) |
| `s600` | 24pt | margen horizontal de la pantalla «El Tablero» |
| `s800` | 32pt | — |
| `s1400` | 56pt | safe-area top (velo de status) |
| `ecosistemaAlto` | 320pt | alto de la zona del héroe «El Ecosistema» |
| `dockBottom` | -22pt | margen inferior del dock flotante (negativo) |
| `chipHorizontal` | 9pt | respiro horizontal de chip/pastilla chica (FER-273) |
| `seccionCanto` | 10pt | canto de sección — antes/después de un Divider (FER-273) |
| `filaRespiro` | 10pt | respiro vertical de fila/chip compacto (FER-273) |
| `handoff14` | 14pt | padding de tarjetas/controles chicos del handoff (FER-273) |
| `handoff44` | 44pt | gap entre bloques de dato gemelos, == mínimo táctil HIG (FER-273) |
| `chipCompactoH` | 11pt | chip compacto del handoff — horizontal (FER-273) |
| `chipCompactoV` | 5pt | chip compacto del handoff — vertical (FER-273) |

### Radios (`LiquidRadius`)

| Token | Valor | Uso |
|---|---|---|
| `hairline` | 0.5pt | antialiasing del trazo de 1pt (capilar divisor) |
| `control` | 12pt | swatches, chips de día, inputs |
| `tarjeta` | 18pt | tiles, tarjetas, contenedores de lista |
| `modulo` | 20pt | módulos de vidrio de «El Tablero» |
| `hoja` | 28pt | sheets y modales |
| `pastilla` | 999pt | botones, dock, barras, badges (Capsule) |

## Índice de componentes

Rol → símbolo → archivo → cuándo usarlo → cuándo no. `archivo` es relativo a
`Packages/StrandDesign/Sources/StrandDesign/`. Este índice **reemplaza** las listas de
componentes a mano de `CLAUDE.md`/`CONTRIBUTING.md`/`DESIGN.md`/`LIBRARY.md` — si buscas
un componente, empieza aquí.

| Rol | Símbolo | Archivo | Cuándo usarlo | Cuándo no |
|---|---|---|---|---|
| Superficie de vidrio | `liquidGlass(_:)` | `LiquidGlass/LiquidGlassRecipes.swift` | Cualquier tile/tarjeta/pastilla/dock nuevo en pantallas Liquid Glass — es la ÚNICA puerta al vidrio (blur + fondo + borde + highlight + sombra ya compuestos). | No para pantallas «Instrumento diurno» sin migrar (usan `.instrumentoCard(_:)`), ni para componer blur/material a mano. |
| Botón CTA | `LiquidGlassButton` | `LiquidGlass/LiquidGlassButton.swift` | Botones pill de pantalla (primary/glass/quiet) con hit-target 44pt ya resuelto. | No para controles inline chicos (usa `LiquidGlassRecipe.pastilla` directo) ni para un botón .plain sin la receta de press. |
| Tile de métrica | `LiquidMetricTile` | `LiquidGlass/LiquidMetricTile.swift` | Grid de métricas del hub/tablero — overline + valor + delta sobre vidrio. | No para una fila de lista (usa `LiquidListRow`) ni para un valor sin la asignación 1:1 de color de `LiquidColor`. |
| Fila de lista | `LiquidListRow` | `LiquidGlass/LiquidListRow.swift` | Listas de hoja/detalle (historial, entradas) que necesitan la fila estándar Liquid. | No para un grid de tiles (usa `LiquidMetricTile`). |
| Chip de selección | `LiquidChipSeleccion` | `LiquidGlass/LiquidChipSeleccion.swift` | Chips de filtro/selección múltiple sobre vidrio. | No para el control segmentado único de la app (usa `SegmentedPillControl`). |
| Control segmentado | `SegmentedPillControl` | `Components.swift` | EL ÚNICO control de rango/segmentos de la app — cualquier selector de periodo/pestaña interna. | No inventar un segmentado nuevo por pantalla; si el look no calza, extiende este (`inkThumb`/`tall`/`thumbTint`). |
| Barra de tabs | `LiquidTabBar` | `LiquidGlass/LiquidTabBar.swift` | La barra de navegación inferior flotante («dock») de la app. | No para un segmentado de contenido dentro de una pantalla (usa `SegmentedPillControl`). |
| Cabecera de hoja | `LiquidSheetHeader` | `LiquidGlass/LiquidSheetHeader.swift` | El encabezado estándar de cualquier hoja/sheet Liquid (título + cierre). | No para el título en pantalla completa (usa `InstrumentoScreenTitle` si la pantalla sigue en Instrumento, o el header propio de la pantalla Liquid). |
| Pie de hoja — método | `LiquidMetodo` | `LiquidGlass/LiquidSheetFoot.swift` | El bloque «cómo se calcula» al pie de una hoja de detalle. | No para el badge de procedencia del dato (usa `LiquidOrigenChip`, mismo archivo). |
| Chip de procedencia | `LiquidOrigenChip` | `LiquidGlass/LiquidSheetFoot.swift` | Marcar de dónde vino un dato (banda/Apple Salud/computado) al pie de una hoja. | No como badge genérico de estado (usa `StatePill`). |
| Gráfica de tendencia (Liquid) | `LiquidTrendChart` | `LiquidGlass/LiquidTrendChart.swift` | Series temporales dentro de una pantalla/hoja ya migrada a Liquid Glass. | No en pantallas aún en Instrumento (usa `TrendChart`, que sigue vigente para ese inventario). |
| Gráfica de tendencia (compartida) | `TrendChart` | `TrendChart.swift` | Serie temporal con hover/crosshair — usada por ambos inventarios (Instrumento y, vía wrapper, Liquid). | No para una línea inline diminuta (usa `Sparkline`). |
| Sparkline inline | `Sparkline` | `Sparkline.swift` | Tendencia diminuta dentro de un tile (Hoy / live-HR). | No como gráfica principal de una pantalla de detalle (usa `TrendChart`/`LiquidTrendChart`). |
| Hipnograma | `Hypnogram` | `Hypnogram.swift` | Bandas de etapa de sueño de una noche. | No para cualquier otra serie categórica (es específico de etapas de sueño). |
| Mosaico anual | `YearHeatStrip` | `YearHeatStrip.swift` | Vista de un año completo estilo calendario de contribuciones (recuperación por día). | No para un rango de 90 días (usa `Calendario90`, mismo archivo). |
| Mosaico de 90 días | `Calendario90` | `YearHeatStrip.swift` | Vista de 90 días («Patrones», calendarios cortos). | No para el año completo (usa `YearHeatStrip`). |
| Pastilla de estado | `StatePill` | `StatePill.swift` | Un estado con tono + texto (conectado/calibrando/etc.), con o sin pulso. | No para el chip de procedencia de dato (usa `LiquidOrigenChip`/`SourceBadge`). |
| Badge de procedencia | `SourceBadge` | `Components.swift` | Marcar «MY-WHOOP» / «APPLE HEALTH» junto a un dato. | No como pastilla de estado genérica (usa `StatePill`). |
| Tile de métrica (Instrumento) | `StatTile` | `StatTile.swift` | Tile de altura fija en pantallas del inventario «Instrumento diurno» aún sin migrar. | No en pantallas ya migradas a Liquid Glass (usa `LiquidMetricTile`). |
| Encabezado de sección (Liquid) | `LiquidSectionHeader` | `LiquidGlass/LiquidSectionHeader.swift` | Abrir una sección en una pantalla Liquid Glass — kicker + aire, sin banda de fondo (FER-273). | No en pantallas «Instrumento diurno» aún sin migrar (usa `InstrumentoSectionBand`, que sí lleva banda de papel). |
| Cápsula de acción (Hoja) | `HojaCapsulaAccion` | `Entrenar/HojaCapsulaAccion.swift` | Acción compacta sobre vidrio DENTRO de una hoja de Entrenar (agregar serie, acción secundaria) que no debe prometer navegación — flecha opcional, apagada por default (FER-280 · 1c, clase 5). | No para una puerta a otra pantalla/hoja (usa `EntrenarCapsulaPuerta`, que siempre trae «›»); no para un CTA de pantalla completa (usa `LiquidGlassButton`/`StrandCTAButton`). |
