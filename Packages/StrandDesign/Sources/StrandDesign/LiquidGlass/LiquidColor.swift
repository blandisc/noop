import SwiftUI

// MARK: - Liquid Glass · Color (handoff «Liquid Glass v1» §4.1)
//
// La paleta del sistema Liquid Glass: tinta (texto/trazos), papel (fondos), verde (única voz
// de marca), tonos de dato con asignación 1:1 por métrica, semánticos y los blancos de vidrio
// (alfas fijos de #FFFFFF que componen las recetas de LiquidGlassRecipe).
//
// Regla de tinte del dato: el tono tiñe SOLO la gota del icono (al 10–12 % de alfa, ver
// `LiquidIconDrop`) y el valor numérico. Nunca el fondo de la tarjeta.
//
// Hex exactos del handoff — no sustituir. Todo hex del sistema vive aquí; pantallas y
// componentes consumen estos tokens.

public enum LiquidColor {

    // MARK: Tinta (texto y trazos)

    /// Texto principal, iconos activos.
    public static let tinta900 = Color(hex: "#221D16")
    /// Texto secundario, kickers de fecha.
    public static let tinta700 = Color(hex: "#5C5648")
    /// Labels, captions neutros, iconos inactivos.
    public static let tinta500 = Color(hex: "#6F6857")
    /// Tracks de anillos, divisores de lista — tinta/900 al 10 %.
    public static let tinta10 = tinta900.opacity(0.10)
    /// Segmentos de barra inactivos, chips de día vacíos — tinta/900 al 7 %.
    public static let tinta7 = tinta900.opacity(0.07)

    // MARK: Papel (fondos)

    /// Inicio del degradado de pantalla.
    public static let papelAlto = Color(hex: "#F8F6EF")
    /// Fin del degradado de pantalla.
    public static let papelBajo = Color(hex: "#F0EDE4")
    /// Relleno del vidrio/lente (dock) — #FBF9F2 al 50 %.
    public static let papelDock = Color(hex: "#FBF9F2").opacity(0.38)
    /// Tarjeta de HOJA — blanco puro (mock canónico `.card{background:#FFFFFF}`): las
    /// tarjetas internas de las hojas van en blanco, no en el papel cálido de pantalla
    /// (#inject r3, pedido del dueño: «los elementos deberían ser blancos»).
    public static let papelTarjeta = Color(hex: "#FFFFFF")

    /// El degradado de pantalla papel/alto → papel/bajo (fondo base de toda pantalla Liquid).
    public static let papelGradient = LinearGradient(
        colors: [papelAlto, papelBajo], startPoint: .top, endPoint: .bottom)

    /// Fondo NEUTRO del rediseño (decisión del dueño, sesión /inject 2026-07-22: adiós al
    /// beige en Hoy) — el color lo ponen la aurora y los orbes, no el papel.
    /// Amend «El Tablero» (FER-28): un punto más frío y claro (#FEFEFD/#F3F4F2) para que la
    /// plasta monocroma del veredicto y la aurora fina de los filos respiren sobre un suelo
    /// casi blanco — el tercio del héroe es «cielo», el tablero «instrumento».
    public static let fondoAlto = Color(hex: "#FEFEFD")
    public static let fondoBajo = Color(hex: "#F3F4F2")
    public static let fondoGradient = LinearGradient(
        colors: [fondoAlto, fondoBajo], startPoint: .top, endPoint: .bottom)

    /// FER-51 · El papel plano del modo Matriz («medios tonos»): tinta sobre papel cálido,
    /// sin tarjetas — un solo lienzo para las gráficas de partículas. Plano a propósito
    /// (el dither necesita un suelo uniforme, no un degradado).
    public static let papelMatriz = Color(hex: "#F6F4EE")

    // MARK: Verde (única voz de marca)

