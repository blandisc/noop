import SwiftUI

// MARK: - Liquid Glass · La forma del día en barras, con scrub
//
// La tira de barras por hora del mapa del día: una barra por hora civil, la punteada
// neutra de «tu calma normal» cruzando el campo, y un arrastre horizontal que nombra la
// hora bajo el dedo en un chip. Port de `StressBarsStrip` + `DashedHLine`
// (`Cenit/Screens/StressDayMapView.swift`, FER-433/447/860), que hoy viven dibujadas a
// mano dentro de la pantalla: aquí conservan su geometría (barra de 10 pt, campo de 96,
// gap mínimo de 2, esquinas de 2, punteada 4/3, cursor que sobresale 1 pt) y cambian de
// PIEL — tinta/papel de `InstrumentoTheme` → tokens Liquid.
//
// Tres contratos que este componente NO puede romper:
//
//  1. `nil` (no hubo lectura) ≠ `0` (se midió y estabas en calma). Una hora sin lectura
//     deja un HUECO —un muñón corto en `tinta7`, deliberadamente MÁS BAJO que la barra
//     más chica posible— y nunca se tiñe del tono. Un cero medido sí es una barra del
//     tono, en su piso. El componente jamás fabrica una altura para lo que no se midió.
//  2. La punteada de referencia es NEUTRA (tinta), nunca teñida del veredicto: es TU
//     normal, no una meta. Con `referencia == nil` no se dibuja ni se menciona en la voz.
//  3. El scrub NO puede robar el scroll vertical. Reusa `liquidScrubPan` (FER-73 · H-S),
//     que no EMPIEZA si el dedo va vertical, y el mapeo dedo→índice ya probado de
//     `ScrubMapeo` (barras = bins, no serie). Este componente no escribe un `DragGesture`.
//
// Contrato: cada `etiqueta` («14:00»), el rótulo de la referencia y el texto del chip
// llegan YA formateados/localizados por el caller. El DS no formatea horas ni acuña copy.

public struct LiquidBarrasHora: View {

    /// Una hora del día: su identidad (0…23), el valor MEDIDO —o `nil` si esa hora no tuvo
    /// lectura— y la etiqueta ya formateada por el caller («14:00»).
    public struct Hora: Identifiable, Equatable, Sendable {
        public let id: Int
        public let valor: Double?
        public let etiqueta: String

        public init(id: Int, valor: Double?, etiqueta: String) {
            self.id = id
            self.valor = valor
            self.etiqueta = etiqueta
        }
    }

    private let horas: [Hora]
    private let tono: Color
    private let referencia: Double?
    private let referenciaEtiqueta: String?
    private let dominio: ClosedRange<Double>
    @Binding private var seleccion: Int?
    private let formatoChip: (Hora) -> String
    private let a11yLabel: String
    private let a11yValueBase: String

    /// En tallas de accesibilidad el eje se queda con sus DOS anclas extremas: el ancla de
    /// en medio es la primera en chocar cuando el contenedor se angosta. Nada se recorta.
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    /// Con «Reducir movimiento» el atenuado del scrub aparece colocado, sin transición.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Geometría interna (port exacto de `StressBarsStrip`)

    /// Alto del campo de barras (`StressBarsStrip.barsHeight`).
    private let altoBarras: CGFloat = 96
    /// Ancho de cada barra (`StressBarsStrip.barWidth`). El gap se reparte con lo que sobra.
    private let anchoBarra: CGFloat = 10
    /// Esquinas de la barra: geometría de DATO, no un radio de layout (el sistema no tiene
    /// token por debajo de `LiquidRadius.control`; mismo literal que el swatch de
    /// `LiquidStageBar`).
    private let radioBarra: CGFloat = 2 // token-exempt: geometría de dato
    /// Patrón de la punteada de referencia (`DashedHLine` + `dash: [4, 3]`).
    private let dashReferencia: [CGFloat] = [4, 3] // token-exempt: geometría de dato
    /// Cuánto sobresale el cursor del scrub por arriba del campo (el `height + 2` / `y: -1`
    /// del original: el hilo respira fuera de la barra que corta).
    private let cursorSobresale: CGFloat = 1

