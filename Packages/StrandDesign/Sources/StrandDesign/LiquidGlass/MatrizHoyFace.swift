import SwiftUI

// MARK: - FER-51 · Cara Matriz (Lane B)
//
// Modelo tonto (`Sendable`, sin lógica) + vista que lo dibuja. La proyección de datos
// vive en `LiquidHoyBuilder.matriz` (capa app). Reusa MatrizChart / OrbeVivo /
// MedidorLunar / LiquidColor. Tinta sobre el suelo vivo de Hoy, sin tarjetas, filos 1 px.

// MARK: Model

/// Payload de gráfica ya derivado — el builder rellena; la vista solo pinta.
public enum MatrizChartPayload: Sendable, Equatable {
    case columnas(noches: [MatrizColumnas.Noche], referencia: Double,
                  referenciaTag: String, dominio: ClosedRange<Double>)
    case lineaRellena(puntos: [Double?], base: Double?, dominio: ClosedRange<Double>,
                      alfa: Double, alertaHoy: MedidorLunar.Alerta)
    case lineaSerena(puntos: [Double?], banda: ClosedRange<Double>?,
                     dominio: ClosedRange<Double>, alertaHoy: MedidorLunar.Alerta)
    case rielZona(p: Double?, zona: ClosedRange<Double>, estela: [Double],
                  alertaHoy: MedidorLunar.Alerta = .ninguna)
    case barrasMini(valores: [Double?])
    case escalerita(niveles: [Int?])
}

/// Una sección de la Matriz (sello + título + valor + chart).
public struct MatrizSeccion: Sendable, Identifiable, Equatable {
    public let id: String
    public let hue: Color
    /// Guardián bicolor (dorado + azul). nil = orbe monocolor.
    public let huesPar: (Color, Color)?
    public let titulo: String
    public let valor: String
    /// Unidad del valor («ms», «bpm», «rpm») — se pinta chica, mismo hue (Grok-UI #7).
    public let unidad: String?
    /// Protagonista del veredicto (sueño / FC): numeral grande; el resto, medio (UX #3).
    public let destacada: Bool
    /// ¿Esta señal VOTA el veredicto? Pinta el sello «vota» (P3 del estudio en frío:
    /// «si etiquetas al abstenido, etiqueta a los votantes» — Sofía).
    public let vota: Bool
    /// Bitácora/referencia (VFC, pasos): numeral un nivel abajo (P7).
    public let terciaria: Bool
    public let sublabel: String?
    public let chartID: String
    public let chart: MatrizChartPayload
    /// Chip del guardián (solo esa sección); nil en el resto.
    public let chip: MatrizHoyModel.ChipGuardian?
    /// Renglones nombrados del guardián (Temp / Resp); nil en el resto.
    public let renglones: [MatrizRenglon]?

    public init(id: String, hue: Color,
                huesPar: (Color, Color)? = nil, titulo: String, valor: String,
                unidad: String? = nil, destacada: Bool = false,
                vota: Bool = false, terciaria: Bool = false,
                sublabel: String? = nil, chartID: String, chart: MatrizChartPayload,
                chip: MatrizHoyModel.ChipGuardian? = nil,
                renglones: [MatrizRenglon]? = nil) {
        self.id = id; self.hue = hue; self.huesPar = huesPar
        self.titulo = titulo; self.valor = valor
        self.unidad = unidad; self.destacada = destacada
        self.vota = vota; self.terciaria = terciaria
        self.sublabel = sublabel
        self.chartID = chartID; self.chart = chart; self.chip = chip
        self.renglones = renglones
    }

    public static func == (lhs: MatrizSeccion, rhs: MatrizSeccion) -> Bool {
        lhs.id == rhs.id && lhs.titulo == rhs.titulo && lhs.valor == rhs.valor
            && lhs.sublabel == rhs.sublabel && lhs.chartID == rhs.chartID
            && lhs.chart == rhs.chart && lhs.chip == rhs.chip
            && lhs.renglones == rhs.renglones
            && lhs.hue == rhs.hue
            && lhs.huesPar?.0 == rhs.huesPar?.0 && lhs.huesPar?.1 == rhs.huesPar?.1
            && lhs.unidad == rhs.unidad && lhs.destacada == rhs.destacada
            && lhs.vota == rhs.vota && lhs.terciaria == rhs.terciaria
    }
}

