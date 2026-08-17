import SwiftUI

// MARK: - Liquid Glass · El comparador: de dos a cuatro métricas superpuestas
//
// La gráfica de «Comparar»: varias métricas dibujadas UNA SOBRE OTRA para leer si se mueven
// juntas. Es el port a Liquid de `OverlayChart` (`Cenit/Screens/CompareView.swift`), que la
// pantalla dibujaba a mano con Swift Charts.
//
// LA REGLA QUE SOSTIENE TODO: **cada serie se normaliza contra SU PROPIO dominio**, nunca
// contra un eje compartido. La VFC vive en milisegundos (≈40–80) y los pasos en miles
// (≈0–16 000): sobre un eje común la VFC sería una raya pegada al piso y la comparación
// —que es de FORMA, no de magnitud— se perdería. Cada línea usa el alto completo del plot
// DENTRO de su escala, así que lo que se compara es el dibujo (sube, baja, se adelanta),
// jamás la altura de una contra la otra. Comparar milisegundos con pasos en un solo eje es
// mentir, y la mentira no se ve: las dos líneas siguen siendo bonitas.
//
// De ahí sale el resto de la forma:
//   · El eje Y NO lleva números — un número compartido sería falso. La escala la dice la
//     LEYENDA, con el dominio de cada serie formateado por el caller («48–72 ms»,
//     «0–16 000 pasos»): el borde de arriba del plot es el tope DE ESA serie, el de abajo
//     su piso. Cada línea carga su propio eje.
//   · Con menos de dos series no hay comparación: se dibuja un pozo con el mensaje del
//     caller, nunca una gráfica de una sola línea disfrazada de comparador.
//
// Interacción: el scrub es `liquidScrubPan` (FER-73) — el gesto de UIKit que NO EMPIEZA si el
// dedo va vertical. Funciona con el DEDO (la versión de papel nació con `.onContinuousHover`,
// muerto en táctil hasta FER-977) y deja vivo el scroll de la pantalla que la contiene. El
// dedo pega a una fecha de la unión de todas las series y la publica por `seleccion`.
//
// Contrato: todo string llega YA localizado (`nombre`, `a11yLabel`, los mensajes de estado) y
// los valores se formatean con el closure del caller — el DS no conoce locales. La FECHA del
// punto leído no se formatea aquí; por eso el tooltip es una pieza HERMANA
// (`LiquidTooltipMulti`) que el caller arma con su propia fecha y coloca donde quiera.

public struct LiquidGraficaSuperpuesta: View {

    /// Una métrica de la comparación: su nombre YA localizado, su color de identidad, sus
    /// puntos y —lo importante— SU escala. El dominio no se deriva de los datos aquí a
    /// propósito: es el caller quien sabe si la escala honesta de esa métrica es su min–max
    /// de la ventana, su banda de referencia o un dominio fijo.
    ///
    /// Las fechas son CLAVES DE DÍA canónicas del caller (el mismo instante para el mismo día
    /// en todas las series): el emparejamiento entre series es por igualdad exacta, igual que
    /// el `day` string del papel. Dos series que fechen el mismo día a horas distintas no se
    /// cruzan — y eso es preferible a un emparejamiento por cercanía, que juntaría en
    /// silencio la noche del lunes con la madrugada del martes.
    public struct Serie: Identifiable {
        public let id: String
        /// YA localizado (contrato: el DS no tiene catálogo).
        public let nombre: String
        /// La identidad de la señal: tiñe su línea, su punto y su gota en leyenda y tooltip.
        public let color: Color
        public let puntos: [(fecha: Date, valor: Double)]
        /// SU escala. Cada serie se normaliza contra esta, nunca contra la de al lado.
        public let dominio: ClosedRange<Double>

        public init(id: String,
                    nombre: String,
                    color: Color,
                    puntos: [(fecha: Date, valor: Double)],
                    dominio: ClosedRange<Double>) {
            self.id = id
            self.nombre = nombre
            self.color = color
            self.puntos = puntos
            self.dominio = dominio
        }
    }

