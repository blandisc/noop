# Auditoría B1 — Pieza equivocada y evasiones (MITAD 1)

> **Solo reporte.** Cero cambios a Swift/CI/linter/baselines.  
> **Issue:** FER-279 · **rama:** `grok/fer-279b1-uso-1788282399-76192-27724`  
> **Fecha:** 2026-09-01 · **ejes:** 1 (pieza equivocada) y 2 (evasiones fuera de gate).  
> **Árbol auditado:** `Cenit/**`, `CenitWidgets`, `CenitWatch`, `Packages/StrandDesign/Sources`.

## Método (qué se leyó)

| Insumo | Uso |
|---|---|
| `docs/design-system/CATALOGO.md` | Índice rol→símbolo→«cuándo no» (líneas 118–140) |
| `docs/design-system/CONTRATO.md` | Matriz de 15 gates + indecidibles (§ Alta estructural / FER-276: `.frame`, `.offset`, `Color.clear`, `.safeAreaPadding`) |
| `docs/design-system/CENSO.md` + `CENSO.json` | Colador §1; TOP archivos; commit `8f08a6342cf0` · 209 `.swift` |
| `Tools/check-design-drift.py` | Las 15 reglas y qué regex **no** ven |
| `Tools/design-drift-baseline.json` | Deuda congelada (contexto; no se reescribe) |
| `docs/design-system/AUDITORIA-SISTEMA.md` | Cruce con Auditoría C (referencia; ejes 3–5 no se auditan aquí) |

Barridos: `rg` de call-sites de cada pieza del catálogo + piezas Liquid hot no listadas; patrones de evasión documentados y formas nuevas (`.fill(….opacity)`, `frame(minHeight:)`, `blur(`, `LinearGradient`, overlays de borde a mano). Clasificación heurística de `CENSO.json` (Color.clear / frame height) + spot-checks con lectura de contexto en `archivo:línea`.

**Fuera de alcance de esta mitad:** ejes 3 (contrabando de generación), 4 (paquete por dentro), 5 (token-exempt caducos).

---

## Resumen ejecutivo

El riesgo de **uso** no está en «alguien metió `LiquidMetricTile` donde iba una fila». Está en lo inverso: **el catálogo describe un inventario que la app ya no usa**, mientras el inventario vivo (`LiquidCajita`, `LiquidRangeSelector`, `LiquidFranjaSeccion`, `LiquidCalendario90`, `EntrenarTile`, tiles compuestos a mano) **no tiene «cuándo no»** que un agente pueda violar — ni un gate que lo vea.

Los 15 gates congelan literales y API legacy; el censo vigila indecidibles de geometría; **nadie gatea rol-de-componente**. Ese hueco es el de esta auditoría.

| Capacidad | Estimación del riesgo de *uso* (ejes 1–2) |
|---|---|
| Gateado (regex / trinquete) | **~25 %** — literales de color/espacio/radio/opacidad-vía-`.opacity(`/motion/legacy listada; no ve rol de pieza |
| Vigilado por censo (sin fail) | **~35 %** — `.frame` / `Color.clear` / `.offset` / clipShape; el censo cuenta, no bloquea |
| Ciego | **~40 %** — pieza equivocada / pieza huérfana / catálogo desfasado / opacidades vía `.fill`·`.stroke`·`.background` / `blur(` suelto / gradientes / `minHeight` decorativo / overlays de borde |

---

## Eje 1 · Pieza equivocada

Hallazgos rankeados por severidad (catálogo miente o se viola → reinvento silencioso → mal uso puntual).

### H1.1 · Catálogo desfasado: piezas «canónicas» con 0 call-sites en APP

**Severidad:** crítica (el «cuándo usarlo» del índice ya no describe el sistema vivo).