    /// CTA, énfasis, palabra destacada del hero, pulsos.
    public static let verdePrimario = Color(hex: "#0C8F62")
    /// Deltas positivos, texto quiet.
    public static let verdeProfundo = Color(hex: "#00774B")
    /// SOLO halos/auroras de fondo (nunca texto).
    public static let verdeAurora = Color(hex: "#2EB27D")
    /// El verde claro de los orbes drift del fondo de Hoy (rgba(80,175,115,…) en el ensamble).
    public static let verdeOrbe = Color(hex: "#50AF73")
    /// Tope del degradado del botón primary (#12A06E → verde/primario).
    public static let verdeBotonAlto = Color(hex: "#12A06E")
    /// Texto sobre el botón primary (papel cálido, no blanco puro).
    public static let tintaSobreVerde = Color(hex: "#F4F1E8")

    // MARK: Tonos de dato (asignación 1:1, no intercambiables)

    /// Sueño.
    public static let indigo = Color(hex: "#5D5A9E")
    /// HRV.
    public static let cian = Color(hex: "#147C8C")
    /// FC en reposo.
    public static let rosa = Color(hex: "#B85068")
    /// Esfuerzo, temperatura de piel.
    public static let ambar = Color(hex: "#C4631F")
    /// Pasos.
    public static let teal = Color(hex: "#4C8998")
    /// Respiración.
    public static let azul = Color(hex: "#3B6FA0")
    /// Amanecer / halos cálidos.
    public static let oro = Color(hex: "#E8C24B")
    /// El ámbar CLARO del clima de atención (decisión del dueño /inject: un solo ámbar,
    /// familia naranja — el oro amarillo queda solo para el dial solar).
    public static let ambarClaro = Color(hex: "#E29A50")
    /// FER-51 · Identidad de TEMPERATURA DE PIEL en «Cosmos y Matriz» (§8 del REQ): un
    /// dorado profundo deliberadamente DISTINTO del ámbar de atención — la identidad y la
    /// alerta no pueden compartir hue. Oscurecido desde el #B08A3E del prototipo para
    /// contraste ≥ 4.5:1 como texto sobre `papelMatriz` (verificado en MatrizContrasteTests);
    /// las partículas/puntos pueden usar la familia clara, el TEXTO usa este.
    public static let doradoTemp = Color(hex: "#8A6A2B")
    /// Identidad de CARGA. Espejo de `InstrumentoTheme.dataOxygen` — un verde de bosque
    /// que NO es `verdePrimario`: esa es la única voz de marca (CTA y veredicto) y también
    /// la zona «bajo» del medidor de estrés, así que una métrica no puede vestirla sin
    /// decir dos cosas con el mismo hex (auditoría de los sellos, ago-2026).
    public static let verdeCarga = Color(hex: "#3F7A5E")

    /// FER-60 · Heatmap de ESTRÉS (contexto, NO vota): una rampa de calor de tres pasos
    /// — nivel bajo = la tinta neutra de la sección (`tinta500`, sin calor); medio y alto
    /// suben por la familia OCRE→SIENA. Deliberadamente DISTINTOS del `atencion`/`ambar`
    /// #C4631F (el naranja de alerta que SÍ vota, en el guardián) y del `negativo` #B3402A:
    /// el estrés es acompañante, no puede vestir el color de la alarma que decide (mismo
    /// principio que `doradoTemp`). Nunca verde (ese es el veredicto). Oscurecidos para
    /// contraste ≥ 4.5:1 como texto sobre `papelMatriz` (verificado en MatrizContrasteTests).
    public static let estresMedio = Color(hex: "#A9752F")
    public static let estresAlto = Color(hex: "#9C5B2E")

    // MARK: Partículas del Ecosistema (FER-10)
    //
    // La tinta de las esferas de partículas del héroe: más profunda que los tonos de dato
    // porque un punto de 0.7–2.2 pt con alfa ≤ .65 lava cualquier tono medio. Un color por
    // clima; el ámbar de atención reusa `atencion` (las decisoras siguen verdes ahí — el
    // ámbar entra por el guardián).

    /// Partícula en rango/atención (verde tinta, más profundo que `verdePrimario`).
    // MARK: Celda sin dato (mosaicos de calendario)

    /// El cuadro de un día SIN lectura en un mosaico de calendario. Es tinta al 7 %: se ve como
    /// un hueco en el papel, no como un cuarto estado con voz propia — un día sin dato no dice
    /// nada del cuerpo y no debe competir con los que sí.
    public static let celdaVacia = tinta900.opacity(0.07)