    /// Lo que el comparador puede decir con lo que le dieron. Los dos estados honestos están
    /// separados porque su causa es distinta y su copy también: «elige al menos dos» le habla
    /// a quien no ha escogido; a quien ya escogió cuatro habría que mentirle para decírselo.
    public enum Estado: Equatable {
        // Público a propósito: el contrato de esta pieza le pide al caller que pregunte el
        // estado ANTES de montar la vista y que repita el orden de la leyenda en su tooltip.
        // Con estos símbolos internos, la app —que es otro módulo— no podía cumplirlo.
        /// El caller trajo menos de dos series: no hay comparación que dibujar.
        case minimo
        /// Hay dos o más, pero la ventana no deja dos con lecturas.
        case sinLecturas
        case datos
    }

    private let series: [Serie]
    private let rango: ClosedRange<Date>
    /// Cómo rotular las fechas del eje X (el DS no conoce locales). Sin él no hay eje — y una
    /// comparación de 90 días sin una sola fecha no deja saber si el cruce fue el lunes o hace
    /// tres semanas. El papel dibujaba 5 marcas.
    private let formatoFechaEje: ((Date) -> String)?
    /// Los tres rótulos de la rejilla. No llevan números —serían falsos con series de escalas
    /// distintas— pero «alto/medio/bajo» SÍ es cierto para toda serie normalizada, y es lo que
    /// el papel decía. YA localizados.
    private let rotulosRejilla: (bajo: String, medio: String, alto: String)?
    @Binding private var seleccion: Date?
    private let formatoValor: (Serie, Double) -> String
    private let a11yLabel: String
    private let mensajeMinimo: String?
    private let mensajeSinLecturas: String?

    /// Las series RECORTADAS a la ventana y sin las que se quedaron sin lecturas. Es también
    /// el orden de la leyenda (y el que el caller debe repetir en el tooltip).
    let seriesVisibles: [Serie]
    /// La unión ordenada de fechas: lo que el dedo puede pisar.
    let fechasScrub: [Date]
    let estado: Estado

    /// Derivados calculados UNA vez por construcción (paridad `OverlayChart.init`, FER-319):
    /// el `body` se re-evalúa en cada tick del scrub, y recortar la ventana + reordenar la
    /// unión ahí reconstruía el dataset entero con cada movimiento del dedo.
    public init(series: [Serie],
                rango: ClosedRange<Date>,
                seleccion: Binding<Date?>,
                formatoValor: @escaping (Serie, Double) -> String,
                a11yLabel: String,
                formatoFechaEje: ((Date) -> String)? = nil,
                rotulosRejilla: (bajo: String, medio: String, alto: String)? = nil,
                mensajeMinimo: String? = nil,
                mensajeSinLecturas: String? = nil) {
        self.formatoFechaEje = formatoFechaEje
        self.rotulosRejilla = rotulosRejilla
        self.series = series
        self.rango = rango
        self._seleccion = seleccion
        self.formatoValor = formatoValor
        self.a11yLabel = a11yLabel
        self.mensajeMinimo = mensajeMinimo
        self.mensajeSinLecturas = mensajeSinLecturas
        let visibles: [Serie] = Self.recortadas(series, rango)
        self.seriesVisibles = visibles
        self.fechasScrub = Self.fechasUnion(visibles)
        self.estado = Self.resolverEstado(series: series, visibles: visibles)
    }

    // MARK: Geometría interna