| Símbolo en CATALOGO | Call-sites APP (`Cenit`+Widgets+Watch) | Qué usa la app en su lugar |
|---|---|---|
| `LiquidMetricTile` | **0** (solo definición + `#Preview` en `LiquidMetricTile.swift:9–107`) | Hoy → `MatrizHoyFace` (`HoyModosHost.swift:53`); detalle → `LiquidCajita` (~39 hits); Salud → `liquidTile` local |
| `StatePill` | **0** (solo `StatePill.swift` + preview) | Chips ad-hoc (`confidenceChip`, ChipGuardian de Matriz, píldoras Entrenar) |
| `LiquidSectionHeader` | **0** (`LiquidSectionHeader.swift:20`) | `LiquidFranjaSeccion` (~23 call-sites en hojas Liquid) |
| `StatTile` | **0** en APP | `EntrenarTile` / tiles locales en pantallas Instrumento |
| `Hypnogram` | **0** | `LiquidHipnograma` (`SleepDetailScreen.swift:368`) |
| `Calendario90` / `YearHeatStrip` | **0** | `LiquidCalendario90` (Stress/Strain/Sleep); sin YearHeatStrip vivo en APP |
| `.instrumentoCard` | **0** en APP | Consistente con Auditoría C; no es defecto de uso |

**Propuesta:** lote de **sincronía CATALOGO** (regenerar `catalogEntries` en `StrandDesignTokens`): marcar huérfanas como «retirada / solo preview» o borrarlas del índice; añadir las piezas calientes con «cuándo / cuándo no». Sin eso, todo «cuándo no» del índice es teatro.

---

### H1.2 · Piezas vivas fuera del índice (sin «cuándo no» que auditar)

**Severidad:** crítica (no se puede detectar «pieza equivocada» si la pieza correcta no está en el diccionario).

| Pieza viva | Hits APP (orden magnitud) | Rol real observado |
|---|---|---|
| `LiquidCajita` / `LiquidCajitaGrid` | ~39 | Mosaico de sub-métricas en detalle (explícitamente *no* es `LiquidMetricTile` — `LiquidCajita.swift:8–11`) |
| `LiquidCalendario90` | ~31 | Calendario 90 d en hojas Liquid |
| `LiquidRangeSelector` | ~23 | Selector de periodo en Cuerpo / hojas de métrica |
| `LiquidFranjaSeccion` | ~23 | Cabecera de sección en hojas Liquid |
| `LiquidChecklistRow` | ~8 | Filas check de factores (≠ `LiquidListRow`) |
| `EntrenarTile` | varios hubs | Tile del dialecto Entrenar (`EntrenarVidrio.swift:288`) |

**Propuesta:** alta en CATALOGO + «cuándo no» cruzado (`LiquidRangeSelector` vs `SegmentedPillControl`; `LiquidFranjaSeccion` vs `LiquidSectionHeader` vs `InstrumentoSectionBand`; `LiquidCajita` vs `LiquidMetricTile` vs `EntrenarTile`).

---

### H1.3 · Dos selectores de periodo: el catálogo dice «uno», la app tiene dos

**Severidad:** alta.

- CATALOGO (`:126`): `SegmentedPillControl` es «**EL ÚNICO** control de rango/segmentos».
- Realidad Liquid: `LiquidRangeSelector` lo sustituyó a propósito (comentario FER-100 en `CuerpoView.swift:531–534`; mismo patrón en `MetricDetailScreen.swift:939`, `SleepDetailScreen.swift:760`, `StrainDetailScreen.swift:265`, `StressDetailScreen.swift:454`, `AppleHealthView.swift:338`, `CompareView`/`TrainingLoadSheet`/`MetricExplorerView`).
- `SegmentedPillControl` sigue vivo en pantallas Instrumento/entrenamiento (`WorkoutHistoryScreen.swift:288`, `:362`; `ExerciseDetailScreen.swift:108`; `TrainingBodyScreen.swift:682`; `RestEditorScreen.swift:170+`; etc.) — **uso legítimo de era**, no contrabando en Liquid.
- `MetricTrendChart.swift:179` aún dibuja `SegmentedPillControl` cuando `showsSelector`, pero **no hay ningún `MetricTrendChart(` en el árbol** → código muerto que contradice el índice.

**Propuesta:** (a) actualizar CATALOGO: periodo Liquid = `LiquidRangeSelector`; segmentado Instrumento/controles no-periodo = `SegmentedPillControl`; (b) borrar o archivar `MetricTrendChart` si nadie lo instancia; (c) regla de censo (no gate regex) «pantalla Liquid + `SegmentedPillControl` con `ExploreRange`» = hallazgo.

