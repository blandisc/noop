<!-- Requerimiento FER-118 · «Hoy en atmósfera». v6, convergido tras 5 rondas adversariales (Sonnet + Opus; DeepSeek sin saldo y Grok con límite de uso, sustituidos por Opus). Espeja el código de los PRs A–F (#1264–#1268 + F). Fuente viva del texto: este archivo; el issue FER-118 en Multica lleva la misma versión. Prototipo aprobado por el dueño: prototipo-atmosfera.html (junto a este archivo). -->

# FER-118 · Hoy en atmósfera: fondo blanco con partículas vivas (Metal), el orbe viaja con el scroll y encima vidrio modular en tres estantes

**Versión:** 6 (tras las rondas adversariales 1–5 — 24 + 35 + 23 + 20 + 11 hallazgos aplicados; espeja el código ya implementado en los PRs A–E, verificado premisa por premisa contra `fer-118-impl`) · **Fecha:** 2026-08-17 · **Carril:** PESADO
**Estado del issue:** `todo` → este documento sustituye la descripción actual de FER-118.
**Prototipo aprobado (fuente visual de verdad):** artifact `31fada67-ad06-42dc-a989-95f34ec3f03c` · repo: rama `fer-118-hoy-atmosfera` → `design-handoff/hoy-en-blanco/prototipo-atmosfera.html`.

> Cómo leer esto. Es un requerimiento **de implementación autónoma**: otra sesión debe poder
> construirlo sin preguntarle nada al dueño. Por eso (a) cada decisión de diseño que el prototipo
> dejaba abierta está TOMADA aquí, con su razón (§13), (b) cada símbolo/archivo citado existe hoy en
> el repo (mapa en §8) y (c) el trabajo va en 6 PRs ordenados con criterios y tests por PR (§9).
> Si al implementar encuentras una contradicción entre este texto y el código actual, **manda el
> código actual para los datos y este texto para el envase** — y anótalo en el PR.

---

## 0. Resumen ejecutivo

Hoy (la pantalla) cambia de envase, no de datos ni de honestidad:

1. **El fondo pasa a BLANCO PURO** (`LiquidColor.papelTarjeta`, #FFFFFF) y detrás de todo,
   **fijas respecto al scroll**, viven **partículas de polvo pintadas por Metal** (deriva lenta hacia
   arriba, respiran, toman el color del veredicto, se mueven un 22 % con el scroll — parallax).
   Se retira la aurora/orbes drift (`LiquidAmbientBackground.hoy`) de Hoy.
2. **El héroe (`LiquidEcosistema`, 320 pt) NO cambia y viaja con el scroll** como hoy. Al bajar,
   solo quedan las partículas atrás del vidrio.
3. **La Matriz deja de ser tinta con filos** y pasa a **módulos de vidrio** (receta nueva
   `.superficieAtmosfera`: blanco al 30 % + blur real + borde de tinta al 8 %) en **cuadrícula de 2
   columnas dentro de tres estantes con «?»**: *Deciden tu día* (Sueño · FC en reposo) · *Te vigila*
   (Guardián, ancho) · *Contexto* (Carga · Esfuerzo / VFC · Estrés / Pasos ancho). El estante
   «Bitácora» desaparece (Pasos entra a Contexto).
4. **El guardián cambia de gráfica**: de «la costura» a **«los dos hilos de puntos»** (una fila de
   puntos por señal, uno por noche, con la banda de tu rango detrás; la noche en que las dos se
   salen va ámbar y anudada; HOY late).
5. **Scrub en las 8 gráficas con los dígitos rodando** (lo que ya existe, extendido al par del
   guardián) + un hint de barrido la primera vez.
6. **Micro-momentos**: entrada en cascada de los módulos, vidrio que cede al presionar
   (`.liquidPress`), color del veredicto con crossfade de 1.6 s en las partículas.

Todo lo demás de Hoy —héroe, franja de estado, aviso de Salud desconectada, hojas, acta, dock, las
7 gráficas restantes, la lógica del builder, las 105 lecciones de FER-110— **se conserva tal cual**.

---

## 1. Contexto y decisiones cerradas del dueño (no re-litigar)

**Por qué.** El dueño rechazó la aurora y quiere una pantalla «simple, minimalista y elegante, en la
intersección de liquid y las hojas de detalle de Tendencias, inclinando a liquid». Tras 5
iteraciones (franjas de vidrio ✗ · módulos de hoja ✗ · Public/Robinhood ✗ · Tide con orbe-fondo y
halo ✗) quedó **esta** dirección, aprobada sobre un prototipo interactivo:

| Decisión del dueño (textual o casi) | Consecuencia en este requerimiento |
|---|---|
| «quiero que el fondo sea blanco» · «quita los blobs de color del fondo» | Fondo #FFFFFF; sin aurora, sin halo, sin degradado, sin plasta. |
| «solamente sean partículas vivas, las que están flotando en Metal» | La única vida del fondo son las partículas; capa Metal. |
| «El orbe se queda donde está. Cuando bajas, lo único que ves son las partículas» | El héroe scrollea con el contenido; el fondo fijo son SOLO las partículas. |
| «Va, dale con el 30 %» (tras ver 10 % / 30 % / 55 %) | Vidrio blanco al 30 %. Condición del dueño (§12): blur REAL; si cae a sólido, subir a 45 %. |
| «un solo teléfono» · «guardián con dos hilos de PUNTOS (uno por noche) y el rango esperado visible» | Nueva gráfica `MatrizHilos`. |
| «asegúrate de que no estamos perdiendo ninguno de los que tenemos hoy» | Las 8 señales presentes; Pasos ancha abajo. |
| «esos dos botones de arriba … no sirve» | Sin botones nuevos arriba. |
| «Vamos a quitar la funcionalidad de que los puedas mover» · «pones el mismo signo de interrogación que tenemos» | Sin widgets movibles; el «?» de los estantes es el actual (`questionmark.circle`, fila entera tocable). |
| «quita lo de "no vota" … que sea más elegante» | Sin sello «vota»/«no vota» por tarjeta: la sección dice quién vota. |
| «los números deberían tener el mismo efecto que tienen ahorita» | `numericText` + `.snappy` se conservan y se extienden al par del guardián. |
| «no se te olvide darle scrub a todas las gráficas» | Scrub en las 8: siete ya lo tenían (FER-62/73); **Pasos no traía `scrubNoches`** → el builder le da su scrub (14 días · fecha, como Esfuerzo). |

**Se descartó, con razón (no volver):** franjas de vidrio de lado a lado; widgets
movibles/redimensionables; botones de notificaciones/historial arriba; leyenda de colores bajo el
guardián; el orbe como fondo fijo con halo (el dueño lo retiró: «el orbe se queda donde está»);
vidrio al 55 % (no revelaba nada) y al 10 % (el fondo competía con las gráficas en días ámbar/rojo).

---

## 2. Objetivo (verificable)

Con la app en el estado `primed` (fixture) en un iPhone 17 Pro simulado, iOS 26, es-MX: la
pantalla Hoy muestra fondo blanco con partículas Metal moviéndose detrás de tres estantes de módulos
de vidrio al 30 % que revelan esas partículas al hacer scroll (el héroe se va con el scroll, las
partículas no), el guardián dibuja dos hilos de puntos con su banda, y las 8 gráficas responden al
scrub con el número rodando — **sin que ningún módulo afirme sobre el cuerpo algo que hoy no
afirma** (los 14 estados del arnés se ven completos y su copy no cambia).

---

## 3. Alcance / fuera de alcance

**Dentro:** todo lo listado en §0, en Hoy (pestaña `.today` → `TodayView`), iOS 17+ (imitación de
vidrio) e iOS 26 (vidrio nativo), es y en, Reduce Motion, Dynamic Type hasta xxxLarge (tope de la app), VoiceOver.

**Fuera (NO tocar en este issue):**
- El héroe (`LiquidEcosistema`, su simulación, sus rótulos, la entrada de arranque, la palabra, la ⓘ, la pastilla «Connect Health»).
- Las hojas (acta, guardián, manuales «?», hojas de métrica), el dock (`LiquidTabBar`), el velo (`LiquidVeil`) salvo quitarle el tinte, `HealthAlertBanner`, `AvisoDesconexion`, el pull-to-sync.
- Cualquier cambio a **datos, cálculo, copy del cuerpo o umbrales** (`LiquidHoyBuilder*`, `HoyGramatica`, `Preparedness`) — salvo los 5 cambios de builder listados en §5.6 (orden de bandas, sublabel del scrub del guardián, retiro de `vota`, retiro de `terciaria`, alta de `scrubPasos`).
- Las 4 deudas abiertas de FER-47 (valores de 14 días como «hoy», lectura de día con guardián en pareja, permiso revocado invisible, «sin lectura de hoy» con dos causas).
- El fondo de las otras pestañas y de las hojas (`LiquidAmbientBackground.tablero`, `LiquidSheetFondo`); el tema oscuro (legacy).
- Widgets movibles, botones arriba, notificaciones, cualquier red.

---

## 4. Anatomía de la pantalla nueva (de arriba a abajo) y qué cambia

```
┌─ TodayView.iosBody ───────────────────────────────────────────────────────────┐
│ .background { LiquidAtmosfera(ambiente:, estado:) }   ← NUEVO (blanco + polvo Metal, fijo)
│ .overlay(top) { LiquidVeil(tone: nil) }               ← CAMBIA solo el tono (nil)
│ GeometryReader → ScrollView (pull-to-sync igual)      ← se le suma la lectura del offset para el parallax
│  ├ HealthAlertBanner                                   (igual)
│  ├ LiquidHoyContent = kicker de fecha + LiquidEcosistema (héroe 320 pt)   (IGUAL, scrollea)
│  └ HoyMatrizHost                                       (igual: franja de estado / aviso; margen 24)
│      └ MatrizHoyFace                                   ← CAMBIA la composición:
│          estante «Deciden tu día» ?  →  [Sueño][FC en reposo]        (vidrio 30 %, 2 col)
│          estante «Te vigila» ?       →  [Guardián · ancho · dos hilos de puntos]
│          estante «Contexto» ?        →  [Carga][Esfuerzo] / [VFC][Estrés] / [Pasos · ancho]
│ .overlay(bottom) LiquidTabBar (RootTabView, igual)
└──────────────────────────────────────────────────────────────────────────────┘
```

Lo que **desaparece**: `LiquidAmbientBackground.hoy` en Hoy (aurora + 3 orbes drift), los filos de
1 px (`filo()`), el sello «vota», el estante «Bitácora», el chevron `›` de cada sección, la gráfica
«costura».

---

## 5. Especificación por componente

### 5.1 El fondo: `LiquidAtmosfera` (blanco + polvo Metal, fijo, con parallax)

**Qué es.** Una vista de StrandDesign, `public struct LiquidAtmosfera: View`, que pinta (a) el
blanco `LiquidColor.papelTarjeta` a pantalla completa y (b) encima un campo de N partículas de
polvo, cada una un disco suave, que derivan lentamente hacia arriba, respiran en alfa, toman el color
del veredicto y se desplazan con el scroll a un 22 %. Va **detrás** del `ScrollView` de Hoy como
`.background`, `.ignoresSafeArea()`, `.allowsHitTesting(false)`.

**API (Swift, StrandDesign):** (nota: es el PRIMER uso de `@Observable`/`import Observation` dentro
del paquete —hoy todo es `ObservableObject`—; compila bajo `StrictConcurrency` con iOS 17/macOS 14
como mínimos del paquete, y el `swift build` + el build iOS del PR B son quienes lo certifican).
```swift
/// El estado que la pantalla empuja al fondo sin recomponerse entera por cada cuadro de scroll.
@MainActor @Observable public final class AtmosferaEstado {   // import Observation (iOS 17+/macOS 14+)
    /// contentOffset.y del scroll de Hoy, ≥ 0 (0 = tope; el overscroll del pull NO cuenta).
    public var desplazamiento: CGFloat = 0
    /// false cuando la pestaña Hoy no está en pantalla (onDisappear) → el reloj se detiene.
    public var visible: Bool = true
    public init() {}
}

public struct LiquidAtmosfera: View {
    public init(ambiente: LiquidAmbiente, estado: AtmosferaEstado)
}
```
`LiquidAmbiente` es el enum existente (`bien · atencion · alerta · neutro`, `LiquidPatterns.swift`)
que Hoy ya calcula (`TodayView.liquidAmbiente`, `LiquidHoyBuilder.ambiente(prep:)`).

**La física del polvo — `PolvoSimulacion` (pura, Foundation-only, ES LA SPEC; el shader la
espeja).** Nuevo archivo `Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/PolvoSimulacion.swift`:

```swift
public enum PolvoSimulacion {
    public enum Fisica {                       // tokens; los mismos viajan al shader en el uniform
        public static let ptPorParticula: CGFloat = 234   // 402×874/1500 del prototipo
        public static let nMin = 600, nMax = 2000
        public static let radioMin: CGFloat = 0.6, radioMax: CGFloat = 2.3
        public static let alfaBase: Double = 0.07, alfaRango: Double = 0.24
        public static let densidadPiso: Double = 0.35        // arriba (detrás del héroe) hay menos
        public static let densidadDesde: Double = 0.23, densidadHasta: Double = 0.80 // fracciones de H
        public static let respiracionAmp: Double = 0.28      // alfa·(0.72 + 0.28·sin)
        public static let respiracionWMin: Double = 0.5, respiracionWRango: Double = 0.9  // rad/s
        public static let derivaXMax: Double = 2.1           // pt/s, simétrica
        public static let derivaYMin: Double = 0.9, derivaYRango: Double = 3.0  // pt/s hacia ARRIBA
        public static let parallax: CGFloat = 0.22
        public static let alfaNeutra: Double = 0.55          // en calibración/sin veredicto
        public static let bordeFade: Double = 40             // los 4 bordes se desvanecen (ver abajo)
        public static let umbralClima: Double = 0.80         // 80 % clima · el resto en 4 cuartos (satélites)
        // CPU-only (NO viajan al shader): `ptPorParticula`, `nMin`, `nMax` — solo los usa
        // `cuenta(lienzo:)`, y al shader llega `n` ya calculado como `uint`.
    }
    public struct Particula: Equatable, Sendable { public let centro: CGPoint; public let radio: CGFloat
                                         public let alfa: Double; public let tono: Tono }
    public enum Tono: Equatable, Sendable { case clima, reposo, sueno, vigiaTemp, vigiaResp, neutra }

    /// Cuántas partículas caben en un lienzo (área/ptPorParticula, acotado).
    public static func cuenta(lienzo: CGSize) -> Int
    /// Hash determinista entero → [0,1). MISMA aritmética uint32 (con wrap) en Swift y en MSL:
    ///   wang(x): x = (x ^ 61) ^ (x >> 16); x = x &* 9; x = x ^ (x >> 4); x = x &* 0x27d4eb2d; x = x ^ (x >> 15)
    ///   hash(i, k) = Double(wang(i &* 0x9E3779B1 &+ k &* 0x85EBCA77)) / 4294967296.0
    public static func hash(_ i: UInt32, _ k: UInt32) -> Double
    /// La partícula `i` en el instante `t` (segundos desde que el fondo apareció), en un lienzo
    /// de tamaño `lienzo`, con `desplazamiento` de scroll y `neutra` (sin veredicto).
    public static func particula(indice: Int, t: TimeInterval, lienzo: CGSize,
                                 desplazamiento: CGFloat, neutra: Bool, still: Bool) -> Particula
    // La cuenta `n` NO es parámetro: la decide `cuenta(lienzo:)` en el Canvas y el
    // `instanceCount` en Metal.
}
```
Reglas de `particula(...)`, con `h(k) = hash(UInt32(i), k)`:
- Base: `x0 = h(0)·W`, `y0 = h(1)·H`; `radio = radioMin + h(2)·(radioMax − radioMin)`.
- Deriva (si `!still`): `vx = (h(6) − 0.5)·2·derivaXMax`, `vy = −(derivaYMin + h(7)·derivaYRango)`;
  `x = wrap(x0 + vx·t, W)`, `y = wrap(y0 + vy·t − parallax·desplazamiento, H)` (wrap = módulo
  positivo; el parallax también envuelve, así el campo es infinito). Con `still` (Reduce Motion /
  `liquidMotionDisabled`): `t` se toma como 0 y `desplazamiento` como 0. **Los bordes se
  desvanecen**: `alfa *= fade(x)·fade(W − x)·fade(y)·fade(H − y)` con `fade(d) = smoothstep(0,
  bordeFade, d)`, `Fisica.bordeFade = 40` pt — sin esto una mota que sale por arriba (densidad 0.35,
  tenue) reaparece abajo (densidad 1, brillante) con un salto de alfa de 3× en un cuadro, y el campo
  «infinito» se ve como un cielo que parpadea en los dos bordes.
- Densidad por altura: `f = densidadPiso + (1 − densidadPiso)·clamp((y/H − densidadDesde)/(densidadHasta − densidadDesde), 0, 1)`
  con la `y` YA envuelta (así detrás de la cuadrícula siempre hay más polvo que detrás del héroe).
- Alfa: `alfa = (alfaBase + alfaRango·f)·(0.5 + 0.5·h(3))·resp·(neutra ? alfaNeutra : 1)`, con
  `resp = still ? 1 : (1 − respiracionAmp) + respiracionAmp·sin(w·t + φ)` (o sea el alfa oscila
  entre 1 − 2·amp = 0.44 y 1, como en el prototipo), `w = respiracionWMin + h(4)·respiracionWRango`, `φ = 2π·h(5)`.
- Tono: `neutra → .neutra`; si no, `k = h(8)`: `k < umbralClima (0.80) → .clima`; si no, `[.reposo, .sueno, .vigiaTemp, .vigiaResp][Int((k − 0.80)/0.05)]` (acotado al último).
- `cuenta = clamp(Int(W·H / ptPorParticula), nMin, nMax)` (iPhone 17 Pro 402×874 → 1 501, `Int` trunca).

**Colores.** El mismo objeto de paleta del héroe: `EcosistemaPaleta.desde(clima:)`
(`EcosistemaPaleta.desde(clima:)`, `EcosistemaMetal.swift`, fuera del `#if canImport(Metal)`) — `clima` por ambiente: `.bien → LiquidColor.particulaVerde`,
`.atencion → particulaAmbar`, `.alerta → particulaRoja`, `.neutro → particulaNeutra` (exactamente
los que usa `Coreografia.tintaClima` para el héroe), `sueno`/`reposo`/`vigiaTemp`/`vigiaResp` = las identidades
besadas 70/30 de la paleta, `neutra` = `particulaNeutra`. Así héroe y polvo comparten un solo
diccionario de color. **Crossfade al cambiar de veredicto:** 1.6 s (`LiquidEcosistemaMotion.ambienteCrossfade`),
interpolando la paleta en sRGB dentro del renderer (guarda `desde`, `hacia`, `inicio`). **Con `still`
(Reduce Motion / renders) el cambio es INSTANTÁNEO** (duración 0): el reloj del polvo está pausado y un
crossfade no podría avanzar nunca — el color del veredicto se ve al momento. Y el `t` que viaja al
renderer es SIEMPRE el real de sesión (nunca congelado en 0): `still` congela posición y respiración
por su cuenta, en la spec y en el shader.

**Reloj y pausas.** Cada backend con SU reloj: el Metal con un
`TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente /* 20 Hz */, paused:))` — 20 Hz
basta para derivas de 1–4 pt/s (movimiento sub-pixel entre cuadros) y cuesta un tercio que 60 Hz —
y el Canvas de respaldo con el suyo a `intervaloSello` (12 Hz). `paused = ambientPaused || !estado.visible || still`, con
`ambientPaused = @Environment(\.liquidAmbientPaused)` (Hoy ya lo pone en `true` con hoja abierta,
app en background u onboarding tapando — `TodayView.swift`, `.environment(\.liquidAmbientPaused, …)`) y `still = reduceMotion || liquidMotionDisabled`.
Además el lienzo Metal se redibuja **bajo demanda** cuando cambia `estado.desplazamiento` (parallax
sigue al dedo aunque el reloj vaya a 20 Hz): `updateUIView → setNeedsDisplay()`, mismo patrón que
`EcosistemaMetalLienzo`. `t` = `date.timeIntervalSince(inicio)` con `inicio` fijado en `onAppear`
del fondo (NO `timeIntervalSinceReferenceDate`: ver la advertencia de `EcosistemaFisicaU` sobre la
precisión de `Float`; con `t` de sesión (< 1 día) un `Float` resuelve 0.02 pt en `vx·t` y 0.01 rad
en `w·t`, suficiente). **Cota del reloj:** `inicio` se re-basa cuando el polvo REANUDA (`onChange(of: paused)` → `false`)
si la sesión ya pasó de `LiquidAtmosfera.maxSesion` = 3600 s: Hoy puede vivir días en background y
a ~10 días de `t` el ULP de un `Float` (0.06) ya cuantiza una deriva de 0.1 pt/cuadro; el salto de
las motas a su posición inicial ocurre en un instante en que nadie las mira. **Cómo llega el desplazamiento al Metal:** `updateUIView` NO es un ámbito
rastreado por Observation — solo corre cuando SwiftUI re-evalúa el representable. Por eso
`AtmosferaMetalLienzo` recibe `desplazamiento: CGFloat` y `t` como PROPIEDADES ALMACENADAS, y es
`LiquidAtmosfera.body` quien lee `estado.desplazamiento` (eso registra la dependencia); leerlo
dentro de `updateUIView` daría parallax cero sin ningún error.

**Arranque de Metal.** `LiquidAtmosfera.onAppear` llama `EcosistemaMetal.compartido.preparar()`
(idempotente) — dentro de `#if os(iOS) && canImport(MetalKit)`, y observando `EcosistemaMetal.compartido`
con `@ObservedObject` bajo la misma guarda (patrón de `LiquidEcosistema.swift:1089/1103`; el paquete
compila para watchOS, donde Metal no existe): en T4/T5 el héroe NO es `LiquidEcosistema` (es `LiquidOrbeDormidoEstado`/la puerta
de conectar) y nadie más habría compilado el shader — sin esto el polvo viviría en Canvas para
siempre en esos estados.

**La paleta.** `EcosistemaPaleta` (SIMD puro, sin tipos de Metal) sale del bloque
`#if canImport(Metal)` de `EcosistemaMetal.swift`: la usan el uniform y el Canvas de respaldo, que
también compilan en watchOS (donde Metal no existe) — sin moverla, el build del Watch truena.

**Backend Metal.** Reusar la infraestructura de FER-13 (`EcosistemaMetal.compartido`, la librería
que se compila en runtime desde `EcosistemaShaders.msl`):
- En `EcosistemaShaders.msl` (**es UNA sola librería**: un error de compilación en `vsPolvo` tumba
  también el Metal del héroe, porque `makeLibrary(source:)` compila el archivo entero; por eso el
  gate de este PR es el test offscreen `testElShaderCompilaYPintaAlgo` + los tests nuevos del polvo,
  y en DEBUG ya existe la `assertionFailure` que hace visible un shader roto): `struct PolvoU` (espejo campo a campo de `EcosistemaPolvoU`, orden
  idéntico, sin `bool`, con padding explícito a múltiplo de 16 B) y `vertex VOut vsPolvo(uint vid [[vertex_id]], uint iid [[instance_id]], constant PolvoU &u [[buffer(0)]])`
  que evalúa **la misma** `particula(...)` (mismo hash Wang en `uint`, mismas fórmulas) y emite el
  quad del disco reutilizando `quadNube`/`fsTrazo` (grosor 0 → disco con AA). Ningún número mágico
  en el shader: radios, alfas, velocidades, densidad, parallax viajan en `PolvoU` desde
  `PolvoSimulacion.Fisica`.
- En `EcosistemaMetal.swift` (los uniforms viven FUERA de `#if canImport(Metal)`, como los del
  héroe): `struct EcosistemaPolvoU`, **campo por campo y en este orden** (stride 192 B, múltiplo
  de 16; los offsets clave se afirman en el test): `colorClima`, `colorNeutra`, `colorReposo`,
  `colorSueno`, `colorVigiaTemp`, `colorVigiaResp` (6 × `SIMD4<Float>` = 96) · `lienzo`
  (`SIMD2<Float>`, offset 96) · `t`, `desplazamiento` (`Float`, 104/108) · los 16 tokens de
  `Fisica` que viajan, como `Float`: `radioMin`, `radioMax`, `alfaBase`, `alfaRango`,
  `densidadPiso`, `densidadDesde`, `densidadHasta`, `respiracionAmp`, `respiracionWMin`,
  `respiracionWRango`, `derivaXMax`, `derivaYMin`, `derivaYRango`, `parallax`, `alfaNeutra`,
  `umbralClima` (112…172) · `neutra`, `still` (`UInt32`, 176/180) · `bordeFade` (`Float`, 184) ·
  `_p1` (`UInt32`, 188). Espejo textual `PolvoU` en el `.msl` (colores `clima`, `neutra`, **`reposo`, `sueno`**,
  `vigiaTemp`, `vigiaResp` como `float4` — **el mismo orden que el struct Swift, campo a campo**: dos
  `SIMD4` transpuestos conservan stride y offsets y el layout-test NO lo caza, por eso el test afirma
  el offset de CADA color, 0/16/32/48/64/80; `lienzo: float2`; `t`, `desplazamiento` y los 16 tokens
  de `Fisica` como `float`; `neutra`, `still` como `uint`; `bordeFade` como `float`; `_p1` de padding
  — **`n` NO viaja en el uniform: es el `instanceCount` del draw**);
  `Recursos` gana `let polvo: MTLRenderPipelineState?` — **opcional a propósito**: si el pipeline
  del polvo no se arma, el héroe NO pierde su Metal (hoy `armar()` devuelve `nil` en cadena si un
  pipeline falla; el del polvo se construye aparte y su fallo solo manda al polvo al Canvas) —
  (vertex `vsPolvo`, fragment `fsTrazo`, mismo blending premultiplicado); `final class
  EcosistemaPolvoRenderer: NSObject` (FUERA del guard iOS, como `EcosistemaMetalRenderer`) con
  `encodar(en:lienzo:)` = UN draw instanciado (`drawPrimitives(.triangleStrip, vertexCount: 4,
  instanceCount: n)`) y `renderizar(en textura:)` para los tests offscreen de macOS; su conformidad
  `MTKViewDelegate` va en una **extensión dentro del `#if os(iOS) && canImport(MetalKit)`**, espejo
  exacto del renderer del héroe; `struct AtmosferaMetalLienzo: UIViewRepresentable`
  (`MTKView` con `isPaused = true`, `enableSetNeedsDisplay = true`, `isOpaque = false`, formato
  `EcosistemaMetal.formato`; `framebufferOnly` en su default — el vidrio del sistema muestrea la capa
  en el compositor, no leyendo la textura del drawable, y bajarlo cuesta perf a pantalla completa;
  queda como plan B en §12) —
  **dentro del mismo `#if os(iOS) && canImport(MetalKit)`** que `EcosistemaMetalLienzo` (el paquete
  también compila para macOS/watchOS y no importa UIKit sin guarda).
- **Fallback Canvas** (macOS, watchOS, previews, `liquidMotionDisabled`, o `recursos == nil` porque
  el shader no compiló): un `Canvas` que dibuja `particula(...)` para `n/2` partículas a
  `LiquidMotion.intervaloSello` (12 Hz, con su propio `TimelineView`); con `still` pinta un solo
  cuadro; el cambio de clima aquí es inmediato (el crossfade vive en el renderer de Metal). Los dos backends recorren
  la misma spec; el contrato es la función, no el rasterizado (misma regla que FER-13).

**Montaje en la app (`TodayView.swift`):**
- `@State private var atmosfera = AtmosferaEstado()` en `TodayView`.
- `.background { LiquidAmbientBackground.hoy(liquidAmbiente) }` (l. 616) → `.background { LiquidAtmosfera(ambiente: liquidAmbiente, estado: atmosfera) }`. Aplica a las DOS ramas del scroll (también al orbe dormido sin fuentes: ahí `liquidAmbiente == .neutro`).
- `LiquidVeil(tone: liquidAmbiente.acento)` (l. 618) → `LiquidVeil(tone: nil)`: el clima ya no tiñe el chrome; vive en las partículas y en los números.
- Parallax: en `todayScroll`, reusando la lectura del pull ya existente (l. 788–801) SIN tocar la
  firma del `for:` (un `onScrollGeometryChange` devuelve UN solo valor): el `pull` que ya llega al
  `action` es `−(contentOffset.y + contentInsets.top)`, así que dentro de ese mismo `action` (iOS 18+)
  y dentro del `onPreferenceChange(TodayScrollOffsetKey.self)` (iOS 17, donde llega `minY` con el
  mismo signo) se escribe `atmosfera.desplazamiento = max(0, −pull)` (solo si cambió). `TodayView.body` NO lee `atmosfera.desplazamiento` (solo pasa el objeto), así
  el scroll no recompone toda la pantalla; solo el fondo se redibuja.
- `atmosfera.visible = true/false` en `.onAppear/.onDisappear` del `iosBody` (cambio de pestaña).
- Borrar `LiquidHoyAmbient` + `LiquidAmbientBackground.hoy` + `hoyOrbs` y sus dos `#Preview`
  (pasan a `LiquidAtmosfera`), **y también `LiquidAmbientOrbs`** (su último llamador vivo era
  `LiquidHoyAmbient.body`: la orfandad la crea este cambio), `LiquidOrbSpec` (solo lo consumían los
  orbes) y `LiquidAmbiente.aurora/orbes/intensidad` (solo los leían los orbes). El `struct
  LiquidAmbientBackground` genérico (`init(auroraStops:orbs:)`, sin llamador desde antes) se reduce
  a `public enum LiquidAmbientBackground {}` — un espacio de nombres para que `.tablero` (extensión
  en `LiquidPlasta.swift`, que sigue vivo) no cambie de sitio.
- La pantalla de referencia del DS `LiquidHoyScreen` (`LiquidHoyScreen.swift`, el `ZStack` de fondo) también monta
  `LiquidAtmosfera` en vez de `.tablero` (con su propio `@State private var atmosfera = AtmosferaEstado()`),
  para que sus previews reflejen Hoy. **Y el arnés de los
  14 estados NO pasa por ella**: `LiquidHoyEstadosRenderTests.swift` (la escena del arnés) arma su propia escena
  (`ZStack { LiquidAmbientBackground.tablero(model.ambiente); VStack { LiquidHoyContent(...) } }`)
  — ahí también se sustituye `.tablero(...)` por `LiquidAtmosfera(ambiente:estado:)` (con un
  `AtmosferaEstado()` local y `liquidMotionDisabled` ya activo en el arnés → Canvas estático), o
  los 14 PNG seguirían validando el fondo viejo. Su aserción `png.count > 50_000` SIGUE pasando con
  el fondo nuevo (medido en el PR D con la atmósfera montada: 136–250 KB por estado — el polvo del
  Canvas aporta más entropía que la plasta); si algún estado bajara del umbral, la aserción pasa a
  contar píxeles no blancos, no a bajar el número.

### 5.2 El vidrio: receta `.superficieAtmosfera`

Nueva `case superficieAtmosfera` en `LiquidGlassRecipe` (`LiquidGlassRecipes.swift`), hermana de
`.superficie`, con:
- forma `RoundedRectangle(cornerRadius: LiquidRadius.modulo /* 20 */, style: .continuous)`;
- relleno **`LiquidColor.vidrioAtmosfera = Color.white.opacity(0.30)`** (token nuevo);
- borde **`LiquidColor.vidrioCanto`** (tinta900, que sube de .06 a **.08** — token de FER-28 hoy
  sin consumidor, con exactamente este propósito: «un filo de tinta bajo el borde blanco»), 0.5 pt,
  y este borde se dibuja **también en el camino nativo iOS 26** (`glassEffect(.regular, in:)`) —el
  filo del sistema es blanco y sobre blanco no existe—. `LiquidGlassLayer` es COMPARTIDO por las
  otras 4 recetas de vidrio real (`superficie`, `pastilla`, `pastillaElevada`, `lente`; las 2 sólidas
  usan `LiquidSolidLayer`, que ya traza borde siempre) y hoy no traza borde en su rama nativa: el
  borde nativo entra como **opt-in explícito** (`bordeSobreNativo: Bool = false` en el layer, `true`
  SOLO en `.superficieAtmosfera`); criterio: esas 4 recetas no ganan borde en iOS 26;
- inner-highlight como `.superficie` (top 0.8 / bottom 0.35), sin streak, sombra
  **`LiquidElevation.modulo(index: 0)`** (la de dos capas de un módulo de vidrio, FER-28: contacto
  corto + ambiente largo — la que dibuja el prototipo);
- material de imitación (< iOS 26): `.ultraThinMaterial` + relleno, igual que `.superficie`.

**Reduce Transparency:** los materiales del sistema y `glassEffect` ya se vuelven opacos solos; no
hay trabajo extra. Verificar en simulador (Ajustes → Accesibilidad) que las tarjetas siguen legibles.

**Condición del dueño (perf):** el blur tiene que ser real. Si en device el vidrio nativo/material
sobre la capa Metal no sostiene 60 fps al scrollear (§11 DoD), la receta cae a
`LiquidSolidLayer` con relleno **blanco al 45 %** (`vidrioAtmosferaSolida = .white.opacity(0.45)`)
— NO al 30 % opaco (se vería gris sucio) — y se anota en el PR.

Documentar la receta y los tokens en `docs/design-system/LIQUID-GLASS.md` (sección de recetas —
cuyo encabezado «4 recetas cerradas» ya era falso con las dos sólidas: pasa a «recetas cerradas», y
de paso la fila `superficie` dice «blanco .30» cuando el código tiene .46 desde /inject, la fila 42
dice `vidrioPastilla .45`/`vidrioLente .5` cuando el código tiene .46/.38, y el bullet de
`LiquidModulo` (§10.2) describe un componente que no existe — anotar ahí que la receta que cumple ese
contrato es `.superficieAtmosfera` — y este mismo cambio crea dos mentiras más: la l. 6 del doc dice
«4 recetas cerradas» (→ «recetas cerradas», igual que el encabezado de la sección) y §10 documenta
`vidrioCanto` = `tinta900 · 6 %` cuando A lo sube a 8 %: corregir las **seis** cosas; un token del DS
mal documentado es tan grave como un hex inline).
`swift run StrandDesignTokens` NO cubre `LiquidColor`/`LiquidGlassRecipe` (solo `InstrumentoTheme`
→ `design-tokens.json` + `DESIGN.md` §8.2): correrlo igual para confirmar «sin diff», pero el gate
real de estos tokens es la revisión de `LIQUID-GLASS.md` a mano.

### 5.3 La cara en estantes (`MatrizHoyFace`)

**El modelo NO cambia** (`MatrizHoyModel`, `MatrizSeccion`, `MatrizRenglon`, `MatrizChartPayload`,
`ordenA11y`); cambia solo cómo `MatrizHoyFace` compone las `bandas`:

| Banda del modelo | Antes (Matriz) | Ahora (Atmósfera) |
|---|---|---|
| `.nivel(rótulo, manualID:)` | rótulo micro + «?» + filo | **cabecera de estante**: rótulo `LiquidType.micro` mayúsculas, tracking `microTracking`, **`tinta700`** (era `tinta500`; el prototipo lo sube un paso), + el mismo «?» de hoy (`questionmark.circle`, fila entera tocable, `matriz.nivel.manual.hint`), sin filo; padding inferior `LiquidSpace.s250` (10). |
| `.split(izq, der)` | dos celdas con filo vertical | **dos módulos de vidrio** lado a lado, gap `LiquidSpace.s300` (12), **igual de altos**: `HStack(alignment: .top) { modulo(izq).frame(maxWidth: .infinity, maxHeight: .infinity); modulo(der).frame(maxWidth: .infinity, maxHeight: .infinity) }.fixedSize(horizontal: false, vertical: true)` — la fila mide el alto del módulo más alto y el otro se estira; el vidrio se aplica al módulo YA estirado. Esto RETIRA a propósito el `.fixedSize` POR CELDA de hoy (`MatrizHoyFace.swift:341-345`, «la celda mide su CONTENIDO… el chart caía al fondo»): en la anatomía nueva la gráfica al pie es lo deseado, y el guardarraíl contra el «encabezado inflado» es que los textos van en un `VStack` propio sin `Spacer` interior — el único `Spacer` vive entre textos y gráfica. Con `dynamicTypeSize >= .accessibility1` → columna única (regla existente). — firma real `modulo(_ s: MatrizSeccion, horizontal: Bool, estirar: Bool)`: en dos columnas `modulo(izq, horizontal: false, estirar: true)` / `modulo(der, …, estirar: true)` dentro de `HStack(alignment: .top, spacing: moduloGap).fixedSize(horizontal: false, vertical: true)`; `estirar` es quien pone `maxHeight: .infinity` DENTRO del módulo (el vidrio se aplica al módulo ya estirado); **con `columnaUnica` los dos van `estirar: false`** en un `VStack(spacing: moduloGap)` (sin fila que igualar, cada uno mide su contenido); `.full` siempre `estirar: false` |
| `.full(s)` | celda ancha | **un módulo ancho**. |

- Márgenes: los módulos van a **`LiquidSpace.s400` (16)** del borde de pantalla —el mismo margen
  que el dock (`LiquidSpace.dockSide`)— para que la columna de vidrio y el dock compartan filo; el
  héroe/kicker conservan su `s600` (24) y la franja de estado también. Una sola fuente por
  elemento: en `HoyMatrizHost` el `.padding(.horizontal, MatrizTokens.margenH)` deja de envolver al
  `VStack` entero y se mueve DENTRO del bloque `if let copy = estadoCopy` (solo la franja/aviso);
  la cara aplica su propio `MatrizTokens.margenModulos = LiquidSpace.s400` (16) a los estantes.
  Criterio anti-regresión (el bug «24 + 16 = 40 desalineados», hallazgo DeepSeek #14 documentado
  en ese mismo archivo): el borde izquierdo de los módulos queda a exactamente 16 pt del bisel y el
  de la franja a 24 — verificar en captura. `HealthAlertBanner` se queda en 24 (alineado con el
  héroe/kicker, no con los módulos) y su comentario «Mismo margen que la Matriz»
  (`TodayView.swift:1033-1035`) y el de `MatrizTokens.margenH` («UN solo dueño… la cara no vuelve a
  sangrar») se reescriben en el mismo PR para que no mientan.
- Entre estantes: `LiquidSpace.s550` (22). **Entre bandas de módulos del mismo estante: `MatrizTokens.moduloGap` (12)**, aplicado como `.padding(.top)` de la banda — y **0** cuando la banda es la primera de la cara o va inmediatamente después de una cabecera de estante (ahí el aire lo pone `estanteCabeceraPad`); `bandaView` recibe por eso `primera:` y `sigueACabecera:`. Bajo el último: aire para el dock como hoy
  (`padding(.bottom, LiquidSpace.s600)` de la cara + lo que ya pone `TodayView`).
- **Sin filos**: `filo()` desaparece.
- **Anatomía de un módulo** (top → bottom; padding `s400` (16) horizontal y arriba, `s300` (12) abajo):
  1. **Fila de título:** `[sello 20 pt] Título` a la izquierda + a la derecha SOLO el **estado del
     guardián** (`chipView`, `LiquidType.caption`, `tonoChip`) cuando la sección lo trae y no se está
     leyendo otra noche (regla existente C3). **El chip vive SIEMPRE ahí, a la derecha del
     título, y en ningún otro sitio**: el mecanismo actual `chipEnSublinea` (chip en el renglón
     del subtítulo cuando hay valor) y la rama «chip en lugar del número cuando `valor.isEmpty`»
     (`MatrizHoyFace.swift:504-511`) se retiran — si el valor viene vacío, el número simplemente
     no se pinta. Así el chip nunca se pinta dos veces. El sello es el actual, con sus tamaños actuales (`SelloGuardianVivo`
     con `radio: selloRadio` para el guardián; `LiquidIconDrop(glifoSello)` con `size: selloRadio·2.5`
     para el resto; `SelloMetricaVista`/`OrbeVivo` de respaldo, sin tocar). El ancla óptica del
     sello (`alignmentGuide(.firstTextBaseline) { d.height * 0.78 }`) estaba calibrada para
     versalitas; con el título en caja normal se **verifica** en captura (PR E) que el 0.78 sigue
     centrando el sello con la inicial en mayúscula de `tituloGemela` (valor de partida 0.78; criterio:
     centro óptico del sello a ±1 pt de la altura de caps del título; si no, se ajusta y se anota el
     factor nuevo en el PR — verificado: 0.78 se queda). El título va en **`LiquidType.tituloGemela` (15 semibold) para TODOS
     los módulos, en caja normal (se retira `.textCase(.uppercase)`)**: la jerarquía tipográfica es
     estante = versalitas micro, módulo = título en caja normal (así está en el prototipo). Una línea,
     `minimumScaleFactor(0.7)`. **Se retira el chevron `›`** (el módulo entero es el botón; trait
     `.isButton` se conserva).
  2. **El número:** en su hue, `.monospacedDigit()`, `contentTransition(.numericText())` +
     `.animation(.snappy, value:)` (RM → identity/nil), en **`LiquidType.valorTileL`** (nuevo,
     `groteskNumber(30, relativeTo: .title)`, tracking −1) para `destacada` (Sueño, FC) y
     **`LiquidType.valorTileM`** (nuevo, `groteskNumber(26, relativeTo: .title2)`) para el resto
     (VFC y Pasos incluidas — el campo `terciaria` se retira, §5.6.3b: el prototipo usa dos tamaños, no tres). Unidad en
     `LiquidType.caption`, mismo hue, `s050` de separación (igual que hoy). **El par del guardián**
     («+0.1° · 14.9», dos colores) también rueda: hoy es UN `Text` concatenado a dos colores sin
     `contentTransition` (`MatrizHoyFace.swift:592-597` en el estado pre-E) y que `numericText` ruede una concatenación
     multicolor NO está documentado — así que el par se parte en tres `Text` adyacentes en un
     `HStack(spacing: 0)` (temp · separador · resp), cada uno con su color, su
     `contentTransition(.numericText())` y su `.snappy`; esa rama sustituye SOLO al camino
     `if let par = s.huesPar, let corte = valor.range(of: " · ")` — el `else` (par sin separador,
     p. ej. «—») se conserva tal cual. Una línea, `minimumScaleFactor(0.6)`.
  3. **El subtítulo:** `LiquidType.caption`, `tinta500`, el `sublabelEfectivo` de hoy (HOY o la noche
     del scrub) con su cruce `.easeInOut(0.15)`; **sin la cápsula «votes»** (se retira; ver §5.6)
     y **sin chip** (vive en la fila de título). Reserva de altura SIN token numérico: cuando no
     hay subtítulo se pinta `Text(" ")` en la misma `caption` con `opacity(0)` — una línea
     reservada por construcción, que escala sola con Dynamic Type (misma intención que tenía
     `encabezadoMinH`, que se retira con la anatomía vieja).
  4. **La gráfica, pegada al pie del módulo:** dentro del módulo el orden es `VStack(alignment: .leading) { fila de título; número; subtítulo; Spacer(minLength: LiquidSpace.s300); gráfica }`, así en gemelas de distinto alto la gráfica de ambas queda al pie. **Un módulo `.full` NO se estira** (`.fixedSize(horizontal: false, vertical: true)` sobre el módulo, `maxHeight` nil): sin gemela mide su contenido — sin ese `fixedSize`, un contenedor que proponga alto de sobra (un render con marco fijo) infla el `Spacer` y la gráfica cae al fondo de un vidrio vacío. Es la actual por payload (`chartView`), altura por `chartAltura`, con el
     `ScrubGesto` y la a11y ajustable tal cual; para `.costura` la vista pasa a `MatrizHilos` (§5.4)
     con altura nueva `MatrizTokens.alturaHilos = 96`.
  - **Pasos (ancho, `.full` con `.barrasMini` en Contexto):** anatomía horizontal como el prototipo:
    fila de título; debajo `HStack(alignment: .bottom)` con `[número + subtítulo]` (ancho mínimo 88 pt)
    a la izquierda y la gráfica ocupando el resto (`alturaBarras`). Regla: **un módulo se compone
    horizontal SOLO si viene de una banda `.full` Y su gráfica es `.barrasMini`** — y ese contexto
    lo pasa `bandaView` explícitamente: en su `case .full(let s)` llama
    `modulo(s, horizontal: !columnaUnica && esHorizontal(s))` con `esHorizontal` = «`case .barrasMini
    = s.chart`», y en `.split` siempre `horizontal: false` — porque el módulo no sabe de qué banda
    viene y Esfuerzo (`.split`, también `.barrasMini`) tiene que seguir vertical. El guardián
    (`.full` + `.costura`) sigue vertical porque su payload no es de barras.
    **A `dynamicTypeSize >= .accessibility1` Pasos vuelve a vertical** (misma regla que la columna
    única): a AX el número escalado se comería la gráfica en la fila horizontal.
  - **Secciones con `renglones`** (camino legado del guardián en dos filas, hoy sin emisor pero con
    previews): se conservan tal cual dentro del módulo (no borrar).
- **Se conservan** el acuse del sello al tocar (`latido`: `scaleEffect(1.10)` + `sensoryFeedback(.selection)`) y `tocar(_:)` tal cual.
- **Botón y gesto (UNA sola anatomía, con o sin scrub):** el botón es el encabezado (título +
  número + subtítulo) y la gráfica lleva el gesto de scrub — separados como hoy (un `DragGesture`
  dentro de un `Button` es ambiguo, patrón #118); sin `scrubNoches` el pan va apagado
  (`liquidScrubPan(enabled: false)`), el toque en la gráfica abre la hoja igual y el control
  ajustable de VoiceOver queda oculto — así el camino «sin scrub: todo el módulo es el botón» de la
  cara vieja desaparece. El «vidrio que cede al
  presionar» se logra SIN escalar el label: el botón usa un `ButtonStyle` privado de la cara
  (`PresionaModulo`) que solo REPORTA `isPressed` a un `@State presionado: String?`, y el módulo
  entero (vidrio incluido) aplica `scaleEffect(pressScale)` + `LiquidMotion.press` cuando su id está
  presionado. Sin `.liquidPress` en el label (encogería el texto dentro de un vidrio quieto). El
  `contentShape` del botón es el rect de los textos con un inset negativo de `s125` (hit ≥ 44 pt),
  nunca el vidrio completo (competiría con `liquidScrubPan`). Un toque limpio sobre la gráfica abre
  la hoja igual (`ScrubGesto.onTap`, como hoy). El prototipo brillaba el vidrio al presionar: NO se
  hace (la única gramática de toque es la escala, decisión previa del dueño).
- **Entrada en cascada:** cada **banda** (cabecera de estante, fila `.split` completa o módulo
  `.full`) lleva `.liquidEntrada(index: 2 + i)` con `i` = su posición en `model.bandas` — los índices
  continúan los del héroe (`LiquidHoyContent` usa 0 y 1). **Las dos gemelas de una `.split` comparten
  índice**: entran juntas, como se ven juntas (8 escalones, no 11): fade + 8 pt, 60 ms de escalón (tokens existentes; el prototipo usaba 40 ms/10 pt —
  se adopta el token). Corre **una vez por lanzamiento** (`LiquidEntrada` guarda `shown` en `@State`
  y el `TabView` mantiene Hoy viva: al volver de otra pestaña NO se repite — es el comportamiento del
  modifier compartido y no se cambia aquí); Reduce Motion → crossfade simple (ya lo hace el modifier).
- **A11y:** se conservan `accessibilityElement(children: .combine)`, `a11yLabel`, `.isButton`,
  `accessibilityIdentifier("matriz-seccion-<id>")`, el control ajustable del scrub, `ordenA11y`.
  Las cabeceras de estante con `manualID` siguen siendo botón con hint; la rama decorativa
  (`manualID == nil`, `accessibilityHidden(true)`) se conserva aunque en la app ya ningún estante la
  use (la usan las fixtures) — no es huérfano de este cambio.
- **Dynamic Type:** ≥ `.accessibility1` columna única; los números escalan por `relativeTo`; ninguna
  altura de módulo fija; las gráficas conservan sus alturas fijas (como hoy). **Hecho verificado en
  simulador:** la app capa Dynamic Type en `xxxLarge` para TODA la jerarquía (`CenitApp.swift:96`,
  FER-394), así que en la app la columna única NO se alcanza nunca — es comportamiento del componente
  del DS (previews/tests); en la app lo que se verifica es `xxxLarge`: dos columnas, sin recortes
  (§11.7).

### 5.4 El guardián: `MatrizHilos` («los dos hilos de puntos»)

Sustituye al dibujo de `MatrizCostura` (la costura) para el payload `.costura(noches:)`. **El
payload NO cambia**: `MatrizCostura.Noche(temp:resp:parFuera:)` (0 = centro de tu banda, 1 = filo,
> 1 fuera, `nil` = no se leyó o no se pudo juzgar) sigue viniendo del builder con su ANCLA
(marcado fuera ≥ 1.02, no marcado ≤ 0.98). `MatrizCostura` pasa de `struct … : View` a
`public enum MatrizCostura` (espacio de nombres) conservando `Noche` y `fraccionFilo(_:)` públicos
—los tests `MatrizCosturaMapeoTests`, `CosturaGuardianTests` y el builder no cambian—; se borran su
cuerpo de dibujo, su `#Preview` y SOLO las constantes exclusivas del dibujo (`filoFrac`, `labioMin`,
`varaAncho`, `aire`, `varaMin`, `cuello`); las cinco que usa `fraccionFilo` (`filoDentro`, `filoFuera`,
`kDentro`, `kFuera`, `ladoBajoFrac`) se quedan; `MatrizTokens.alturaCostura` (58) queda huérfano y
se retira (`alturaHilos` lo sustituye); `MatrizChartSnapshotTests` deja de referenciar la costura dibujada y estrena `test_hilos` (§9, PR C).

`public struct MatrizHilos: View { init(chartID: String, noches: [MatrizCostura.Noche], hueTemp: Color = LiquidColor.doradoTemp, hueResp: Color = LiquidColor.azul, resaltado: Int? = nil) }`
— `Canvas` de altura `MatrizTokens.alturaHilos` (96), inset horizontal
`MatrizHoyFace.chartInset(.costura(noches: noches))` (el mismo que usa el dedo — fuente única P-3),
**que cambia a `hilosInset` = `hilosAnillo + hilosAnilloLatido + hilosAnilloTrazo/2` = 8 pt** (era
`max(chartInset, puntoDatoRadio + endpointBorde)` = 5, y el anillo de HOY latiendo llega a 8 pt del
centro: se cortaba contra el borde), N = `noches.count` (20 en vivo), `x(i) =
MatrizChartDraw.xAt(index: i, count: N, width:, inset:)` (la función de la familia, con su guarda
`count > 1` → centro; NO una fórmula a mano que divide entre cero con N = 1). Guarda de arranque
como la costura: `n > 0` y al menos un valor no-nil, si no `rejillaFantasma`.

Geometría vertical: dos líneas base, **temperatura arriba `yT = 28`**, **respiración abajo `yR = 68`**
(en un alto de 96), amplitud `A = 16` pt (constantes nuevas en `MatrizTokens`: `hilosBaseTemp`,
`hilosBaseResp`, `hilosAmplitud`).

**Mapeo (la honestidad no se negocia):** cada punto se coloca con **`MatrizCostura.fraccionFilo`**,
FIRMADO: `dy = fraccionFilo(v)·A` y `y = base − sign(v)·dy` (caliente/rápido = arriba de la base;
frío/lento = abajo, apretado al 22 % como hoy). Así:
- lo que el motor marcó fuera (v ≥ 1.02) cae por encima de `filoFuera` y lo no marcado (≤ 0.98) por
  debajo de `filoDentro`: el hueco del filo se conserva y sigue midiendo más que el grosor de un
  trazo (invariante de `MatrizCosturaMapeoTests`);
- el marco es inviolable (`fraccionFilo ≤ 1` → los puntos nunca salen del lienzo).
- **La banda («tu rango esperado»)** de cada hilo: arriba **`A·filoBanda`** con
  `MatrizCostura.filoBanda = filoDentro = 0.58` (público, nuevo) — NO `fraccionFilo(1)`, que vale
  0.75 (el filo cae en el tramo de AFUERA del mapeo, y con 0.75 una noche marcada a 1.02 = 12.07 pt
  quedaría 0.07 pt «fuera» de un borde a 12.0: dentro de la banda a ojo, contradiciendo al motor) —;
  abajo `A·fraccionFilo(−1)` (≈ 0.13·A). Con `A = 16`: dentro (≤ 0.98) ≤ 9.20 pt, borde 9.28 pt,
  marcado fuera (≥ 1.02) ≥ 12.07 pt: el centro de todo punto marcado queda ≥ 2.8 pt fuera del
  borde. Es **asimétrica a propósito**: el borde superior es el filo que el guardián vigila; el
  inferior existe pero no grita (el centinela nunca marca una noche fría). Se pinta con el hue del hilo a
  `MatrizTokens.hilosFillAlfa` (0.10 — es `costuraFillAlfa` renombrado; el prototipo aprobó «la banda
  de rango al 10 %») con esquinas redondas de radio = medio alto de la banda; el **hilo central** (tu
  base) es una línea de 1 pt del hue a 0.30 (`MatrizTokens.hilosBaseAlfa`, nuevo).
- **La banda SOLO se dibuja si ese hilo tiene ≥ 1 noche con valor no-nil** en la ventana. Qué
  significa eso por señal, y por qué es honesto (decisión, ver §13): la **respiración** viene `nil`
  cuando el motor no la juzgó (sin base) → sin banda ni puntos; la **temperatura** viene con valor
  siempre que hubo lectura, anclada al juicio del motor cuando lo hubo y CRUDA cuando no
  (`noche == nil`, `LiquidHoyBuilder+Matriz.swift:353`) — su banda es el corte PÚBLICO y absoluto
  (±`thermalOutC` sobre una desviación que ya viene normalizada contra tu base), así que existe con
  cualquier lectura y la posición de una noche sin juicio «cuadra por construcción: mismo corte,
  mismo número» (comentario del builder). Un punto crudo ≥ 1 dice «esa noche la desviación superó
  el corte público», que es el DATO, no un juicio del motor sobre tu cuerpo — igual que la curva de
  FC dibuja un valor sobre su banda. NO se toca el camino de datos (fuera de alcance §3).
- **Puntos:** dentro (|v| < 1, y no `parFuera`): radio 3, alfa 0.45; **fuera (v ≥ 1)**: radio 4,
  alfa 1 (lleno). «Fuera» se lee del valor, no de una bandera aparte: el ancla del builder garantiza
  que solo lo que el motor marcó (o la temperatura por su corte público, que es el mismo número)
  cruza el filo — no agregar banderas `tempFuera/respFuera` a `Noche` (esa clase de bug ya se mató en
  FER-110 P-2). La señal ausente esa noche NO se coloca en la banda: se marca con el mismo hueco de
  la costura (P-2) — un punto mínimo de 1.4 pt en `tinta500` al 0.35 SOBRE la línea base, del color
  de nadie (`hilosHuecoRadio`/`hilosHuecoAlfa`).
- **La noche en que el par votó (`parFuera`)**: columna de resplandor ámbar
  (**`LiquidColor.atencion`** — el mismo de la costura; NO `ambarClaro`, que es un tono de AMBIENTE y
  da 2.3:1 sobre blanco, bajo el piso 3:1 de un objeto de dato — a alfa `hilosAlertaAlfa`·0.5 = 0.11,
  ancho `hilosColumnaFactor` 1.2·paso, esquinas `s150`), los DOS puntos en `atencion` llenos, y un
  **nudo**: línea punteada (`hilosNudoDash` [2, 2.5], `hilosNudoTrazo` 1.5, `atencion`) que une los
  dos puntos (solo si esa noche trae las dos lecturas). `atencion` entra a la lista de hues del test
  de contraste (4.08:1 sobre blanco). Todos los números de esta gráfica son tokens de `MatrizTokens` (§8, fila C): la CI de
  design-lint NO corre `no-opacity-literal`/`no-radius-literal` sobre `Packages/StrandDesign`, así que
  el gate aquí es la revisión, no la máquina.
- **HOY (índice N−1)** cuando no hay scrub activo: sus dos puntos llevan un **anillo** (radio
  `hilosAnillo` 5.2, trazo `hilosAnilloTrazo` 1.6, su hue) que **late** con la frecuencia del sello
  vivo en calma (`hilosLatidoW` 1.15 rad/s): fase `f = (sin(t·1.15) + 1)/2`, radio `5.2 + 2·f`
  (crece 2 pt, `hilosAnilloLatido`, como el `@keyframes late { r 5.2→7.2 }` del prototipo) y
  alfa `1 − 0.7·f`; `TimelineView` a `LiquidMotion.intervaloSello`, pausado con `quieto =
  reduceMotion || ambientPaused || motionDisabled` (quieto = f 0: anillo fijo a 5.2 y alfa 1).
  De ahí el inset de 8 pt: 5.2 + 2 + 0.8 (medio trazo).
- **Scrub (`resaltado`)**: la noche leída dibuja el cursor vertical (`LiquidColor.tinta500`, 1.2 pt,
  de arriba abajo del lienzo) y sus dos puntos a radio 5, alfa 1; el anillo de HOY se apaga mientras
  hay scrub.
- **Sin base para NADA** (las 20 noches `nil` en ambos hilos): la rejilla fantasma de la familia
  (`MatrizChartDraw.rejillaFantasma`, como toda gráfica de la Matriz sin datos); no se inventa rango.
- Reduce Motion: idéntico pero sin latido (todo estático y completo).
- El **hint de barrido** (primera vez): un `overlay` sobre la gráfica del guardián: una franja vertical
  de `MatrizTokens.hintAncho` (60 pt) pintada con un `LinearGradient` **horizontal** (`.leading →
  .trailing`) de `tinta900.opacity(0)` → **`LiquidColor.tinta7`** (token existente; nunca un
  `opacity(0.07)` inline) → `tinta900.opacity(0)`, recortada al `LiquidRadius.control` de la gráfica,
  que cruza de izquierda a derecha una vez, 1.4 s con `.easeInOut`, 0.9 s después de entrar a la vista; se controla con
  `@AppStorage("today.scrubHints") var n = 0` (mismo patrón que `ecosistemaSeparaciones` /
  `maxSeparacionHints`): se muestra mientras `n < 3`, incrementa por aparición, y **un scrub
  completado en cualquier gráfica pone `n = 3`**. `accessibilityHidden(true)`; bajo Reduce Motion no
  se muestra. **Cuenta como «mostrado» solo si de verdad se vio**: el `ScrollView` de Hoy no es
  lazy y monta la Matriz entera al abrir, así que un `onAppear` a secas quemaría el contador de 3 en
  tres lanzamientos sin que nadie hubiera bajado hasta el guardián — en iOS 18+ lo decide
  `onScrollVisibilityChange(threshold: 0.6)` sobre el overlay del hint; antes, el `onAppear`.
  Vive en la cara (`MatrizHoyFace`) con el contador inyectado por `HoyMatrizHost` (la
  cara es del DS y no lee `AppStorage`: `MatrizHoyFace.init` gana `mostrarHintScrub: Bool = false`,
  `onHintMostrado: () -> Void = {}` (la cara avisa cuando lo mostró; el host incrementa) y
  `onScrubCompletado: () -> Void = {}` (un arrastre terminó; el host pone el contador en 3; lo
  dispara `ScrubGesto` en su `onEnd` **solo si `scrub?.id == id`** — es decir, si hubo al menos un
  `onChange` — vía un nuevo parámetro `onCompletado`) — CON
  valores por default, para que los 7 call sites actuales (host, 3 `#Preview`, 3 snapshots) sigan
  compilando). El overlay del hint (`HintBarrido`) vive sobre la gráfica del par (`case .costura`
  del payload — no por id), solo si `mostrarHintScrub && !reduceMotion && !liquidMotionDisabled`.

Tests nuevos (`MatrizHilosTests.swift`, puros, sin Canvas — la geometría se expone en un
`enum MatrizHilos.Geometria` con estáticas puras: `y(_ v: Double, base: CGFloat) -> CGFloat`,
`banda(base: CGFloat) -> ClosedRange<CGFloat>`, `hayBase(_ valores: [Double?]) -> Bool`,
`estilo(v:parFuera:leido:) -> Estilo` (`.dentro/.fuera/.par/.leido`) con `radio(_:)`/`alfa(_:)`, y
`fase(_ t: TimeInterval, quieto: Bool) -> Double`; los 9 tests reales de `MatrizHilosTests.swift`
cubren esta lista, no 1:1 por número):
1. `y(0.98) < y(1.02)` en distancia a la base y la diferencia ≥ hueco (`fraccionFilo(1.02) − fraccionFilo(0.98)`)·A > 2.2 pt.
2. Nunca sale del lienzo: para v ∈ {−900, −3, 0, 3, 500}, `0 ≤ y ≤ 96`.
3. Banda nil cuando todas las noches del hilo son nil; presente con una sola no-nil.
4. Estilo: `estilo(v: 0.5, parFuera: false, leido: false) == .dentro` → `radio` 3, `alfa` 0.45; `v = 1.5` → `.fuera` (4, 1); `parFuera` → `.par` (4, 1, tinta `atencion`); `leido` → `.leido` (5, 1).
5. La banda es asimétrica; su borde superior es `A·filoBanda` y el inferior `y(−1)`; **todo punto con
   v ≥ 1.02 cae FUERA de la banda con su centro a ≥ 2.5 pt del borde**, y todo punto con v ≤ 0.98
   cae dentro.
6. Frío (v = −0.5) queda por debajo de la base y más cerca que caliente (v = 0.5) (lado bajo apretado).

### 5.5 El scrub y los números (qué se conserva, qué se extiende)

- Se conserva TODO el mecanismo actual: `ScrubGesto` + `liquidScrubPan` (no arranca si el dedo va
  vertical), `ScrubMapeo` (bins vs series), `chartInset` único, háptica por noche cruzada
  (`sensoryFeedback(.selection, trigger: scrubTick)`), `valorEfectivo/sublabelEfectivo`, el chip
  del guardián que se calla al leer otra noche, el control ajustable de VoiceOver, y el scrub vivo
  bajo Reduce Motion (solo se apaga la animación).
- Extensión 1: el par del guardián rueda (§5.3.2).
- Extensión 1b: **Pasos gana scrub**: `scrubPasos` en el builder (14 días, `HoyGramatica.formatoMiles`,
  sublabel = fecha; sin lectura → `matriz.scrub.sinlectura`), calcado de `scrubEsf`. Era la única
  de las 8 sin `scrubNoches` (el doc de FER-62 decía «barrasMini no tenía scrub… hasta ahora» solo
  para Esfuerzo).
- Extensión 2: **el subtítulo del guardián durante el scrub dice si el par votó** (dueño): el
  builder produce para cada `ScrubNoche` del guardián `sublabel = fecha` cuando esa noche NO es
  `parFuera`, y `sublabel = String(format: String(localized: "matriz.guardian.scrub.par", defaultValue: "%@ · both moved out together"), fecha)`
  (es: «%@ · las dos se salieron juntas») cuando SÍ lo es. `parFuera` = el juicio del motor para ese
  día (`tempOut && respOut`), nunca re-derivado: en `LiquidHoyBuilder+Matriz.swift` el `.map` que
  arma `scrubCostura` (l. ~367-384) lee **`nochesCostura[idx].parFuera` del arreglo SIN recortar**
  (mismo índice que `keys20`; NO `nochesCosturaVivas`, que ya está ventaneado por `iniGuardian` — el
  recorte se aplica después, igual que hoy con `scrubCosturaVivo`). Sin lectura:
  `matriz.scrub.sinlectura` como hoy.
- El hint de barrido (§5.4).

### 5.6 Cambios del builder (`Cenit/Screens/Hoy/LiquidHoyBuilder+Matriz.swift`) — los ÚNICOS

1. **Bandas:** quitar `.nivel("matriz.nivel.bitacora", manualID: nil)`; `.full(seccionPasos)`
   queda como última banda del estante Contexto. Orden final: `nivel(deciden) · split(sleep, rhr) ·
   nivel(vigila) · full(guardian) · nivel(contexto) · split(carga, strain) · split(hrv, stress) · full(steps)`.
   `ordenA11y` no cambia. Borrar la clave `matriz.nivel.bitacora` del catálogo (edición de texto
   crudo, nunca `json.dump`).
2. **Scrub del guardián:** `sublabel` con `matriz.guardian.scrub.par` cuando `parFuera` (§5.5).
3. **`vota`:** la cápsula «votes» YA NO SE PINTA en la app desde FER-55 (los dos únicos emisores del
   builder pasan `vota: false`, `LiquidHoyBuilder+Matriz.swift:125/175`); lo que hace este PR es
   retirar el cadáver: el campo `MatrizSeccion.vota` (declarado en `MatrizHoyFace.swift`, junto con
   la rama que pintaba la cápsula — un solo archivo, se toca en D porque el builder deja de pasar el
   argumento en el mismo PR), los dos `vota: false` del builder y la clave `matriz.vota` del catálogo.
   Ningún test lo afirma (verificado: `grep -rn "\.vota"` → 0); si algo deja de compilar (fixtures
   que pasen `vota:`), se quita el argumento — nunca se reescribe la intención del test.
4. **`terciaria`** (PR E): con dos tamaños de número (30/26) el campo `MatrizSeccion.terciaria` deja de
   dirigir nada visual → **se elimina** del modelo y del builder (VFC y Pasos lo pasaban `true`), con
   la misma regla que `vota` (nunca reescribir la intención de un test).
5. **`scrubPasos`** (PR E): Pasos gana `scrubNoches` (14 días, `HoyGramatica.formatoMiles`,
   `matriz.scrub.sinlectura` para el día sin dato) — §5.5; el único añadido de datos, y es solo
   formato de lo que ya se dibuja.
Nada más del builder cambia. **Prohibido** tocar valores, sublabels de HOY, chips, umbrales, la
costura del par (los datos), `quienSeSalioHoy`, el acta.

### 5.7 Lo que se conserva tal cual (y hay que verificar que sigue igual)

Héroe completo (`LiquidEcosistema`, incluido `EcosistemaListado` a partir de `.xxxLarge`); kicker;
franja de estado (`estadoGrupo`) y `AvisoDesconexion`; `HealthAlertBanner`; pull-to-sync y su
pista; todas las hojas y sus rutas (`abrirHojaCaras`, `manual.deciden`, `manual.contexto`,
`guardian`, métricas, acta); el dock; `LiquidVeil` (solo `tone: nil`); las 7 gráficas restantes
(`MatrizColumnas`, `MatrizRegla`, `MatrizColina`, `MatrizBarrasMini`, `MatrizLineaRellena`,
`MatrizEscalerita`, y `MatrizLineaSerena` como legado); el sello vivo del guardián; los ids de a11y.

---

## 6. Estados (qué pinta cada capa) — el contenido NO cambia, solo el envase

Regla general: **cada estado muestra exactamente lo que muestra HOY** (héroe, franja, valores «—»,
subtítulos, chips), dentro del envase nuevo. Ningún módulo pinta un dato que hoy no pinta.

| Estado (`Plantilla` / variante) | Polvo (color) | Héroe | Franja/aviso | Módulos | Guardián (hilos) |
|---|---|---|---|---|---|
| T1 pleno · `.full` (verde) | `bien` → `particulaVerde` | palabra + ⓘ | ninguna | 8 con datos | banda(s) si hay base; puntos; HOY late; chip «En calma»/«vigilando…» |
| T1/T2 · `.caution` (ámbar) | `atencion` → `particulaAmbar` | ídem | ninguna | ídem | ídem |
| T1/T2 · `.easy` (rojo) | `alerta` → `particulaRoja` | ídem | ninguna | ídem | ídem |
| Fiebre: par fuera hoy (eclipse) | el del veredicto | eclipse (héroe actual) | ninguna | ídem | HOY: los dos puntos ámbar + nudo + resplandor; chip ámbar/rojo |
| Desfase (histéresis) | el del veredicto | subtítulo de desfase actual | ninguna | ídem | ídem |
| T2 provisional | el del veredicto | «confianza» actual | ninguna | ídem | ídem |
| T3 `.calibrando` | `neutro` → `particulaNeutra` × 0.55 | «Conociéndote · Noche N de M» | calla | valores que haya; «—» donde no | **sin banda de respiración** (nil sin juicio); temperatura con banda si hay lecturas (corte público, §5.4); chip «Conociéndote» |
| T3 `.leyendo` / `.sinSync` / `.nocheNoRegistrada` / `.senalInsuficiente` | `neutro` | «No reading today» actual | la causa actual | «—» / lo que haya | lo que haya; sin inventar |
| T4 sin permiso | `neutro` | «Connect Apple Health…» + CTA | calla | «—» | solo líneas base |
| T5 dormido (sin fuentes) — `ambiente(prep: nil) == .neutro` | `neutro` | orbe dormido (`LiquidOrbeDormidoEstado`) sobre blanco + polvo neutro | — | (no hay Matriz) | — |
| Base rancia (`!isNightAnchored`) — `ambiente(prep:)` ya devuelve `.neutro` | `neutro` | «héroe rancio» actual (`hero.title.rancia`) | — | ídem | ídem |
| Salud desconectada con caché (T1/T2) | el del veredicto | ídem | `AvisoDesconexion` (rosa, respira) | ídem | ídem |
| Reduce Motion (cualquiera) | quieto, sin parallax, sin respiración | quieto (ya) | quieto (ya) | sin cascada, sin latido, scrub vivo sin animación | sin latido, sin hint |
| Dynamic Type xxxLarge (tope de la app; ≥ AX1 solo en el DS) | igual | `EcosistemaListado` desde xxxLarge (ya) | igual | dos columnas (columna única solo ≥ AX1 en el DS) | igual |
| Sin Metal / shader no compila | Canvas n/2 · 12 Hz | Canvas (ya) | sin cambio | sin cambio (los módulos y `MatrizHilos` son SwiftUI/Canvas, no dependen de Metal) | sin cambio |

Idiomas: es y en (todas las claves nuevas con `en` + `es`).

---

## 7. Reglas duras e invariantes (rechazo automático si se rompen)

1. **Offline.** Nada de red. (Trivial aquí, pero es la regla #1.)
2. **El DS es ley.** Cero hex/tamaños/espaciados inline: todo lo nuevo (`vidrioAtmosfera`,
   `vidrioCanto` a .08, `valorTileL/M`, `alturaHilos`, `hilosBase*`, `hilosAmplitud`,
   `hilosBaseAlfa`, `margenModulos`, `PolvoSimulacion.Fisica.*`) es token con `#Preview`.
3. **Honestidad.** Nada afirma sobre el cuerpo lo que el motor no juzgó: la banda del guardián solo
   con base; «fuera» solo con la marca del motor (vía el ancla ≥ 1.02); el sublabel «las dos se
   salieron juntas» solo con `parFuera`; el chip se calla al leer otra noche; sin lectura = hueco.
   El copy de HOY de cada módulo es EXACTAMENTE el actual.
4. **Un solo reloj por capa y pausable**: polvo a 20 Hz (`intervaloAmbiente`), pausado con hoja
   abierta / background / onboarding / tab oculto / RM; el latido de HOY a 12 Hz (`intervaloSello`).
5. **Reduce Motion completo**: todo estático pero COMPLETO (nada desaparece); el scrub sigue vivo.
6. **Metal es opcional**: si `EcosistemaMetal.recursos == nil` la pantalla se ve (Canvas), nunca en
   blanco.
7. **`.msl`, no `.metal`** (el toolchain de Metal no es requisito de build) — se extiende el archivo
   existente.
8. **Nada de constantes mágicas en el shader**: todo viaja en el uniform desde `PolvoSimulacion.Fisica`;
   el layout Swift↔MSL se afirma en un test.
9. **Un concern por PR**, `-jobs 4`, un build a la vez, `Tools/verify.sh` antes de cerrar cada PR,
   etiqueta `ci-app` en los PRs que tocan `Cenit/**`.
10. **`.xcstrings` como texto crudo**, claves bajo `en` y `es` (nunca `es-MX`), sin em-dash.

---

## 8. Arquitectura: dónde vive cada cosa (mapa archivo → cambio)

| Archivo | Cambio | PR |
|---|---|---|
| `Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/LiquidColor.swift` | + `vidrioAtmosfera` (.white .30), `vidrioCanto` .06 → .08 (token FER-28 sin consumidor, reusado como el canto de tinta), + `vidrioAtmosferaSolida` (.white .45, plan B) | A |
| `…/LiquidGlass/LiquidType.swift` | + `valorTileL` (30, `.title`), + `valorTileM` (26, `.title2`), + `valorTileTracking = -1` | A |
| `…/LiquidGlass/LiquidGlassRecipes.swift` | + `case superficieAtmosfera` + `LiquidGlassLayer.bordeSobreNativo` (opt-in; solo esta receta) + `#Preview` sobre blanco con polvo estático | A |
| `…/LiquidGlass/MatrizTokens.swift` (**PR C**, con su consumidor — en A romperían el paquete porque `costuraAlertaAlfa`/`alturaCostura` aún tienen lector en `MatrizCostura.swift`) | + `alturaHilos 96`, `hilosBaseTemp 28`, `hilosBaseResp 68`, `hilosAmplitud 16`, `hilosBaseAlfa 0.30`, `hilosFillAlfa` (renombra `costuraFillAlfa`, 0.10), `hilosAlertaAlfa` (renombra `costuraAlertaAlfa`, 0.22), `hilosPuntoDentro 3`, `hilosPuntoFuera 4`, `hilosPuntoLeido 5`, `hilosPuntoDentroAlfa 0.45`, `hilosAnillo 5.2`, `hilosAnilloTrazo 1.6`, `hilosAnilloLatido 2`, `hilosLatidoW 1.15` (misma frecuencia que el sello vivo en calma), `hilosHuecoRadio 1.4`, `hilosHuecoAlfa 0.35`, `hilosNudoTrazo 1.5`, `hilosNudoDash [2, 2.5]`, `hilosColumnaFactor 1.2`; − `alturaCostura` | C |
| `…/LiquidGlass/MatrizTokens.swift` (**PR E**, con su consumidor) | + `margenModulos = s400`, `moduloPadH = s400`, `moduloPadTop = s400`, `moduloPadBottom = s300`, `moduloGap = s300`, `moduloTextoMinAncho 88`, `estanteGap = s550`, `estanteCabeceraPad = s250`, `hintAncho 60`, `hintDuracion 1.4`, `hintEspera 0.9`; − `bandaV`, `colGap`, `filoAlfa`, `encabezadoMinH` (sin lector tras la anatomía nueva) | E |
| `docs/design-system/LIQUID-GLASS.md` | receta + tokens | A (+ remate en F, `63b2fe53`: l. 6 «recetas cerradas» y `vidrioCanto` 8 % en §10) |
| `…/LiquidGlass/PolvoSimulacion.swift` (**nuevo**) | la spec pura + `Fisica` | B |
| `…/Resources/EcosistemaShaders.msl` | + `PolvoU` + `vsPolvo` | B |
| `…/LiquidGlass/EcosistemaMetal.swift` | + `EcosistemaPolvoU`, `Recursos.polvo`, `EcosistemaPolvoRenderer`, `AtmosferaMetalLienzo` | B |
| `…/LiquidGlass/LiquidAtmosfera.swift` (**nuevo**) | `AtmosferaEstado`, `LiquidAtmosfera` (Metal + Canvas), `#Preview`s (4 climas + RM) | B |
| `Packages/StrandDesign/Tests/StrandDesignTests/PolvoSimulacionTests.swift` (**nuevo**), `EcosistemaPlanTests.testLayoutDeLosUniformes` (+ stride 192 y OFFSETS clave de `EcosistemaPolvoU`, no solo el total) + `testLaFisicaDelPolvoSaleDeLosTokens`, `EcosistemaMetalRenderTests` (+ 7 tests de polvo: compila y pinta, determinista, vive, quieto ignora t/parallax, parallax mueve, neutro más tenue, crossfade interpola) | tests | B (+ los offsets de los 6 colores, 0/16/32/48/64/80, en F `63b2fe53`) |
| `docs/ARCHITECTURE.md` | Hoy: capa de fondo Metal fija + parallax por `AtmosferaEstado`; el héroe scrollea | B (y D) |
| `…/LiquidGlass/MatrizHilos.swift` (**nuevo**) · `MatrizCostura.swift` (→ enum namespace, + `filoBanda`) · `MatrizHoyFace.chartView/chartAltura/chartInset` | la gráfica nueva | C |
| `…/Tests/StrandDesignTests/MatrizContrasteTests.swift` | + `testHuesDeModulosPasanSobreElVidrioDeLaAtmosfera` (fondo `papelTarjeta`, en A) y `testHuesDeModulosAguantanElPeorPixelDeLaAtmosfera` (piso de regresión, peso rojo 0.217, `atencion` en la lista — llegó en E, se lista aquí por archivo) | A/E |
| `…/Tests/StrandDesignTests/MatrizHilosTests.swift` (**nuevo**, geometría pura) · `MatrizChartSnapshotTests.swift` (+ `test_hilos`, los 6 estados a PNG) | tests | C |
| `Cenit/Screens/TodayView.swift` | fondo → `LiquidAtmosfera`; `AtmosferaEstado`; parallax en `todayScroll`; `LiquidVeil(tone: nil)`; `visible` on/offAppear | D |
| `…/LiquidGlass/LiquidPatterns.swift` | − `LiquidHoyAmbient`, − `hoy(_:)`, − `hoyOrbs` (huérfanos) — y sus dos `#Preview` (l. ~419, 430-433) pasan a `LiquidAtmosfera` o se borran, o el paquete no compila | D |
| `…/LiquidGlass/LiquidHoyScreen.swift` | fondo de la referencia → `LiquidAtmosfera` + `LiquidVeil(tone: nil)` (§13.14) | D |
| `…/Tests/StrandDesignTests/LiquidHoyEstadosRenderTests.swift` | el arnés de 14 estados arma su propia escena con `.tablero` → `LiquidAtmosfera` (Canvas estático) | D |
| `…/LiquidGlass/MatrizHoyFace.swift` | − campo `MatrizSeccion.vota` + la rama que pintaba la cápsula (§5.6.3) — el builder deja de pasar el argumento en este mismo PR | D |
| `…/LiquidGlass/LiquidPlasta.swift` | el comentario de `.tablero` deja de citar a `.hoy(_:)` (retirado) | D |
| `Cenit/Screens/Hoy/LiquidHoyBuilder+Matriz.swift` | §5.6.1–3 (bandas · scrub par · vota) | D |
| `Cenit/Screens/Hoy/LiquidHoyBuilder+Matriz.swift` | §5.6.4–5: − `terciaria:` (VFC, Pasos) + `scrubPasos` — junto con el modelo que los pierde/usa | E |
| `Cenit/Resources/Localizable.xcstrings` | + `matriz.guardian.scrub.par` (en/es); − `matriz.nivel.bitacora`, − `matriz.vota` | D |
| `CenitUnitTests/HoyMatrizBuilderTests.swift` | bandas (8, sin bitácora), scrub par, sin `vota` | D |
| `…/LiquidGlass/MatrizHoyFace.swift` | composición en estantes/módulos (§5.3), hint, sin filos/chevron/vota/`chipEnSublinea`/`terciaria`; los tokens de la anatomía vieja que queden sin lector (`bandaV`, `colGap`, `filoAlfa`, `encabezadoMinH`) se retiran | E |
| `Cenit/Screens/Hoy/HoyModosHost.swift` | margen de la franja vs. margen de la cara; `mostrarHintScrub` + `onScrubCompletado` con `@AppStorage("today.scrubHints")` | E |
| `…/Tests/StrandDesignTests/MatrizHoyFaceSnapshotTests.swift` | sus fixtures YA traen 4 `.nivel` (incl. `"Logbook"`, l. 124) → quitar Bitácora, dar `manualID` a los tres estantes, quitar `terciaria:`; el `render` pasa a rendir SOBRE `LiquidAtmosfera` (estático, `liquidMotionDisabled`) con marco 390×1040; `test_orden_a11y…` intacto | E |
| `MatrizHoyFacePreviewData` (en `MatrizHoyFace.swift`) | hoy NO tiene ningún `.nivel` (lista plana de `.full`/`.split`): las previews del DS se dejan como están (siguen compilando y muestran módulos sin cabeceras); no es fixture de nada — opcional añadirles estantes | E |
| `CenitUITests/CenitScreenshotTests.swift` + `docs/fixtures/today*.png` | `acceptedTermsVersion` 2.0 + espera de 5 s también en vacío; regenerar las capturas de Hoy (8 estados = 32 PNG) | F |
| `docs/appmap/index.html` + `docs/appmap/shots/hoy-*.png` | muro regenerado desde las fixtures nuevas (`sync_shots` + `build_served`); Entrenar no se toca | F |
| `CHANGELOG.md` | una entrada por PR visible (C, D, E) | C/D/E |

**Decisiones técnicas (con alternativa descartada):**
- *Parallax por `@Observable` en vez de `@State CGFloat` en `TodayView`* — porque un `@State`
  escrito por cuadro recompone las ~1 800 líneas de `TodayView` a 60 Hz; con el objeto solo el fondo
  se invalida.
- *Renderer hermano (`EcosistemaPolvoRenderer`) en vez de meter el polvo en el plan del héroe* — el
  héroe vive en un lienzo de 364×324 dentro del scroll y el polvo es fijo a pantalla completa; son
  dos vistas Metal con reloj y pausa distintos (60 Hz vs 20 Hz). Comparten `Recursos` (una sola
  compilación del shader).
- *Posiciones derivadas del índice (hash) en vez de un buffer de partículas* — misma disciplina que
  FER-13 (la GPU nunca recibe la lista); el CPU-fallback y los tests usan la misma función.
- *20 Hz para el polvo* — velocidades ≤ 4 pt/s ⇒ ≤ 0.2 pt por cuadro: invisible; y el parallax va
  por demanda a la velocidad del scroll.
- *`fraccionFilo` reusado para los hilos* — es la única forma de heredar los 7 invariantes ya
  probados (hueco del filo, marco, lado bajo) sin re-litigar la honestidad.
- *Radio 20 (`LiquidRadius.modulo`) y no 24* — reuso del token de módulos de vidrio (FER-28); el
  DS manda sobre el CSS del prototipo.
- *`.liquidPress` (0.97) sin brillo* — decisión previa del dueño («la única gramática de toque»).

---

## 9. Plan de entrega: 6 PRs, en este orden, cada uno mergeable solo

Rama por PR desde `origin/iOS` actualizado: `fer-118a-vidrio-tokens`, `fer-118b-atmosfera`,
`fer-118c-hilos`, `fer-118d-fondo-hoy`, `fer-118e-cara-vidrio`, `fer-118f-estados-capturas`
(la rama `fer-118-hoy-atmosfera` solo guarda el prototipo; no implementar ahí). El orden es
A → B → C → D → E → F: el fondo (D) entra ANTES que la cara (E) para que nunca haya vidrio sobre la
aurora vieja; entre D y E la Matriz de tinta vive unos días sobre blanco + polvo (estado intermedio
aceptable, ya visto por el dueño en el prototipo «Hoy en blanco»). Cada PR:
`Closes`/`Part of FER-118` en el cuerpo, `Tools/verify.sh` verde, CHANGELOG cuando es visible,
`ci-app` si toca `Cenit/**`. Squash-merge, borrar rama, sincronizar `~/code/noop` con `--ff-only`.

| PR | Contenido | Carril de gate | Criterios de cierre propios |
|---|---|---|---|
| **A** `vidrio+tokens` | §5.2 + tokens de §8 (A) + docs DS | ligero (paquete) | `swift test` StrandDesign verde; `#Preview` de la receta; `MatrizContrasteTests` extendido en DOS fondos: (a) `papelTarjeta` (el vidrio al 30 % sobre blanco, el caso medio: las motas cubren ~3 % del área) y (b) el **peor pixel realista**: `particulaRoja` al alfa máximo de mota (0.31) bajo blanco al 30 % (`0.783·blanco + 0.217·rojo`). En (a) —criterio de A—: los 9 hues que pintan numerales (indigo, rosa, doradoTemp, azul, verdeCarga, ambar, cian, teal, verdePrimario) ≥ 3:1 (AA-large) y `tinta700`/`tinta500` ≥ 4.5:1. (b) es criterio del **PR E** (§8) y ahí la lista suma `atencion` (el ámbar del par): en (b) NO se afirma AA — medido: ámbar 2.85, teal 2.75, verdePrimario 2.86, `atencion` 2.85, `tinta500` 3.86 — y no hace falta (WCAG G18 mide los píxeles ADYACENTES a la letra; una mota de ≤ 4.6 pt cada ~234 pt² no es el fondo de un numeral de 30 pt): (b) es un **piso de regresión** con la holgura medida (numerales ≥ 2.7, grises ≥ 3.8) que dispara si sube el alfa del polvo, se oscurece `particulaRoja` o se aclara un hue (§13.29); design-tokens sin diff |
| **B** `atmósfera` | §5.1 completo (spec, shader, renderer, vista, previews, tests); NO se monta aún en la app | pesado (Metal + concurrencia) | `PolvoSimulacionTests` (abajo); `testLayoutDeLosUniformes` con `EcosistemaPolvoU`; render offscreen: compila y pinta algo, es determinista con `t` fijo, distinto entre `t=0` y `t=3` (vivo), y `still` ignora `t`; previews de 4 climas + RM; ARCHITECTURE.md |
| **C** `hilos` | §5.4 (vista + namespace + tests) | pesado (gráfica con invariantes de honestidad) | `MatrizHilosTests` 1–6 (geometría pura); `MatrizCosturaMapeoTests` + `CosturaGuardianTests` intactos y verdes; snapshot del guardián en 6 estados (calma con HOY / una fuera / par ámbar / sin base de respiración / leyendo / sin datos) como `MatrizChartSnapshotTests.test_hilos` (macOS, `ImageRenderer`, PNG `matriz_hilos.png` en `/tmp/noop-fer51/`, con `liquidMotionDisabled`); CHANGELOG |
| **D** `fondo de Hoy` | §5.1 montaje + §5.6 + xcstrings + `LiquidHoyScreen` + borrar huérfanos | pesado (app + Metal) · `ci-app` | build app; `HoyMatrizBuilderTests` (bandas sin bitácora, scrub par, sin vota); en simulador: fondo blanco, polvo vivo, parallax al scrollear (visible), pausa con hoja abierta (verificable con un `print` temporal o Instruments), color cambia con crossfade entre `primed`/`strained`; RM estático; `LiquidHoyEstadosRenderTests` verde; CHANGELOG |
| **E** `cara en vidrio` | §5.3 + §5.5 + hint + snapshots | pesado (rediseño de pantalla; UI ya aprobada en prototipo → sin nuevo gate de preview) · **`ci-app` obligatorio** (toca `Cenit/**`: host y builder) | `MatrizHoyFaceSnapshotTests` nuevos; `test_orden_a11y…` verde; en simulador es y en: 3 estantes, 8 módulos, sin filos, sin «votes», sin chevron, números 30/26 rodando al scrubbear las 8, hint una vez, cascada, press; `xxxLarge` (tope de la app, `CenitApp.swift:96`): dos columnas sin recortes — la columna única (≥ AX1) se verifica SOLO en el DS (`MatrizHoyFaceSnapshotTests` / el `#Preview` de la cara); VoiceOver lee 8 secciones en orden; CHANGELOG |
| **F** `estados+capturas` | los 8 `test_today_*` del arnés a mano (§11; 8 estados = 32 PNG en `docs/fixtures/`; el arnés fija **idioma `es` + locale `es_MX`** a propósito —`CenitScreenshotTests.baseArgs`; nunca `es-MX` como idioma (§7.10)— y no acepta idioma: el inglés se verifica A MANO en §11, no con fixtures), revisión de los 14 estados del arnés, ajustes menores de pulido que salgan de mirar las capturas (SIN cambiar copy), actualización de `docs/appmap` | ligero | capturas nuevas commiteadas; lista de verificación de §11 marcada en el PR |

**Gate independiente (`/qa`)** en B, C, D y E con los criterios de §10 como checklist; **`/simplify`**
tras D y E. Si `/qa` FALLA 3 rondas → parar y escalar al dueño (punto crítico).

`PolvoSimulacionTests` (mínimo): determinismo (misma entrada → misma partícula); `hash` en [0,1) y
distinto para índices vecinos; `cuenta` acotada y ≈ área/234; wrap (t grande → sigue en el lienzo);
continuidad **al cuadro real (20 Hz)**: la posición en `t` y `t + 1/20` difiere < 0.3 pt (salvo cuando la mota envuelve el lienzo); densidad: alfa medio de las partículas con
y > 0.8H mayor que con y < 0.23H; tono: en 2 000 índices, `.clima` ≈ 80 % ± 3 y cada satélite ≈ 5 % ± 2;
`neutra` fuerza `.neutra` y multiplica alfa por 0.55; `still` ⇒ `particula(t: 0) == particula(t: 99)`
y sin parallax; parallax mueve `y` −0.22·desplazamiento (envuelto).

---

## 10. Criterios de aceptación (globales, verificables)

1. Fondo de Hoy = blanco `papelTarjeta` + partículas Metal vivas; sin aurora ni orbes drift; el
   fondo NO scrollea; el héroe SÍ.
2. Las partículas derivan hacia arriba, respiran, toman el color del veredicto (`particulaVerde/Ambar/Roja`,
   neutra al 55 % en calibración/sin veredicto) con crossfade de 1.6 s, y se desplazan 22 % con el scroll.
3. Vidrio real (`glassEffect` en iOS 26 / `ultraThinMaterial` antes) al 30 % de blanco con borde de
   tinta al 8 %, radio 20, en los 8 módulos; el borde se ve en ambos caminos.
4. Tres estantes con «?» funcional (abre las mismas hojas que hoy): Deciden tu día (Sueño · FC) ·
   Te vigila (Guardián ancho) · Contexto (Carga · Esfuerzo / VFC · Estrés / Pasos ancho); sin
   «Bitácora»; sin filos; sin chevron **en el encabezado de los 8 módulos** (el camino legado de
   `renglones`, hoy sin emisor, conserva el suyo); el campo `vota` y su clave desaparecen del código
   (la cápsula ya no se pintaba).
5. Las 8 señales presentes con su gráfica actual (columnas, regla, colina, barras, línea rellena,
   escalerita, barras) y el guardián con dos hilos de puntos + banda + hilo central; HOY late.
6. Scrub en las 8 con número (30/26) rodando y sublabel cruzando; el par del guardián rueda; su
   subtítulo dice «las dos se salieron juntas» SOLO en noches `parFuera`; háptica por noche.
7. Honestidad: banda solo con base; punto «fuera» solo con marca del motor (≥ 1.02); sin lectura =
   hueco; el copy de HOY de cada módulo idéntico al actual (diff de strings = solo las 3 claves de §8).
8. Reduce Motion: sin parallax, sin deriva, sin respiración, sin latido, sin cascada, sin hint;
   todo visible y completo; scrub funcional.
9. Pausas: reloj del polvo detenido con hoja abierta, app en background, onboarding y pestaña oculta.
10. Sin Metal (Canvas) la pantalla se ve igual (menos densa); nunca en blanco.
11. Dynamic Type: `xxxLarge` (el tope de la app, FER-394) legible sin recortes en dos columnas; AX1 columna única solo en el DS (preview/test); VoiceOver: 8 secciones en `ordenA11y`, gráficas ajustables.
12. Rendimiento: scroll de Hoy sin hitches visibles en iPhone 17 Pro (device del dueño) y en el
    simulador iPhone SE 3.ª gen; si no se sostiene, plan B (§12) aplicado y anotado.
13. Los 14 PNG del arnés (`LiquidHoyEstadosRenderTests`) validan **fondo + héroe** (PR D; el arnés no
    monta la Matriz); la cara nueva se valida con `MatrizHoyFaceSnapshotTests` (PR E) y los 8
    fixtures de `CenitScreenshotTests` (PR F, idioma `es` + locale `es_MX`, como fija el arnés); el inglés se recorre a mano
    en simulador (§11); ningún estado nuevo ni perdido.
14. Todos los tests nuevos listados en §9 existen y pasan; ninguno de los existentes se borra salvo
    los que afirmaban lo que este cambio retira (`vota`, la costura dibujada) — y esos se reescriben,
    no se eliminan en bloque.

---

## 11. Definition of Done (comandos y qué mirar)

```bash
# Paquete (rápido) — por PR A/B/C/D
cd Packages/StrandDesign && swift build && swift test
swift test --filter PolvoSimulacionTests
swift test --filter EcosistemaMetalRenderTests        # se salta sin GPU; en el Mac del dueño corre
swift test --filter MatrizHilosTests
swift test --filter MatrizHoyFaceSnapshotTests        # PNGs a /tmp/noop-fer51/
swift test --filter LiquidHoyEstadosRenderTests       # PNGs a /tmp/noop-liquid/estado_*.png (14 estados)
swift run StrandDesignTokens                          # docs de tokens sin diff (CI design-tokens)

# App — por PR D/E/F (un build a la vez; esperar idle)
while pgrep -q swift-frontend; do sleep 30; done
Tools/prune-deriveddata.sh
Tools/verify.sh            # auto: linters + paquetes tocados + build-for-testing de la app
Tools/verify.sh app-tests  # CenitUnitTests en simulador (firmado)
# PR F · fixtures de Hoy — NO se usa `Tools/capture-screens.sh` tal cual: corre la CLASE entera
# (Entrenar incluido, ~40 PNG, sale != 0 si cualquier prueba falla) y hace `simctl shutdown all`
# al salir (mata simuladores ajenos). El script no se toca; se invoca el mismo xcodebuild a mano
# SOLO con los 8 `test_today_*`, en el device de las fixtures (iPhone 17 Pro Max, 1320×2868):
xcodebuild test -project Cenit.xcodeproj -scheme Cenit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -allowProvisioningUpdates -jobs 4 \
  $(for s in empty primed strained balanced rundown insufficient calibrating downloading; do \
      echo -n " -only-testing CenitUITests/CenitScreenshotTests/test_today_$s"; done) 2>&1 | tee /tmp/cap.log
grep '^FIXTURE_WRITTEN:' /tmp/cap.log | sed 's/^FIXTURE_WRITTEN: //' | while read f; do cp "$f" docs/fixtures/; done
python3 -c "import importlib.util as u; sp=u.spec_from_file_location('m','Tools/build-appmap.py'); m=u.module_from_spec(sp); sp.loader.exec_module(m); m.sync_shots('docs/fixtures'); m.build_served()"
git checkout docs/appmap/shots/entrenar-*.png   # el muro solo cambia en Hoy (un concern por PR)
# `baseArgs` pinea `-noop.acceptedTermsVersion 1.0` y `Terms.currentVersion` es "2.0" → F lo sube a
# 2.0 (si no, captura la puerta de Términos); y el estado vacío espera 5 s como los demás (a 2 s
# salía en blanco: su héroe entra con la misma coreografía de ~2.8 s).
python3 Tools/check-xcstrings-es.py && python3 Tools/check-xcstrings-emdash.py && python3 Tools/find-dead-strings.py
```

**A mano en simulador (PR D y E), iPhone 17 Pro · iOS 26 · es-MX y en:**
1. `-noop.fixture primed`: fondo blanco, polvo verde vivo, héroe verde; scrollear: el héroe se va,
   el polvo se queda y se mueve un poco (parallax); las tarjetas revelan polvo (vidrio); 3 estantes;
   Pasos ancho abajo; sin «votes», sin filos.
2. Scrub en las 8: número rueda, sublabel cruza, háptica; en el guardián el par rueda y el sub dice
   la fecha (o «las dos se salieron juntas» si el fixture trae par).
3. `-noop.fixture strained` (ámbar/rojo): color del polvo cambia; volver a `primed`: crossfade.
4. `-noop.fixture calibrating`: polvo neutro tenue; guardián sin banda de respiración; chip «Conociéndote».
5. Abrir el acta (ⓘ) y una hoja: el polvo se detiene (verificar con `print`/Instruments); cerrar: sigue.
6. Ajustes → Accesibilidad → Reducir movimiento: todo quieto, todo visible; scrub funciona; sin hint.
7. Dynamic Type `xxxLarge` (`xcrun simctl ui <udid> content_size extra-extra-extra-large`; los tamaños AX se capan a xxxLarge por `CenitApp.swift:96`); VoiceOver: recorrer los 8 módulos y ajustar el guardián con swipes.
8. Reduce Transparency: tarjetas opacas y legibles.
9. Si hay runtime iOS 18 instalado: mismo recorrido con vidrio de imitación y el borde visible; si
   no, anotarlo en el PR.
9b. `-noop.fixture empty` (T5, sin fuentes): el orbe dormido, `HealthAlertBanner` y —si hay carga
   real— `TrainingLoadStrip` sobre blanco + polvo neutro: legibles y sin bordes raros (ninguno se
   diseñó contra blanco puro; si algo se ve mal se anota, no se rediseña aquí).
10. Cambiar de pestaña y volver: el polvo se pausa/reanuda (la cascada NO se repite: corre una vez por lanzamiento).

**Perf (PR D/E):** Instruments → Animation Hitches (o el HUD de fps del simulador) durante 3 s de
scroll continuo en Hoy: sin hitches ≥ 2 cuadros sostenidos. En el iPhone del dueño (17 Pro) lo
verifica el dueño al construir; el implementador lo verifica en simulador y lo declara.

---

## 12. Riesgos y planes B (decididos)

| Riesgo | Señal | Plan B |
|---|---|---|
| Vidrio real sobre Metal no da 60 fps | hitches en el scroll con 8 módulos | receta a sólido `vidrioAtmosferaSolida` (blanco 45 %), sin material; anotar en PR y en el issue |
| El shader `vsPolvo` no compila en runtime | `recursos == nil` / assertion en DEBUG | Canvas n/2 a 12 Hz (ya previsto); arreglar el shader antes de mergear (el test offscreen lo cacha) |
| Parallax con `@Observable` recompone de más | CPU alto al scrollear | verificar que `TodayView.body` no lee `desplazamiento`; si aun así recompone, pasar el offset por `preference` directo al `UIViewRepresentable` |
| iOS 17: `onScrollGeometryChange` no existe | — | camino de preferencia ya existente (`TodayScrollOffsetKey`) |
| El borde de tinta no se ve con `glassEffect` | revisión visual | overlay explícito de `strokeBorder` en el camino nativo (ya requerido) |
| El vidrio NO muestrea la capa Metal (`MTKView`) y se ve gris plano | revisión visual en simulador/device (en el simulador iOS 26 SÍ muestrea: verificado en captura, las motas se ven a través de los módulos) | 1) `MTKView.isOpaque = false`, `layer.isOpaque = false` (ya); 2) probar `framebufferOnly = false`; 3) si sigue sin muestrear, montar el polvo con `Canvas` + `.drawingGroup()` (capa SwiftUI que el material sí ve) manteniendo `PolvoSimulacion` como spec — el Metal queda para el héroe; anotar en el PR |
| `vsPolvo` no compila y la librería (única) cae → héroe Y polvo en Canvas | `testElShaderCompilaYPintaAlgo` + los renders del polvo FALLAN; `assertionFailure` en DEBUG | NO hay degradación parcial posible: el gate es que el PR B no se mergea con la librería rota. `Recursos.polvo` opcional protege SOLO del fallo de `makeRenderPipelineState` del polvo (héroe intacto) |
| Density/alfa se ven distintos en device vs prototipo | juicio del dueño al construir | los 5 números viven en `PolvoSimulacion.Fisica`; se ajustan en un PR ligero posterior, no aquí |

---

## 13. Decisiones tomadas en este requerimiento (registro para el dueño; ninguna bloquea)

1. **Radio 20** (`LiquidRadius.modulo`) en vez de 24 del prototipo — reuso de token.
2. **Margen de módulos 16** (`s400`, = dock) y héroe/franja en 24 — la columna de vidrio y el dock comparten filo.
3. **Cabecera de estante en `tinta700`** (prototipo) — antes `tinta500`.
4. **Título de módulo en caja normal, `tituloGemela` 15 para todos** — la jerarquía estante(versalitas)/módulo(caja normal) del prototipo; el encabezado principal del módulo deja de alternar `tituloFila/tituloGemela` (`tituloFila` sigue vivo en los renglones legados y en otras pantallas).
5. **Dos tamaños de número (30/26)**, terciarias a 26 — el prototipo no tiene tercer tamaño.
6. **Sin chevron `›`** — el módulo es el botón (HIG: las tarjetas no llevan chevron).
7. **El sub del guardián en reposo NO añade la regla** («Una sola no cuenta; juntas, sí» del prototipo) — contradice FER-57 (la regla vive solo tras el «?»). Se conserva `matriz.guardian.sub`.
8. **Banda de los hilos asimétrica** (mismo mapeo que los puntos) — la geometría no puede contradecirse: un punto «al filo» cae en el borde de la banda; el lado bajo apretado dice «esto no vota».
9. **`fraccionFilo` reusado**; `MatrizCostura` queda como namespace (sin renombrar el payload `.costura`) — mínimo churn, invariantes heredados.
10. **Cascada con tokens del DS** (60 ms / 8 pt) en vez de 40 ms / 10 pt.
11. **`.liquidPress` sin brillo** — gramática de toque única (decisión previa).
12. **Hint de barrido**: hasta 3 veces o hasta el primer scrub, `@AppStorage("today.scrubHints")` (prefijo `today.` como `today.ecosistemaSeparaciones`) — espejo de `maxSeparacionHints`.
13. **20 Hz para el polvo** + redibujo bajo demanda con el scroll.
14. **`LiquidVeil(tone: nil)`** — el clima ya no tiñe el chrome superior.
14b. **Bajo Reduce Motion el cambio de clima del polvo es INSTANTÁNEO** (no el fade de 0.3 s que
    conservaba `LiquidHoyAmbient` «porque un fade no es movimiento»): a diferencia de la plasta,
    el polvo se dibuja con su reloj PAUSADO bajo RM y un fade necesitaría reloj; encender el reloj
    solo para el fade sería más código para un fundido de 0.3 s. Registrado como desviación.
14c. **El 20 % de motas con las cuatro identidades del héroe** (reposo · sueño · vigía temp · vigía
    resp, besadas 70/30 con el clima) SE CONSERVA: está en el prototipo que el dueño aprobó y no es
    decoración — es el eco de los satélites del héroe (los mismos colores, la misma paleta), la
    razón por la que el fondo se lee como «la misma materia» que el orbe. El fondo no vota: por eso
    el 80 % es el clima y las identidades van tenues.
15. **El «vota» se elimina del modelo** (no solo de la cara) — sin lector, sin campo.
16. **Sublabel del scrub del guardián** = fecha, y «· las dos se salieron juntas» solo con `parFuera`; el estado (chip) se calla al leer otra noche (regla existente).
17. **Sin nuevo gate de preview HTML**: el prototipo aprobado cubre los 4 veredictos y §6 fija los demás estados como «mismo contenido, nuevo envase». Si al implementar un estado se ve raro, se captura y se anota; no se cambia copy.
18. **Reduce Transparency**: sin trabajo extra (el sistema opaca los materiales); solo verificar.
19. **El dock no se toca** (su borde blanco desaparece sobre blanco; queda la sombra e3). Posible issue aparte.
20. **La temperatura sin juicio del motor se dibuja cruda contra el corte público** (como hoy en la costura y como aceptaron las 8 vueltas de FER-110): la banda de temperatura = ±`thermalOutC`, existe con cualquier lectura; un punto crudo ≥ 1 dice «superó el corte público», que es dato, no juicio. No se toca el camino de datos.
21. **`filoBanda` = `filoDentro` (0.58)** como borde superior de la banda de los hilos — no `fraccionFilo(1)` (0.75): con 0.75 lo marcado por el motor caía dentro de la banda a ojo.
22. **El inset de la gráfica del par sube a 8 pt** (`hilosInset`, para el anillo de HOY latiendo) y es el mismo del dedo (P-3).
23. **`.full` no se estira; gemelas sí** (`estirar`), ver §5.3.4.
24. **El ámbar del par es `atencion`, no `ambarClaro`** (contraste 4.08 vs 2.34 sobre blanco): el
    prototipo usaba el claro; el DS manda.
25. **Pasos gana scrub** (`scrubPasos`): «scrub en todas» era literal del dueño y Pasos era la única sin él.
26. **`presionado` es uno para toda la cara** (dos dedos en dos módulos = el primero deja de ceder antes de soltarlo; caso raro, sin estado colgado).
27. **`framebufferOnly` en default** (hipótesis de plan B, no requisito).
28. **El reloj del polvo se re-basa al reanudar tras 1 h** de sesión (presupuesto de `Float`).
29. **El «peor píxel» de la atmósfera es un piso de regresión, no una promesa AA**: sobre una
    mota roja al alfa máximo cuatro hues bajan a ~2.8:1 y `tinta500` a 3.86 (medido con la receta de A, test añadido en E);
    el fondo WCAG de un numeral es el blanco, y el test fija la holgura real para que nadie la
    consuma sin verlo. Bajar el alfa del polvo o tocar tokens del DS para «ganar» ese píxel se
    descartó (el polvo aprobado se vería más tenue; los hues son de toda la app).
30. **La columna única (≥ AX1) vive solo en el DS**: la app capa Dynamic Type en xxxLarge
    (FER-394); no se levanta el tope aquí (fuera de alcance) y no se borra el camino (es del
    componente).
31. **El arnés de capturas se corrige en F, no se rehace**: `baseArgs` sube `acceptedTermsVersion` a
    2.0 (la puerta de Términos tapaba las capturas desde FER-1003) y se corren solo los 8 `test_today_*` con el `xcodebuild` de §11 (el script corre la clase entera y apaga todos los simuladores; no se modifica).

---

## 14. Glosario de nombres nuevos (para no inventar otros)

`LiquidAtmosfera` · `AtmosferaEstado` · `PolvoSimulacion` (+ `.Fisica`, `.Particula`, `.Tono`,
`hash`, `cuenta`, `particula`) · `EcosistemaPolvoU` / MSL `PolvoU` · `vsPolvo` ·
`EcosistemaPolvoRenderer` · `AtmosferaMetalLienzo` · `LiquidGlassRecipe.superficieAtmosfera` ·
`LiquidColor.vidrioAtmosfera` / `.vidrioCanto` (.08) / `.vidrioAtmosferaSolida` ·
`LiquidType.valorTileL` / `.valorTileM` / `.valorTileTracking` · `MatrizHilos` (+ `.Geometria`) ·
`MatrizTokens.alturaHilos` / `hilosBaseTemp` / `hilosBaseResp` / `hilosAmplitud` / `hilosBaseAlfa` /
`LiquidAmbiente.particulaColor` (el switch clima→tinta de partícula, en `LiquidAtmosfera.swift`) / `MatrizCostura.filoBanda` / `LiquidAtmosfera.maxSesion` · `hilosFillAlfa` / `hilosAlertaAlfa` / `hilosPunto*` / `hilosAnillo*` / `hilosHueco*` / `hilosInset` (= `hilosAnillo + hilosAnilloLatido + hilosAnilloTrazo/2` = 8) / `hilosLatidoW` / `hilosNudoTrazo` / `hilosNudoDash` / `hilosColumnaFactor` / `margenModulos` / `modulo*` / `estante*` ·
`matriz.guardian.scrub.par` (clave) · `today.scrubHints` (AppStorage).