    /// Muñón del HUECO: la hora que no se midió. Es el número que hace VISIBLE el contrato
    /// nº 1 — vive por debajo de `altoMinimo`, así que un hueco NUNCA puede confundirse con
    /// un cero medido, ni siquiera de reojo.
    static let altoHueco: CGFloat = 8
    /// Piso de una barra MEDIDA: hasta un cero honesto deja marca (`max(10, …)` del original).
    static let altoMinimo: CGFloat = 10

    /// - Parameters:
    ///   - horas: el día, en el orden en que se dibuja (la barra i es `horas[i]`).
    ///   - tono: la identidad de la señal. Tiñe SOLO las barras medidas.
    ///   - referencia: dónde cruza «tu normal», en unidades del dominio. `nil` = no se dibuja.
    ///   - referenciaEtiqueta: su rótulo YA localizado («tu calma normal»).
    ///   - dominio: la escala del campo. Todo valor se clampea a él.
    ///   - seleccion: el **`id` de la hora** bajo el dedo (no el índice del arreglo), o `nil`
    ///     si nadie está leyendo. El componente lo escribe al arrastrar y lo limpia al soltar.
    ///   - formatoChip: cómo se lee una hora en el chip. Puro y síncrono; también decide qué
    ///     dice una hora sin lectura (el DS no acuña esa frase).
    public init(horas: [Hora],
                tono: Color,
                referencia: Double?,
                referenciaEtiqueta: String?,
                dominio: ClosedRange<Double>,
                seleccion: Binding<Int?>,
                formatoChip: @escaping (Hora) -> String,
                a11yLabel: String,
                a11yValue: String) {
        self.horas = horas
        self.tono = tono
        self.referencia = referencia
        self.referenciaEtiqueta = referenciaEtiqueta
        self.dominio = dominio
        self._seleccion = seleccion
        self.formatoChip = formatoChip
        self.a11yLabel = a11yLabel
        self.a11yValueBase = a11yValue
    }

    // MARK: Matemática pura (la que fija los contratos, testeable en frío)

    /// Fracción 0–1 de `valor` dentro del dominio, SIEMPRE clampeada. Un dominio degenerado
    /// (ancho 0) no produce NaN: cae a 0.
    static func fraccion(_ valor: Double, dominio: ClosedRange<Double>) -> CGFloat {
        let span = dominio.upperBound - dominio.lowerBound
        guard span > 0 else { return 0 }
        let u = (valor - dominio.lowerBound) / span
        return CGFloat(Swift.min(1, Swift.max(0, u)))
    }

    /// Alto de la barra de una hora. **`nil` = no hay barra**: esa hora no se midió y el
    /// componente dibuja un hueco, no una altura inventada. Un cero MEDIDO sí devuelve
    /// altura (`altoMinimo`) — es el contrato nº 1, en una sola función.
    static func alto(valor: Double?, dominio: ClosedRange<Double>, altoTotal: CGFloat) -> CGFloat? {
        guard let valor else { return nil }
        return Swift.max(altoMinimo, fraccion(valor, dominio: dominio) * altoTotal)
    }

    /// El relleno de una barra: el tono SOLO tiñe lo medido; el hueco va en tinta apagada
    /// (`tinta7`, el token de «segmento de barra inactivo»). Un hueco teñido afirmaría una
    /// lectura que no existe.
    static func relleno(valor: Double?, tono: Color) -> Color {
        valor == nil ? LiquidColor.tinta7 : tono
    }

    /// Dónde cruza la punteada, como fracción del campo. **`nil` = no se dibuja** (sin
    /// referencia, o con un dominio degenerado donde no se puede colocar honestamente).
    static func fraccionReferencia(_ referencia: Double?, dominio: ClosedRange<Double>) -> CGFloat? {
        guard let referencia, dominio.upperBound > dominio.lowerBound else { return nil }
        return fraccion(referencia, dominio: dominio)
    }