    /// El mismo hueco cuando debe leerse a tamaño de pip en una leyenda, donde 7 % desaparece.
    public static let celdaVaciaPip = tinta900.opacity(0.14)

    public static let particulaVerde = Color(hex: "#10694E")
    /// Partícula en desgaste (rojo tinta, más profundo que `negativo`).
    public static let particulaRoja = Color(hex: "#963426")
    /// FER-22 (decisión B del dueño): en ATENCIÓN el orbe mismo absorbe el ámbar —
    /// la variante partícula del hue de atención, ahondada como sus hermanas.
    public static let particulaAmbar = Color(hex: "#96501A")
    /// Partícula neutra: calibrando y el orbe del guardián tranquilo.
    public static let particulaNeutra = Color(hex: "#737670")
    /// Partícula blanca: el realce especular puro de la simulación del orbe (tinta `.blanco`).
    /// El sistema es dueño del blanco, no el componente de superficie (FER-31).
    public static let particulaBlanca = Color.white

    /// Las MISMAS tintas de partícula de arriba, en componentes sRGB 0–1.
    ///
    /// Existen porque la entrada (FER-41) tiene que INTERPOLAR del gris neutro al color del
    /// veredicto, y un `Color` de SwiftUI no expone sus componentes de forma portátil: leerlos
    /// exigiría `UIColor`/`NSColor`, que este paquete no puede importar (compila para iOS,
    /// macOS y watchOS por igual). Interpolar con dos capas superpuestas en vez de con números
    /// deja al orbe perdiendo densidad a medio teñido, así que los números son la vía honesta.
    ///
    /// Cada terna es el hex de su hermana de arriba: si una cambia, la otra cambia con ella.
    /// `LiquidColorTintaTests` lo verifica para que no puedan separarse en silencio.
    public enum ParticulaRGB {
        public static let verde: (r: Double, g: Double, b: Double) = (0x10 / 255, 0x69 / 255, 0x4E / 255)
        public static let roja: (r: Double, g: Double, b: Double) = (0x96 / 255, 0x34 / 255, 0x26 / 255)
        public static let ambar: (r: Double, g: Double, b: Double) = (0x96 / 255, 0x50 / 255, 0x1A / 255)
        public static let neutra: (r: Double, g: Double, b: Double) = (0x73 / 255, 0x76 / 255, 0x70 / 255)
    }

    /// Interpola en sRGB de la tinta neutra a `destino` (`k` = 0 neutra … 1 destino). Es el
    /// teñido de la entrada: un solo color por frame, sin capas apiladas que se laven.
    public static func particulaTeñida(hacia destino: (r: Double, g: Double, b: Double),
                                       k: Double) -> Color {
        let u = min(1, max(0, k))
        let n = ParticulaRGB.neutra
        return Color(.sRGB,
                     red: n.r + (destino.r - n.r) * u,
                     green: n.g + (destino.g - n.g) * u,
                     blue: n.b + (destino.b - n.b) * u,
                     opacity: 1)
    }
    /// El rojo CLARO del clima de alerta (par simétrico de `ambarClaro` — el ambiente de
    /// alerta usaba `rosa`, que es el tono 1:1 de FC en reposo, no un clima).
    public static let rojoClaro = Color(hex: "#E06C56")

    // MARK: Semánticos

    /// Deltas a favor.
    public static let positivo = Color(hex: "#00774B")
    /// Fuera de rango.
    public static let atencion = Color(hex: "#C4631F")
    /// Deltas en contra.
    public static let negativo = Color(hex: "#B3402A")
    /// La voz de «atención» PARA TEXTO CHICO: el ámbar #C4631F ronda 3.5:1 sobre vidrio
    /// (falla AA); esta variante oscurecida pasa 4.5:1 (pasada UI /inject 2026-07-22).
    public static let atencionTexto = Color(hex: "#8F4712")

    // MARK: Blancos de vidrio (alfas fijos de #FFFFFF — §4.1)

