# Auditoría B2 — Contrabando, el paquete por dentro y exenciones (MITAD 2)

> **Solo reporte.** Cero cambios a Swift/CI/linter/baselines.  
> **Issue:** FER-279 · **rama:** `grok/fer-279b2-uso-1788282407-76269-1258`  
> **Fecha:** 2026-09-01 · **carril:** uso del sistema (ejes **3–5**; ejes 1–2 = otro lane).  
> **Complementa:** `AUDITORIA-SISTEMA.md` (FER-279C, mapa de eras del paquete).

## Qué leí

| Insumo | Para qué |
|---|---|
| `docs/design-system/CONTRATO.md` | Matriz de 15 gates, carve-outs, taxonomía `token-exempt`, indecidibles |
| `docs/design-system/CATALOGO.md` | Roles / cuándo-no; tokens FER-273 reflejados |
| `docs/design-system/CENSO.md` (`8f08a6342cf0`) | §2 exempts, §5 deuda por generación |
| `Tools/check-design-drift.py:100–155` | Regex de las 15 reglas; `RE_LEGACY_API` exacto |
| `Tools/design-drift-baseline.json` | Deuda congelada (`no-legacy-api` = **161** hits / **54** archivos) |
| `docs/design-system/AUDITORIA-SISTEMA.md` | Mapa de eras — no se re-litiga; se cruza |
| Commit `93d3105d` (FER-273) | Qué piezas se acuñaron **sin** aplicar a call-sites |
| Árbol vivo | `rg` sobre `Cenit/**`, `CenitApp`, `CenitWidgets`, `CenitWatch`, `Packages/StrandDesign/Sources` |

## Método

- **Eje 3:** lo que `RE_LEGACY_API` ve → símbolos/helpers/`theme.*` de Instrumento/papel **fuera** de esa lista → ¿baseline o ciego?
- **Eje 4:** StrandDesign post-FER-273: piezas sin consumidor, duplicados de valor, huérfanos.
- **Eje 5:** muestra de **20** `token-exempt`; motivo vs tokens que ya existen (FER-273/275).

---

## Eje 3 · Contrabando de generación

### Qué ve el gate (y qué no)

`Tools/check-design-drift.py:107–111` solo matchea:

```
InstrumentoTheme | InstrumentoFlowTitle | InstrumentoToolChip | InstrumentoTabHeader
| PaperStepper | SectionBand | InstrumentoSectionBand | StrandPalette
| .instrumentoTheme(
```

Raíces: `Cenit/{Screens,Onboarding,System,App,Data,LiveActivity,Media}`.  
**Fuera:** `Packages/StrandDesign` (definiciones), `CenitWidgets`/`CenitWatch` (carve-out), **`CenitApp`** (no está en las raíces).

Live vs baseline de esos símbolos: **161/161, 54/54 — sin contrabando *dentro* de la lista**. El riesgo está en lo que la lista no nombra.

### Hallazgos (rankeados por impacto)

#### C3-1 · CRÍTICO — `InstrumentoType` es la tipografía Instrumento viva e invisible al gate

| | |
|---|---|
| **Evidencia** | **130** hits / **31** archivos APP (`Cenit`+`CenitApp`). Top: `WorkoutHistoryScreen.swift` (19), `ExerciseDetailScreen.swift` (14), `LiveStrengthSheet.swift` (11). También en territorio Liquid: `Hoy/HoyModosHost.swift:113,151,155`, `TodayView.swift:68,942`, `EntrenarView.swift:677,838,1154,1286`. |
| **Por qué escapa** | `InstrumentoType` **no** está en `RE_LEGACY_API`. El gate ve `InstrumentoTheme` / `StrandPalette`, no la familia tipográfica. |
| **Propuesta** | Ampliar `no-legacy-api` con `\bInstrumentoType\b` (+ alta legal de baseline con el conteo actual) **o** lote `/migracion` tipografía → `LiquidType` / `StrandFont` y luego prohibir. Preferible: gate + baseline (congela) y lote que baje el trinquete. |

#### C3-2 · CRÍTICO — `theme.paper` / `theme.ink` sin el símbolo `InstrumentoTheme` en la línea