/// Renglón nombrado del guardián (Temp piel / Resp) con su línea serena.
public struct MatrizRenglon: Sendable, Identifiable, Equatable {
    public let id: String
    public let titulo: String
    public let valor: String
    public let unidad: String?
    /// Estado en palabras bajo el renglón («dentro de tu banda», «típica tuya») — P2.
    public let sublabel: String?
    public let hue: Color
    public let chartID: String
    public let chart: MatrizChartPayload
    public let subrayado: MedidorLunar.Alerta

    public init(id: String, titulo: String, valor: String, unidad: String? = nil,
                sublabel: String? = nil,
                hue: Color, chartID: String, chart: MatrizChartPayload,
                subrayado: MedidorLunar.Alerta = .ninguna) {
        self.id = id; self.titulo = titulo; self.valor = valor; self.unidad = unidad
        self.sublabel = sublabel
        self.hue = hue
        self.chartID = chartID; self.chart = chart; self.subrayado = subrayado
    }

    public static func == (lhs: MatrizRenglon, rhs: MatrizRenglon) -> Bool {
        lhs.id == rhs.id && lhs.titulo == rhs.titulo && lhs.valor == rhs.valor
            && lhs.chartID == rhs.chartID && lhs.chart == rhs.chart
            && lhs.subrayado == rhs.subrayado && lhs.hue == rhs.hue
            && lhs.unidad == rhs.unidad && lhs.sublabel == rhs.sublabel
    }
}

/// Modelo tonto de la cara Matriz. Sin lógica: el builder proyecta todo.
public struct MatrizHoyModel: Sendable, Equatable {

    /// Chip del guardián — texto + tono ya resueltos por el builder (§8 / criterio 10).
    public struct ChipGuardian: Sendable, Equatable {
        public enum Tono: Sendable, Equatable {
            case calma       // verde
            case terciario   // vigilando una sola señal — sin cálidos
            case atencion    // ámbar — par 1.ª noche
            case alarma      // rojo — racha ≥ 2
        }
        public let texto: String
        public let tono: Tono
        public init(texto: String, tono: Tono) {
            self.texto = texto; self.tono = tono
        }
    }

    /// Banda visual §7: ancha completa o dividida (2 elementos a11y).
    /// Las divididas son MITADES EXACTAS — el filo parte la banda al centro
    /// (decisión de diseño; el ancho variable se retiró, hallazgo Grok #3).
    public enum Banda: Sendable, Equatable {
        case full(MatrizSeccion)
        case split(izq: MatrizSeccion, der: MatrizSeccion)
        /// Rótulo de NIVEL (Opción A del dueño): «Deciden tu día · Vigila · Contexto ·
        /// Bitácora» — el orden enseña el modelo sin manual. Con `manualID` la fila
        /// entera es tocable (FER-54): un «?» hueco discreto anuncia la hoja-manual
        /// que explica ese nivel; `nil` = decorativo como siempre.
        case nivel(String, manualID: String?)
    }

    /// Orden VISUAL de arriba a abajo (§7). Bandas divididas = 2 elementos a11y.
    public let bandas: [Banda]

    public init(bandas: [Banda]) {
        self.bandas = bandas
    }

    /// Orden de lectura VoiceOver = orden visual; bandas divididas expanden a 2 ids.
    public var ordenA11y: [String] {
        var ids: [String] = []
        for b in bandas {
            switch b {
            case .full(let s): ids.append(s.id)
            case .split(let izq, let der):
                ids.append(izq.id); ids.append(der.id)
            case .nivel:
                break   // decorativo: VoiceOver lee las secciones, no las capas.
            }
        }
        return ids
    }
}

// MARK: - Face view