    /// Alto del área de datos: 260 — el que declara la gráfica de papel (`OverlayChart.height`)
    /// y, en la familia Liquid, el de la curva de FC. Cuatro líneas necesitan aire: por debajo
    /// de esto los cruces se amontonan y la comparación deja de leerse.
    private let alto: CGFloat = LiquidChartAlto.curvaFC
    /// Respiro vertical: ninguna línea pega contra el borde. Mismo valor que el margen del
    /// plot de la familia (`LiquidChartPlot.margenV`).
    private static let margenV: CGFloat = LiquidSpace.s250
    /// Inset horizontal a AMBOS lados (el plot de la familia solo lo reserva a la derecha):
    /// aquí la x sale del TIEMPO absoluto de la ventana, así que un punto que caiga justo en
    /// el primer día se sienta en x = 0 y su anillo de scrub —el adorno más ancho, 10 pt— se
    /// saldría por la izquierda.
    private static let inset: CGFloat = LiquidSpace.s200
    /// Muestra de leyenda: un TROZO DE LÍNEA de 14×3 con esquinas de 2, no un cuadrito de
    /// color — dice «así se ve esta serie allá arriba» (paridad `CompareView.legend`).
    private let muestraAncho: CGFloat = 14
    private let muestraAlto: CGFloat = 3
    private let muestraRadio: CGFloat = 2

    /// En tallas de accesibilidad la fila de leyenda deja de ser una línea (muestra · nombre ·
    /// escala) y se apila: nada se recorta ni se aprieta contra el borde.
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// Pulso háptico al cruzar de fecha durante el scrub (paridad de la familia; se dispara
    /// con `.sensoryFeedback`, nunca llamando al generador desde el gesto).
    @State private var tic: Int = 0
    /// Entrada: las series aparecen con un fade. Con Reduce Motion o motion congelado se
    /// pintan ASENTADAS, sin viaje.
    @State private var entrado = false