| | |
|---|---|
| **Evidencia** | **~284** hits de `theme.(paper\|ink\|…)` solo en `Cenit/Screens`+`App`. Patrón típico: `@Environment(\.instrumentoTheme) private var theme` una vez → cientos de `theme.ink` que el regex de legacy **no** cuenta (solo `\bInstrumentoTheme\b` / `\.instrumentoTheme(`). Ej.: `SessionKeypad.swift:113–115`, `TrainingBodyScreen.swift:330–334`, `ShareCardView.swift:26–28`. |
| **Por qué escapa** | El consumo cromático de la era papel pasa por el Environment alias `theme`, no por el nombre del tipo. |
| **Propuesta** | No hay regex barato sin FP. **Vigilancia por censo** (ya clasifica por símbolo importado, `CENSO.md` §5) + regla de proceso: pantalla Liquid nueva no introduce `@Environment(\.instrumentoTheme)`. Lote: migrar `theme.*` → `LiquidColor.*` pantalla a pantalla. |

#### C3-3 · ALTO — Helpers que envuelven API vieja (el regex ve el wrapper, no la era)

| Helper | Hits APP | Archivo definición | ¿En `RE_LEGACY_API`? |
|---|---|---|---|
| `instrumentoConfirm(` | **15** / 10 files | `ConfirmCard.swift:50` | **No** |
| `instrumentoOverline()` | **54** | `Instrumento.swift:449` | **No** |
| `instrumentoHero(` | **6** | `Instrumento.swift:442` | **No** |
| `instrumentoOverlineProminent()` | **1** | `Instrumento.swift:458` | **No** |
| `instrumentoInput(` | **2** | `InputCard.swift:18` | **No** |
| `sheetPaper(` | **2** (refs/comentarios; ManualWorkout lo retiró) | `SheetPaper.swift:28` | **No** |

Ejemplos call-site: `AppMap.swift:544` (`.instrumentoConfirm`), `LiveStrengthSheet.swift:1071` (`.instrumentoOverline`), `WeeklyPlanEditorView.swift:156` (`.instrumentoInput`).

| | |
|---|---|
| **Propuesta** | Extender `RE_LEGACY_API` con `\binstrumento(Confirm|Overline|Hero|Input|OverlineProminent)\b|\.sheetPaper\(`; baseline + lote de reemplazo (`LiquidType.kicker` / `LiquidSheet` / diálogo Liquid). |

#### C3-4 · ALTO — `CenitMetrics` dialecto Instrumento dentro de hubs ya Liquid

| | |
|---|---|
| **Evidencia** | `Entrenar/EntrenarHub*.swift` y `CuerpoView.swift:291` usan `CenitMetrics.space1/space2/gap/cardGap` en pantallas del universo Liquid Glass. Ej.: `EntrenarHubPar.swift:41`, `EntrenarHubHeroe.swift:96,136,151`, `EntrenarHubConstancia.swift:72` (`CenitMetrics.space1 + 2` — además roza `no-token-arithmetic`). |
| **Por qué escapa** | `CenitMetrics` **no** es legacy-api; es el dialecto de espacio «Instrumento» compartido. Gate de spacing solo ve literales, no el nombre de familia. |
| **Propuesta** | Ya cubierto como ruta de consolidación en `AUDITORIA-SISTEMA.md` §1 (alias valor-neutral). Acción: lote Fase 1 CONTRATO en hubs Liquid (`CenitMetrics.space2` → `LiquidSpace.s200`, etc.) — no regla nueva. |

#### C3-5 · MEDIO — `StrandPalette` vivo fuera de raíces gateadas + residuales en Screens

| | |
|---|---|
| **Evidencia** | `CenitApp/App/RootTabView.swift:209` — `.tint(StrandPalette.accent)` (**`CenitApp` no está en raíces `legacy`**). En raíces: `ProgressionSetupScreen.swift:140`, `SessionKeypad.swift:306` (`StrandPalette.disabledOpacity`) — sí gateados/congelados. `StrandOpacity.dim` es el token canónico equivalente (`Palette.swift:207`). |
| **Propuesta** | (1) Añadir `CenitApp` a raíces `legacy`/`exempt` **o** aceptar carve-out documentado. (2) Lote de 2 call-sites: `StrandPalette.disabledOpacity` → `StrandOpacity.dim`. |

#### C3-6 · MEDIO — Tipografía Instrumento en pantallas ya «Liquid» (contrabando de generación, no solo deuda)

| | |
|---|---|
| **Evidencia** | `HoyModosHost.swift:113` / `:151` / `:155` — `InstrumentoType.grotesk` en el host de modos de Hoy (DNA Liquid). `TodayView.swift:68,942`. Misma generación tipográfica que el papel, sobre lienzo El Eje. |
| **Propuesta** | Issue de polish acotado (N≤10): esos call-sites → `LiquidType` / `StrandFont` body. No esperar al lote masivo de C3-1. |

#### C3-7 · BAJO — Lo que el gate sí congela (sin sorpresa)

