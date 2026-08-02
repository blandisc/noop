# «Liquid Glass v1» — el sistema de vidrio (handoff 2026-07)

> **Papel cálido + vidrio líquido + una sola voz verde.** Liquid Glass es la evolución del ADN
> «Instrumento diurno» para las pantallas rediseñadas: conserva sus axiomas (papel cálido, un
> dato dominante, **color solo en el dato**, jerarquía por espacio) y les suma una materialidad
> de vidrio con 4 recetas cerradas, una escala tipográfica Space Grotesk propia y un contrato
> de motion nombrado. La fuente de verdad hifi es el bundle
> `design_handoff_liquid_glass/` (viewport 402 pt); este doc mapea ese handoff a los tokens
> Swift reales.

- **Código canónico:** `Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/`
- **Entry points:** `LiquidColor` · `LiquidType` · `LiquidSpace` / `LiquidRadius` ·
  `LiquidElevation` + `liquidGlass(_:)` · `LiquidMotion` · `LiquidIcon`
- **Pantalla de referencia:** `LiquidHoyScreen` (§7.1 del handoff), armada 100 % por composición
- **Relación con Instrumento:** conviven en el mismo paquete; Liquid Glass es el lenguaje de las
  pantallas del rediseño 2026-07+. No mezclar recetas de vidrio Liquid con superficies
  Instrumento en una misma pantalla.

---

## 0. La regla del 90 %

Una pantalla se arma como Lego: **tokens → átomos → componentes → pantalla**.

- ≥ 90 % de la UI de una pantalla sale de componentes/modificadores reutilizables del sistema.
- Si algo no existe, primero se crea el componente en el sistema (con su `#Preview`), luego se
  usa en la pantalla. **No se dibuja one-off en la pantalla.**
- Prohibido en pantallas: hex, duraciones, radios, sombras o blur sueltos. Todo sale de tokens o
  de componentes que ya los encapsulan. (Las specs internas de un componente — el padding 7/12
  de un tile — viven DENTRO del componente, nunca en la pantalla.)

## 1. Color (`LiquidColor`)

| Grupo | Tokens | Regla |
|---|---|---|
| Tinta | `tinta900` `#221D16` · `tinta700` `#5C5648` · `tinta500` `#6F6857` · `tinta10` · `tinta7` | texto/trazos; alfas para tracks y divisores |
| Papel | `papelAlto` `#F8F6EF` · `papelBajo` `#F0EDE4` · `papelDock` · `papelGradient` | fondo de pantalla = degradado alto→bajo |
| Verde (única voz de marca) | `verdePrimario` `#0C8F62` · `verdeProfundo` `#00774B` · `verdeAurora` `#2EB27D` (SOLO halos) · `verdeOrbe` · `verdeBotonAlto` | CTA, énfasis, palabra del hero, pulsos |
| Tonos de dato (1:1, no intercambiables) | `indigo`→sueño · `cian`→HRV · `rosa`→FC reposo · `ambar`→esfuerzo/temp. piel · `teal`→pasos · `azul`→respiración · `oro`→amanecer | **el tono tiñe SOLO la gota (10–12 % alfa) y el valor numérico — nunca el fondo de la tarjeta** |
| Semánticos | `positivo` `#00774B` · `atencion` `#C4631F` · `negativo` `#B3402A` | deltas y estados (`LiquidDeltaTone`, `LiquidSignalState`) |
| Partículas del Ecosistema (FER-10) | `particulaVerde` `#10694E` · `particulaRoja` `#963426` · `particulaNeutra` `#737670` · `rojoClaro` `#E06C56` | tinta de las esferas de partículas del héroe (verde=rango/atención, roja=desgaste, neutra=calibrando/guardián) y el rojo claro del clima de alerta |
| Blancos de vidrio | `vidrioEspecular` .92 · `vidrioBorde*` .72–.9 · `vidrioStreak` .55 · `vidrioLente` .5 · `vidrioPastilla` .45 · `vidrioSuperficie` .30 | alfas fijos de `#FFFFFF`; solo los consumen las recetas |

## 2. Tipografía (`LiquidType`)

Space Grotesk (la voz ya empaquetada, vía `InstrumentoType.grotesk`) para display, valores,
labels y botones; SF para cuerpo y captions. Cada token trae su tracking hermano; los
MAYÚSCULAS se aplican con los helpers `Text.liquidKicker()/liquidLabel()/liquidMicro()`.