---

### H1.4 · Reinvento del tile de métrica (el rol del catálogo, sin la pieza)

**Severidad:** alta (misma anatomía, N implementaciones).

| Sitio | Qué hace | Por qué es «pieza equivocada» / vacío de catálogo |
|---|---|---|
| `AppleHealthView.swift:435–533` | `liquidStatTile` → `liquidTile`: gota + label + valor + sparkline + caption sobre `liquidTarjetaSeccion`; el comentario (`:435–436`) admite que **no** usa `LiquidMetricTile` porque exige `delta` | Grid de métricas del hub de Salud — rol de `LiquidMetricTile`, anatomía casi idéntica, API demasiado rígida |
| `BreathingView.swift:409–438` | `readoutTile` a mano + `liquidGlass(.superficieSolida)` + `CenitMetrics.tileHeight` | Tile de lectura; debería ser cajita/tile del sistema o extensión tipada |
| `TrainingBodyScreen.swift:1006–1014` | `tile(...)` sobre `EntrenarTile` | OK si Entrenar tiene dialecto propio — pero EntrenarTile **no está en CATALOGO**, así que el «cuándo no» de StatTile/LiquidMetricTile no aplica |
| `WorkoutHistoryScreen.swift:416–424`, `:728+` | `todoTiles` / `monthTile` vía `EntrenarTile` | Idem |
| `Entrenar/EntrenarHubMarcasVolumen.swift:56+`, `EntrenarHubPar.swift:58+` | `marcaTile` / `volumenTile` | Idem |

**Propuesta:** (1) aflojar `LiquidMetricTile` (delta/origen opcionales) **o** promover un `LiquidMetricTile.simple` / reusar `LiquidCajita` con gota; (2) lote AppleHealth → pieza del sistema; (3) documentar `EntrenarTile` como dialecto Entrenar con frontera explícita.

---

### H1.5 · `StatePill` huérfano: el estado se dibuja a mano

**Severidad:** media-alta.

| Sitio | Evidencia | Lectura |
|---|---|---|
| `ActivityRecoverySheet.swift:197–205` | `confidenceChip`: texto solid/building + `Capsule().stroke` punteado | **Badge de estado** (tono + texto). CATALOGO: eso es `StatePill` (`:137`), no procedencia |
| `MatrizHoyFace.swift:767–775` | `chipView(ChipGuardian)` — texto teñido sin pastilla | Estado del guardián; no reusa `StatePill` |
| `EntrenarHubHeroe.swift:94–113` | `subPill` Capsule + fill opacity | CTA/anuncio, no StatePill — pero demuestra pastillas locales sin pieza compartida |

**No** se observó `LiquidOrigenChip` usado como estado genérico (los 16 call-sites son pies de hoja de procedencia — uso correcto: Sleep/Strain/Stress/SkinTemp/BodyAge/FitnessAge/ActivityRecovery/MetricDetail/Explorer/TrainingLoad/Hoy sheet).  
`SourceBadge` en `WorkoutDetailScreen.swift:568` marca procedencia de workout — **uso correcto** del «cuándo usarlo»; la pantalla sigue en Instrumento.

**Propuesta:** o bien adoptar `StatePill`/`Liquid`-equivalente para confianza/guardián, o marcar `StatePill` como legacy en CATALOGO y publicar la pastilla de estado Liquid real (p. ej. extender el chip de `LiquidTendenciaCard` que el comentario de `confidenceChip` ya cita).

---

### H1.6 · Cabecera de sección: tres APIs, un catálogo incompleto

**Severidad:** media.

- Liquid vivo: `LiquidFranjaSeccion(` en BodyAge/Strain/Sleep/Prep/Stress/FitnessAge/ActivityRecovery/SkinTemp/MetricExplorer/MetricDetail (p. ej. `SleepDetailScreen.swift:140`, `MetricDetailScreen.swift:532`).
- Catálogo enseña `LiquidSectionHeader` (0 usos) y prohíbe usarlo en Instrumento.
- Instrumento aún correcto: `InstrumentoSectionBand` en `WeeklyPlanEditorView.swift:211+`, `WorkoutHistoryScreen.swift:460+`, `ExerciseLibraryScreen.swift:230+`.

