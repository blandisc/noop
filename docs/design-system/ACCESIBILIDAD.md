# Accesibilidad

> Compañero de [`DESIGN.md`](DESIGN.md) y [`LENGUAJE.md`](LENGUAJE.md). Documenta la práctica de
> accesibilidad **que la app ya sigue y prueba** — contraste, Dynamic Type, VoiceOver, movimiento
> reducido y áreas táctiles — con sus reglas, dónde viven en el código, y la **deuda conocida** (lo
> que aún no está cubierto). No propone un estándar nuevo: describe el vigente y lo hace auditable.
>
> Cénit no es un dispositivo médico. Accesibilidad aquí = usable con VoiceOver, Dynamic Type, alto
> contraste y Reduce Motion, en una app iOS de **Liquid Glass · El Eje** (vidrio teñido sobre
> lienzo blanco). El contraste AA del vidrio teñido (`LiquidTono` × rol) se documenta en
> [`LIQUID-GLASS.md` §4.1](LIQUID-GLASS.md); las pantallas de papel de la generación anterior
> («Instrumento diurno», absorbida · en migración) siguen midiendo contra `paper` mientras migran.

---

## 1. Contraste (WCAG AA)

**Regla:** cada par texto/fondo libra WCAG AA, con **dos pisos según el tamaño**:

| Piso | Cuándo aplica | Ejemplo |
|---|---|---|
| **3:1** (AA texto grande, ≥24 pt) | Numerales de dato y direccionales | numeral del héroe, dial, valores de gráfica |
| **4.5:1** (AA texto normal, <24 pt) | Tinta y deltas chicos | `positiveText`/`negativeText`, cuerpo |

**Cómo se verifica (tres capas):**

1. **Helper WCAG en el generador de tokens** — `CenitDesignTokens/main.swift` hace su propia
   matemática sRGB→lineal→luminancia→ratio, la fórmula canónica `(L1+0.05)/(L2+0.05)`. La columna
   `ratio` de la tabla de color en `DESIGN.md` §8.2 (inventario Instrumento en migración) es ese
   contraste medido contra `paper`.
2. **Tests de contraste** que fijan ratios exactos:
   - `FitnessAgeContrastTests.swift` — numerales del héroe ≥ **3.0** (verdict/paper = 3.63,
     warning/paper = 4.62, fijados con precisión 0.1 para que el spec no mienta).
   - `InstrumentoThemeEngineTests.swift` — prueba que `verdict` **no** libra el piso de 4.5 a 12 pt
     y que `positiveText` **sí** (por eso `positiveText`/`negativeText` son reparaciones OKLab más
     oscuras de `verdict`/`critical` para deltas chicos). Aplica al inventario de papel aún en
     migración.
   - `LiquidTonoContrasteTests.swift` — contrato AA del **vidrio teñido** unificado: `rotulo`
     ≥ 4.5:1 sobre `mix(#FFFFFF, base, 0.10)`; `tesela` ≥ 3:1 sobre relleno opaco (ver
     [`LIQUID-GLASS.md` §4.1](LIQUID-GLASS.md)).
3. **Tabla documentada** en `DESIGN.md` §8.2 (generada, no editable a mano; generación anterior
   en migración).

**Tokens deliberadamente NO-AA** (documentados como tal, no son bug):
- `inkDim` — celdas sin dato: el «—» y su glifo. Bajo contraste a propósito.
- `inkMuted` — el chrome más callado: tabs inactivas (FER-708).

> **Nota histórica:** la regla **«AA a cada hora»** venía del tema por hora (FER-132) de la
> generación «Instrumento diurno», donde el papel cambiaba a lo largo del día y cada tono de
> dato se re-oscurecía contra el papel vivo. Ese motor se **retiró en FER-398**; el inventario
> de papel que aún migra usa un solo `.base`. No lo cites como comportamiento vigente del marco
> canónico (Liquid Glass · El Eje).

---

## 2. Dynamic Type

**Regla (FER-394):** el texto de lectura escala con la preferencia del usuario; los numerales
pegados a geometría **no**. La decisión está codificada y comentada en `Typography.swift:10-17`.

| Escala (anclado a `Font.system(.textStyle)`) | Fijo a propósito (geometría / chrome) |
|---|---|
| `title1/2/3`, `headline`, `body`, `subhead`, `caption`, `footnote`, `unit`, `overline`, `mono`, `bodyNumber`, `captionNumber`, serif (vía `UIFontMetrics`) | `display()` (numeral del anillo), `number()`, `tabTitle` (pareado a glifo 22×22, debe alinear al deslizar), `GlyphSize` (SF Symbols), `micro` (11 pt) |

- **Por qué fijo:** un numeral dentro del anillo de recuperación o del dial no puede moverse con
  Dynamic Type sin romper la geometría. El chrome de tabs debe conservar tamaño para alinear.
- **Techo:** la app **cap­a el rango superior en xxxLarge** en la raíz.

> **Deuda conocida:** no hay snapshot ni preview que ejercite `.dynamicTypeSize` grande. El split
> fijo/escala se garantiza por construcción (qué token mapea a qué text style), no por un render de
> tipo grande. Candidato a issue: agregar un snapshot a AX5/xxxLarge.

---

## 3. VoiceOver