`displayXL` 54/700 −1.9 (legado hero) · `displayL` 30/700 (palabra del veredicto FER-10) · `displayM` 40/700 · `displayS` 22/700 −0.5 («Conociéndote»: la calibración habla más bajito) · `orbita` 8/600 +2.2 (SOLO etiquetas in-canvas del Ecosistema, exenta de Dynamic Type como los glifos) · `valorL` 20/700 tabular ·
`titulo` 15/700 · `tituloFila` 13/600 · `cuerpo` SF 12.5 · `kicker` 11/600 +2 MAYÚS ·
`unidad` SF 11 tinta/500 · `caption` 9/500 · `label` 8.5/600 +1.2 MAYÚS · `micro` 8/700 +0.8 ·
`microEstado` 7.5/600 · `boton` 14/600 +0.2 · `tab(active:)` SF 10 400/600.

**Aproximaciones documentadas:** SwiftUI no fija line-height, así que el hero logra el 0.96 del
handoff apilando líneas con `displayXLLineSpacing` (−17) y `cuerpo` aproxima 1.55 con
`cuerpoLineSpacing` (4).

## 3. Espaciado y radios (`LiquidSpace` / `LiquidRadius`)

Escala cerrada base 4 con medios pasos: `s050`=2 · `s100`=4 · `s150`=6 · `s200`=8 · `s300`=12 ·
`s400`=16 · `s550`=22 (**margen H de pantalla**) · `s800`=32 · `s1400`=56 (**safe-area top**);
dock: `dockSide`=16, `dockBottom`=14. `ecosistemaAlto`=324 (la zona del héroe FER-10; sustituye a `senalGap`/`senalesAlto`, retirados con la fila de orbes).

Cinco radios, ninguno más: `control`=12 · `tarjeta`=18 · `hoja`=28 (reservado sheets) ·
`pastilla`=999 (`Capsule`) · orbe=50 % (`Circle`). **Un radio nuevo es un cambio al sistema.**

## 4. Vidrio (`liquidGlass(_:)` — 4 recetas cerradas, nunca blur suelto)

Cada receta es el stack completo: material + relleno blanco + borde + inner-highlight
(+ especular) + sombra. En nativo el backdrop-filter se calibra con materiales del sistema
(§8 del handoff): `.ultraThinMaterial` para superficie/pastilla, `.thinMaterial` para lente.

| Receta | API | Composición | Sombra |
|---|---|---|---|
| velo | `LiquidVeil` (vista) | blur + degradado de papel, máscara de desvanecimiento 55 %→100 % | — |
| superficie | `.liquidGlass(.superficie)` | blanco .30, borde .72, highlight .8→.35, r/tarjeta | e/0 |
| pastilla | `.liquidGlass(.pastilla)` / `.pastillaElevada` | blanco .45, borde .8, highlight superior, r/pastilla | e/0 / e/1 |
| lente | `.liquidGlass(.lente)` | papelDock, anillo interior 4 lados, **streak especular**, r/pastilla | e/3 |
| esfera | `LiquidSphere(tone:)` | radial blanco→tono .22, borde .9, especular elíptico | e/2(tono) |

Elevación (`LiquidElevation`): `e0` reposo · `e1` tarjeta · `e2(tone:)` señal (glow del tono) ·
`e3` flotante — vía `.liquidShadow(_:)`. Ninguna pantalla escribe `.shadow` a mano.

## 5. Motion (`LiquidMotion` — el contrato)

**Tokens primero, cero `0.3`/`.easeInOut` crudos en features. Animar estado, no frames.**

| | Tokens |
|---|---|
| Duraciones | `instant` 120 ms · `quick` 240 ms · `gentle` 420 ms · `sheetDuration` 560 ms · `flowPeriod` 9 s · `driftPeriods` 16–26 s |
| Easings | `glassOut(_:)` cubic-bezier(0.2, 0.6, 0.2, 1) · `glassSpring(_:)` (0.34, 1.4, 0.4, 1) · `ambient(_:)` ease-in-out · `flowLinear(_:)` linear (SOLO pulsos que viajan) |

Recetas (las pantallas solo consumen esto):

- **press** — `.buttonStyle(.liquidPress)`: scale 0.97 · instant · glass-out. Todo tappable.
- **lift** — `.liquidLift(tone:)`: −2 pt + e/0→e/2(tono) · quick. Solo plataformas con puntero.
- **entrada** — `.liquidEntrada(index:)`: fade + rise 8 pt · gentle · stagger 60 ms entre
  hermanos. Los bloques de Hoy la usan en cascada (header→orbes→hero→carga→tiles).