    /// `.92` — highlight especular.
    public static let vidrioEspecular = Color.white.opacity(0.92)
    /// `.9` — borde de esfera / gota.
    public static let vidrioBordeFuerte = Color.white.opacity(0.9)
    /// `.85` — bordes de vidrio.
    public static let vidrioBorde = Color.white.opacity(0.85)
    /// `.8` — borde de pastilla + inner-highlights.
    public static let vidrioBordePastilla = Color.white.opacity(0.8)
    /// `.72` — borde de superficie (tiles).
    public static let vidrioBordeSuperficie = Color.white.opacity(0.72)
    /// `.55` — streak especular del dock.
    public static let vidrioStreak = Color.white.opacity(0.55)
    /// `.5` — relleno lente/dial.
    public static let vidrioLente = Color.white.opacity(0.38)
    /// `.35` — realce especular de la pastilla del selector del dock en la IMITACIÓN pre-iOS 26
    /// (el vidrio nativo no la necesita). Nombrado (FER-31) para que el `LiquidTabBar` no lleve
    /// `Color.white.opacity(...)` crudo.
    public static let vidrioRealcePastilla = Color.white.opacity(0.35)
    /// `.46` — relleno pastilla. Subido de 0.32 para estabilizar el vidrio durante
    /// el arrastre de la hoja: menos backdrop = menos «blanqueo» al bajar (pedido del dueño).
    public static let vidrioPastilla = Color.white.opacity(0.46)
    /// `.46` — relleno superficie tile. Subido de 0.30 (canon previo del doc §1
    /// LIQUID-GLASS.md) por la misma razón — la tabla dependía del backdrop y cambiaba
    /// de valor al arrastrar/scrollear la hoja.
    public static let vidrioSuperficie = Color.white.opacity(0.46)

    // MARK: Vidrio de «El Tablero» (FER-28 — módulos de Hoy sobre fondo casi blanco)
    //
    // Sobre el suelo claro nuevo, un vidrio blanco liso se «lava» y pierde el filo. Tres
    // tokens lo devuelven al terreno de lo caro: densidad progresiva del relleno hacia abajo,
    // un canto exterior de tinta hairline que dibuja el borde contra el papel, y la
    // «refracción honesta» (la plasta se ve más viva a través del vidrio que fuera).

    /// Canto exterior hairline de un módulo — tinta/900 al 6 %, 0.5 pt. Es lo que separa

    // MARK: - Pantalla de detalle (FER-102)

    /// El velo del tono para la franja de sección de una pantalla de detalle: **4 %**, el
    /// mismo alfa que `LiquidVeil`. Plano, no degradado — un gradiente vuelve la franja una
    /// barra de cabecera teñida, y la franja es una costura, no un encabezado.
    /// El gris neutro de formulario era lo más «papel» que quedaba en la pantalla.
    public static func franjaVelo(_ tone: Color) -> Color { tone.opacity(0.04) }

    /// El tono **oscurecido lo justo** para que sirva de campo teñido con tinta calada.
    ///
    /// POR QUÉ EXISTE: el campo de `LiquidCampoMetrica` cala papel (`papelAlto`) sobre el tono
    /// de la métrica. Medido contra WCAG AA, **solo el índigo de Sueño pasa**: el rótulo al 85 %
    /// da 4.62:1 sobre índigo pero 3.16:1 sobre el ámbar de Esfuerzo, y sobre rosa, verde y
    /// ámbar **no pasa ni a opacidad plena** — o sea, subir el alfa no puede arreglarlo. La
    /// única salida es bajar la luminancia del tono. (El mismo defecto vive hoy en el papel,
    /// con `OnFieldOpacity.secondary` = .75 en los 15 call sites de `HeroInvertido`.)
    ///
    /// Mezcla negro en pasos de 1 % hasta que el rótulo pase 4.5:1, y se detiene ahí — no
    /// aplica un factor fijo. Así **el índigo de Sueño sale intacto** (necesita 0 %) y cada
    /// tono paga solo lo suyo: azul 8 %, cian 13 %, rosa 14 %, verde 21 %, ámbar 22 %. Un tono
    /// nuevo en la familia no puede romper el contraste sin que nadie se entere.
    ///
    /// Es una función pura sobre sRGB: `LiquidCampoContrasteTests` la comprueba en frío.
    public static func tonoCampo(_ tone: Color) -> Color {
        let c = tone.rgbaComponents
        var k = 0.0
        while k <= 0.60 {
            let oscuro = (r: c.r * (1 - k), g: c.g * (1 - k), b: c.b * (1 - k))
            if contraste(calado: papelAltoRGB, alfa: LiquidCampo.alfaRotulo, sobre: oscuro) >= 4.5 {
                break
            }
            k += 0.01
        }
        return Color(red: c.r * (1 - k), green: c.g * (1 - k), blue: c.b * (1 - k))
    }

