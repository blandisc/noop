import SwiftUI

// MARK: - Liquid Glass · Núcleo de gráficas (épico hoja de resumen, F3b/F4)
//
// Las piezas COMPARTIDAS de la familia de gráficas Liquid (explorador de niveles, trend
// 14d, curva FC): el estado común, la banda común y el motor de plot que dibuja washes
// (I1), grid, eje X de fechas, serie con joya y el overlay de scrub (I2). Decisión del
// contrato §4: RE-VESTIR la interacción existente, no rediseñarla — el gesto es el
// `scrubGesture` público de TrendChart, el snap es `ChartScrubMath`, la háptica es
// `ChartHaptics` y la regla es `CrosshairRule`; aquí solo cambia la PIEL (tokens
// `LiquidChart`/`LiquidColor`).
//
// Copy: todo string llega YA localizado del caller (contrato D3); el DS no conoce locales.
// Por eso el eje, el popup y la frase de VoiceOver se arman con CLOSURES del caller y el
// paquete jamás inventa un separador ni un formato de fecha.

// MARK: - Estado común

/// El estado de una gráfica de la hoja Liquid. `.vacio` carga el mensaje ya localizado
/// del caller («Sin lecturas en este rango»).
public enum LiquidChartEstado: Equatable, Sendable {
    case datos
    case cargando
    case vacio(String)
}

// MARK: - Banda común (I1)

/// Una banda de clasificación detrás de la serie. Intervalo half-open `[lo, hi)` como
/// `MetricLevels`; `lo == nil` = abierta por abajo, `hi == nil` = abierta por arriba.
/// `activa` ilumina su wash (I1: 8 % reposo / 16 % activa / 3 % el resto).
public struct LiquidChartBanda: Sendable {
    public let lo: Double?
    public let hi: Double?
    public let color: Color
    public let activa: Bool

    public init(lo: Double?, hi: Double?, color: Color, activa: Bool) {
        self.lo = lo
        self.hi = hi
        self.color = color
        self.activa = activa
    }

    /// Una banda SIN cotas no contiene NADA — la misma guarda que `TrendBand.contains`
    /// (`TrendChart.swift:47`). Sin ella los dos lados abiertos se cancelan y la banda se
    /// traga todo valor: como este resolver decide el wash, el color de cada disco, el del
    /// anillo del scrub y el del popup, un caller que olvidara sus cortes lavaría la gráfica
    /// entera con un solo color y nadie lo notaría. Decir «no tengo intervalo» es honesto;
    /// decir «todo» es una mentira que la pantalla no distingue de una clasificación real.
    func contiene(_ v: Double) -> Bool {
        guard lo != nil || hi != nil else { return false }
        return (lo == nil || v >= lo!) && (hi == nil || v < hi!)
    }
}

// MARK: - Altos de gráfica (paridad Instrumento, contrato §5 «candidatos menores»)

/// Altos de la familia: 144 explorador, 140 trend 14d, 260 curva FC, 32 mini (renglón del
/// guardián: banda + línea + joya + scrub, sin título ni ejes).
enum LiquidChartAlto {
    /// Explorador de niveles. 168→144 (auditoría Grok+DeepSeek 2026-08-03): a 168 la tarjeta
    /// de nivel+plot dominaba la hoja; el mock la traza a ~130 de área útil (+ franja de eje).
    /// Debe ir de la mano con `LiquidSheetSkeleton.Alto.grafica`, o la hoja brinca al cargar.
    static let explorador: CGFloat = 144
    static let trend: CGFloat = 140
    static let curvaFC: CGFloat = 260
    static let mini: CGFloat = 32
}

// MARK: - Índice que lee VoiceOver

/// Resuelve qué punto nombra el `accessibilityValue` de una gráfica: el punto bajo el dedo
/// mientras dura el scrub, o el ÚLTIMO de la serie en reposo. Lo comparten las tres
/// envolturas para que la regla sea una sola.
enum LiquidChartA11y {
    static func indice(_ scrub: Int?, _ n: Int) -> Int {
        guard n > 0 else { return 0 }
        if let s = scrub, s >= 0, s < n { return s }
        return n - 1
    }
}

// MARK: - Rotor «Gráficas» / audio graph (FER-29 · AXChartDescriptor)

/// Publica la serie del plot al rotor de gráficas de VoiceOver (audio graph). Reusa los
/// mismos closures de formato del scrub para que cada punto se lea con la MISMA cabeza
/// que el popup táctil y el `accessibilityValue` (contrato D3: el DS no inventa formatos).
///
/// **Cómo probarlo (iPhone):** VoiceOver ON → enfoca la gráfica → rotor (giro de dos
/// dedos) → elige «Gráficas» → desliza un dedo arriba/abajo para recorrer fecha → valor.
/// El label/value de la gráfica siguen intactos; el rotor es ADICIONAL.
///
/// Interno (no `private`) para poder verificar en frío `makeChartDescriptor()` sin
/// montar VoiceOver en el host de tests.
struct LiquidChartAXDescriptor: AXChartDescriptorRepresentable {
    let puntos: [(fecha: Date, valor: Double)]
    let dominio: ClosedRange<Double>
    var formatoValorScrub: ((Double) -> String)? = nil
    var formatoFechaScrub: ((Date) -> String)? = nil
    var formatoFechaEje: ((Date) -> String)? = nil
    var formatoScrub: ((Double, Date) -> String)? = nil