    public var body: some View {
        contenido
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: a11yLabel))
            .accessibilityValue(Text(verbatim: valorA11y))
    }

    @ViewBuilder private var contenido: some View {
        switch estado {
        case .minimo:
            LiquidChartVacio(mensaje: mensajeMinimo ?? "", alto: alto)
        case .sinLecturas:
            LiquidChartVacio(mensaje: mensajeSinLecturas ?? mensajeMinimo ?? "", alto: alto)
        case .datos:
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                plot
                leyenda
            }
        }
    }

    // MARK: - Plot

    private var plot: some View {
        VStack(spacing: LiquidSpace.s100) {
            lienzo
            GeometryReader { geo in ejeX(geo.size.width) }
                .frame(height: formatoFechaEje == nil ? 0 : LiquidChart.ejeXAlto)
        }
    }

    private var lienzo: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let xs: [CGFloat] = fechasScrub.map { x($0, w) }
            ZStack(alignment: .topLeading) {
                rejilla(w, h)
                Group {
                    ForEach(seriesVisibles) { (s: Serie) in
                        trazo(s, w, h)
                    }
                }
                .opacity(entrado || motionDisabled ? 1 : 0)
                if let fecha = fechaDibujada {
                    overlayScrub(fecha, w, h)
                }
            }
            .contentShape(Rectangle())
            // FER-73 · el gesto NO EMPIEZA si el dedo va vertical: el scrub funciona con el
            // dedo y el scroll de la pantalla que contiene la gráfica sigue vivo. NUNCA
            // `.onContinuousHover` (muerto en táctil) ni un `DragGesture` que gane el touch.
            .liquidScrubPan(
                enabled: fechasScrub.count > 1,
                onChange: { (p: CGPoint) in
                    guard let i = ChartScrubMath.nearestIndex(toX: p.x, xs: xs),
                          fechasScrub.indices.contains(i) else { return }
                    let nueva: Date = fechasScrub[i]
                    guard seleccion != nueva else { return }
                    seleccion = nueva
                    tic &+= 1
                },
                onEnd: { seleccion = nil })
        }
        .frame(maxWidth: .infinity)
        .frame(height: alto)
        .sensoryFeedback(.selection, trigger: tic)
        .onAppear {
            guard !entrado, !motionDisabled else { return }
            if reduceMotion {
                entrado = true
            } else {
                withAnimation(LiquidMotion.entrada) { entrado = true }
            }
        }
    }

    /// Tres reglas mudas: piso, mitad y techo del plot. No llevan etiqueta porque no hay un
    /// número que sea verdad para todas las series — solo dan un suelo al ojo.
    @ViewBuilder private func rejilla(_ w: CGFloat, _ h: CGFloat) -> some View {
        ForEach([0.0, 0.5, 1.0], id: \.self) { (f: Double) in
            Rectangle()
                .fill(LiquidColor.tinta900.opacity(LiquidChart.gridAlfa))
                .frame(width: Swift.max(0, w), height: 1)
                .offset(x: 0, y: yFraccion(f, h) - 0.5)
        }
        // Los tres rótulos de la rejilla. No llevan números —serían falsos con series de
        // escalas distintas— pero «alto / medio / bajo» SÍ es cierto para toda serie
        // normalizada, y es lo que el papel decía. Sin ellos la rejilla es decoración.
        if let r = rotulosRejilla {
            let textos: [String] = [r.bajo, r.medio, r.alto]
            let alturas: [Double] = [0.0, 0.5, 1.0]
            ForEach(0..<3, id: \.self) { (i: Int) in
                Text(verbatim: textos[i])
                    .font(LiquidType.unidadCompacta)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize()
                    .offset(x: 0, y: yFraccion(alturas[i], h) - LiquidSpace.s300)
            }
        }
    }

    /// El eje X: 5 marcas de fecha repartidas en la ventana, como el papel. Sin él, una
    /// comparación de 90 días no deja saber si el cruce fue el lunes o hace tres semanas.
    @ViewBuilder private func ejeX(_ w: CGFloat) -> some View {
        if let formato = formatoFechaEje {
            let span = rango.upperBound.timeIntervalSince(rango.lowerBound)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    let t = rango.lowerBound.addingTimeInterval(span * Double(i) / 4)
                    Text(verbatim: formato(t))
                        .font(LiquidType.unidadCompacta)
                        .foregroundStyle(LiquidColor.tinta500)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity,
                               alignment: i == 0 ? .leading : (i == 4 ? .trailing : .center))
                }
            }
            .frame(width: Swift.max(0, w), height: LiquidChart.ejeXAlto)
        }
    }

    /// La línea de una serie + sus discos por dato cuando de verdad caben (el gate de densidad
    /// de la familia: si dos discos se tocarían, no se dibuja ninguno — una tira pegada deja
    /// de ser contable y pasa a ser textura).
    @ViewBuilder private func trazo(_ s: Serie, _ w: CGFloat, _ h: CGFloat) -> some View {
        let centros: [CGFloat] = s.puntos.map { x($0.fecha, w) }
        if s.puntos.count > 1 {
            Path { (p: inout Path) in
                for (i, punto) in s.puntos.enumerated() {
                    let pt = CGPoint(x: centros[i], y: y(punto.valor, s.dominio, h))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(s.color, style: StrokeStyle(lineWidth: LiquidChart.lineaAncho,
                                                lineCap: .round, lineJoin: .round))
        }
        if LiquidChart.hayEspacioParaPuntos(centros: centros) {
            ForEach(Array(s.puntos.enumerated()), id: \.offset) { (i: Int, punto: (fecha: Date, valor: Double)) in
                Circle()
                    .fill(s.color)
                    .frame(width: LiquidChart.puntoDatoRadio * 2,
                           height: LiquidChart.puntoDatoRadio * 2)
                    .offset(x: centros[i] - LiquidChart.puntoDatoRadio,
                            y: y(punto.valor, s.dominio, h) - LiquidChart.puntoDatoRadio)
            }
        }
        // Una serie de UN solo punto no traza línea: se marca con su disco para que exista.
        if s.puntos.count == 1, let punto = s.puntos.first {
            Circle()
                .fill(s.color)
                .frame(width: LiquidChart.puntoDatoRadio * 2,
                       height: LiquidChart.puntoDatoRadio * 2)
                .offset(x: x(punto.fecha, w) - LiquidChart.puntoDatoRadio,
                        y: y(punto.valor, s.dominio, h) - LiquidChart.puntoDatoRadio)
        }
    }

    /// La regla vertical que corta el plot + un anillo por serie que TENGA lectura ese día.
    /// La serie que no midió ese día no recibe anillo: el hueco es el dato.
    @ViewBuilder private func overlayScrub(_ fecha: Date, _ w: CGFloat, _ h: CGFloat) -> some View {
        let cx: CGFloat = x(fecha, w)
        CrosshairRule(x: cx, height: h,
                      color: LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa))
        ForEach(seriesVisibles) { (s: Serie) in
            if let v = Self.valor(s, en: fecha) {
                Circle()
                    .fill(LiquidColor.papelAlto)
                    .overlay(Circle().strokeBorder(s.color, lineWidth: LiquidChart.scrubAnilloBorde))
                    .frame(width: LiquidChart.scrubAnilloDiametro,
                           height: LiquidChart.scrubAnilloDiametro)
                    .offset(x: cx - LiquidChart.scrubAnilloDiametro / 2,
                            y: y(v, s.dominio, h) - LiquidChart.scrubAnilloDiametro / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Leyenda (el eje que el plot no puede dibujar)

    private var leyenda: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(seriesVisibles) { (s: Serie) in
                filaLeyenda(s)
            }
        }
    }

    @ViewBuilder private func filaLeyenda(_ s: Serie) -> some View {
        let escala: String = escalaDe(s)
        Group {
            if tamanoTexto.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    HStack(spacing: LiquidSpace.s250) {
                        muestra(s)
                        nombreLeyenda(s)
                    }
                    escalaLeyenda(escala)
                }
            } else {
                HStack(spacing: LiquidSpace.s250) {
                    muestra(s)
                    nombreLeyenda(s)
                    Spacer(minLength: LiquidSpace.s300)
                    escalaLeyenda(escala)
                }
            }
        }
        .padding(.vertical, LiquidSpace.s150)
    }

    private func muestra(_ s: Serie) -> some View {
        RoundedRectangle(cornerRadius: muestraRadio, style: .continuous)
            .fill(s.color)
            .frame(width: muestraAncho, height: muestraAlto)
    }

    private func nombreLeyenda(_ s: Serie) -> some View {
        Text(verbatim: s.nombre)
            .font(LiquidType.tituloFila)
            .foregroundStyle(LiquidColor.tinta900)
    }

    private func escalaLeyenda(_ escala: String) -> some View {
        Text(verbatim: escala)
            .font(LiquidType.captionLectura)
            .monospacedDigit()
            .foregroundStyle(LiquidColor.tinta700)
    }

    /// Los dos extremos del dominio de la serie, con el formateador del caller. Es el eje Y
    /// que el plot no puede imprimir: «arriba de la gráfica, esta línea vale esto».
    private func escalaDe(_ s: Serie) -> String {
        "\(formatoValor(s, s.dominio.lowerBound)) – \(formatoValor(s, s.dominio.upperBound))"
    }

    // MARK: - VoiceOver

    /// Resume TODAS las series a la vez, en el orden de la leyenda: el punto bajo el dedo o,
    /// en reposo, la última fecha con lecturas. La fecha no entra en la frase porque el DS no
    /// formatea fechas (contrato); quien la dice es el tooltip del caller.
    ///
    /// Interno (no `private`) para poder fijar el contrato en frío.
    var valorA11y: String {
        switch estado {
        case .minimo:      return mensajeMinimo ?? ""
        case .sinLecturas: return mensajeSinLecturas ?? mensajeMinimo ?? ""
        case .datos:
            guard let fecha = fechaDibujada ?? fechasScrub.last else { return mensajeSinLecturas ?? "" }
            return seriesVisibles.compactMap { (s: Serie) -> String? in
                guard let v = Self.valor(s, en: fecha) else { return nil }
                return "\(s.nombre) \(formatoValor(s, v))"
            }
            .joined(separator: ", ")
        }
    }

    // MARK: - Mapeo

    /// La fecha que se DIBUJA: la del binding, pegada a la unión. El scrub siempre escribe
    /// una fecha de la unión; si el caller escribe otra (la selección de otra vista, por
    /// ejemplo), la regla y los anillos siguen contando la MISMA fecha en vez de
    /// contradecirse — una regla sin puntos se leería como un día sin datos.
    private var fechaDibujada: Date? {
        guard let sel = seleccion, !fechasScrub.isEmpty else { return nil }
        if fechasScrub.contains(sel) { return sel }
        return fechasScrub.min(by: {
            abs($0.timeIntervalSince(sel)) < abs($1.timeIntervalSince(sel))
        })
    }

    /// Ancho ÚTIL: el único origen de verdad horizontal (lo usan el mapeo de puntos y el snap
    /// del dedo; desincronizarlos pondría el anillo donde el dedo no está).
    private func plotW(_ w: CGFloat) -> CGFloat {
        Swift.max(1, w - Self.inset * 2)
    }

    /// x por TIEMPO absoluto dentro de la ventana — no por índice: las series comparadas no
    /// tienen los mismos días (VFC se mide a ratos, los pasos todos los días), así que
    /// repartir por índice pondría la lectura nº 5 de una encima de la nº 5 de la otra
    /// aunque sean semanas distintas.
    private func x(_ fecha: Date, _ w: CGFloat) -> CGFloat {
        let span: TimeInterval = rango.upperBound.timeIntervalSince(rango.lowerBound)
        let util: CGFloat = plotW(w)
        guard span > 0 else { return Self.inset + util / 2 }
        let f: Double = fecha.timeIntervalSince(rango.lowerBound) / span
        return Self.inset + CGFloat(Swift.min(Swift.max(f, 0), 1)) * util
    }

    /// y de una fracción 0…1 del plot (0 = piso, 1 = techo).
    private func yFraccion(_ f: Double, _ h: CGFloat) -> CGFloat {
        let piso: CGFloat = h - Self.margenV
        return piso - CGFloat(f) * (piso - Self.margenV)
    }

    /// y de un valor CONTRA SU DOMINIO. Aquí es donde vive la regla del componente.
    private func y(_ v: Double, _ dominio: ClosedRange<Double>, _ h: CGFloat) -> CGFloat {
        yFraccion(Self.normalizado(v, en: dominio), h)
    }

    // MARK: - Puro (lo que fija el contrato en frío)

    /// Normaliza `v` dentro de SU dominio → 0…1, recortado a los extremos. Un dominio plano
    /// (`hi == lo`) cae al medio para que la serie se dibuje como una línea centrada en vez
    /// de desaparecer contra un borde (paridad `CompareSeries.normalized`).
    static func normalizado(_ v: Double, en dominio: ClosedRange<Double>) -> Double {
        let lo: Double = dominio.lowerBound
        let hi: Double = dominio.upperBound
        guard hi > lo else { return 0.5 }
        return Swift.min(Swift.max((v - lo) / (hi - lo), 0), 1)
    }

    /// Los puntos DENTRO de la ventana. Un punto fuera no se dibuja ni se puede scrubbear:
    /// si se colara, la línea saldría del plot y el eje afirmaría un tramo que el usuario no
    /// pidió ver.
    static func enRango(_ puntos: [(fecha: Date, valor: Double)],
                        _ rango: ClosedRange<Date>) -> [(fecha: Date, valor: Double)] {
        puntos.filter { rango.contains($0.fecha) }
    }

    /// Las series recortadas a la ventana, en el orden del caller, SIN las que se quedaron
    /// sin lecturas (paridad `CompareView.overlaySection`, que filtra `!rows.isEmpty` antes
    /// de dibujar y de armar la leyenda).
    public static func recortadas(_ series: [Serie], _ rango: ClosedRange<Date>) -> [Serie] {
        series.compactMap { (s: Serie) -> Serie? in
            let dentro = enRango(s.puntos, rango).sorted { $0.fecha < $1.fecha }
            guard !dentro.isEmpty else { return nil }
            return Serie(id: s.id, nombre: s.nombre, color: s.color,
                         puntos: dentro, dominio: s.dominio)
        }
    }

    /// La unión ORDENADA y sin repetidos de las fechas visibles: lo que el dedo puede pisar.
    public static func fechasUnion(_ visibles: [Serie]) -> [Date] {
        var set = Set<Date>()
        for s in visibles { for p in s.puntos { set.insert(p.fecha) } }
        return set.sorted()
    }

    /// `.minimo` mira lo que el caller TRAJO (nadie escogió dos métricas todavía);
    /// `.sinLecturas` mira lo que la ventana DEJÓ. Con una sola línea no se dibuja gráfica:
    /// una comparación de uno no es una comparación.
    ///
    /// Ojo (caller): el contrato es de 2 a 4 series. Con más de cuatro el componente NO
    /// recorta —tirar una serie en silencio sería mentir sobre lo que se está comparando—
    /// pero la lectura se degrada: cuatro colores es el techo legible sobre papel.
    public static func resolverEstado(series: [Serie], visibles: [Serie]) -> Estado {
        if series.count < 2 { return .minimo }
        if visibles.count < 2 { return .sinLecturas }
        return .datos
    }

    /// El mismo veredicto, resuelto desde cero (lo que usan las pruebas y cualquier caller
    /// que quiera preguntar antes de montar la vista).
    public static func resolverEstado(_ series: [Serie], _ rango: ClosedRange<Date>) -> Estado {
        resolverEstado(series: series, visibles: recortadas(series, rango))
    }

    /// El valor de una serie en una fecha EXACTA (paridad `CompareSeries.value(on:)`, que
    /// casaba por clave de día).
    static func valor(_ s: Serie, en fecha: Date) -> Double? {
        s.puntos.first(where: { $0.fecha == fecha })?.valor
    }
}

