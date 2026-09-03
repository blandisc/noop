# Catálogo Liquid Glass

<!-- GENERADO por `swift run CenitDesignTokens` desde `Packages/CenitDesign/Sources/CenitDesignTokens/main.swift` — no editar a mano. `rol`/`simbolo`/valores salen del código; `archivo`/`cuándo usarlo`/`cuándo no` son la tabla curada `catalogEntries` de ese mismo archivo. -->

Diccionario + índice del sistema **Liquid Glass · El Eje** (FER-229), leído directo del API
público de `CenitDesign` — mismo trato que `color.instrumento` en
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

### OLED (Watch y Dynamic Island) (`LiquidOLED`)

| Token | Valor | Uso |
|---|---|---|
| `fondo` | `#000000` | negro puro (OLED apaga el píxel) |
| `superficie` | `#1F1C18` | superficie elevada sobre negro |
| `tinta` | `#ECE9E0` | tinta principal sobre negro |
| `tintaSecundaria` | `#A6A298` | tinta secundaria |
| `tintaTerciaria` | `#8B8370` | tinta terciaria / apagada |
| `borde` | `rgba(236,233,224,0.14)` | canto fino sobre negro |
| `bordeFuerte` | `rgba(236,233,224,0.28)` | canto fuerte sobre negro |
| `verde` | `#2EB27D` | verde de veredicto AA sobre negro |
| `ambar` | `#E29A50` | ámbar de atención sobre negro |
| `negativo` | `#CD4A42` | rojo de error legible sobre negro |
| `rosa` | `#BD546C` | rosa de FC sobre negro |

### Espaciado (`LiquidSpace` / mixtos de `LiquidLayout`)

| Token | Valor | Uso |
|---|---|---|
| `s025` | 1pt | micro-gap — rótulo ↔ dato dentro de una columna |
| `s050` | 2pt | gaps de segmentos de barra |
| `s075` | 3pt | respiro exterior de la pastilla táctil |
| `s100` | 4pt | — |
| `s125` | 5pt | gap rótulo ↔ ratio / diámetro |
| `s150` | 6pt | gota ↔ label |
| `s175` | 7pt | paso fino entre s150 y s200 (FER-318) |
| `s200` | 8pt | gap del grid de tiles |
| `s225` | 9pt | padding vertical interior de la pastilla táctil |
| `s250` | 10pt | gap entre módulos de «El Tablero» |
| `s300` | 12pt | padding H de tile, separación entre bloques chicos |
| `s350` | 14pt | padding del recibo térmico / screenTop (FER-309) |
| `s400` | 16pt | padding H de pastilla / interior horizontal de módulo |
| `s450` | 18pt | paso entre s400 y s550 (FER-318) |
| `s550` | 22pt | margen horizontal de pantalla (legacy Liquid) |
| `s600` | 24pt | margen horizontal de la pantalla «El Tablero» |
| `s700` | 28pt | gap entre secciones de una hoja/lista |
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

### Controles (`LiquidControl`)

| Token | Valor | Uso |
|---|---|---|
| `hitTarget` | 44pt | objetivo táctil mínimo HIG (44 pt) |
| `sm` | 32pt | chips, filas densas |
| `md` | 44pt | control por defecto (== hitTarget) |
| `lg` | 56pt | CTAs, controles destacados |
| `tileAltura` | 104pt | altura única del tile de métrica (FER-309) |

### Radios (`LiquidRadius`)

| Token | Valor | Uso |
|---|---|---|
| `hairline` | 0.5pt | antialiasing del trazo de 1pt (capilar divisor) |
| `chip` | 8pt | badge chico del handoff (FER-275) |
| `insetTarjeta` | 10pt | sub-tarjeta anidada dentro de otra tarjeta |
| `control` | 12pt | swatches, chips de día, inputs |
| `tile` | 17pt | esquina del tile de métrica de Hoy (FER-309) |
| `tarjeta` | 18pt | tiles, tarjetas, contenedores de lista |
| `modulo` | 20pt | módulos de vidrio de «El Tablero» |
| `hoja` | 28pt | sheets y modales |
| `pastilla` | 999pt | botones, dock, barras, badges (Capsule) |