    /// `#F8F6EF` en componentes — el calado del campo, para la matemática de contraste.
    static let papelAltoRGB = (r: 248.0 / 255, g: 246.0 / 255, b: 239.0 / 255)

    /// Razón de contraste WCAG 2.1 de `calado` compuesto al alfa dado sobre un fondo opaco.
    static func contraste(calado: (r: Double, g: Double, b: Double), alfa: Double,
                          sobre fondo: (r: Double, g: Double, b: Double)) -> Double {
        func canal(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        func luminancia(_ c: (r: Double, g: Double, b: Double)) -> Double {
            0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b)
        }
        let compuesto = (r: calado.r * alfa + fondo.r * (1 - alfa),
                         g: calado.g * alfa + fondo.g * (1 - alfa),
                         b: calado.b * alfa + fondo.b * (1 - alfa))
        let a = luminancia(compuesto), b = luminancia(fondo)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// «caro» de «lavado» sobre fondo claro: un filo de tinta bajo el borde blanco.
    public static let vidrioCanto = tinta900.opacity(0.06)

    /// Factor de saturación del backdrop de un módulo («refracción honesta»): lo que pasa
    /// detrás del vidrio se ve 1.28× más vivo que fuera. En iOS 26 el vidrio nativo aporta
    /// refracción real; en el fallback se aplica sobre el material que muestrea el fondo.
    public static let vidrioRefraccion: Double = 1.28

    /// Relleno blanco de un módulo por índice de profundidad (0…3): la densidad sube hacia
    /// abajo — .42 → .46 → .50 → .54 — para que la pila de vidrio gane cuerpo conforme baja.
    /// Índices fuera de rango se clampan a los extremos.
    public static func vidrioSuperficieDensidad(_ index: Int) -> Color {
        let alfas: [Double] = [0.42, 0.46, 0.50, 0.54]
        let i = min(max(index, 0), alfas.count - 1)
        return Color.white.opacity(alfas[i])
    }

    // MARK: Plasta de «El Tablero» (FER-28 — 4 masas pálidas monocromas del veredicto)
    //
    // La plasta es UNA familia de clima a la vez, cuatro masas suaves (blur 52) que laten y
    // derivan detrás del vidrio. Son tonos MUY pálidos —luminancia casi constante entre
    // climas— porque una masa de 320 pt difuminada a alfa .5 sobre suelo casi blanco lava
    // cualquier tono medio. El verde es el canon aprobado (mockup); ámbar/rojo/neutro son la
    // misma coreografía trasladada de hue a luminancia pareja (crossfade de 1.6 s al cambiar).

    /// Verde «en rango» — el canon del mockup aprobado (principal → derivas).
    public static let plastaVerde: [Color] = [
        Color(hex: "#A9DFC6"), Color(hex: "#CBEBDA"),
        Color(hex: "#93D4B4"), Color(hex: "#DFF2E7"),
    ]
    /// Ámbar «atención» — familia cálida a la misma luminancia.
    public static let plastaAmbar: [Color] = [
        Color(hex: "#F0D8B4"), Color(hex: "#F7E7CE"),
        Color(hex: "#E9C79A"), Color(hex: "#FBEEDC"),
    ]
    /// Rojo «alerta» — familia rosada a la misma luminancia.
    public static let plastaRojo: [Color] = [
        Color(hex: "#F1CBC3"), Color(hex: "#F8DDD8"),
        Color(hex: "#ECB6AD"), Color(hex: "#FBE5E1"),
    ]
    /// Neutro «calibrando» — gris cálido, sin fingir veredicto.
    public static let plastaNeutra: [Color] = [
        Color(hex: "#DCE0DA"), Color(hex: "#E9ECE6"),
        Color(hex: "#D1D6CF"), Color(hex: "#EFF1EC"),
    ]
}

// MARK: - Estado de señal (§5.2 SignalOrb · §5.5 CargaBar)

/// El estado semántico compartido por las señales: `ok` habla en verde, `atencion` en ámbar.
/// Cada superficie toma de aquí su anillo, caption, tinte de esfera y status — nunca los
/// re-deriva.
public enum LiquidSignalState: Sendable {
    case ok, atencion