#if DEBUG

// MARK: - Previews

/// Datos de demo: dos escalas que NO se parecen en nada (ms contra miles de pasos) para que
/// el preview enseñe justo lo que el componente promete.
private enum SuperpuestaDemo {
    static let cal = Calendar.current
    static let hoy: Date = cal.startOfDay(for: Date())

    static func fecha(_ diasAtras: Int) -> Date {
        cal.date(byAdding: .day, value: -diasAtras, to: hoy) ?? hoy
    }

    static var ventana: ClosedRange<Date> { fecha(29)...hoy }

    static func serie(id: String, nombre: String, color: Color,
                      base: Double, onda: Double, dominio: ClosedRange<Double>,
                      cada: Int = 1, dias: Int = 30) -> LiquidGraficaSuperpuesta.Serie {
        let puntos: [(fecha: Date, valor: Double)] = stride(from: dias - 1, through: 0, by: -cada)
            .map { (d: Int) -> (fecha: Date, valor: Double) in
                let k = Double(dias - 1 - d)
                return (fecha: fecha(d), valor: base + onda * sin(k / 3.1) + Double(Int(k) % 5))
            }
        return .init(id: id, nombre: nombre, color: color, puntos: puntos, dominio: dominio)
    }

    static var vfc: LiquidGraficaSuperpuesta.Serie {
        serie(id: "hrv", nombre: "VFC", color: LiquidColor.cian,
              base: 58, onda: 12, dominio: 38...84, cada: 2)
    }
    static var sueno: LiquidGraficaSuperpuesta.Serie {
        serie(id: "sleep", nombre: "Sueño", color: LiquidColor.indigo,
              base: 420, onda: 55, dominio: 300...540)
    }
    static var pasos: LiquidGraficaSuperpuesta.Serie {
        serie(id: "steps", nombre: "Pasos", color: LiquidColor.teal,
              base: 8_600, onda: 3_900, dominio: 0...16_000)
    }
    static var carga: LiquidGraficaSuperpuesta.Serie {
        serie(id: "strain", nombre: "Carga", color: LiquidColor.ambar,
              base: 11, onda: 4.5, dominio: 0...21)
    }