/// Cara Matriz completa: héroe compacto + 5 bandas §7 + filos 1 px.
/// Breakpoint: Dynamic Type ≥ accessibility1 o ancho estrecho → columna única con scroll.
public struct MatrizHoyFace: View {
    private let model: MatrizHoyModel
    private let onTapSeccion: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Acuse del sello: el orbe de la sección tocada late una vez (cariño §micro).
    @State private var latido: String?

    public init(model: MatrizHoyModel, onTapSeccion: @escaping (String) -> Void) {
        self.model = model
        self.onTapSeccion = onTapSeccion
    }

    public var body: some View {
        // El héroe de la pantalla es el ecosistema de partículas que ya vive arriba — la
        // Matriz NO repite orbe ni palabra, NO trae fondo propio (la telemetría se imprime
        // directo sobre el suelo vivo de Hoy) y NO scrollea por su cuenta: mide su contenido
        // y el scroll es el de la pantalla (revisión del dueño en vivo, 2026-08-06).
        let columnaUnica = dynamicTypeSize >= .accessibility1
        VStack(spacing: 0) {
            ForEach(Array(model.bandas.enumerated()), id: \.offset) { _, banda in
                bandaView(banda, columnaUnica: columnaUnica)
                if case .nivel = banda {} else { filo() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, LiquidSpace.s600)
        .sensoryFeedback(.selection, trigger: latido)
        .accessibilityElement(children: .contain)
    }

    /// El texto de un rótulo de nivel (compartido por el decorativo y el tocable).
    private func nivelTexto(_ rotulo: String) -> some View {
        Text(rotulo)
            .font(LiquidType.micro)
            .tracking(LiquidType.microTracking)
            .textCase(.uppercase)
            .foregroundStyle(LiquidColor.tinta500)
    }

    /// Toca una sección: dispara su hoja + el latido del sello.
    private func tocar(_ id: String) {
        if !reduceMotion {
            withAnimation(.spring(duration: 0.3)) { latido = id }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeOut(duration: 0.25)) { latido = nil }
            }
        }
        onTapSeccion(id)
    }