Símbolos de la lista en APP (conteo vivo, dentro de raíces):  
`InstrumentoSectionBand` 15 · `InstrumentoFlowTitle` 6 · `PaperStepper` 4 · `InstrumentoToolChip` 4 · `InstrumentoTabHeader` 1 · `LiquidMenu` / `LiquidMenuItem` (WeeklyPlan, Hoja, Library…; migrados desde PaperMenu en FER-283).  
`StatTile` / `.instrumentoCard` — **0 consumidores APP** (solo PKG + preview).  
Baseline monótono: OK.

---

## Eje 4 · El paquete por dentro

Cruce con `AUDITORIA-SISTEMA.md` (FER-279C). Aquí solo lo que afecta **uso** y piezas **post-FER-273**.

### Hallazgos

#### C4-1 · ALTO — `LiquidSectionHeader` acuñado y huérfano de APP

| | |
|---|---|
| **Evidencia** | Definición `LiquidGlass/LiquidSectionHeader.swift:20`. Catálogo: «reemplazo Liquid de `InstrumentoSectionBand`». **0** usos en `Cenit`/`CenitApp`. Mientras: `InstrumentoSectionBand` sigue vivo — `WeeklyPlanEditorView.swift:211,399,442`, `WorkoutHistoryScreen.swift:460,505,607,763,828,874,1070,1126` (15 hits). Commit FER-273 lo declaró: adoptar es `/migracion`, no del acuñado. |
| **Propuesta** | Lote `/migracion` de los **15** call-sites → `LiquidSectionHeader` (pantallas Instrumento que migren, o wrap valor-neutral si el kicker ya calza). Hasta entonces: pieza «muerta al nacer» en el catálogo. |

#### C4-2 · ALTO — Tokens FER-273/275 casi sin wrap; exenciones siguen diciendo «sin token»

| Token | Definición | Usos APP (aprox.) | Cluster CENSO que debía absorber |
|---|---|---|---|
| `LiquidSpace.chipHorizontal` (=9) | `LiquidLayout.swift:89` | **1** | horizontal/chip handoff |
| `LiquidSpace.seccionCanto` / `filaRespiro` (=10) | `:97` / `:103` | **1** cada uno | edge ≠ rowVPad |
| `LiquidSpace.handoff14` / `handoff44` | `:109` / `:115` | **4** / **2** | 14 / 44 del handoff |
| `LiquidChip.compactoHorizontal/Vertical` | `:168` / `:170` | **4** sitios (ExerciseDetail + ProgressionSetup) | chip 11/5 |
| `LiquidType.cuerpoBanner` | `LiquidType.swift:163–164` | **0** APP | cuerpo de banner 13pt |

| | |
|---|---|
| **Propuesta** | Lote de wrapping Fase 1 (checklist CONTRATO: igualdad exacta + test de valor). Baja exempts y baja baseline `token-exempt` / `no-spacing-literal` / `no-adhoc-font` según el caso. Ver Eje 5. |

#### C4-3 · MEDIO — `StatTile` / `instrumentoCard` / `StatePill` sin consumidor APP

| Pieza | APP | Notas |
|---|---|---|
| `StatTile` | 0 (solo comentario `MetricCatalog.swift:57`) | Catálogo aún lo enseña para Instrumento |
| `.instrumentoCard` | 0 APP (solo preview PKG) | Candidato a borrar tras quitar preview — alineado con Auditoría C |
| `StatePill` | **0** APP / 14 PKG | Catálogo lo recomienda vs `LiquidOrigenChip`; nadie en app lo usa |
| `SourceBadge` | 2 APP | Vive |
| `LiquidOrigenChip` | 16 APP | Vive |

| | |
|---|---|
| **Propuesta** | `StatePill`: o se adopta donde `SourceBadge`/chips ad-hoc duplican rol, o se marca «solo PKG/preview» en CATALOGO. `StatTile`/`instrumentoCard`: dejar morir cuando cierre `/migracion` del último tema Instrumento (decisión ya en DECISIONS). |

#### C4-4 · MEDIO — Diez (=10) con muchos nombres, rol poco claro fuera del par decidido

Además del par **decidido** `seccionCanto` / `filaRespiro` / `rowVPad` (misma cifra, roles distintos — CONTRATO):

- `CenitMetrics.insetRadius` = 10 (`Components.swift:39`)
- `CenitMetrics.headerGap` = 10 (`:81`)
- `WidgetMetrics` / `HomeWidgetMetrics` dayLabel/weekGap = 10
- `EntrenarHubMetrics.cuerpoGap` / `historialFilaGap` / `restTrackTop` = 10
- Varios privados de chart (`altoBarra`, `margenV`, …) = 10