    /// El formateador vive en el caller (el DS no conoce unidades ni locales).
    static let formato: (LiquidGraficaSuperpuesta.Serie, Double) -> String = { s, v in
        switch s.id {
        case "hrv":    return "\(Int(v.rounded())) ms"
        case "sleep":  return "\(Int(v.rounded() / 60))h \(Int(v.rounded()) % 60)m"
        case "steps":  return "\(Int(v.rounded()))"
        default:       return String(format: "%.1f", v)
        }
    }
}

/// Envoltura con estado: el binding de selección es del caller, así que el preview lo
/// sostiene (y el de «con scrub» arranca ya posado en una fecha).
private struct SuperpuestaPreview: View {
    let series: [LiquidGraficaSuperpuesta.Serie]
    var seleccionInicial: Date? = nil
    @State private var seleccion: Date? = nil

    init(series: [LiquidGraficaSuperpuesta.Serie], seleccionInicial: Date? = nil) {
        self.series = series
        self.seleccionInicial = seleccionInicial
        _seleccion = State(initialValue: seleccionInicial)
    }

    var body: some View {
        LiquidGraficaSuperpuesta(
            series: series,
            rango: SuperpuestaDemo.ventana,
            seleccion: $seleccion,
            formatoValor: SuperpuestaDemo.formato,
            a11yLabel: "Comparando " + series.map(\.nombre).joined(separator: ", "),
            mensajeMinimo: "Elige al menos dos métricas para compararlas.",
            mensajeSinLecturas: "Ninguna de estas métricas tiene lecturas en esta ventana.")
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo(tone: LiquidColor.cian))
            .environment(\.liquidMotionDisabled, true)
    }
}