**Propuesta:** CATALOGO debe listar `LiquidFranjaSeccion` como cabecera Liquid; `LiquidSectionHeader` → retirar o alias; gate/censo «`InstrumentoSectionBand` en archivo que ya importa solo Liquid* de superficie» (cuando exista migración).

---

### H1.7 · Gráficas del índice vs familia Liquid

**Severidad:** media (desfase de nombres, poco mal uso cruzado).

- Sueño usa `LiquidHipnograma` (`SleepDetailScreen.swift:368`), no `Hypnogram`.
- Calendarios Liquid usan `LiquidCalendario90`, no `Calendario90`.
- `LiquidTrendChart` solo aparece en `LiquidMetricSheetView.swift:706`; el resto de tendencias Liquid van por `LiquidGraficaNiveles` / charts de Matriz — otra familia ausente del índice.
- `Sparkline` (~6) se usa como spark inline (`AppleHealthView.swift:520`) — **conforme** al «cuándo usarlo»; no se vio como gráfica principal de detalle.

**Propuesta:** actualizar índice (LiquidHipnograma, LiquidCalendario90, LiquidGraficaNiveles, LiquidTrendChart); dejar Hypnogram/Calendario90/YearHeatStrip como Instrumento o retiradas.

---

### H1.8 · Lo que *no* se encontró (anti-hallazgos útiles)

- No hay `LiquidMetricTile` usado como fila de lista.
- No hay `StatePill` usado como procedencia (está muerto).
- No hay `.instrumentoCard` en pantallas Liquid.
- `LiquidChipSeleccion` en `CompareView.swift:330` es chip de métrica seleccionada con quitar — calza el «cuándo usarlo» (filtro/selección), no un segmentado.
- `LiquidListRow` en Ajustes / DataSources / MetricExplorer / Compare — uso de fila; los hand-rolls de Ajustes (`:225–244`, `:495–528`) son por slots que la pieza no expone (Picker / Deshacer), con `token-exempt(paridad)` — deuda de API de la pieza, no mal rol.

---

## Eje 2 · Evasiones vivas fuera de gate

Los indecidibles que CONTRATO/FER-276 deja fuera del regex, más formas que el colador del censo **aún no lista**.

### 2.A · Indecidibles documentados (CENSO §1) — dato vs decoración

Conteos del censo (`CENSO.md` / `CENSO.json`, commit `8f08a6342cf0`):

| Patrón | Hits censo | Archivos | Lectura tras spot-check |
|---|---|---|---|
| `.frame(height:)` «decorativo» | 146 | 42 | Mezcla fuerte: ver buckets abajo |
| `.frame(width:)` «decorativo» | 109 | 38 | Idem + canvases de preview |
| `Color.clear` | 64 | 27 | ~53 % preview; resto layout/selección |
| `.offset` | 10 | 7 | Pocos; varios gesto/dato |
| `clipShape(RoundedRectangle)` | 12 | 8 | Widgets + un puñado APP |
| `.safeAreaPadding` | **0** vivos | — | El indecidible listado **no aparece**; sí hay `safeAreaInset` (API distinta, no censada) |

#### `.frame(height:)` — buckets heurísticos sobre los 146 del censo

| Bucket | ~N | Ejemplos `archivo:línea` | Veredicto |
|---|---|---|---|
| Preview canvas (393×852, 800, 900…) | ~13+ (AppMap solo suma 9× height) | `AppMap.swift:47`, `:116`, …; `OnboardingWizard.swift:306` | **Legítimo** (canvas de mapa/preview) — ruido en el censo |
| Hairline / divisor ≤1 pt | ~30 | `AjustesView.swift:244` (0.5, paridad LiquidListRow); `EntrenarView.swift:991` | Debería ser token `LiquidRadius.hairline` / divisor de pieza — **decoración tokenizable** |
| Geometría de dato / track | ~41 | `CuerpoView.swift:712` (104×3 track); `:904–907` (barra calibración); `TrainingBodyScreen.swift:968` (exempt dato); `AppleHealthView.swift:523` (spark 22) | **Dato-legítimo** o ya exempt — OK vigilado |
| Chrome / alto de bloque | ~62 | `TrainingBodyScreen.swift:1033` (trend 48); `BreathingView` tileHeight vía frame; overlays height 1 | Candidatos a token de layout o a pieza |