**Regla:** todo lo que comunica significado tiene nombre hablado; lo decorativo se oculta. Uso real
(conteos en `Cenit/` + `CenitDesign`): `accessibilityLabel` 251, `accessibilityElement` 177,
`accessibilityHidden` 87, `accessibilityValue` 44, `accessibilityHint` 41.

**Patrones establecidos:**

- **Valor hablado con contexto**, no solo el número. `ContributionBars`: `accessibilityValue =
  "te rejuvenece 1.8 años"` en vez de «−1.8».
- **Componer hijos en un elemento:** `.accessibilityElement(children: .combine)` en pantallas de
  detalle (`WorkoutDetailScreen`, `StrainDetailScreen`, `MuscleMapScreen`); `.ignore` donde los
  hijos son decorativos.
- **Ocultar lo decorativo — consistente:** SF Symbols y dibujos con `.accessibilityHidden(true)`
  (`StatePill` glifo, `ThermalTicket`, `ECGWave`, `GraficaRangos`, glifos de estado vacío).
- **El numeral honesto habla:** el placeholder `—` de `MetricRow` → label «no reading today» (no
  lee «guion»).

> **Deuda conocida:** solo el `—` tiene label hablado dedicado. Los otros glifos honestos (`··`
> calibrando, `~N` estimado) dependen del label del elemento que los rodea. Candidato a issue: dar
> label hablado a `··` («calibrando») y `~N` («estimado, ~N»). `accessibilityRepresentation` no se
> usa (0).

**Al construir un componente nuevo:** dale `accessibilityLabel` a lo que significa, `accessibilityValue`
si carga un número que se lee mejor con palabras, y `accessibilityHidden(true)` a cada glifo/dibujo
decorativo. Compón con `.accessibilityElement(children: .combine)` cuando varias piezas son una idea.

---

## 4. Movimiento reducido (Reduce Motion)

**Regla:** todo lo animado respeta `accessibilityReduceMotion` — o salta al estado final, o no anima.
El movimiento se reserva para lo que está vivo (el «ahora», una lectura en vivo); ver filosofía en
`BreathingDot.swift`.

Tres patrones vigentes (en `ContributionBars`, `BodyAgeBand`, `RecoveryZoneGauge`, `FiveRules`,
`BreathingDot`):

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// A) proteger el withAnimation
if animated && !reduceMotion { withAnimation(StrandMotion.drawIn) { drawn = true } }

// B) ramificar al estado final al instante
if reduceMotion { drawn = true } else { withAnimation(StrandMotion.drawIn) { drawn = true } }

// C) precomputar un bool
let animating = animateEntrance && !reduceMotion
```

> **Deuda conocida:** el patrón es correcto pero **copy-paste por sitio** — `StrandMotion` define
> curvas (`drawIn`, `breathe`), no una compuerta de reduce-motion. Candidato a issue: un modifier
> compartido (p. ej. `.strandEntrance(_:reduceMotion:)`) que encapsule el gate, para no depender de
> recordarlo en cada pantalla nueva.

---

## 5. Áreas táctiles

**Regla:** mínimo **44 pt** de blanco táctil (HIG).

- Token central: `Metrics.control = 44` en `Components.swift`. La variante «alta» del control
  segmentado crece a 44 pt.
- `CompactTrendToggle`, `SegmentedPillControl`, `QuietButton` y el scrub de gráficas documentan el
  mínimo de 44 pt en `DESIGN.md §…` (44pt/«toca, no hover»).
- `contentShape` se usa 141× para extender el área de toque más allá de lo dibujado.
- Interacción es **toque, no hover** (press-drag para el scrub + háptico de selección).

---

## 6. Checklist para una pantalla/componente nuevo

- [ ] Cada par texto/fondo libra su piso AA (3:1 numeral ≥24pt, 4.5:1 texto). Si agregas un color,
      corre `swift run CenitDesignTokens` y revisa el `ratio` en la tabla.
- [ ] El texto de lectura usa tokens de `StrandFont` que escalan; solo la geometría usa los fijos.
- [ ] VoiceOver: labels en lo que significa, valores hablados en números clave, `accessibilityHidden`
      en lo decorativo.
- [ ] Toda animación se ramifica bajo `accessibilityReduceMotion`.
- [ ] Blancos táctiles ≥44 pt (`Metrics.control` / `contentShape`).

---

## 7. Deuda conocida (resumen — candidatos a issue)

| Hueco | Dónde | Severidad |
|---|---|---|
| Sin snapshot de Dynamic Type grande (AX/xxxLarge) | `Typography.swift` (solo por construcción) | media |
| `··` y `~N` sin label hablado dedicado | numeral honesto | media |
| Reduce Motion copy-paste, sin helper central | 5 componentes | baja/media |
| `accessibilityRepresentation` sin usar | — | baja |

---

### Ver también
- [`DESIGN.md`](DESIGN.md) — marco canónico Liquid Glass · El Eje; §8.2 (tabla de contraste del inventario Instrumento en migración), split fijo/escala, 44pt.
- [`LIQUID-GLASS.md`](LIQUID-GLASS.md) §4.1 — contrato AA del vidrio teñido (`LiquidTono` / `LiquidRegimen`).
- [`LENGUAJE.md`](LENGUAJE.md) §5.6 — «el numeral nunca miente» (base del label honesto).
- [`I18N.md`](I18N.md) — internacionalización.