#Preview("Superpuesta · 2 series") {
    SuperpuestaPreview(series: [SuperpuestaDemo.vfc, SuperpuestaDemo.sueno])
}

#Preview("Superpuesta · 4 series") {
    SuperpuestaPreview(series: [SuperpuestaDemo.vfc, SuperpuestaDemo.sueno,
                                SuperpuestaDemo.pasos, SuperpuestaDemo.carga])
}

#Preview("Superpuesta · escalas muy distintas") {
    // VFC en milisegundos (≈40–80) contra pasos en miles (0–16 000): sobre un eje compartido
    // la VFC sería una raya pegada al piso. Aquí las dos usan el alto completo dentro de SU
    // dominio y la leyenda dice cuál es ese dominio.
    SuperpuestaPreview(series: [SuperpuestaDemo.vfc, SuperpuestaDemo.pasos])
}

#Preview("Superpuesta · con scrub") {
    SuperpuestaPreview(series: [SuperpuestaDemo.vfc, SuperpuestaDemo.sueno, SuperpuestaDemo.pasos],
                       seleccionInicial: SuperpuestaDemo.fecha(9))
}

#Preview("Superpuesta · una sola serie (sin comparación)") {
    // El estado honesto: con una sola métrica no se dibuja una línea sola disfrazada de
    // comparador — se dice con el mensaje del caller.
    SuperpuestaPreview(series: [SuperpuestaDemo.vfc])
}

#Preview("Superpuesta · sin lecturas en la ventana") {
    // Dos métricas elegidas, pero la ventana no deja dos con datos: otra causa, otra frase.
    SuperpuestaPreview(series: [
        SuperpuestaDemo.vfc,
        .init(id: "temp", nombre: "Temp. de piel", color: LiquidColor.doradoTemp,
              puntos: [(fecha: SuperpuestaDemo.fecha(400), valor: 0.4)],
              dominio: -1...1),
    ])
}

#Preview("Superpuesta · AX") {
    SuperpuestaPreview(series: [SuperpuestaDemo.vfc, SuperpuestaDemo.sueno,
                                SuperpuestaDemo.pasos, SuperpuestaDemo.carga],
                       seleccionInicial: SuperpuestaDemo.fecha(9))
        .dynamicTypeSize(.accessibility3)
}
#endif