### Tipografía (`LiquidType` — familia nueva)

`Font` no se introspecciona desde el generador; nombre + tamaño/peso/Dynamic Type curados
del source. Solo la familia tipográfica nueva (FER-303/306/310/318).

| Token | Tamaño | Peso | Dynamic Type |
|---|---|---|---|
| `captionRegular` | 10.5 | regular | no |
| `captionFuerte` | 10.5 | semibold | no |
| `captionNegrita` | 10.5 | bold | no |
| `captionLecturaNegrita` | 10.5 | bold | sí (.caption2) |
| `tituloFilaMedia` | 13 | medium | no |
| `tituloFilaNegrita` | 13 | bold | no |
| `tituloGemelaMedia` | 15 | medium | no |
| `relojCompacto` | 15 tabular | regular | no |
| `pie` | .caption2 | regular | sí |
| `cuerpoLista` | .subheadline | regular | sí |
| `subtituloFila` | .footnote | regular | sí |
| `filaConteoNumero` | .caption tabular | medium | sí |

## Índice de componentes

Rol → símbolo → archivo → cuándo usarlo → cuándo no. `archivo` es relativo a
`Packages/CenitDesign/Sources/CenitDesign/`, salvo piezas de app (p. ej. `Cenit/Screens/…`)
que se anotan desde la raíz del repo. Este índice **reemplaza** las listas de componentes
a mano de `CLAUDE.md`/`CONTRIBUTING.md`/`DESIGN.md`/`LIBRARY.md` — si buscas un componente,
empieza aquí.