**TOP archivos frame height (censo):** `TrainingBodyScreen.swift` 17 · `AppMap.swift` 9 · `LiveStrengthSheet.swift` 9 · `CuerpoView.swift` 8 · `WorkoutHistoryScreen.swift` 8.

**Propuesta:** el censo debería **excluir** `#Preview` / `AppMap` canvases del colador de evasiones (o etiquetarlos `preview`) para que el TOP deje de gritar 852 pt. Lote de hairlines → token/divisor público de `LiquidListRow`.

#### `Color.clear` — buckets

| Bucket | ~N | Ejemplos | Veredicto |
|---|---|---|---|
| Host de `#Preview` (`.sheet`) | ~34 | `MetricDetailScreen.swift:2164+` (serie de previews) | Ruido — no es relleno visual de producto |
| Probe de layout (`GeometryReader` + onAppear) | ~4 | `AjustesView.swift:59` | Legítimo |
| Spacer de columna / matchedGeometry | ~10+ | `HojaTarjetaEjercicio.swift:231–239`; `RoutineSheetLiveTarjeta.swift:458–467`; `RoutineSheetLive.swift:426` | Layout — OK |
| Fondo de selección / listRow | ~8 | `ExerciseLibraryScreen.swift:207`, `:655`; `SessionKeypad.swift:115`; `RoutineSheet.swift:531` | Chrome de estado seleccionado — candidato a token/pieza, no a prohibir clear |
| Placeholder de tab | 1 | `CenitApp/App/RootTabView.swift:413` | Sistema |

**Propuesta:** no gatear `Color.clear`; sí etiquetar en censo `preview` vs `layout` vs `chrome-selección`. Casi nada de los 64 es «Color.clear como relleno que debería ser papel».

#### `.offset` (10) — casi todos defendibles

| Sitio | Uso |
|---|---|
| `CuerpoView.swift:82` | Arrastre (`dragX`) — gesto |
| `WeeklyPlanEditorView.swift:1072` | Offset de panel — interacción |
| `WorkoutDetailScreen.swift:478` | Reveal animado HRR |
| `TrainingBodyScreen.swift:706`, `:969`, `:972` | Marcas sobre geometría de dato |
| `LiveStrengthSheet.swift:1745` | Tick visual en control |
| `ReceiptPrinterScreen.swift:146`, `:153` | Ticket térmico (pieza propia) |
| `TrainingLoadStrip.swift:106` | Thumb sobre strip |

**Propuesta:** mantener fuera de gate; el volumen es bajo y el censo basta.

#### `.safeAreaPadding`

Cero hits. El riesgo listado en CONTRATO está **vacío hoy**. Sí hay `safeAreaInset` (`OnboardingPiezas.swift:624`, `LiveStrengthSheet.swift:271`, `:1103`, `RoutineSheet.swift:206`, etc.) — **ciego** para el colador actual.

**Propuesta:** o ampliar el censo a `safeAreaInset` (solo conteo), o retirar `.safeAreaPadding` de la lista de indecidibles «vivos».

---

### 2.B · Formas nuevas que nadie listó (ciegas al gate y al censo §1)