| | |
|---|---|
| **Propuesta** | No mintear más roles=10. Documentar en CATALOGO el mapa «10pt → qué rol»; privados de chart se quedan. `EntrenarHubMetrics.*Gap=10` → candidatos a `LiquidSpace.s250` o `filaRespiro` si el rol calza (lote hub). |

#### C4-5 · BAJO — Huérfanos ya reportados en Auditoría C (no re-auditar)

Capa z-index huérfana (archivo ya ausente del árbol), `StrandElevation` (casi solo PKG: `TodayBanner.swift:90`, `InputCard.swift:143`). Ruta: dejar morir. Sin hallazgo nuevo.

#### C4-6 · BAJO — Tres opacidades «disabled» distintas

| Símbolo | Valor | Archivo |
|---|---|---|
| `StrandOpacity.dim` | 0.45 | `Palette.swift` (canónico) |
| `StrandPalette.disabledOpacity` | 0.45 | `Palette.swift:43` (alias legacy) |
| `PaperStepper.disabledOpacity` | **0.35** | `PaperStepper.swift:72` (privado) |
| `CenitMetrics` N/A | — | — |
| `Widget` path | — | — |

| | |
|---|---|
| **Propuesta** | Call-sites APP → `StrandOpacity.dim`. El 0.35 de PaperStepper es deuda local del componente legacy. |

---

## Eje 5 · Anotaciones `token-exempt` (muestra 20)

**Universo:** ~228 hits / 63 archivos (APP+PKG+Widgets). Forma categorizada `token-exempt(...)`: **~14**; forma bare `token-exempt:`: **~187**.  
Criterio de «obsoleta»: el motivo dice *no hay token* / *candidato* / *sin token exacto* y **hoy el token existe con igualdad exacta** (FER-273/275), o el wrap ya ocurrió en sitios hermanos.

### Tabla de muestra (20)

| # | Archivo:línea | Motivo actual | ¿Sigue cierto? | Token / realidad | Acción propuesta |
|---|---|---|---|---|---|
| 1 | `ExerciseDetailScreen.swift:789` | «14 del handoff…» | **No** (falta wrap) | `LiquidSpace.handoff14` | Wrap → bajar exempt |
| 2 | `LiveStrengthSheet.swift:1072` | «sin token exacto (edge ≠ rowVPad)» | **No** | `LiquidSpace.seccionCanto` (canto post-header) | Wrap |
| 3 | `LiveStrengthSheet.swift:1087` | idem | **No** | `seccionCanto` (Divider) | Wrap |
| 4 | `LiveStrengthSheet.swift:1092` | idem | **No** | `filaRespiro` / `seccionCanto` | Wrap (elegir rol) |
| 5 | `LiveStrengthSheet.swift:1095` | «sin token… (cardPadding candidato)» | **No** — `CenitMetrics.cardPadding` **ya existe** y se usa en `:1081` | `CenitMetrics.cardPadding` / `LiquidSpace.s400` | Wrap; motivo mentía |
| 6 | `WorkoutHistoryScreen.swift:183` | «cardPadding candidato» | **No** | idem 16pt | Wrap |
| 7 | `WorkoutHistoryScreen.swift:1613` | idem | **No** | idem | Wrap |
| 8 | `WorkoutImportView.swift:97` | idem | **No** | idem | Wrap |
| 9 | `LiveStrengthSheets.swift:362` | idem (vertical 16) | **No** | idem | Wrap |
| 10 | `WorkoutHistoryScreen.swift:179` | «cuerpo de banner (13pt…)» | **No** | `LiquidType.cuerpoBanner` (**0** usos APP) | Wrap cluster ×6+ |
| 11 | `SaveErrorToast.swift:33` | idem | **No** | idem | Wrap |
| 12 | `StarterTemplatesSheet.swift:83` | idem | **No** | idem | Wrap |
| 13 | `WeeklyPlanEditorView.swift:127` | idem | **No** | idem | Wrap |
| 14 | `WorkoutImportView.swift:585` | «44 del handoff / touchTarget» | **Parcial** | `LiquidSpace.handoff44` (rol layout; no `hitTarget`) | Wrap con `handoff44` |
| 15 | `WorkoutImportView.swift:599` | idem | **Parcial** | idem | Wrap |
| 16 | `TrainingBodyScreen.swift:333` | «sin token… (horizontal/chip handoff)» **11/5** | **No** | `LiquidChip.compactoHorizontal/Vertical` — ya usado en `ExerciseDetailScreen.swift:338,548,592` | Wrap hermano |
| 17 | `ExerciseDetailScreen.swift:236` | «edge ≠ rowVPad» (padding 10) | **No** | `filaRespiro` / `seccionCanto` | Wrap |
| 18 | `ExerciseDetailScreen.swift:454` | idem | **No** | `seccionCanto` | Wrap |
| 19 | `TrainingBodyScreen.swift:283` | idem | **No** | `seccionCanto` | Wrap |
| 20 | `WorkoutHistoryScreen.swift:655` | «horizontal/chip handoff» **9/3** | **Parcial** | H=`chipHorizontal` (9); V=3 → `LiquidSpace.s075` si rol calza, si no queda `falta-pieza` honesta | Wrap H; revisar V |