| Rol | Símbolo | Archivo | Cuándo usarlo | Cuándo no |
|---|---|---|---|---|
| Superficie de vidrio | `liquidGlass(_:)` | `LiquidGlass/LiquidGlassRecipes.swift` | Cualquier tile/tarjeta/pastilla/dock nuevo en pantallas Liquid — ÚNICA puerta al vidrio (blur + fondo + borde + highlight + sombra compuestos). | No componer blur/material/sombra a mano; en hub Entrenar preferir `EntrenarModulo`/`EntrenarTile` (ya fijan régimen mosaico). |
| Módulo mosaico (Entrenar) | `EntrenarModulo` | `Entrenar/EntrenarVidrio.swift` | Contenedor a lo ancho del hub/hojas Entrenar — fija `regimen: .mosaico` por construcción. | No en pantallas sobrias (Hoy/detalle); ahí `liquidGlass(tono:regimen: .sobrio)` o receta de forma. |
| Tile mosaico (Entrenar) | `EntrenarTile` | `Entrenar/EntrenarVidrio.swift` | Tesela del grid 2-col del hub Entrenar (marcas, volumen, descanso…) — mosaico + minHeight fijo. | No para sub-métricas de una hoja Liquid de detalle (usa `LiquidCajita`); no reinventar tile local. |
| Cajita de sub-métrica | `LiquidCajita` | `LiquidGlass/LiquidCajita.swift` | Mosaico de lecturas en detalle Liquid (rótulo · valor · pie) vía `LiquidCajita`/`LiquidCajitaGrid`. | No es el tile de hub con gota+delta (`LiquidMetricTile` está huérfano); no para filas de lista (`LiquidListRow`). |
| Fila de lista | `LiquidListRow` | `LiquidGlass/LiquidListRow.swift` | Listas de hoja/detalle Liquid (historial, entradas) con la fila estándar. | No para un grid de lecturas (usa `LiquidCajita`); no para check de factores (usa `LiquidChecklistRow`). |
| Fila check de factores | `LiquidChecklistRow` | `LiquidGlass/LiquidChecklistRow.swift` | Fila presente/ausente de un factor (edad corporal, fitness, fuentes) con tono. | No como fila genérica de navegación (usa `LiquidListRow`). |
| Franja de sección (Liquid) | `LiquidFranjaSeccion` | `LiquidGlass/LiquidFranjaSeccion.swift` | Cabecera a sangre de sección en hojas Liquid de métrica (velo del tono al 4 %). | No en pantallas Instrumento aún en papel (usa `InstrumentoSectionBand`); no inventar banda local. |
| Selector de periodo (Liquid) | `LiquidRangeSelector` | `LiquidGlass/LiquidRangeSelector.swift` | Selector de periodo en Cuerpo / hojas Liquid (S·M·3M·…) con tick del tono. | No en pantallas Instrumento/entrenamiento que aún usan `SegmentedPillControl`; no reinventar periodo. |
| Control segmentado (Instrumento) | `SegmentedPillControl` | `Components.swift` | Segmentado vivo en pantallas Instrumento/entrenamiento (historial, editors, no-periodo). | No como selector de periodo en pantalla ya Liquid (usa `LiquidRangeSelector`). |
| Chip de selección | `LiquidChipSeleccion` | `LiquidGlass/LiquidChipSeleccion.swift` | Chips de filtro/selección múltiple sobre vidrio. | No para periodo Liquid (`LiquidRangeSelector`) ni segmentado Instrumento (`SegmentedPillControl`). |
| Barra de tabs | `LiquidTabBar` | `LiquidGlass/LiquidTabBar.swift` | La barra de navegación inferior flotante («dock») de la app. | No para un segmentado de contenido dentro de una pantalla. |
| Menú «···» | `LiquidMenu` | `LiquidGlass/LiquidMenu.swift` | El menú contextual de un «···» en pantalla Liquid: filas con icono, subtítulo de estado, destructiva al final y un nivel de submenú. | No para una acción única (usa un botón); no reinventar el popover a mano. |
| Cabecera de hoja | `LiquidSheetHeader` | `LiquidGlass/LiquidSheetHeader.swift` | El encabezado estándar de cualquier hoja/sheet Liquid (título + cierre). | No para el título en pantalla completa (header propio de la pantalla). |
| Pie de hoja — método | `LiquidMetodo` | `LiquidGlass/LiquidSheetFoot.swift` | El bloque «cómo se calcula» al pie de una hoja de detalle. | No para el badge de procedencia del dato (usa `LiquidOrigenChip`, mismo archivo). |
| Chip de procedencia | `LiquidOrigenChip` | `LiquidGlass/LiquidSheetFoot.swift` | Marcar de dónde vino un dato (banda/Apple Salud/computado) al pie de una hoja Liquid. | No como pastilla de estado genérica; en listas/detalle de entreno usa `LiquidOrigenBadge`. |
| Badge de procedencia (Liquid) | `LiquidOrigenBadge` | `LiquidGlass/LiquidSheetFoot.swift` | Pastilla caps de procedencia en historial/detalle de entrenamiento (Apple/Manual/Medido). `tono: nil` = neutro. | No en pie de hoja con glifo (usa `LiquidOrigenChip`); no como pastilla de estado (`LiquidStatePill`). |
| Botón pill Liquid | `LiquidGlassButton` | `LiquidGlass/LiquidGlassButton.swift` | Botones pill de pantalla Liquid (primary/glass/quiet/solida) con hit-target 44pt ya resuelto. | No para CTA de tinta a lo ancho en flujo Instrumento/Entrenar (usa `CenitCTAButton`); no `.plain` sin press. |
| Botón pastilla sólida | `LiquidGlassButton(.solida)` | `LiquidGlass/LiquidGlassButton.swift` | Acción pill OPACA sobre hoja El Eje (p. ej. «Crear ejercicio» en Biblioteca) — papel sin vidrio-sobre-vidrio. | No cuando quieras vidrio translúcido (usa `.glass`); no CTA a lo ancho (usa `CenitCTAButton`); no acción destructiva (`.destructive`). |
| Campo de búsqueda Liquid | `LiquidCampoBusqueda` | `LiquidGlass/LiquidCampoBusqueda.swift` | Campo de búsqueda con lupa + limpiar sobre `.superficieSolida` (Biblioteca y listas Liquid). | No reinventar HStack+TextField a mano; no para campos de métrica teñidos (usa `LiquidCampoMetrica`); no campo de texto genérico (usa `LiquidCampoTexto`). |
| Campo de texto Liquid | `LiquidCampoTexto` | `LiquidGlass/LiquidCampoTexto.swift` | Campo de texto El Eje (nombre, deporte, notas, números) — padding + `.superficieSolida` + `cuerpoLista`; teclado/multilínea/sufijo opcionales (FER-339). | No para búsqueda con lupa (usa `LiquidCampoBusqueda`); no campo teñido de métrica (usa `LiquidCampoMetrica`); no dejar `TextField` suelto en pantallas Liquid. |
| Fila de ejercicio (Biblioteca) | `EntrenarFilaEjercicio` | `Entrenar/EntrenarFilaEjercicio.swift` | Fila del catálogo de ejercicios: miniatura + nombre/meta + récord + chevron/Agregar (FER-289). | No para filas de historial de sesión (usa `EntrenarFilaFuerza`/`EntrenarFilaCardio`); no dibujar la fila a mano en la Biblioteca. |
| Chip de herramienta (Entrenar) | `EntrenarChipHerramienta` | `Entrenar/EntrenarChipHerramienta.swift` | Puerta de herramienta ancha (Crear plan / Nueva sección) sobre `.pastillaSolida` — mismo contrato que el viejo `InstrumentoToolChip` (FER-292). | No para CTA pill de hoja (`LiquidGlassButton`); no para cápsula outline (`OutlineCapsule`); no reinventar HStack+SF a mano. |
| Fila de ajuste (hoja-herramienta) | `EntrenarFilaHerramienta` | `Entrenar/EntrenarFilaHerramienta.swift` | Fila rótulo + nota/valor + control en hojas Entrenar (Progresión, Descanso) — papel opaco, capilar tinta10. | No para filas de navegación (usa `LiquidListRow`); no para filas de catálogo (`EntrenarFilaEjercicio`). |
| Stepper de ajuste Entrenar | `EntrenarStepper` | `Entrenar/EntrenarStepper.swift` | Control − valor + de hoja-herramienta (incremento, reloj de descanso) — tallas `.fila`/`.hoja`. | No para steppers Instrumento de papel (`PaperStepper`/`StepperButton`); el caller formatea el valor. |
| Toggle Liquid | `LiquidToggleStyle / .liquid` | `LiquidGlass/LiquidToggleStyle.swift` | Switch cromo El Eje (tinta900/tinta10/papelTarjeta) en hojas Liquid — `.toggleStyle(.liquid)`. | No en pantallas aún Instrumento (usa `.instrumento`); no teñir el track con el color del dato. |
| Título de flujo Liquid | `LiquidFlowTitle` | `LiquidGlass/LiquidFlowTitle.swift` | Cabecera kicker + displayS de pantallas empujadas sin salida propia (Tickets). | No cuando ya hay `EntrenarHojaCabecera`; no en pantallas Instrumento (usa `InstrumentoFlowTitle`). |
| CTA de tinta (barra) | `CenitCTAButton` | `CenitCTAButton.swift` | CTA sólido/outline a lo ancho (o compacto) en flujos Entrenar/Instrumento — una sola barra canónica. | No reinventar barra con radius/padding ad-hoc; en chrome Liquid de hoja preferir `LiquidGlassButton`. |
| Atrás / cerrar | `BackButton` | `BackButton.swift` | Disco de salir/atrás en hojas y pantallas Instrumento/Entrenar (`role: .back`/`.close`). | No para una acción con nombre en el header (usa `HeaderActionButton`); no SF Symbol suelto. |
| Acción de header | `HeaderActionButton` | `HeaderActionButton.swift` | Cápsula con label (Guardar, Terminar) pareja de `BackButton` en la barra de encabezado. | No para salir/cerrar (usa `BackButton`); no botón `.bordered` ad-hoc en ese slot. |
| Confirmación (tarjeta) | `ConfirmCard / .instrumentoConfirm` | `ConfirmCard.swift` | Reemplazo de `.confirmationDialog`: tarjeta de vidrio + scrim; API `.instrumentoConfirm`. | No usar `.confirmationDialog`/alert genérico para decisiones con consecuencia; cada acción nombra lo que hace. |
| Diálogo de texto (Liquid) | `LiquidInputCard / .liquidInput` | `LiquidGlass/LiquidInputCard.swift` | Prompt de texto centrado (Nueva/Renombrar carpeta): cristal El Eje + scrim; misma firma que el viejo `.instrumentoInput` (FER-292). | No usar `.alert`/`TextField` suelto para nombrar; no para confirmaciones sin campo (usa `.instrumentoConfirm`/`liquidConfirm`). |
| Toast de error al guardar | `.saveErrorToast` | `Cenit/Screens/SaveErrorToast.swift` | Banner auto-descarte «No se pudo guardar» tras un write fallido (modifier de app). | No reinventar banner rojo local; no para confirmaciones (usa `.instrumentoConfirm`). |
| Bloque patrón (Instrumento) | `.patternBlock(_:bar:)` | `SessionInstruments.swift` | Fondo `patternBlock` + barra lateral de tono para avisos/errores en pantallas Instrumento. | No en hojas ya Liquid (usa `LiquidPatternBlock`); no pintar `theme.patternBlock` a mano sin la barra. |
| Bloque patrón (Liquid) | `LiquidPatternBlock` | `LiquidGlass/LiquidPatternBlock.swift` | «Tu patrón» / lectura quieta en hojas Liquid — overline + líneas + barra del tono, sin vidrio. | No en pantallas Instrumento (usa `.patternBlock`); no envolverlo en `liquidGlass`. |
| Gráfica de tendencia (Liquid) | `LiquidTrendChart` | `LiquidGlass/LiquidTrendChart.swift` | Series temporales dentro de una pantalla/hoja ya migrada a Liquid Glass. | No en pantallas aún en Instrumento (usa `TrendChart`). |
| Gráfica de tendencia (compartida) | `TrendChart` | `TrendChart.swift` | Serie temporal con hover/crosshair — inventario Instrumento y wrappers. | No para una línea inline diminuta (usa `Sparkline`). |
| Sparkline inline | `Sparkline` | `Sparkline.swift` | Tendencia diminuta dentro de un tile (Hoy / live-HR). | No como gráfica principal de una pantalla de detalle (usa `TrendChart`/`LiquidTrendChart`). |
| Hipnograma (Liquid) | `LiquidHipnograma` | `LiquidGlass/LiquidHipnograma.swift` | Bandas de etapa de sueño de una noche en hoja Liquid. | No usar el `Hypnogram` legado (0 call-sites APP); no para otras series categóricas. |
| Calendario 90 días (Liquid) | `LiquidCalendario90` | `LiquidGlass/LiquidCalendario90.swift` | Mosaico de 90 días en hojas Liquid (Stress/Strain/Sleep). | No usar `Calendario90`/`YearHeatStrip` del índice viejo (0 call-sites APP). |
| Encabezado de sección (Liquid) | `LiquidSectionHeader` | `LiquidGlass/LiquidSectionHeader.swift` | Abrir una sección en una pantalla Liquid Glass — kicker + aire, sin banda de fondo (FER-273; adopción en Ola 3). | No en pantallas «Instrumento diurno» aún sin migrar (usa `InstrumentoSectionBand`, que sí lleva banda de papel). |
| Cápsula de acción (Hoja) | `HojaCapsulaAccion` | `Entrenar/HojaCapsulaAccion.swift` | Acción compacta sobre vidrio DENTRO de una hoja de Entrenar que no promete navegación — flecha opcional, apagada por default (FER-280·1c). | No para una puerta a otra pantalla/hoja (usa `EntrenarCapsulaPuerta`); no para un CTA de pantalla completa (usa `LiquidGlassButton`/`CenitCTAButton`). |
| Cápsula outline de acción | `OutlineCapsule` | `OutlineCapsule.swift` | Acción secundaria en cápsula con `hairlineStrong` ± fill (raise, Start/Stop, filtro, Use, Match…) — sm/md + press. | No CTA de tinta a lo ancho (`CenitCTAButton`); no pill Liquid de hoja (`LiquidGlassButton`); no acción de header (`HeaderActionButton`). |
| Pastilla de estado Liquid | `LiquidStatePill` | `LiquidGlass/LiquidStatePill.swift` | Estado vivo/listo sobre cristal (`.pastillaSolida`) o chip de valencia Δ% — sustituye `statusPill` a mano y chips de signo. | No pastilla Instrumento de chrome (`StatePill`); no procedencia (`LiquidOrigenChip`/`LiquidOrigenBadge`); no filtro removible (`LiquidChipSeleccion`). |
| Toast de deshacer | `UndoToast` | `LiquidGlass/UndoToast.swift` | Snack de tinta «X borrado · Deshacer» tras un delete reversible (rutina/carpeta/sesión) — receta de WeeklyPlanEditor. | No para error de escritura (usa `.saveErrorToast`); no aviso Liquid de lectura (usa `LiquidAviso`); no confirmación (usa `.instrumentoConfirm`). |
| Aviso Liquid | `LiquidAviso` | `LiquidGlass/LiquidAviso.swift` | Heads-up / desconexión / nudge / aviso con pie de acciones en pantalla Liquid — `LiquidPatternBlock` + `liquidTarjetaSeccion` (receta HealthAlertBanner); icono/CTA/pie opcionales. | No snack de deshacer (`UndoToast`); no error de escritura (`.saveErrorToast`); no banner Instrumento de Hoy aún sin migrar (`TodayBanner`). |
| Rampas de dato Liquid | `LiquidRampas` | `LiquidGlass/LiquidRampas.swift` | Color de zona HR (`hrZone`), fatiga muscular 0…1 (`muscleLoad`) o tinte de familia de movimiento (`movementFamilyTint`) sin tocar `InstrumentoTheme` desde pantallas. | No inventar rampas locales; no leer `InstrumentoTheme.base.hrZoneRamp`/`muscleLoadColor`/`movementFamilyTint` desde `Cenit/`/`CenitApp/`. |
| Barra de progreso (pista+relleno) | `LiquidBarraProgreso` | `LiquidGlass/LiquidBarraProgreso.swift` | Cualquier riel de avance 0…1 (calibración, dosis, sesión, volumen): pista + relleno Capsule con tono/altura; opcional marca/contorno. | No para barra con rótulo/delta/promedio (`LiquidBarraMarca`); no conteo en ventana (`LiquidBarraConteo`); no etapas de sueño (`LiquidStageBar`); no chrome de acción (`OutlineCapsule`). |
| Halo / glow geométrico | `LiquidGlow · LiquidGlowDisco` | `LiquidGlass/LiquidGlow.swift` | Contorno que late (aviso, filo con aura) o disco radial desenfocado (orbe de respiración): la pantalla pasa color/fase y el blur vive en la pieza. | No para sombra de elevación (`liquidShadow`); no vidrio (`liquidGlass(_:)`); no `.blur` + fill a mano en pantallas. |