    /// Lo que dicta VoiceOver: la lectura del caller y —SOLO si de verdad hay línea— el
    /// rótulo de la referencia. Sin referencia la voz no la menciona (contrato nº 2).
    static func a11yValue(base: String, referencia: Double?, referenciaEtiqueta: String?) -> String {
        guard referencia != nil,
              let etiqueta = referenciaEtiqueta, !etiqueta.isEmpty else { return base }
        return base.isEmpty ? etiqueta : "\(base), \(etiqueta)"
    }

    /// El valor compuesto por el init (lo que verifica el test del cableado).
    var a11y: String {
        Self.a11yValue(base: a11yValueBase, referencia: referencia,
                       referenciaEtiqueta: referenciaEtiqueta)
    }

    // MARK: Cuerpo

    /// Índice del arreglo bajo el dedo (la selección viaja por `id`, no por posición: el
    /// caller puede mandar un día parcial que arranque en cualquier hora).
    private var indiceSeleccionado: Int? {
        guard let seleccion else { return nil }
        return horas.firstIndex { $0.id == seleccion }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            filaChip
            campo
            eje
        }
        // Pulso por hora cruzada, como en el original (`.sensoryFeedback(.selection, …)`).
        .sensoryFeedback(.selection, trigger: seleccion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: a11y))
    }

    /// La lectura del scrub vive ARRIBA del campo, en una fila de alto RESERVADO (el
    /// `readout` de 40 pt del original): al aparecer el chip nada brinca. La reserva es un
    /// chip fantasma —no un número mágico—, así que mide exactamente lo que medirá el real
    /// en cualquier talla de texto.
    private var filaChip: some View {
        ZStack(alignment: .leading) {
            // Dos líneas (valor + hora), como el chip real: si reservara una sola, la fila
            // crecería al aparecer y el campo brincaría.
            LiquidScrubPopup(valor: "—", fecha: "—", color: .clear).hidden()
            if let i = indiceSeleccionado {
                let hora = horas[i]
                LiquidScrubPopup(valor: formatoChip(hora),
                                 fecha: hora.etiqueta,
                                 // Una hora sin lectura no tiene identidad de dato que
                                 // mostrar: su gota va en tinta, no en el tono.
                                 color: hora.valor == nil ? LiquidColor.tinta500 : tono)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var campo: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let gap = Self.gap(ancho: w, anchoBarra: anchoBarra, cuenta: horas.count)
            ZStack(alignment: .bottomLeading) {
                // Piso del campo (el `hairlineStrong` del original).
                Rectangle()
                    .fill(LiquidColor.tinta10)
                    .frame(height: LiquidChart.lineaSecundariaAncho)
                lineaReferencia
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(horas) { barra($0) }
                }
                .frame(width: w, height: altoBarras, alignment: .bottom)
                .animation(reduceMotion ? nil : LiquidMotion.glassOut(LiquidMotion.instant),
                           value: seleccion)
            }
            .frame(width: w, height: altoBarras, alignment: .bottom)
            .overlay(alignment: .leading) { cursor(ancho: w) }
            .contentShape(Rectangle())
            // FER-73 · H-S: el gesto NO EMPIEZA si el dedo va vertical, así una pantalla que
            // scrollea sigue scrolleando aunque el dedo arranque sobre las barras. Nunca un
            // `DragGesture` propio: esa es la regresión cara que este modificador cerró.
            .liquidScrubPan(
                enabled: horas.count > 1,
                onChange: { p in
                    guard horas.count > 1 else { return }
                    // Barras = BINS de ancho igual (no una serie): el mapeo probado de
                    // `ScrubMapeo` ya distingue los dos casos.
                    let i = ScrubMapeo.indice(x: p.x, inset: 0, ancho: w,
                                              count: horas.count, esSerie: false)
                    guard horas.indices.contains(i) else { return }
                    if seleccion != horas[i].id { seleccion = horas[i].id }
                },
                onEnd: { seleccion = nil })
        }
        // 96 pt de alto: muy por encima del piso táctil de `LiquidControl.hitTarget` (44).
        .frame(height: altoBarras)
    }

    /// El gap que reparte el ancho sobrante entre las barras (fórmula del original), con el
    /// piso de 2 pt para que en un contenedor angosto las barras no se peguen.
    static func gap(ancho: CGFloat, anchoBarra: CGFloat, cuenta: Int) -> CGFloat {
        let n = Swift.max(cuenta, 1)
        let sobra = (ancho - anchoBarra * CGFloat(n)) / CGFloat(Swift.max(n - 1, 1))
        return Swift.max(LiquidSpace.s050, sobra)
    }

    private func barra(_ hora: Hora) -> some View {
        let alto = Self.alto(valor: hora.valor, dominio: dominio, altoTotal: altoBarras)
        return RoundedRectangle(cornerRadius: radioBarra, style: .continuous)
            .fill(Self.relleno(valor: hora.valor, tono: tono))
            .frame(width: anchoBarra, height: alto ?? Self.altoHueco, alignment: .bottom)
            .opacity(opacidad(hora))
    }

    /// Mientras alguien lee una hora, el resto del día cede foco (el `× 0.3` del original,
    /// aquí con el alfa de «fuera de foco» de la familia).
    private func opacidad(_ hora: Hora) -> Double {
        guard let seleccion, seleccion != hora.id else { return 1 }
        return LiquidChart.puntoApagadoAlfa
    }

    /// «Tu calma normal»: punteada NEUTRA cruzando el campo con su rótulo pegado arriba a la
    /// derecha. La tinta es del sistema, nunca el tono — es tu normal, no una meta (contrato
    /// nº 2). Sin referencia, aquí no se dibuja nada.
    @ViewBuilder private var lineaReferencia: some View {
        if let frac = Self.fraccionReferencia(referencia, dominio: dominio) {
            VStack(alignment: .trailing, spacing: LiquidSpace.s050) {
                if let referenciaEtiqueta {
                    // Chrome geométrico DENTRO del plot: no escala con Dynamic Type (misma
                    // exención que las etiquetas de eje de la familia); la lectura accesible
                    // la sirve el `accessibilityValue`.
                    Text(verbatim: referenciaEtiqueta)
                        .font(LiquidType.caption)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                LineaPunteadaH()
                    .stroke(LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa),
                            style: StrokeStyle(lineWidth: LiquidChart.scrubReglaAncho,
                                               dash: dashReferencia))
                    .frame(height: LiquidChart.scrubReglaAncho)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(y: -frac * altoBarras)
            .allowsHitTesting(false)
        }
    }

    /// El hilo que marca la hora bajo el dedo: regla vertical del sistema (I2), del ancho de
    /// su bin, sobresaliendo 1 pt por arriba.
    @ViewBuilder private func cursor(ancho: CGFloat) -> some View {
        if let i = indiceSeleccionado, !horas.isEmpty {
            let centro = (CGFloat(i) + 0.5) / CGFloat(horas.count) * ancho
            Rectangle()
                .fill(LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa))
                .frame(width: LiquidChart.scrubReglaAncho,
                       height: altoBarras + cursorSobresale * 2)
                .offset(x: centro - LiquidChart.scrubReglaAncho / 2, y: -cursorSobresale)
                .allowsHitTesting(false)
        }
    }

    /// Anclas del eje, con las etiquetas QUE MANDÓ EL CALLER (el DS no formatea horas):
    /// primera · media · última. En tallas AX se queda con los extremos.
    private var anclas: [String] {
        guard let primera = horas.first, let ultima = horas.last else { return [] }
        guard horas.count > 1 else { return [primera.etiqueta] }
        guard horas.count > 2, !tamanoTexto.isAccessibilitySize else {
            return [primera.etiqueta, ultima.etiqueta]
        }
        return [primera.etiqueta, horas[horas.count / 2].etiqueta, ultima.etiqueta]
    }

    @ViewBuilder private var eje: some View {
        if !anclas.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(anclas.enumerated()), id: \.offset) { i, etiqueta in
                    if i > 0 { Spacer(minLength: LiquidSpace.s200) }
                    Text(verbatim: etiqueta)
                        .font(LiquidType.caption)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: LiquidChart.ejeXAlto)
        }
    }
}