- **sheet** — `LiquidMotion.sheet` + `sheetTransition`: 560 ms glass-spring (API lista).
- **ring progress** — `ringProgress` (gentle): SignalOrb y el knob de CargaBar animan a su
  valor al entrar, con `Shape.trim` / `animatableData` — nunca Core Animation.
- **drift** — `driftProgress(time:period:reverse:)` sobre `TimelineView`: orbes de fondo,
  translate(28, 20) + scale 1.1, alternate, 16–26 s. Nunca por debajo de 9 s.
- **flow** — `flowPulseProgress(time:delay:)`: el pulso viaja el cable cada 9 s (delays
  0/0.8/1.6) dibujado con `trim`. *Desviación deliberada:* el `stroke-dash` animado del
  prototipo se reemplazó por `trim` — el dash de CoreGraphics renderea segmentos falsos
  sobre estas béziers y `trim` es la gramática nativa equivalente.

- **Ecosistema (FER-10)** — `LiquidEcosistemaMotion` + `EcosistemaSimulacion` (física pura,
  testeable): **fusión** (viaje 1.55 s back-out s=1.35, stretch direccional 16 %, destello con
  8 chispas en el contacto, asentamiento 4·e^(−2.5τ)·sin(11τ)), **separación** (anticipación
  0.22 s squeeze 5 %; pegajosa — no se re-une hasta el siguiente tap), **órbita** (lunas
  0.85/−0.6 rad/s, guardián 0.32), **acreción** (34 espirales, caída ≈18 s), **eclipse**
  (1.8 s — el guardián deja su órbita SOLO con `.juntas`) y **ambiente** (crossfade
  monocromo 1.6 s, que SÍ se conserva bajo Reduce Motion).

**Reduce Motion (no negociable):** `drift`/`flow` se congelan, `entrada` degrada a crossfade
simple, los progresos aparecen colocados. Los consumidores leen `accessibilityReduceMotion`;
para previews/tests existe `\.liquidMotionDisabled` (además congela la UI ya asentada, porque
`ImageRenderer` no dispara `onAppear`).

## 6. Iconografía (`LiquidIcon` + `SVGPathData`)

Sin librería de iconos: cada glifo guarda el **path SVG exacto del handoff** (stroke 1.4–1.8,
round caps) y un parser interno (M/L/H/V/C/S/Q/A/Z, arcos→béziers) lo convierte a `Path`.
Catálogo: 8 métricas (`luna onda corazon llama pasos termo resp estres`), 3 señales
(`*Senal`), 5 modos (`rayo envivo intervalo movilidad respira`), `chevron`. Los glifos del
TabBar viven en `LiquidTabBar` (viewBox 23). Tests de bounds por glifo en `LiquidGlassTests`.

## 7. Átomos, componentes y patrones

**Átomos:** `LiquidIconDrop` (gota 22/13 al 10 %; 28/15 al 12 % en ModeTile) ·
`LiquidDeltaCaption` · `LiquidSphere`.

**Componentes (contrato = props del handoff §5):**

| Componente | Props clave |
|---|---|
| `LiquidMetricTile` | label · value · unit · delta · deltaTone · tone · icon (· action) |
| `LiquidEcosistema` (FER-10) | senales · hero · guardian · ambiente · calibracion · rotulos (`EcosistemaRotulos`) · heroPuerta/Hint · fusionInicial · onTapVeredicto/onTapSenal — el héroe de esferas de partículas; física en `EcosistemaSimulacion` (pura, `particula(i:)` determinista = spec del shader de Fase B) |
| `LiquidCargaBar` | label · pos 0–100 · zone 0–3 · status · state |
| `LiquidTabBar` | active: hoy/tendencias/entrenar/ajustes (· onSelect) |
| `LiquidGlassButton` | label · variant: primary/glass/quiet (· expands · action) |
| `LiquidModeTile` | label · icon · tone (· action) |
| `LiquidListRow` + `LiquidListCard` | title · subtitle · trailing? · tone · divider |

**Patrones (se componetizan al aparecer en una 3.ª pantalla):** `LiquidAmbientBackground`
(aurora + orbes drift para otros presets) · `LiquidHoyAmbient` (FER-10: el preset `.hoy` es
MONOCROMO — tres manchas del color del veredicto, crossfade 1.6 s; la aurora y el índigo se
retiraron de Hoy) · `LiquidVeil` · `LiquidScreenHeader` · `LiquidDialSeal` (24 h: noche
índigo, día tinta, marcador verde). *Retirados con el Ecosistema:* `LiquidSignalOrb`,
`LiquidSignalCables`, `LiquidHeroVeredicto/Demotado` (Hoy era su único consumidor).