### Controles que **sí** siguen válidos (fuera de la tabla de 20, para no sesgar)

- `ExerciseDetailScreen.swift:1023` / `:1045` — `token-exempt(dato):` geometría de gráfica (34) — **válido**.
- `DataSourcesView.swift:617–621` — radio 4 geometría de dato — **válido**.
- `ProgressionSetupScreen.swift:224` — `opacity(0.001)` hit-testing — **válido** (`unico`/`sistema`).
- `WiggleEffect.swift:40,42` — `token-exempt(unico):` springs escénicos — **válido** (FER-278).
- `OnboardingPiezas.swift:645` — velo que arranca en opacidad 0 — **válido**.

### Lectura del eje 5

De la muestra de 20: **~16 obsoletas o parcialmente obsoletas** (el token ya existe; la anotación quedó de adorno o el motivo «sin token» es falso). **~4 parciales** (un eje del padding ya tiene token, el otro no).  
Patrón de clase: FER-273/275 acuñó tokens **sin** lote de wrap → el censo y las exempts siguen narrando 2026-08.  
**Propuesta de clase (no una a una):** un issue «Lote wrap FER-273 residuales» que (1) reemplace literales donde hay igualdad exacta, (2) borre o reescriba el `token-exempt`, (3) baje el baseline. Las que queden deben cambiar el motivo a algo cierto (`optico`, `dato`, o `falta-pieza` solo si *aún* no hay token).

---

## Veredicto global

### Cobertura del riesgo (contrabando + deuda disfrazada de «uso del sistema»)

| Capa | Qué cubre bien | % del riesgo (ejes 3–5) |
|---|---|---|
| **Gateado** (15 reglas + baseline monótono) | Lista corta de símbolos Instrumento/Paper; literales de spacing/font/radius/opacity/motion; conteo de exempts; `CenitApp` **no** entra en legacy | **~30 %** |
| **Vigilado por censo** | Generación por símbolo (`CENSO.md` §5: Cenit 20 archivos Instrumento); clusters ×3 de exempts; evasiones indecidibles | **~25 %** |
| **Ciego** | `InstrumentoType` (130); `theme.*` (~284); helpers `instrumento*`; `CenitMetrics` en hubs Liquid; exempts post-token; `StrandPalette` en `CenitApp`; `LiquidSectionHeader` huérfano | **~45 %** |

### Tres movimientos que más bajan el riesgo ciego

1. **Regla:** meter `InstrumentoType` + helpers `instrumento(Confirm|Overline|Hero|…)` en `no-legacy-api` (+ alta legal de baseline).  
2. **Lote:** wrap de residuales FER-273/275 (tabla Eje 5) — baja exempts mentirosas y enseña los tokens.  
3. **Migración acotada:** `InstrumentoSectionBand` → `LiquidSectionHeader` (15 sitios) + tipografía Instrumento en Hoy/Today (C3-6).

### Lo que este lane **no** cubrió

Ejes 1–2 (pieza equivocada; evasiones `.frame`/`.offset`/`Color.clear`) — otro lane.  
No se ejecutó `verify.sh` / build / test (prohibido por spec).

---

## Apéndice · Conteos crudos (reproducibles)

```bash
# InstrumentoType
rg -c --glob '*.swift' '\bInstrumentoType\b' Cenit CenitApp

# theme.* cromático
rg -c --glob '*.swift' '\btheme\.(paper|ink|muted|accent|border|card)\b' Cenit/Screens Cenit/App

# Helpers
rg -c --glob '*.swift' '\binstrumento(Confirm|Overline|Hero|Input)\b' Cenit CenitApp

# Legacy gateado vs baseline
python3 -c "import json; b=json.load(open('Tools/design-drift-baseline.json')); print(sum(b['no-legacy-api'].values()), len(b['no-legacy-api']))"

# Exempts banner 13pt aún literales
rg -n 'token-exempt: cuerpo de banner' Cenit --glob '*.swift'
```