// MARK: - La punteada horizontal (port de `DashedHLine`)

/// Una sola línea a media altura de su caja: existe para que el `dash` la corte en guiones
/// y para que la caja de 1 pt aterrice exactamente donde el `offset` la pone.
private struct LineaPunteadaH: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Previews

#if DEBUG
private enum BarrasHoraDemo {
    /// Un día plausible en la escala 0–3 del mapa de estrés.
    static func perfil(_ h: Int) -> Double {
        switch h {
        case 0..<6: return 0.4
        case 6..<9: return 1.4
        case 9..<13: return 2.1
        case 13..<15: return 2.7
        case 15..<19: return 1.6
        case 19..<22: return 0.9
        default: return 0.5
        }
    }

    static func etiqueta(_ h: Int) -> String { h < 10 ? "0\(h):00" : "\(h):00" }

    /// `huecos` = horas SIN lectura; `ceros` = horas MEDIDAS en calma absoluta. Las dos
    /// juntas son la prueba de ojo del contrato nº 1.
    static func dia(huecos: Set<Int> = [], ceros: Set<Int> = []) -> [LiquidBarrasHora.Hora] {
        (0...23).map { h in
            let v: Double? = huecos.contains(h) ? nil : (ceros.contains(h) ? 0 : perfil(h))
            return .init(id: h, valor: v, etiqueta: etiqueta(h))
        }
    }