    func makeChartDescriptor() -> AXChartDescriptor {
        let categorias: [String] = Self.categoriasUnicas(puntos.map { formatearFecha($0.fecha) })
        let xAxis = AXCategoricalDataAxisDescriptor(title: "", categoryOrder: categorias)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "",
            range: dominio.lowerBound...dominio.upperBound,
            gridlinePositions: [],
            valueDescriptionProvider: { [formatoValorScrub] (v: Double) -> String in
                if let f = formatoValorScrub { return f(v) }
                // Sin formato de valor: el número crudo. La etiqueta por punto (si hay
                // `formatoScrub`) carga la frase compuesta completa.
                return String(format: "%g", v)
            }
        )
        let puntosDatos: [AXDataPoint] = zip(puntos, categorias).map { (p, cat) in
            // Misma cabeza que `valorA11y` / popup: frase compuesta del caller si existe.
            let label: String? = {
                if let f = formatoScrub { return f(p.valor, p.fecha) }
                if let f = formatoValorScrub { return f(p.valor) }
                return nil
            }()
            return AXDataPoint(x: cat, y: p.valor, label: label)
        }
        let serie = AXDataSeriesDescriptor(name: "", isContinuous: true, dataPoints: puntosDatos)
        return AXChartDescriptor(
            title: nil,
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [serie]
        )
    }

    /// Fecha del eje X: popup del scrub → eje dibujado → fecha corta local (último recurso
    /// honesto; el DS no conoce locales del producto).
    private func formatearFecha(_ d: Date) -> String {
        if let f = formatoFechaScrub { return f(d) }
        if let f = formatoFechaEje { return f(d) }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .none
        return fmt.string(from: d)
    }

    /// El eje categórico exige categorías únicas; dos puntos con la misma etiqueta de
    /// fecha (p. ej. mismo día en series horarias mal formateadas) se desambiguán con un
    /// sufijo, para no colapsar puntos en el rotor.
    private static func categoriasUnicas(_ base: [String]) -> [String] {
        var vistas: [String: Int] = [:]
        return base.map { cat in
            let n = vistas[cat, default: 0]
            vistas[cat] = n + 1
            return n == 0 ? cat : "\(cat) (\(n + 1))"
        }
    }
}

/// Aplica el descriptor solo cuando hay serie; una serie vacía no publica rotor vacío.
private extension View {
    @ViewBuilder
    func liquidChartAXDescriptor(_ descriptor: LiquidChartAXDescriptor?) -> some View {
        if let descriptor {
            self.accessibilityChartDescriptor(descriptor)
        } else {
            self
        }
    }
}

// MARK: - Popup del scrub (reemplaza el chip cápsula negro)

/// La pieza que nombra el punto scrubbeado: gota del color de SU banda + valor + fecha,
/// sobre papel alto con borde de tinta y elevación `e/1`. Rectangular con esquinas suaves
/// (`LiquidRadius.control`), nunca cápsula — habla el mismo idioma que el selector (I3).
///
/// Ambas líneas llegan YA formateadas del caller (D3). El tamaño de texto se topa en AX2:
/// es una pieza TRANSITORIA que vive dentro del plot; sin tope, en AX5 mediría más alto que
/// el propio área de datos y el clamp de `ChartTooltipPlacement` degeneraría. La lectura
/// accesible la sirve el `accessibilityValue` de la gráfica, que escala sin límite.
struct LiquidScrubPopup: View {
    let valor: String
    var fecha: String? = nil
    let color: Color

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
        return HStack(spacing: LiquidSpace.s200) {
            Circle()
                .fill(color)
                .frame(width: LiquidChart.popupPuntoDiametro,
                       height: LiquidChart.popupPuntoDiametro)
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: valor)
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.tinta900)
                if let fecha {
                    Text(verbatim: fecha)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta700)
                }
            }
        }
        .padding(.horizontal, LiquidSpace.s200)
        .padding(.vertical, LiquidSpace.s150)
        // Vidrio, no papel beige (pedido del dueño /inject): base del sistema + un
        // velo blanco, que es el mismo lenguaje de las recetas de vidrio.
        .background { LiquidGlassBase.ultraFino(forma) }
        .background(LiquidColor.vidrioStreak, in: forma)   // white .55 — token del sistema
        .overlay(forma.strokeBorder(LiquidColor.tinta10, lineWidth: 1))
        .liquidShadow(LiquidElevation.e1, silhouette: forma)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// El popup MEDIDO y colocado con `ChartTooltipPlacement` (patrón `PositionedTooltip`):
/// va arriba y AL LADO del punto —nunca encima— se voltea cuando no cabe y se clampea al
/// RECT DEL PLOT (no al `GeometryReader` completo), para no montarse sobre la canaleta de
/// labels Y ni sobre la franja de fechas del eje X.
///
/// El centrado en la x del ancla tapaba justo el dato que el popup nombra: recortaba el
/// anillo del scrub y partía la curva en muñones sueltos que se leían como un glitch.
private struct LiquidScrubPopupColocado: View {
    let valor: String
    let fecha: String?
    let color: Color
    /// Ancla en coordenadas del rect del plot (ya sin canaleta).
    let anclaje: CGPoint
    /// Rect del plot: ancho útil × piso (sin la franja del eje X).
    let contenedor: CGSize
    /// Desplazamiento de vuelta a coordenadas del GeometryReader.
    let canaleta: CGFloat

    @State private var medido: CGSize = .zero