    @ViewBuilder
    private func bandaView(_ banda: MatrizHoyModel.Banda, columnaUnica: Bool) -> some View {
        switch banda {
        case .full(let s):
            seccionView(s)
                .padding(.vertical, MatrizTokens.bandaV)
        case .nivel(let rotulo, let manualID):
            if let manualID {
                // FER-54: la fila entera es el hit (≥44 pt); el «?» hueco en el mismo
                // gris del rótulo — visible al que busca, invisible al que ya sabe.
                Button { tocar(manualID) } label: {
                    HStack(spacing: LiquidSpace.s150) {
                        nivelTexto(rotulo)
                        Image(systemName: "questionmark.circle")
                            .font(LiquidType.infoGlifoCompacto.weight(.medium))
                            .foregroundStyle(LiquidColor.tinta500)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, MatrizTokens.bandaV)
                    .frame(minHeight: LiquidControl.hitTarget, alignment: .bottomLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(rotulo))
                .accessibilityHint(Text(String(localized: "matriz.nivel.manual.hint",
                                               defaultValue: "How this works",
                                               bundle: .main)))
            } else {
                nivelTexto(rotulo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, MatrizTokens.bandaV)
                    .accessibilityHidden(true)
            }
        case .split(let izq, let der):
            if columnaUnica {
                VStack(spacing: 0) {
                    seccionView(izq).padding(.vertical, MatrizTokens.bandaV)
                    filo()
                    seccionView(der).padding(.vertical, MatrizTokens.bandaV)
                }
            } else {
                // Mitades iguales: el filo vertical parte la banda al centro.
                HStack(alignment: .top, spacing: 0) {
                    seccionView(izq)
                        // La celda mide su CONTENIDO: sin esto una propuesta alta del
                        // layout inflaba el encabezado flexible y el chart caía al
                        // fondo (regresión cazada en vivo).
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, MatrizTokens.colGap)
                        .padding(.vertical, MatrizTokens.bandaV)
                    Rectangle()
                        .fill(LiquidColor.tinta900.opacity(MatrizTokens.filoAlfa))
                        .frame(width: 1)
                        // Mismo borde que las columnas que separa (edge-to-edge, como
                        // los filos horizontales — convergencia de simetría R2).
                        .padding(.vertical, MatrizTokens.bandaV)
                    seccionView(der)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, MatrizTokens.colGap)
                        .padding(.vertical, MatrizTokens.bandaV)
                }
            }
        }
    }

    @ViewBuilder
    private func seccionView(_ s: MatrizSeccion) -> some View {
        if let renglones = s.renglones {
            // Sección con renglones (guardián): SIN botón contenedor — anidar botones
            // rompe hit-testing y el foco de VoiceOver (hallazgo Grok #1). El encabezado
            // es su propio botón y cada renglón el suyo.
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                Button {
                    tocar(s.id)
                } label: {
                    encabezado(s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: a11yLabel(s)))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("matriz-seccion-\(s.id)")
                ForEach(renglones) { r in
                    renglónView(r)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                tocar(s.id)
            } label: {
                VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                    encabezado(s)
                    chartView(s.chart, hue: s.hue, chartID: s.chartID)
                        .frame(height: chartAltura(s.chart))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: a11yLabel(s)))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("matriz-seccion-\(s.id)")
        }
    }

    private func encabezado(_ s: MatrizSeccion) -> some View {
        // Dos renglones a lo ANCHO de la celda: [orbe · título · valor · ›] y debajo
        // [sello vota · estado]. El sello/estado dentro del VStack del título competía
        // con el Spacer y se estrujaba a 1 carácter por línea (torre — cazada en arnés).
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            HStack(alignment: .firstTextBaseline, spacing: MatrizTokens.selloTexto) {
                // Orbe de partículas puro, sin glifo (revisión del dueño en vivo): el
                // eco del héroe junto a cada título, con el hue de identidad.
                OrbeVivo(radio: MatrizTokens.selloRadio, hue: s.huesPar?.0 ?? s.hue,
                         semillaID: "sello-\(s.id)", huePar: s.huesPar?.1, fps: 12)
                    // El orbe no es texto: ancla su centro óptico al centro de las
                    // versalitas del título (hallazgo Grok-UI #3; afinado en vivo).
                    .alignmentGuide(.firstTextBaseline) { d in d.height * 0.78 }
                    // Acuse del tacto: el eco del héroe responde al dedo (§micro).
                    .scaleEffect(latido == s.id ? 1.10 : 1)
                Text(s.titulo)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta700)
                    .textCase(.uppercase)
                    // Nunca partir palabra («RESTIN-G HR»): hasta 2 líneas por espacio
                    // y encoge un poco antes de quebrar.
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: LiquidSpace.s200)
                if let chip = s.chip {
                    chipView(chip)
                } else {
                    valorCompuesto(s)
                }
                // Affordance de tap discreta (UX #6): cada sección abre su detalle.
                LiquidIcon(.chevron, size: 8, color: LiquidColor.tinta500)
                    .alignmentGuide(.firstTextBaseline) { d in d.height * 0.85 }
            }
            if s.vota || s.sublabel != nil {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    if s.vota {
                        // P3: las votantes llevan su sello — el modelo se lee solo.
                        Text(String(localized: "matriz.vota", defaultValue: "votes"))
                            .font(LiquidType.micro)
                            .foregroundStyle(LiquidColor.verdePrimario)
                            .padding(.horizontal, LiquidSpace.s150)
                            .padding(.vertical, LiquidSpace.s025)
                            .overlay(Capsule().strokeBorder(
                                LiquidColor.verdePrimario.opacity(0.45), lineWidth: 1)) // token-exempt: aro del sello «vota» al 45 %
                            .fixedSize()
                    }
                    if let sub = s.sublabel {
                        Text(sub)
                            .font(LiquidType.caption)
                            .foregroundStyle(LiquidColor.tinta500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Alineado con el título (después del orbe), a lo ancho de la celda.
                .padding(.leading, MatrizTokens.selloRadio * 2 + MatrizTokens.selloTexto)
            }
        }
        // Techo común en bandas divididas: reservar la línea de sublabel aunque
        // falte, para que los lienzos gemelos arranquen parejos (Grok-UI #6).
        .frame(minHeight: MatrizTokens.encabezadoMinH, alignment: .top)
    }

    /// Numeral + unidad chica en el mismo hue (Grok-UI #7); los protagonistas del
    /// veredicto (sueño/FC) en `valorL`, el resto en `valorM` (UX #3). El numeral
    /// rueda al refrescar (`numericText`) en vez de parpadear.
    private func valorCompuesto(_ s: MatrizSeccion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s050) {
            Text(s.valor)
                .font(s.destacada ? LiquidType.valorL
                      : (s.terciaria ? LiquidType.valorS : LiquidType.valorM))
                .foregroundStyle(s.hue)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: s.valor)
            if let u = s.unidad {
                Text(u)
                    .font(LiquidType.caption)
                    .foregroundStyle(s.hue)
            }
        }
        // El numeral JAMÁS se parte («46» → «4/6»): una línea, encoge antes de
        // envolver. Sin layoutPriority: estrangulaba al título hasta volverlo una
        // torre de 1 carácter (regresión cazada en vivo).
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private func renglónView(_ r: MatrizRenglon) -> some View {
        Button {
            onTapSeccion(r.id)
        } label: {
            VStack(alignment: .leading, spacing: MatrizTokens.renglonV) {
                // Sentence-case a propósito: los renglones son SUB-señales del guardián
                // (voz subordinada); el ritmo/baseline sí es el mismo del encabezado.
                HStack(alignment: .firstTextBaseline, spacing: MatrizTokens.selloTexto) {
                    Text(r.titulo)
                        .font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta700)
                    Spacer(minLength: MatrizTokens.selloTexto)
                    HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s050) {
                        Text(r.valor)
                            .font(LiquidType.valorM)
                            .foregroundStyle(r.hue)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: r.valor)
                        if let u = r.unidad {
                            Text(u)
                                .font(LiquidType.caption)
                                .foregroundStyle(r.hue)
                        }
                    }
                    .underline(r.subrayado != .ninguna,
                               color: r.subrayado == .alarma
                               ? LiquidColor.negativo : LiquidColor.atencion)
                    // Chevron gemelo del encabezado: el renglón también abre su hoja
                    // y sus numerales alinean con los del header (Grok simetría R1).
                    LiquidIcon(.chevron, size: 8, color: LiquidColor.tinta500)
                        .alignmentGuide(.firstTextBaseline) { d in d.height * 0.85 }
                }
                if let sub = r.sublabel {
                    // P2: el estado en palabras — el número deja de asustar.
                    Text(sub)
                        .font(LiquidType.caption)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                chartView(r.chart, hue: r.hue, chartID: r.chartID)
                    .frame(height: MatrizTokens.alturaRenglon)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(r.titulo), \(r.valor)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("matriz-renglon-\(r.id)")
    }

    private func chipView(_ chip: MatrizHoyModel.ChipGuardian) -> some View {
        let color: Color = {
            switch chip.tono {
            case .calma: return LiquidColor.verdePrimario
            case .terciario: return LiquidColor.tinta500
            case .atencion: return LiquidColor.atencion
            case .alarma: return LiquidColor.negativo
            }
        }()
        return Text(chip.texto)
            .font(LiquidType.caption)
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func chartView(_ payload: MatrizChartPayload, hue: Color,
                           chartID: String) -> some View {
        switch payload {
        case .columnas(let noches, let ref, let tag, let dom):
            MatrizColumnas(chartID: chartID, noches: noches, referencia: ref,
                           referenciaTag: tag, dominio: dom, hue: hue)
        case .lineaRellena(let pts, let base, let dom, let alfa, let alerta):
            MatrizLineaRellena(chartID: chartID, puntos: pts, base: base, dominio: dom,
                               hue: hue, alfa: alfa, alertaHoy: alerta)
        case .lineaSerena(let pts, let banda, let dom, let alerta):
            MatrizLineaSerena(chartID: chartID, puntos: pts, banda: banda, dominio: dom,
                              hue: hue, alertaHoy: alerta)
        case .rielZona(let p, let zona, let estela, let alertaHoy):
            MatrizRielZona(chartID: chartID, p: p, zona: zona, estela: estela, hue: hue,
                           alertaHoy: alertaHoy)
        case .barrasMini(let valores):
            MatrizBarrasMini(chartID: chartID, valores: valores, hue: hue)
        case .escalerita(let niveles):
            MatrizEscalerita(chartID: chartID, niveles: niveles, hue: hue)
        }
    }

    private func chartAltura(_ p: MatrizChartPayload) -> CGFloat {
        switch p {
        case .rielZona: return MatrizTokens.alturaRiel
        case .barrasMini: return MatrizTokens.alturaBarras
        case .escalerita: return MatrizTokens.alturaEscalera
        default: return MatrizTokens.alturaLinea
        }
    }

    private func filo() -> some View {
        Rectangle()
            .fill(LiquidColor.tinta900.opacity(MatrizTokens.filoAlfa))
            .frame(height: 1)
    }

    private func a11yLabel(_ s: MatrizSeccion) -> String {
        var parts = [s.titulo, s.valor]
        if let sub = s.sublabel { parts.append(sub) }
        if let chip = s.chip { parts.append(chip.texto) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
private enum MatrizHoyFacePreviewData {
    static var t1Bueno: MatrizHoyModel {
        let noches: [MatrizColumnas.Noche] = (0..<14).map { i in
            .init(valor: 420 + Double(i % 4) * 12, alerta: .ninguna)
        }
        let fc: [Double?] = (0..<20).map { i in 58 + Double(i % 5) }
        let vfc: [Double?] = (0..<20).map { i in 40 + Double(i % 7) }
        let estela: [Double] = [0.9, 1.0, 1.05, 0.95, 1.1]
        let strain: [Double?] = (0..<14).map { Double(10 + $0) }
        let steps: [Double?] = (0..<14).map { Double(6000 + $0 * 200) }
        let stress: [Int?] = [0, 1, 0, 1, 1, 0, 1]
        let temp: [Double?] = (0..<20).map { _ in 0.1 }
        let resp: [Double?] = (0..<20).map { _ in 14.0 }

        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "7:12",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: noches, referencia: 420,
                                     referenciaTag: "7 h", dominio: 240...600))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "52",
                        chartID: "matriz-rhr",
                        chart: .lineaRellena(puntos: fc, base: 56, dominio: 45...75,
                                             alfa: 1.0, alertaHoy: .ninguna)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "68 ms",
                        sublabel: "Does not vote",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(puntos: vfc, base: 45, dominio: 20...80,
                                             alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                        dominio: -1...1, alertaHoy: .ninguna),
                    chip: .init(texto: "At ease", tono: .calma),
                    renglones: [
                        MatrizRenglon(id: "skintemp", titulo: "Skin temp",
                                      valor: "+0.1°", hue: LiquidColor.doradoTemp,
                                      chartID: "matriz-guardian-temp",
                                      chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                                          dominio: -1...1, alertaHoy: .ninguna)),
                        MatrizRenglon(id: "resp", titulo: "Breathing",
                                      valor: "14.0", hue: LiquidColor.azul,
                                      chartID: "matriz-guardian-resp",
                                      chart: .lineaSerena(puntos: resp, banda: 12...16,
                                                          dominio: 8...22, alertaHoy: .ninguna)),
                    ])),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "1.12",
                        sublabel: "Steady",
                        chartID: "matriz-carga",
                        chart: .rielZona(p: 1.12, zona: 0.8...1.3, estela: estela)),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "12.4",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: strain))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta900,
                        titulo: "Stress", valor: "Low",
                        sublabel: "vs your 7 days",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: stress)),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "8 432",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: steps))),
            ])
    }

    static var t2Calibrando: MatrizHoyModel {
        let vacioNoches = [MatrizColumnas.Noche](repeating: .init(valor: nil), count: 14)
        let vacio20 = [Double?](repeating: nil, count: 20)
        let vacio14 = [Double?](repeating: nil, count: 14)
        let vacio7 = [Int?](repeating: nil, count: 7)
        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "—",
                    sublabel: "Getting to know you",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: vacioNoches, referencia: 420,
                                     referenciaTag: "7 h", dominio: 240...600))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "—",
                        sublabel: "Getting to know you",
                        chartID: "matriz-rhr",
                        chart: .lineaRellena(puntos: vacio20, base: nil, dominio: 45...75,
                                             alfa: 1.0, alertaHoy: .ninguna)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "—",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(puntos: vacio20, base: nil, dominio: 20...80,
                                             alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "—",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: vacio20, banda: nil, dominio: -1...1,
                                        alertaHoy: .ninguna))),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "—",
                        sublabel: "Calibrating",
                        chartID: "matriz-carga",
                        chart: .rielZona(p: nil, zona: 0.8...1.3, estela: [])),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "—",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: vacio14))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta900,
                        titulo: "Stress", valor: "—",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: vacio7)),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "—",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: vacio14))),
            ])
    }

    static var t3Alerta: MatrizHoyModel {
        let noches: [MatrizColumnas.Noche] = (0..<14).map { i in
            .init(valor: i == 13 ? 5.0 : 7.0,
                  alerta: (i == 13 || i == 5) ? .atencion : .ninguna)
        }
        let fc: [Double?] = (0..<20).map { i in i == 19 ? 72.0 : 58.0 }
        let temp: [Double?] = (0..<20).map { i in i >= 17 ? 0.9 : 0.1 }
        let resp: [Double?] = (0..<20).map { i in i >= 17 ? 17.0 : 14.0 }
        let estela: [Double] = [1.0, 1.1, 1.2, 1.3, 1.4]
        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "5:00",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: noches, referencia: 7,
                                     referenciaTag: "7 h", dominio: 4...10))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "72",
                        chartID: "matriz-rhr",
                        chart: .lineaRellena(puntos: fc, base: 56, dominio: 45...80,
                                             alfa: 1.0, alertaHoy: .atencion)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "38 ms",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(
                            puntos: (0..<20).map { _ in 38.0 as Double? },
                            base: 45, dominio: 20...80, alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                        dominio: -1...1, alertaHoy: .alarma),
                    chip: .init(texto: "Temperature and breathing off · 3rd night",
                                tono: .alarma),
                    renglones: [
                        MatrizRenglon(id: "skintemp", titulo: "Skin temp",
                                      valor: "+0.9°", hue: LiquidColor.doradoTemp,
                                      chartID: "matriz-guardian-temp",
                                      chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                                          dominio: -1...1, alertaHoy: .alarma),
                                      subrayado: .alarma),
                        MatrizRenglon(id: "resp", titulo: "Breathing",
                                      valor: "17.0", hue: LiquidColor.azul,
                                      chartID: "matriz-guardian-resp",
                                      chart: .lineaSerena(puntos: resp, banda: 12...16,
                                                          dominio: 8...22, alertaHoy: .alarma),
                                      subrayado: .alarma),
                    ])),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "1.48", sublabel: "Building",
                        chartID: "matriz-carga",
                        chart: .rielZona(p: 1.48, zona: 0.8...1.3, estela: estela)),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "14.0",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: (0..<14).map { Double(10 + $0) }))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta900,
                        titulo: "Stress", valor: "High",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: [0, 1, 1, 2, 2, 1, 2])),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "3 200",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: (0..<14).map { Double(3000 + $0 * 50) }))),
            ])
    }
}

#Preview("Matriz · T1 bueno") {
    MatrizHoyFace(model: MatrizHoyFacePreviewData.t1Bueno, onTapSeccion: { _ in })
}

#Preview("Matriz · T2 calibrando") {
    MatrizHoyFace(model: MatrizHoyFacePreviewData.t2Calibrando, onTapSeccion: { _ in })
}

#Preview("Matriz · T3 alerta") {
    MatrizHoyFace(model: MatrizHoyFacePreviewData.t3Alerta, onTapSeccion: { _ in })
}
#endif