| Forma | Señal APP | Por qué evade | Ejemplos | Propuesta |
|---|---|---|---|---|
| **Opacidad vía `.fill(x.opacity(…))` / stroke / background** | `.fill(…opacity)` ~17; stroke+opacity ~24; background+opacity ~8; vs `.opacity(literal)` ~67 que **sí** ve `no-opacity-literal` | El regex solo mira `.opacity(` como modificador de vista | `EntrenarHubHeroe.swift:113` (`verdeCarga.opacity(subPillFondoAlfa)`); `HoyModosHost.swift:194` (exempt); `ExerciseDetailScreen.swift:988` (exempt 0.10); `ProgressionSetupScreen.swift:228` | Extender censo (AST ya podría) a `MemberAccess .opacity` bajo `fill`/`stroke`/`background`; no gatear a ciegas (muchas son dato/halo) |
| **`frame(minHeight: N)` decorativo** | Decenas; excluyendo 44 HIG quedan 46, 52, 56, 38, 40, 32, 96, 520… | `no-spacing-literal` no ve `minHeight` | `WeeklyPlanEditorView.swift:323` (52); `LiveStrengthSheet.swift:1783` (38); `WorkoutImportView.swift:560` (520); `AjustesView.swift:319` (32) | Censo de `minHeight`/`maxHeight` literales; tokenizar los que repiten (52/56) o `LiquidControl.hitTarget` donde sea 44 |
| **`blur(` suelto en APP** | Pocos pero expresivos | Fuera de `liquidGlass` | `HoyModosHost.swift:192` (halo 6+3×fase); `BreathingView.swift:349` (`LiquidSpace.s550` como radio de blur — **token de espacio usado como blur**) | Censo `blur(radius:`; regla: blur de superficie solo vía receta; Breathing/Hoy documentar o mover a token de efecto |
| **`LinearGradient` inline** | Varios en Screens sin exempt | No hay regla | `TrainingBodyScreen.swift:419` (`theme.muscleLoadRamp`); `Hoy/HojaDecideTuDia.swift:113`; `CuerpoView.swift:1695–1706` (campo — parte receta); `EntrenarView.swift:729` | Censo; gradientes de identidad → token/pieza; los de `LiquidCampo` ya encapsulados |
| **Overlay + stroke de borde a mano** | ~35 `.overlay(…stroke` en Cenit | `no-raw-shadow`/`no-sheet-glass` no cubren borde | `ActivityRecoverySheet.swift:203–204`; `RoutineSheetLiveFoco.swift:243`, `:287`, `:501`; `EntrenarHubHeroe.swift:123`, `:170`; `HojaDecideTuDia.swift:75` | Es el «canto» que `liquidGlass` ya compone — censo de strokeBorder Capsule/RoundedRect fuera de StrandDesign; lote hacia receta o `LiquidChip` |
| **`safeAreaInset`** | Varios sheets/live | Lista de indecidibles nombra otra API | Ver §2.A | Añadir al censo |
| **Composición material a mano en PKG** | `ultraThinMaterial` dentro de recetas | Esperado en StrandDesign | `LiquidGlassRecipes.swift`, `EntrenarVidrio`, `ConfirmCard` | OK **dentro** del paquete; el «cuándo no» de `liquidGlass` ya lo dice — vigilar solo APP (hoy APP casi no llama material crudo) |

---

### 2.C · Qué ven / no ven los 15 gates (mapa rápido)

| Gate | Ve | No ve (relevante a ejes 1–2) |
|---|---|---|
| `no-hex` / `no-raw-color` | `Color(hex:`, `Color.white/black` | Tonos vía `theme.*` Instrumento; opacidades en fill |
| `no-opacity-literal` | `.opacity(0.3)` | `.fill(c.opacity(0.3))`, stroke/background con opacity |
| `no-spacing-literal` | padding/spacing/lineWidth digit | `frame(width/height/minHeight:)`, offset, safeArea* |
| `no-radius-literal` | `cornerRadius: N` | `clipShape(RoundedRectangle(cornerRadius:))` parcial; radios en Path |
| `no-legacy-api` | Lista fija Instrumento/Paper/StrandPalette | Helpers que envuelven legacy; `theme.paper` sin símbolo listado; **piezas huérfanas del catálogo** |
| `no-sheet-glass` | `.liquidGlass(.superficie\|pastilla)` | Composición blur+material a mano; `.superficieSolida` |
| `token-exempt` | Cuenta exenciones | No valida que el motivo siga siendo cierto (eje 5) |
| — | — | **Rol de componente** (eje 1) — 100 % ciego |

---

## Veredicto global

### ¿Se usa bien el sistema?