    var body: some View {
        // Estimación de arranque solo para el primer frame; el `onAppear` la corrige.
        let tam: CGSize = medido == .zero ? CGSize(width: 88, height: 34) : medido
        let p: CGPoint = ChartTooltipPlacement.positionBeside(anchor: anclaje,
                                                              tooltipSize: tam,
                                                              in: contenedor,
                                                              gap: LiquidSpace.s200)
        return LiquidScrubPopup(valor: valor, fecha: fecha, color: color)
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { medido = g.size }
                        .onChange(of: g.size) { _, nuevo in medido = nuevo }
                }
            }
            .position(x: p.x + canaleta, y: p.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Motor de plot compartido

/// El plot compartido de la familia: washes de banda (I1), grid con `gridAlfa`, fila de
/// fechas del eje X, serie con puntos por dato y joya endpoint, y scrub (I2: regla vertical
/// punteada + anillo por banda + popup rectangular medido). La interacción reusa las piezas
/// públicas del paquete (`scrubGesture` / `ChartScrubMath` / `ChartHaptics` /
/// `CrosshairRule`) — nunca se reimplementa el gesto.
struct LiquidChartPlot: View {
    /// La serie que el plot DIBUJA: **siempre ordenada por fecha**. La garantía vive en el
    /// componente (como en el init viejo de `TrendChart`, que ordenaba sin preguntar) y no
    /// en cada caller: con `mapeoPorTiempo` una serie desordenada además rompe
    /// `fraccionTiempo`, que toma `first`/`last` como extremos del span.
    let puntos: [(fecha: Date, valor: Double)]
    /// Para cada punto ORDENADO, su índice en el arreglo que pasó el caller. Es la
    /// identidad en el caso normal (serie ya ordenada) y el único puente correcto para
    /// `onScrub` / `scrubFijo`: quien los lee indexa SU arreglo, no el nuestro.
    /// Interno (no privado) a propósito: es lo que verifica el test del orden defensivo —
    /// que el índice publicado siga siendo el del caller aunque la serie llegue revuelta.
    let ordenOriginal: [Int]
    let bandas: [LiquidChartBanda]
    let dominio: ClosedRange<Double>
    let ticksY: [(valor: Double, etiqueta: String)]
    let tono: Color
    let puntoHoy: (fecha: Date, valor: Double)?
    let hoyAnillo: Bool
    /// Línea horizontal de REFERENCIA (p. ej. la FC en reposo de anoche bajo la curva del
    /// día — FER-103 · TND-23): punteada, en la misma tinta que la regla del scrub. Es
    /// CONTEXTO, no dato, así que vive con washes y grid, fuera del fade de entrada de la
    /// serie. La etiqueta que la nombra es del caller (el caption bajo la gráfica, paridad
    /// del papel); solo se pinta si cae dentro del dominio. `nil` = sin línea.
    var lineaRef: Double? = nil
    /// La frase COMPUESTA «valor · fecha» del caller. Es la voz de VoiceOver (el DS no
    /// puede acuñar el separador ni el orden — D3) y el fallback de una línea del popup
    /// cuando el caller no parte el formato en dos.
    var formatoScrub: ((Double, Date) -> String)? = nil
    /// Línea de VALOR del popup (la de arriba). Si viene, gana sobre `formatoScrub`.
    var formatoValorScrub: ((Double) -> String)? = nil
    /// Línea de FECHA del popup (la de abajo). Solo se pinta junto a `formatoValorScrub`.
    var formatoFechaScrub: ((Date) -> String)? = nil
    /// Etiqueta de la fila de fechas bajo el plot. `nil` = SIN eje X (geometría previa
    /// intacta: respiro simétrico arriba y abajo, sin franja reservada).
    var formatoFechaEje: ((Date) -> String)? = nil
    /// `false` (por defecto) reparte los puntos por ÍNDICE — correcto para una serie
    /// diaria, donde cada punto es un día y no hay huecos. `true` reparte por TIEMPO real:
    /// obligatorio cuando la serie puede tener huecos (la curva FC del día se arma con
    /// `GROUP BY ts / bucket` y los buckets sin muestras simplemente no existen), porque un
    /// eje de horas repartido por índice afirmaría una linealidad temporal falsa.
    var mapeoPorTiempo: Bool = false
    /// `false` (por defecto) deja TODOS los puntos por dato a opacidad plena. `true` los
    /// apaga fuera de la banda activa — paridad `GraficaRangos`, donde el apagado es la
    /// respuesta a que el usuario TOQUE un carril. Es opt-in porque `bandas` casi siempre
    /// trae una banda activa (la del último dato), y con eso el plot apagaba la serie sin
    /// que nadie hubiera seleccionado nada.
    var atenuarFuera: Bool = false
    let alto: CGFloat
    /// SOLO previews/arnés: pinta el overlay de scrub asentado en un índice fijo. NO
    /// publica índice al caller (el a11y del arnés debe quedarse en el último punto).
    /// Llega en índices del CALLER (se traduce a la serie ordenada).
    var scrubFijo: Int? = nil
    /// El índice bajo el dedo, publicado al caller para que su `accessibilityValue` siga
    /// el scrub. Se emite desde `.onChange` (jamás durante el update de la vista) y vuelve
    /// a `nil` al soltar. En `ImageRenderer` los `.onChange` no disparan: en los PNG del
    /// arnés el valor se queda en el último punto, por diseño.
    var onScrub: ((Int?) -> Void)? = nil

    /// Init explícito (no memberwise) para que el orden defensivo por fecha corra UNA vez
    /// por construcción y no en cada acceso a la geometría.
    init(puntos: [(fecha: Date, valor: Double)],
         bandas: [LiquidChartBanda],
         dominio: ClosedRange<Double>,
         ticksY: [(valor: Double, etiqueta: String)],
         tono: Color,
         puntoHoy: (fecha: Date, valor: Double)?,
         hoyAnillo: Bool,
         lineaRef: Double? = nil,
         formatoScrub: ((Double, Date) -> String)? = nil,
         formatoValorScrub: ((Double) -> String)? = nil,
         formatoFechaScrub: ((Date) -> String)? = nil,
         formatoFechaEje: ((Date) -> String)? = nil,
         mapeoPorTiempo: Bool = false,
         atenuarFuera: Bool = false,
         alto: CGFloat,
         scrubFijo: Int? = nil,
         onScrub: ((Int?) -> Void)? = nil) {
        // Camino rápido O(n): la serie ya viene ordenada en todos los callers vivos, así
        // que no se copia ni se reordena nada; la red solo cuesta el barrido.
        let yaOrdenada: Bool = puntos.indices.dropFirst()
            .allSatisfy { puntos[$0 - 1].fecha <= puntos[$0].fecha }
        let orden: [Int] = yaOrdenada
            ? Array(puntos.indices)
            : puntos.indices.sorted { puntos[$0].fecha < puntos[$1].fecha }
        self.puntos = yaOrdenada ? puntos : orden.map { puntos[$0] }
        self.ordenOriginal = orden
        self.bandas = bandas
        self.dominio = dominio
        self.ticksY = ticksY
        self.tono = tono
        self.puntoHoy = puntoHoy
        self.hoyAnillo = hoyAnillo
        self.lineaRef = lineaRef
        self.formatoScrub = formatoScrub
        self.formatoValorScrub = formatoValorScrub
        self.formatoFechaScrub = formatoFechaScrub
        self.formatoFechaEje = formatoFechaEje
        self.mapeoPorTiempo = mapeoPorTiempo
        self.atenuarFuera = atenuarFuera
        self.alto = alto
        self.scrubFijo = scrubFijo
        self.onScrub = onScrub
    }

    @State private var hoverX: CGFloat? = nil
    @State private var entrado = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// Canaleta izquierda para los labels del eje Y (26 de paridad `GraficaRangos`); sin
    /// ticks no hay canaleta (curva FC). Se ENSANCHA cuando la etiqueta más larga no cabe
    /// («7h 30m» de sueño mide ~38): con 26 fijos el label truncaba a «7h 3…» o invadía la
    /// serie. El ancho se estima por conteo de caracteres — igual que la vieja
    /// `GraficaRangos` — porque la geometría se necesita ANTES de que el texto se mida.
    private static let canaletaMin: CGFloat = 26
    private static let anchoCaracterEje: CGFloat = 5.6

    private var canaleta: CGFloat {
        guard !ticksY.isEmpty else { return 0 }
        let masLargo = ticksY.map(\.etiqueta.count).max() ?? 2
        // s300 de aire entre la etiqueta y el plot (pedido del dueño: con s100 el número
        // quedaba pegado a la gráfica).
        let estimado = CGFloat(masLargo) * Self.anchoCaracterEje + LiquidSpace.s300
        return Swift.max(Self.canaletaMin, estimado)
    }
    /// Respiro vertical del plot (la serie nunca pega contra el borde).
    private static let margenV: CGFloat = 10
    /// Media caja de línea del label del eje Y: por debajo de esto choca con las fechas.
    private static let respiroLabelY: CGFloat = 7
    /// Inset derecho, SIEMPRE reservado. Existe por el ANILLO del scrub (10 pt, el más
    /// grande de los adornos): sobre el último punto sobresaldría 5 pt del plot. Es
    /// constante a propósito — si dependiera de `puntoHoy`, la misma serie se re-escalaría
    /// 8 pt en cuanto entrara la lectura de la mañana.
    private static let insetDerecho: CGFloat = LiquidSpace.s200

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Snap del dedo al punto más cercano: el MISMO `ChartScrubMath` del explorador,
            // sobre el MISMO ancho útil que usa `x(_:_:)` — un solo origen de verdad, o el
            // anillo caería donde el dedo no está (I2).
            let iHover = hoverX.flatMap { (hx: CGFloat) -> Int? in
                if mapeoPorTiempo {
                    let xs: [CGFloat] = puntos.indices.map { x($0, w) }
                    return ChartScrubMath.nearestIndex(toX: hx, xs: xs)
                }
                return ChartScrubMath.nearestIndex(toX: hx - canaleta,
                                                   count: puntos.count,
                                                   width: plotW(w))
            }
            let iActivo = iHover ?? scrubFijoOrdenado
            ZStack(alignment: .topLeading) {
                washes(w, h)
                grid(w, h)
                lineaReferencia(w, h)
                ejeX(w, h)
                Group {
                    serie(w, h)
                    puntosDato(w, h)
                    joya(w, h)
                }
                .opacity(entrado || motionDisabled ? 1 : 0)
                if let i = iActivo, puntos.indices.contains(i) {
                    overlayScrub(i, w, h)
                }
            }
            // FER-219 · «cambiar de periodo SALTA, no morfa». `LiquidRangeSelector` muta el
            // binding del rango DENTRO de `withAnimation(LiquidMotion.selector)`, así que la
            // serie nueva entraba interpolando washes, grid, etiquetas de eje, puntos y joya
            // mientras la polilínea (un `Path`) saltaba de golpe: un híbrido incoherente. Con
            // la transacción neutralizada, la gráfica entera se re-asienta en un frame.
            // `value` es `[Date]` a propósito: `puntos` es un arreglo de tuplas y NO conforma
            // `Equatable`. Solo dispara cuando cambia la serie, así que ni el fade de entrada
            // (`entrado`) ni la animación de I1 (`washes`, que cambia con `indiceActiva`) se
            // ven afectados salvo que ambos muten en el MISMO update.
            .transaction(value: puntos.map(\.fecha)) { $0.animation = nil }
            .contentShape(Rectangle())
            // Scrub que NO roba el scroll vertical de la hoja: `liquidScrubPan` discrimina dirección
            // (gestureRecognizerShouldBegin: abs(vx) > abs(vy), igual que la Matriz) en vez del viejo
            // `scrubGesture` (highPriorityGesture DragGesture minimumDistance:0) que ganaba TODO el
            // touch —incluido el vertical— y trababa el scroll cuando el dedo arrancaba sobre la
            // gráfica. El scrub horizontal se mantiene idéntico; el arrastre vertical pasa al scroll.
            .liquidScrubPan(
                enabled: puntos.count > 1,
                onChange: { p in
                    var tx = Transaction(); tx.disablesAnimations = true
                    withTransaction(tx) { hoverX = p.x }
                },
                onEnd: {
                    var tx = Transaction(); tx.disablesAnimations = true
                    withTransaction(tx) { hoverX = nil }
                }
            )
            .onChange(of: iHover) { _, nuevo in
                // Háptica solo al caer en un punto NUEVO (no al soltar) — paridad GraficaRangos.
                if nuevo != nil { ChartHaptics.datumChanged() }
                // El índice se publica AQUÍ, nunca desde el body («Modifying state during
                // view update»), y TRADUCIDO al arreglo del caller: el plot dibuja su copia
                // ordenada, pero quien lo lee (`valorA11y`) indexa la suya. Al soltar,
                // `hoverX` se limpia y el caller vuelve solo al último punto.
                onScrub?(nuevo.flatMap { (i: Int) -> Int? in
                    ordenOriginal.indices.contains(i) ? ordenOriginal[i] : nil
                })
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: alto)
        .onAppear {
            // Entrada: fade dur/gentle. Con motion congelado (previews/renders) o Reduce
            // Motion el chart se pinta ASENTADO, sin animación de entrada.
            guard !entrado, !motionDisabled else { return }
            if reduceMotion {
                entrado = true
            } else {
                withAnimation(LiquidMotion.entrada) { entrado = true }
            }
        }
        // FER-29 · rotor «Gráficas» (audio graph). ADICIONAL al label/value del caller;
        // no se publica con serie vacía. `.cargando`/`.vacio` no llegan aquí (el plot
        // solo se monta en la rama `.datos` de las envolturas).
        .liquidChartAXDescriptor(puntos.isEmpty ? nil : LiquidChartAXDescriptor(
            puntos: puntos,
            dominio: dominio,
            formatoValorScrub: formatoValorScrub,
            formatoFechaScrub: formatoFechaScrub,
            formatoFechaEje: formatoFechaEje,
            formatoScrub: formatoScrub
        ))
    }

    // MARK: Geometría

    /// `scrubFijo` llega en índices del CALLER; el overlay dibuja sobre la serie ORDENADA.
    private var scrubFijoOrdenado: Int? {
        guard let s = scrubFijo else { return nil }
        return ordenOriginal.firstIndex(of: s)
    }

    /// Alto de la franja del eje X (0 cuando el caller no pidió fila de fechas).
    private var ejeAlto: CGFloat { formatoFechaEje == nil ? 0 : LiquidChart.ejeXAlto }

    /// El piso del ÁREA DE DATOS. Con eje X la franja de fechas ES el respiro inferior (el
    /// margen de abajo se retira: si no, la región de datos perdería ~15 % de altura a
    /// igual alto nominal y el wash de la banda más baja quedaría flotando sobre las
    /// fechas sin aterrizar en nada). Los tres dominios llegan con padding del caller, así
    /// que ningún punto se sienta en el piso.
    private func pisoY(_ h: CGFloat) -> CGFloat {
        formatoFechaEje == nil ? h - Self.margenV : h - ejeAlto
    }

    /// Ancho ÚTIL para el mapeo de puntos: el ÚNICO origen de verdad de la geometría
    /// horizontal. Lo usan `x(_:_:)` y el snap del dedo; jamás se reparte `w - canaleta`
    /// suelto en otro sitio (desincronizarlos rompe I2 sin fallar en compilación).
    private func plotW(_ w: CGFloat) -> CGFloat {
        Swift.max(1, w - canaleta - Self.insetDerecho)
    }

    /// Ancho de FONDO (washes I1 y grid): llega hasta el borde. El inset es del mapeo de
    /// puntos, no del telón — un hueco de 8 pt en los washes se leería como un corte.
    private func fondoW(_ w: CGFloat) -> CGFloat { Swift.max(0, w - canaleta) }

    private func x(_ i: Int, _ w: CGFloat) -> CGFloat {
        let n = puntos.count
        guard n > 1 else { return canaleta + plotW(w) / 2 }
        if mapeoPorTiempo, let f = fraccionTiempo(i) {
            return canaleta + CGFloat(f) * plotW(w)
        }
        return canaleta + CGFloat(i) * plotW(w) / CGFloat(n - 1)
    }

    /// Posición 0…1 del punto `i` sobre el TIEMPO real de la serie. `nil` si la serie no
    /// abarca tiempo (todos los sellos iguales) — entonces se cae al reparto por índice.
    private func fraccionTiempo(_ i: Int) -> Double? {
        guard let t0 = puntos.first?.fecha, let tn = puntos.last?.fecha else { return nil }
        let span = tn.timeIntervalSince(t0)
        guard span > 0 else { return nil }
        return puntos[i].fecha.timeIntervalSince(t0) / span
    }

    private func y(_ v: Double, _ h: CGFloat) -> CGFloat {
        let lo = dominio.lowerBound, hi = dominio.upperBound
        let clamped = Swift.max(lo, Swift.min(hi, v))
        let f = hi > lo ? (clamped - lo) / (hi - lo) : 0.5
        let piso = pisoY(h)
        return piso - CGFloat(f) * (piso - Self.margenV)
    }

    /// Índice del punto de `fecha` (exacto, o el más cercano en tiempo).
    private func indiceDe(_ fecha: Date) -> Int? {
        guard !puntos.isEmpty else { return nil }
        if let i = puntos.firstIndex(where: { $0.fecha == fecha }) { return i }
        var mejor = 0
        var mejorD = TimeInterval.greatestFiniteMagnitude
        for (i, p) in puntos.enumerated() {
            let d = abs(p.fecha.timeIntervalSince(fecha))
            if d < mejorD { mejorD = d; mejor = i }
        }
        return mejor
    }

    // MARK: Washes de banda (I1 — luminosidad de lo seleccionado)

    private func washes(_ w: CGFloat, _ h: CGFloat) -> some View {
        let hayActiva = bandas.contains { $0.activa }
        let indiceActiva = bandas.firstIndex { $0.activa }
        return ForEach(Array(bandas.enumerated()), id: \.offset) { _, b in
            let top = y(Swift.min(b.hi ?? dominio.upperBound, dominio.upperBound), h)
            let fondo = y(Swift.max(b.lo ?? dominio.lowerBound, dominio.lowerBound), h)
            Rectangle()
                .fill(b.color)
                .opacity(hayActiva
                         ? (b.activa ? LiquidChart.bandaActivaAlfa : LiquidChart.bandaApagadaAlfa)
                         : LiquidChart.bandaReposoAlfa)
                .frame(width: fondoW(w), height: Swift.max(0, fondo - top))
                .offset(x: canaleta, y: top)
        }
        .animation(reduceMotion || motionDisabled ? nil : LiquidMotion.lift, value: indiceActiva)
    }

    // MARK: Grid + labels del eje Y

    /// Las marcas del eje Y que de verdad CABEN: si dos quedan a menos de una caja de
    /// línea, la de abajo se salta (/inject: con el dominio acotado, «+0.8 °C» y «+0.4»
    /// se encimaban en temperatura de piel). La primera siempre entra.
    private func ticksYVisibles(_ h: CGFloat) -> [(valor: Double, etiqueta: String)] {
        var out: [(valor: Double, etiqueta: String)] = []
        var ultimaY: CGFloat = -.greatestFiniteMagnitude
        for t in ticksY.sorted(by: { $0.valor > $1.valor }) {
            let ty = y(t.valor, h)
            if ty - ultimaY < Self.respiroLabelY * 2 && !out.isEmpty { continue }
            out.append(t)
            ultimaY = ty
        }
        return out
    }

    @ViewBuilder private func grid(_ w: CGFloat, _ h: CGFloat) -> some View {
        let piso = pisoY(h)
        ForEach(Array(ticksYVisibles(h).enumerated()), id: \.offset) { _, t in
            let ty = y(t.valor, h)
            Rectangle()
                .fill(LiquidColor.tinta900.opacity(LiquidChart.gridAlfa))
                .frame(width: fondoW(w), height: 1)
                .offset(x: canaleta, y: ty - 0.5)
            // Con eje X, el label que quede a menos de media línea del piso se salta: si
            // no, choca con la primera fecha en la esquina inferior izquierda.
            if ejeAlto == 0 || ty <= piso - Self.respiroLabelY {
                Text(verbatim: t.etiqueta)
                    .font(LiquidType.unidadCompacta)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta500)
                    .lineLimit(1)
                    // Encajonado en su canaleta: una etiqueta larga («7h 30m») invadiría
                    // el plot y se pelearía con la serie.
                    .minimumScaleFactor(0.75)
                    .frame(width: canaleta, alignment: .leading)
                    .offset(x: 0, y: ty - 6)
            }
        }
    }

    // MARK: Línea de referencia (contexto punteado, TND-23)

    /// Patrón de la punteada de referencia — paridad `LiquidBarrasHora.dashReferencia`.
    private static let dashReferencia: [CGFloat] = [4, 3] // token-exempt: geometría de dato

    /// La punteada horizontal de referencia: misma tinta y grosor que la regla del scrub,
    /// cortada en guiones para que jamás compita con la serie (la familia ya habla así:
    /// `LiquidBarrasHora`). Fuera de dominio no se pinta — el caller decide si su dominio
    /// la incluye (la curva FC ya ensancha el suyo hasta la FC en reposo).
    @ViewBuilder private func lineaReferencia(_ w: CGFloat, _ h: CGFloat) -> some View {
        if let ref = lineaRef, dominio.contains(ref) {
            let ry = y(ref, h)
            Path { p in
                p.move(to: CGPoint(x: canaleta, y: ry))
                p.addLine(to: CGPoint(x: canaleta + fondoW(w), y: ry))
            }
            .stroke(LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa),
                    style: StrokeStyle(lineWidth: LiquidChart.scrubReglaAncho,
                                       dash: Self.dashReferencia))
        }
    }

    // MARK: Eje X (fila de fechas)

    /// Los índices CANDIDATOS a marca, antes de resolver colisiones. Las marcas
    /// INTERIORES desde 5 puntos (pedido del dueño /inject: con los 7 del rango «S» el
    /// eje se quedaba en dos fechas y se veía vacío; con 4 o menos sí se tocarían).
    private var candidatosEjeX: [Int] {
        let n = puntos.count
        guard n > 1 else { return n == 1 ? [0] : [] }
        // Con series cortas se marcan TODOS los puntos (pedido del dueño /inject: quería
        // ver cada fecha); de 9 en adelante volvemos a los cuartiles para no saturar.
        if n <= 8 { return Array(0..<n) }
        var out: [Int] = []
        // Con mapeo por TIEMPO los cuartiles se toman del SPAN, no del índice: en una
        // serie con huecos (12 lecturas en 90 días) el punto nº 6 puede caer al 90 % del
        // eje, y marcar «el índice de en medio» pondría la etiqueta pegada a la última.
        if mapeoPorTiempo, fraccionTiempo(0) != nil {
            for q in [0.0, 0.25, 0.5, 0.75, 1.0] {
                guard let i = indiceEnFraccion(q) else { continue }
                if out.last != i { out.append(i) }
            }
            return out
        }
        for q in [0, 0.25, 0.5, 0.75, 1.0] {
            let i = Int((Double(n - 1) * q).rounded())
            if out.last != i { out.append(i) }
        }
        return out
    }

    /// El punto cuya posición TEMPORAL queda más cerca de la fracción `q` del span.
    private func indiceEnFraccion(_ q: Double) -> Int? {
        var mejor: Int? = nil
        var mejorD = Double.greatestFiniteMagnitude
        for i in puntos.indices {
            guard let f = fraccionTiempo(i) else { continue }
            let d = abs(f - q)
            if d < mejorD { mejorD = d; mejor = i }
        }
        return mejor
    }

    /// Semiancho ESTIMADO de una etiqueta del eje (el texto todavía no se ha medido:
    /// misma cuenta por conteo de caracteres que la canaleta del eje Y).
    private func medioEtiquetaEje(_ etiqueta: String) -> CGFloat {
        CGFloat(etiqueta.count) * Self.anchoCaracterEje / 2
    }

    /// La x DIBUJADA de una etiqueta: el centro de SU punto, clampeado al plot para que
    /// ninguna se salga por los extremos.
    private func xEtiquetaEje(_ i: Int, _ w: CGFloat, _ medio: CGFloat) -> CGFloat {
        let ancho = fondoW(w)
        return Swift.min(Swift.max(x(i, w), canaleta + medio), canaleta + ancho - medio)
    }

    /// Las marcas que de verdad se pintan. Con mapeo por ÍNDICE los candidatos van
    /// equiespaciados y no se tocan; con mapeo por TIEMPO dos lecturas consecutivas pueden
    /// caer a 3 pt una de otra (el clamp de `xEtiquetaEje` protege los DOS bordes, jamás a
    /// las vecinas), así que se descarta toda etiqueta que se encimaría con la anterior ya
    /// colocada. La ÚLTIMA marca es intocable —es la lectura más reciente— y reserva su
    /// hueco antes de repartir el resto.
    private func marcasEjeX(_ w: CGFloat, _ fmt: (Date) -> String) -> [Int] {
        let candidatos = candidatosEjeX
        guard mapeoPorTiempo, candidatos.count > 1 else { return candidatos }
        func medio(_ i: Int) -> CGFloat { medioEtiquetaEje(fmt(puntos[i].fecha)) }
        let ultimo: Int = candidatos[candidatos.count - 1]
        let medioUltimo: CGFloat = medio(ultimo)
        let reserva: CGFloat = xEtiquetaEje(ultimo, w, medioUltimo) - medioUltimo - LiquidSpace.s200
        var out: [Int] = []
        var bordeDerecho: CGFloat = -.greatestFiniteMagnitude
        for i in candidatos.dropLast() {
            let m: CGFloat = medio(i)
            let cx: CGFloat = xEtiquetaEje(i, w, m)
            guard cx - m >= bordeDerecho, cx + m <= reserva else { continue }
            out.append(i)
            bordeDerecho = cx + m + LiquidSpace.s200
        }
        out.append(ultimo)
        return out
    }

    @ViewBuilder private func ejeX(_ w: CGFloat, _ h: CGFloat) -> some View {
        if let fmt = formatoFechaEje {
            let marcas = marcasEjeX(w, fmt)
            let cy = pisoY(h) + ejeAlto / 2
            ForEach(Array(marcas.enumerated()), id: \.offset) { (k: Int, i: Int) in
                let etiqueta: String = fmt(puntos[i].fecha)
                let base = Text(verbatim: etiqueta)
                    .font(LiquidType.unidadCompacta)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta500)
                    .lineLimit(1)
                    .fixedSize()
                // TODAS centradas en SU punto (pedido del dueño: las fechas no cuadraban
                // con sus bolitas porque la primera y la última se pegaban al borde).
                base.position(x: xEtiquetaEje(i, w, medioEtiquetaEje(etiqueta)), y: cy)
            }
        }
    }

    // MARK: Serie, puntos por dato y joya endpoint

    @ViewBuilder private func serie(_ w: CGFloat, _ h: CGFloat) -> some View {
        if puntos.count > 1 {
            Path { p in
                for (i, punto) in puntos.enumerated() {
                    let pt = CGPoint(x: x(i, w), y: y(punto.valor, h))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(tono, style: StrokeStyle(lineWidth: LiquidChart.lineaAncho,
                                             lineCap: .round, lineJoin: .round))
        }
    }

    /// Un disco por muestra cuando la serie es corta Y hay aire real entre puntos. El
    /// punto ACOMPAÑA a su wash (paridad `GraficaRangos`): con `atenuarFuera`, en la banda
    /// activa va a tono pleno y fuera de ella se apaga. **Solo con opt-in**: `bandas` casi
    /// siempre trae una activa (la del último dato), así que atarlo a `hayActiva` a secas
    /// apagaba media serie sin que el usuario hubiera tocado ningún carril — ni paridad
    /// `GraficaRangos` (que apaga al TOCAR) ni paridad con la hoja vieja (que no apagaba
    /// nunca). En reposo, la banda activa se sigue diciendo con el wash (I1).
    @ViewBuilder private func puntosDato(_ w: CGFloat, _ h: CGFloat) -> some View {
        let n = puntos.count
        // Densidad REAL, no solo conteo: 60 puntos en un iPhone SE se tocarían. El arreglo
        // de la separación vive en `LiquidChart.hayEspacioParaPuntos` (mide el paso MÍNIMO
        // entre centros ya mapeados, que con `mapeoPorTiempo` no es el promedio). El `n <=
        // puntoDatoUmbral` de la condición corta ANTES de construir el arreglo de centros,
        // así que la serie larga no paga el barrido.
        if n > 1, n <= LiquidChart.puntoDatoUmbral,
           LiquidChart.hayEspacioParaPuntos(centros: puntos.indices.map { x($0, w) }) {
            let hayActiva = atenuarFuera && bandas.contains { $0.activa }
            ForEach(Array(puntos.enumerated()), id: \.offset) { i, punto in
                // Mismo resolver de banda que el anillo del scrub.
                let banda = bandas.first { $0.contiene(punto.valor) }
                let encendido: Bool = !hayActiva || (banda?.activa ?? false)
                let r: CGFloat = encendido
                    ? LiquidChart.puntoDatoRadio
                    : LiquidChart.puntoDatoRadio * LiquidChart.puntoApagadoEscala
                Circle()
                    .fill(banda?.color ?? tono)
                    .opacity(encendido ? 1 : LiquidChart.puntoApagadoAlfa)
                    .frame(width: r * 2, height: r * 2)
                    .offset(x: x(i, w) - r, y: y(punto.valor, h) - r)
            }
        }
    }

    @ViewBuilder private func joya(_ w: CGFloat, _ h: CGFloat) -> some View {
        if let hoy = puntoHoy, let i = indiceDe(hoy.fecha) {
            let px = x(i, w)
            let py = y(hoy.valor, h)
            if hoyAnillo {
                // Anillo hueco: hoy sigue marcado mientras exploras otro nivel (paridad
                // `markedPointHollow`, MetricLevelsExplorer:145) — misma geometría que el
                // anillo del scrub para hablar un solo lenguaje.
                Circle()
                    .fill(LiquidColor.papelAlto)
                    .overlay(Circle().strokeBorder(tono, lineWidth: LiquidChart.scrubAnilloBorde))
                    .frame(width: LiquidChart.scrubAnilloDiametro,
                           height: LiquidChart.scrubAnilloDiametro)
                    .offset(x: px - LiquidChart.scrubAnilloDiametro / 2,
                            y: py - LiquidChart.scrubAnilloDiametro / 2)
            } else {
                // La JOYA DE HOY: papel (casi-blanco) relleno + filo del tono. Fidelidad al
                // mock canónico (`.dot.today{fill:#fff;stroke:var(--tono)}`, auditoría
                // Grok+DeepSeek 2026-08-03): hoy es SIEMPRE una joya blanca ribeteada del
                // tono, un marcador fijo distinto de los puntos de dato —no un punto relleno
                // del tono, indistinguible del resto—. Antes se invertía (relleno del tono,
                // borde de papel) y solo al explorar otro nivel se volvía anillo.
                Circle()
                    .fill(LiquidColor.papelAlto)
                    .overlay(Circle().strokeBorder(tono, lineWidth: LiquidChart.endpointBorde))
                    .frame(width: LiquidChart.endpointRadio * 2,
                           height: LiquidChart.endpointRadio * 2)
                    .offset(x: px - LiquidChart.endpointRadio,
                            y: py - LiquidChart.endpointRadio)
            }
        }
    }

    // MARK: Overlay de scrub (I2 — regla punteada + anillo por banda + popup)

    /// La línea de valor del popup: el formato partido si el caller lo dio, o la frase
    /// compuesta como única línea.
    private func textoValorScrub(_ i: Int) -> String? {
        if let f = formatoValorScrub { return f(puntos[i].valor) }
        if let f = formatoScrub { return f(puntos[i].valor, puntos[i].fecha) }
        return nil
    }

    @ViewBuilder private func overlayScrub(_ i: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
        let px = x(i, w)
        let py = y(puntos[i].valor, h)
        let piso = pisoY(h)
        let colorAnillo = bandas.first { $0.contiene(puntos[i].valor) }?.color ?? tono

        // La regla vertical que corta el plot — la pieza pública compartida, con la tinta
        // Liquid (`scrubReglaAlfa`). Termina en el PISO: cruzar la franja de fechas sería
        // tachar el eje.
        CrosshairRule(x: px, height: piso,
                      color: LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa))

        // El anillo sobre el punto, en el color de SU banda (paridad HighlightDot flat).
        Circle()
            .fill(LiquidColor.papelAlto)
            .overlay(Circle().strokeBorder(colorAnillo, lineWidth: LiquidChart.scrubAnilloBorde))
            .frame(width: LiquidChart.scrubAnilloDiametro,
                   height: LiquidChart.scrubAnilloDiametro)
            .offset(x: px - LiquidChart.scrubAnilloDiametro / 2,
                    y: py - LiquidChart.scrubAnilloDiametro / 2)
            .allowsHitTesting(false)

        // El popup «valor / fecha» flota junto al punto, MEDIDO (nunca estimado) y
        // clampeado al rect del plot.
        if let valorTexto = textoValorScrub(i) {
            let fechaTexto: String? = formatoValorScrub == nil
                ? nil
                : formatoFechaScrub.map { $0(puntos[i].fecha) }
            LiquidScrubPopupColocado(valor: valorTexto,
                                     fecha: fechaTexto,
                                     color: colorAnillo,
                                     anclaje: CGPoint(x: px - canaleta, y: py),
                                     contenedor: CGSize(width: fondoW(w), height: piso),
                                     canaleta: canaleta)
        }
    }
}