**Pantalla de referencia:** `LiquidHoyScreen` + `LiquidHoyModel` (estado del §9; `.ejemplo` =
datos del ensamble). Orden §7.1: fondo → cabecera → señales → hero → CargaBar → grid 2×4 de
tiles → velo + TabBar. Previews con y sin motion.

**Composición en app (FER-1045):** `LiquidHoyContent` es la columna COMPONIBLE — sin
ScrollView, sin TabBar, sin fondo ni safe-areas propios; el app es dueño del scroll
(pull-to-sync), del dock y monta `LiquidAmbientBackground` detrás. Acciones por id estable
(`onTapMetric/onTapSenal/onTapCarga/onTapHero`). El modelo habla por estados: `Hero`
(.veredicto con `highlightTone` / .demotado), `Senal.progress: Double?` (nil = SIN DATOS),
`Carga?` (.medida / .calibrando / ausente), dial con noche opcional y `origen` por métrica.
`\.liquidAmbientPaused` (scenePhase) congela drift/pulsos en background. En Cénit, el puente
de datos reales es `LiquidHoyBuilder` (app layer): proyección pura del estado ya derivado,
con paridad probada por fixtures.

## 8. Desviaciones documentadas vs. el prototipo HTML

1. **Pulso de cables con `trim`, no stroke-dash** (§5 arriba). Mismo periodo/delays/largo.
2. **SignalOrb: arco y punto reconciliados.** El HTML rotaba el arco a −155° pero calculaba el
   punto con −245°, dejando el punto 90° detrás del extremo. Se sigue la fórmula documentada y
   la prosa del README («en el extremo del progreso»): arco desde −245° (las ~7:30 del dial) y
   punto EN el extremo.
3. **Line-height:** aproximado con spacing negativo/positivo (§2), porque SwiftUI no lo fija.
4. **Backdrop blur:** materiales del sistema calibrados, como pide el propio handoff §8; los
   inner-shadows de CSS se aproximan con trazos interiores en degradado blanco.
5. **e/2 en atención:** el prototipo usaba alfa 0.20 para el glow ámbar del orbe; el sistema usa
   la spec única de `e/2` (0.18) para no bifurcar el token.
6. **`LiquidHill` — excepción sancionada a «color solo en el dato».** La colina de la hoja de
   Carga (`LiquidHill`) conserva su lenguaje de zonas coloreadas del `LoadHillView` de
   «Instrumento»: cuesta y cresta en verde, descenso en ámbar, caída en rojo. Rompe a propósito
   la regla del datum único (§0/§1) porque el color de zona ES la identidad del instrumento —
   el usuario lee la topografía por color. Decisión del dueño (2026-07-24), tras comparar contra
   un bullet-graph neutro. Es la ÚNICA superficie Liquid con esta excepción; no se extiende a
   otros componentes.

7. **Periodos orbitales del Ecosistema < 9 s.** Las lunas (T≈7.4/10.5 s) y el guardián
   viven bajo el piso de 9 s del drift ambiental — sancionado (FER-10): la órbita es DATO
   coreografiado (las señales que alimentan el veredicto), no ambiente. El piso de 9 s
   sigue gobernando el fondo.
8. **El lienzo del Ecosistema es un sistema cerrado 364×324** (`EcosistemaSimulacion.Geometria`)
   escalado al ancho disponible — specs internas de componente (regla §0), no tokens de
   `LiquidSpace`; mismo precedente que los paths de los cables retirados.

## 9. Cómo extender el sistema

1. ¿Falta un token? Se agrega a `LiquidColor`/`LiquidType`/`LiquidSpace`/`LiquidMotion` con doc
   y (si es visual) `#Preview` — nunca inline en la pantalla.
2. ¿Falta un componente? Se crea en `LiquidGlass/` con props explícitas + `#Preview`, y la
   pantalla lo instancia.
3. ¿Un patrón se repite en una tercera pantalla? Se promueve a componente con contrato.
4. Motion nuevo = receta nueva en `LiquidMotion` con su token de duración/easing y su
   comportamiento bajo Reduce Motion definido. No existe otra gramática de movimiento.