**A medias.** Donde el inventario Liquid *nuevo* está cableado (hojas de métrica con `LiquidFranjaSeccion` + `LiquidCajita` + `LiquidOrigenChip` + `LiquidMetodo` + `LiquidRangeSelector`), el uso es coherente y el «cuándo no» clásico casi no se viola. El fallo estructural es otro: **el CATALOGO y varias piezas «estrella» (`LiquidMetricTile`, `StatePill`, `LiquidSectionHeader`, `StatTile`, Hypnogram/Calendario90 del índice) describen un sistema que la app ya abandonó**, y el sistema que sí corre no está indexado — así que «pieza equivocada» se manifiesta como **reinvento** (AppleHealth `liquidTile`, `confidenceChip`, tiles Entrenar) más que como call-site prohibido.

### ¿Qué se le escapa a los 15 gates?

1. Todo el eje de **rol de componente** (pieza A en rol de B; pieza muerta; pieza viva sin entrada).  
2. Indecidibles de geometría (ya asumido) — y el censo los **infla** con previews/AppMap.  
3. Opacidad cromática por **miembro** `.opacity` dentro de fill/stroke (bypass limpio de `no-opacity-literal`).  
4. `minHeight` / `blur` / gradientes / bordes overlay / `safeAreaInset`.

### Reparto del riesgo (ejes 1–2)

| Canal | % del riesgo de uso | Qué cubre |
|---|---|---|
| **Gateado** | **~25 %** | Literales y legacy listada; no evita H1.1–H1.5 |
| **Vigilado por censo** | **~35 %** | frame/clear/offset; útil si se re-etiqueta preview vs chrome |
| **Ciego** | **~40 %** | Catálogo desfasado, reinvento de tiles/estado, opacidades fill, minHeight, blur, gradientes, bordes |

### Acciones propuestas (prioridad)

1. **Lote CATALOGO vivo** — alta: `LiquidCajita`, `LiquidRangeSelector`, `LiquidFranjaSeccion`, `LiquidCalendario90`, `LiquidHipnograma`, `EntrenarTile`, `LiquidChecklistRow`; baja/retira: `LiquidMetricTile` (o aflojar API), `StatePill`, `LiquidSectionHeader`, `Hypnogram`/`Calendario90`/`YearHeatStrip` si Instrumento ya no las llama.  
2. **Censo: etiquetar preview/AppMap** en evasiones frame/clear; añadir `minHeight`, `blur(`, `safeAreaInset`, `.fill/.stroke(.opacity`.  
3. **Lote AppleHealth `liquidTile` → pieza del sistema** (extensión de MetricTile o Cajita+gota).  
4. **Una pastilla de estado Liquid** (o resucitar StatePill) para `confidenceChip` y similares.  
5. **No abrir gate regex** de `.frame`/`.offset`/`Color.clear` — el falso positivo mataría el trinquete; el censo bien etiquetado es la herramienta correcta.

---

## Apéndice · Inventario de call-sites (APP)

Conteo aproximado `rg` sobre `Cenit` + `CenitWidgets` + `CenitWatch` (hits / archivos), 2026-09-01:

| Pieza | Hits / files | En CATALOGO |
|---|---|---|
| `LiquidGlassButton` | 48 / 17 | sí |
| `LiquidCajita*` | ~39 / varios | **no** |
| `liquidGlass` | 33 / 17 | sí |
| `LiquidCalendario90` | ~31 / 5 | **no** (índice dice `Calendario90`) |
| `LiquidListRow` | 27 / 4 | sí |
| `LiquidRangeSelector` | ~23 / ~10 | **no** |
| `LiquidFranjaSeccion` | ~23 / ~10 | **no** |
| `SegmentedPillControl` | 17 / 9 | sí |
| `LiquidOrigenChip` | 16 / 11 | sí |
| `LiquidMetodo` | 15 / 12 | sí |
| `InstrumentoSectionBand` | 15 / 4 | vía legacy |
| `LiquidSheetHeader` | 7 / 6 | sí |
| `Sparkline` | 6 / 4 | sí |
| `SourceBadge` | 4 / 1 | sí |
| `LiquidTrendChart` | 1 / 1 | sí |
| `LiquidChipSeleccion` | 1 / 1 | sí |
| `LiquidTabBar` | 1 / 1 | sí |
| `LiquidMetricTile` / `StatePill` / `StatTile` / `LiquidSectionHeader` / `Hypnogram` / `Calendario90` / `YearHeatStrip` / `instrumentoCard` | **0** | sí (desfasados) |