// MARK: - Pozos de estado compartidos

/// El pozo de gráfica vacía: el mensaje ya localizado del caller sobre un wash quieto.
struct LiquidChartVacio: View {
    let mensaje: String
    let alto: CGFloat

    var body: some View {
        Text(verbatim: mensaje)
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LiquidSpace.s400)
            .frame(maxWidth: .infinity)
            .frame(height: alto)
            .background(LiquidColor.tinta7,
                        in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
    }
}

/// El pozo de carga: skeleton sobrio y ESTÁTICO (tres trazos mudos) — nada parpadea, y con
/// motion congelado se ve exactamente igual.
struct LiquidChartCargando: View {
    let alto: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Capsule().fill(LiquidColor.tinta10).frame(height: 2)
            Capsule().fill(LiquidColor.tinta10).frame(height: 2)
                .padding(.trailing, LiquidSpace.s800)
            Capsule().fill(LiquidColor.tinta10).frame(height: 2)
                .padding(.trailing, LiquidSpace.s400)
        }
        .padding(.horizontal, LiquidSpace.s400)
        .frame(maxWidth: .infinity)
        .frame(height: alto)
        .background(LiquidColor.tinta7,
                    in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
        .accessibilityHidden(true)
    }
}

#if DEBUG
// Preview del plot + pozos. FER-29: el plot publica `AXChartDescriptor` (rotor «Gráficas»).
// Con VoiceOver: enfoca la gráfica → rotor → «Gráficas» → recorre punto a punto
// (fecha → valor con la misma cabeza que el popup del scrub). Label/value del caller
// no se reemplazan — el rotor es adicional. `.cargando`/`.vacio` no llevan descriptor.
#Preview("Liquid · Chart core (plot + pozos)") {
    let bandas: [LiquidChartBanda] = [
        .init(lo: 71, hi: nil, color: LiquidColor.positivo, activa: false),
        .init(lo: 49, hi: 71, color: LiquidColor.cian, activa: true),
        .init(lo: nil, hi: 49, color: LiquidColor.atencion, activa: false),
    ]
    let cal: Calendar = Calendar.current
    let puntos: [(fecha: Date, valor: Double)] = (0..<14).map { (i: Int) -> (fecha: Date, valor: Double) in
        let fecha: Date = cal.date(byAdding: .day, value: i - 13, to: Date())!
        let onda: Double = 14.0 * sin(Double(i) / 2.1)
        let ruido: Double = Double((i * 7) % 5)
        return (fecha: fecha, valor: 56.0 + onda + ruido)
    }
    let ejeFmt: (Date) -> String = { (d: Date) -> String in
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: d)
    }
    let popupFecha: (Date) -> String = { (d: Date) -> String in
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d)
    }
    return VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        // Plot con banda activa iluminada + eje de fechas + puntos por dato + joya +
        // scrub asentado en un índice fijo + AXChartDescriptor (rotor Gráficas).
        LiquidChartPlot(puntos: puntos, bandas: bandas, dominio: 30...95,
                        ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
                        puntoHoy: (puntos[13].fecha, puntos[13].valor), hoyAnillo: false,
                        formatoScrub: { (v: Double, _: Date) in "\(Int(v)) ms" },
                        formatoValorScrub: { (v: Double) in "\(Int(v)) ms" },
                        formatoFechaScrub: popupFecha,
                        formatoFechaEje: ejeFmt,
                        alto: LiquidChartAlto.explorador, scrubFijo: 7)
            .accessibilityLabel(Text(verbatim: "VFC, demo 14 días"))
            .accessibilityValue(Text(verbatim: "56 ms"))
            .liquidGlass(.superficie) // token-exempt: preview, fuera de una hoja
        LiquidChartCargando(alto: LiquidChartAlto.trend)
        LiquidChartVacio(mensaje: "Sin lecturas en este rango.", alto: LiquidChartAlto.trend)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
    .environment(\.liquidMotionDisabled, true)
}
#endif