    /// El tono base del estado (tiñe esfera, glow e/2 y gradiente de segmento activo).
    public var tone: Color {
        switch self {
        case .ok: return LiquidColor.verdePrimario
        case .atencion: return LiquidColor.atencion
        }
    }

    /// El anillo de progreso del orbe (`rgba(tono, 0.45)` ok / `0.6` atención).
    public var ring: Color {
        switch self {
        case .ok: return LiquidColor.verdePrimario.opacity(0.45)
        case .atencion: return LiquidColor.atencion.opacity(0.6)
        }
    }

    /// El caption/status del estado. Pasada UI /inject: en ok habla TINTA (el único verde
    /// protagonista es la palabra del veredicto); en atención, el ámbar de texto AA.
    public var caption: Color {
        switch self {
        case .ok: return LiquidColor.tinta500
        case .atencion: return LiquidColor.atencionTexto
        }
    }

    /// El color del texto de status de CargaBar (verde/primario, no profundo).
    public var status: Color {
        switch self {
        case .ok: return LiquidColor.verdePrimario
        case .atencion: return LiquidColor.atencion
        }
    }
}

// MARK: - Tono de delta (§5.1 MetricTile)

/// Dirección de un delta contra la base personal. `up` = a favor, `down` = en contra,
/// `neutral` = en tu base. El color sale de los semánticos — el caption jamás inventa color.
public enum LiquidDeltaTone: Sendable {
    case up, down, neutral

    public var color: Color {
        switch self {
        case .up: return LiquidColor.positivo
        case .down: return LiquidColor.negativo
        case .neutral: return LiquidColor.tinta500
        }
    }
}

#if DEBUG
#Preview("Liquid · Color") {
    let swatch: (String, Color) -> AnyView = { name, color in
        AnyView(HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 40, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(LiquidColor.tinta10))
            Text(name).font(.system(size: 11)).foregroundStyle(LiquidColor.tinta700)
        })
    }
    return ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            Text("TINTA · PAPEL · VERDE").font(LiquidType.kicker).tracking(LiquidType.kickerTracking)
                .foregroundStyle(LiquidColor.tinta500)
            swatch("tinta/900", LiquidColor.tinta900)
            swatch("tinta/700", LiquidColor.tinta700)
            swatch("tinta/500", LiquidColor.tinta500)
            swatch("verde/primario", LiquidColor.verdePrimario)
            swatch("verde/profundo", LiquidColor.verdeProfundo)
            swatch("verde/aurora", LiquidColor.verdeAurora)
            Text("TONOS DE DATO").font(LiquidType.kicker).tracking(LiquidType.kickerTracking)
                .foregroundStyle(LiquidColor.tinta500)
            swatch("índigo · sueño", LiquidColor.indigo)
            swatch("cian · hrv", LiquidColor.cian)
            swatch("rosa · fc reposo", LiquidColor.rosa)
            swatch("ámbar · esfuerzo/piel", LiquidColor.ambar)
            swatch("teal · pasos", LiquidColor.teal)
            swatch("azul · respiración", LiquidColor.azul)
            swatch("oro · amanecer", LiquidColor.oro)
            Text("ECOSISTEMA (FER-10)").font(LiquidType.kicker).tracking(LiquidType.kickerTracking)
                .foregroundStyle(LiquidColor.tinta500)
            swatch("partícula · verde", LiquidColor.particulaVerde)
            swatch("partícula · roja", LiquidColor.particulaRoja)
            swatch("partícula · ámbar", LiquidColor.particulaAmbar)
            swatch("partícula · neutra", LiquidColor.particulaNeutra)
            swatch("rojo claro · clima alerta", LiquidColor.rojoClaro)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(LiquidColor.papelGradient)
}
#endif