    static func chip(_ h: LiquidBarrasHora.Hora) -> String {
        guard let v = h.valor else { return "sin lectura" }
        let decimas = Int((v * 10).rounded())
        return "\(decimas / 10).\(decimas % 10)"
    }

    static func tira(_ horas: [LiquidBarrasHora.Hora],
                    referencia: Double? = 1,
                    seleccion: Binding<Int?>) -> some View {
        LiquidBarrasHora(horas: horas,
                         tono: LiquidColor.ambar,
                         referencia: referencia,
                         referenciaEtiqueta: referencia == nil ? nil : "tu calma normal",
                         dominio: 0...3,
                         seleccion: seleccion,
                         formatoChip: chip,
                         a11yLabel: "Tu día, hora por hora",
                         a11yValue: "Pico a las 14:00")
            .padding(LiquidSpace.s550)
            .background(LiquidColor.papelGradient)
    }
}

/// Interactivo: arrastra sobre las barras para leer cada hora.
private struct BarrasHoraDemoVista: View {
    let horas: [LiquidBarrasHora.Hora]
    var referencia: Double? = 1
    @State private var seleccion: Int? = nil

    var body: some View {
        BarrasHoraDemo.tira(horas, referencia: referencia, seleccion: $seleccion)
    }
}

#Preview("Horas · día completo") {
    BarrasHoraDemoVista(horas: BarrasHoraDemo.dia())
}

/// El contrato nº 1 a la vista: las 3:00 se MIDIERON en cero (barra del tono, en su piso) y
/// las 4:00–5:00 no tuvieron lectura (muñón corto y apagado). No se parecen.
#Preview("Horas · con huecos") {
    BarrasHoraDemoVista(horas: BarrasHoraDemo.dia(huecos: [4, 5, 11, 12, 20],
                                                  ceros: [3]))
}

/// Sin `referencia` no hay punteada ni rótulo — y la voz tampoco la menciona.
#Preview("Horas · sin referencia") {
    BarrasHoraDemoVista(horas: BarrasHoraDemo.dia(), referencia: nil)
}

/// Con la hora bajo el dedo fija: el chip nombra las 14:00 y el resto del día cede foco.
#Preview("Horas · hora seleccionada") {
    BarrasHoraDemo.tira(BarrasHoraDemo.dia(huecos: [4, 5]), seleccion: .constant(14))
}

/// Sin ninguna hora: el campo queda con su piso y su referencia, sin inventar barras.
#Preview("Horas · vacío") {
    BarrasHoraDemoVista(horas: [])
}

#Preview("Horas · AX") {
    BarrasHoraDemoVista(horas: BarrasHoraDemo.dia(huecos: [4, 5]))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
