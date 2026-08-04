import SwiftUI

// MARK: - Liquid Glass · Domino de la regla del guardián (FER-33 · F3a)
//
// Dibuja la regla del guardián: dos carriles (señales) × N noches en puntos sobre rieles.
// Una sola señal fuera no enciende nada; solo la pareja en las últimas noches enciende el
// cerco, la flecha y la pastilla de consecuencia. El componente no conoce el motor: recibe
// puntos ya decididos y strings ya localizados (contrato D3). Color no habla: el diagrama
// entero es un solo elemento de accesibilidad con el label del caller.

public struct LiquidDominoRegla: View {

    /// Cómo amaneció una señal esa noche.
    public enum Punto: Sendable, Equatable {
        /// El motor no la marcó.
        case dentro
        /// El motor la marcó fuera de tu patrón.
        case fuera
        /// Esa noche no hubo lectura de esta señal.
        case sinDato
    }

    public struct Carril: Sendable, Identifiable {
        public let id: String
        /// El glifo de la señal, el MISMO que usa su renglón en la tarjeta de arriba.
        public let icono: LiquidIcon.Glyph
        /// El hue 1:1 de la señal (ámbar para temperatura, azul para respiración).
        public let tono: Color
        /// Izquierda → derecha; la última es ANOCHE. Todos los carriles traen la misma cantidad.
        public let noches: [Punto]
        /// Label de VoiceOver de este carril, YA compuesto y localizado por el caller.
        public let a11y: String

        public init(id: String, icono: LiquidIcon.Glyph, tono: Color,
                    noches: [Punto], a11y: String) {
            self.id = id
            self.icono = icono
            self.tono = tono
            self.noches = noches
            self.a11y = a11y
        }
    }

    private let carriles: [Carril]
    private let cercoUltimas: Int?
    private let etiquetas: [String]
    private let consecuencia: String
    private let encendida: Bool
    private let a11yLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    // Geometría del diagrama (constantes con nombre, como otros instrumentos del DS).
    private static let puntoDiametro: CGFloat = 10
    private static let gotaSize: CGFloat = 18
    private static let gotaIconSize: CGFloat = 10
    private static let rielGrosor: CGFloat = 1
    private static let cercoBorde: CGFloat = 1.5
    private static let sinDatoBorde: CGFloat = 1.4
    private static let pastillaBorde: CGFloat = 1.5
    private static let sinDatoDash: [CGFloat] = [2, 2]
    private static let pastillaDash: [CGFloat] = [3, 3]
    private static let flechaPt: CGFloat = 13
    /// Paso vertical entre centros de carril (paridad del mockup HTML: 26 pt).
    private static let carrilPaso: CGFloat = 26
    /// Aire del cerco alrededor de los puntos que encierra.
    private static let cercoPadH: CGFloat = 10
    private static let cercoPadV: CGFloat = 8
    /// Alto de la fila de rótulos bajo las últimas columnas.
    private static let etiquetaAlto: CGFloat = 14

    /// - Parameters:
    ///   - carriles: normalmente 2 (temperatura y respiración).
    ///   - cercoUltimas: cuántas noches finales encierra el cerco; `nil` = sin cerco.
    ///   - etiquetas: rótulos de las últimas noches, YA localizados («anteanoche», «anoche»).
    ///     Se alinean a las ÚLTIMAS columnas; las demás quedan sin rótulo.
    ///   - consecuencia: el texto de la pastilla, YA localizado («día más leve»).
    ///   - encendida: `true` cuando la regla se cumplió y la consecuencia es real.
    ///   - a11yLabel: el label del diagrama completo, YA compuesto por el caller.
    public init(carriles: [Carril],
                cercoUltimas: Int? = nil,
                etiquetas: [String] = [],
                consecuencia: String,
                encendida: Bool = false,
                a11yLabel: String) {
        self.carriles = carriles
        self.cercoUltimas = cercoUltimas
        self.etiquetas = etiquetas
        self.consecuencia = consecuencia
        self.encendida = encendida
        self.a11yLabel = a11yLabel
    }

    private var animacion: Animation? {
        (reduceMotion || motionDisabled) ? nil : LiquidMotion.lift
    }

    private var nochesCount: Int {
        carriles.first?.noches.count ?? 0
    }

    private var diagramaAlto: CGFloat {
        let lanes = max(carriles.count, 1)
        let cuerpo = Self.gotaSize + CGFloat(lanes - 1) * Self.carrilPaso
        let labels = etiquetas.isEmpty ? 0 : (LiquidSpace.s100 + Self.etiquetaAlto)
        return cuerpo + labels
    }

    public var body: some View {
        VStack(spacing: LiquidSpace.s100) {
            diagrama
            flecha
            pastilla
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .animation(animacion, value: encendida)
        .animation(animacion, value: cercoUltimas)
    }

    // MARK: - Diagrama

    private var diagrama: some View {
        GeometryReader { geo in
            let count = nochesCount
            let plotX0 = Self.gotaSize + LiquidSpace.s200
            let plotW = max(0, geo.size.width - plotX0)
            let xs = Self.columnasX(count: count, width: plotW)
            let laneYs = Self.carrilesY(count: carriles.count)

            ZStack(alignment: .topLeading) {
                // Cerco: encierra las últimas columnas abarcando todos los carriles.
                if let n = cercoUltimas, n > 0, count > 0, !laneYs.isEmpty {
                    cerco(n: n, count: count, xs: xs, plotX0: plotX0, laneYs: laneYs)
                        .transition(.opacity)
                }

                // Carriles: gota + riel + puntos.
                ForEach(Array(carriles.enumerated()), id: \.element.id) { i, carril in
                    let cy = laneYs[i]
                    LiquidIconDrop(carril.icono, tone: carril.tono,
                                   size: Self.gotaSize, iconSize: Self.gotaIconSize)
                        .position(x: Self.gotaSize / 2, y: cy)

                    if count >= 2 {
                        Path { p in
                            p.move(to: CGPoint(x: plotX0 + xs[0], y: cy))
                            p.addLine(to: CGPoint(x: plotX0 + xs[count - 1], y: cy))
                        }
                        .stroke(LiquidColor.tinta10, lineWidth: Self.rielGrosor)
                    }

                    ForEach(0..<min(count, carril.noches.count), id: \.self) { j in
                        punto(carril.noches[j])
                            .position(x: plotX0 + xs[j], y: cy)
                    }
                }

                // Rótulos bajo las últimas columnas.
                if !etiquetas.isEmpty, count > 0, let lastY = laneYs.last {
                    let baseY = lastY + Self.gotaSize / 2 + LiquidSpace.s100 + Self.etiquetaAlto / 2
                    // #inject r5 · Los rótulos de las últimas noches («night before last» ·
                    // «last night») van como GRUPO alineado a la derecha del plot, no
                    // centrados bajo cada columna: dos frases largas bajo columnas contiguas
                    // se solapaban (o la del borde se cortaba). El grupo derecho ya asocia
                    // con las últimas noches sin pisarse (revisión adversarial DeepSeek+Grok).
                    HStack(spacing: LiquidSpace.s300) {
                        Spacer(minLength: 0)
                        ForEach(etiquetas.indices, id: \.self) { i in
                            Text(verbatim: etiquetas[i])
                                .font(LiquidType.caption)
                                .foregroundStyle(LiquidColor.tinta500)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: geo.size.width, alignment: .trailing)
                    .position(x: geo.size.width / 2, y: baseY)
                }
            }
        }
        .frame(height: diagramaAlto)
        .frame(maxWidth: .infinity)
    }

    private func cerco(n: Int, count: Int, xs: [CGFloat],
                       plotX0: CGFloat, laneYs: [CGFloat]) -> some View {
        let start = max(0, count - n)
        let left = plotX0 + xs[start] - Self.puntoDiametro / 2 - Self.cercoPadH
        let right = plotX0 + xs[count - 1] + Self.puntoDiametro / 2 + Self.cercoPadH
        let top = laneYs[0] - Self.puntoDiametro / 2 - Self.cercoPadV
        let bottom = laneYs[laneYs.count - 1] + Self.puntoDiametro / 2 + Self.cercoPadV
        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        return RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
            .fill(LiquidColor.atencion.opacity(LiquidChart.filaActivaAlfa))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                    .strokeBorder(LiquidColor.atencion, lineWidth: Self.cercoBorde)
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func punto(_ p: Punto) -> some View {
        switch p {
        case .dentro:
            Circle()
                .fill(LiquidColor.tinta10)
                .frame(width: Self.puntoDiametro, height: Self.puntoDiametro)
        case .fuera:
            Circle()
                .fill(LiquidColor.atencion)
                .frame(width: Self.puntoDiametro, height: Self.puntoDiametro)
        case .sinDato:
            Circle()
                .strokeBorder(
                    LiquidColor.tinta500,
                    style: StrokeStyle(lineWidth: Self.sinDatoBorde, dash: Self.sinDatoDash))
                .frame(width: Self.puntoDiametro, height: Self.puntoDiametro)
        }
    }

    // MARK: - Flecha y pastilla

    private var flecha: some View {
        Image(systemName: "arrow.down")
            .font(LiquidType.iconSF(size: Self.flechaPt))
            .foregroundStyle(encendida ? LiquidColor.atencion : LiquidColor.tinta500)
            .accessibilityHidden(true)
    }

    private var pastilla: some View {
        Text(verbatim: consecuencia)
            .font(LiquidType.label)
            .tracking(LiquidType.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(encendida ? LiquidColor.atencionTexto : LiquidColor.tinta500)
            .padding(.horizontal, LiquidSpace.s400)
            .padding(.vertical, LiquidSpace.s200)
            .background {
                Capsule()
                    .fill(encendida
                          ? LiquidColor.atencion.opacity(LiquidChart.filaActivaAlfa)
                          : Color.clear)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        encendida ? LiquidColor.atencion : LiquidColor.tinta10,
                        style: StrokeStyle(
                            lineWidth: Self.pastillaBorde,
                            dash: encendida ? [] : Self.pastillaDash))
            }
    }

    // MARK: - Geometría

    /// Centros X de las columnas de noches dentro del ancho del plot (0…width).
    private static func columnasX(count: Int, width: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        if count == 1 { return [width / 2] }
        let r = puntoDiametro / 2
        let usable = max(0, width - puntoDiametro)
        return (0..<count).map { i in
            r + usable * CGFloat(i) / CGFloat(count - 1)
        }
    }

    /// Centros Y de cada carril, anclados al centro de la gota-icono.
    private static func carrilesY(count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let y0 = gotaSize / 2
        return (0..<count).map { y0 + CGFloat($0) * carrilPaso }
    }
}

#if DEBUG
private enum LiquidDominoReglaPreviewData {
    static let dentro: [LiquidDominoRegla.Punto] = [.dentro, .dentro, .dentro, .dentro, .dentro]
    static let unaFuera: [LiquidDominoRegla.Punto] = [.dentro, .dentro, .dentro, .dentro, .fuera]
    static let juntasTemp: [LiquidDominoRegla.Punto] = [.dentro, .dentro, .dentro, .fuera, .fuera]
    static let juntasResp: [LiquidDominoRegla.Punto] = [.dentro, .dentro, .dentro, .fuera, .fuera]
    static let sinDato: [LiquidDominoRegla.Punto] = [.dentro, .dentro, .dentro, .dentro, .sinDato]

    static func carriles(temp: [LiquidDominoRegla.Punto],
                         resp: [LiquidDominoRegla.Punto]) -> [LiquidDominoRegla.Carril] {
        [
            .init(id: "temp", icono: .termo, tono: LiquidColor.ambar,
                  noches: temp, a11y: "Temperatura de piel"),
            .init(id: "resp", icono: .resp, tono: LiquidColor.azul,
                  noches: resp, a11y: "Respiracion"),
        ]
    }
}

#Preview("Liquid · DominoRegla") {
    ScrollView {
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {
            // 1 · Todo dentro, pastilla apagada.
            previewBloque(titulo: "Dentro de tu patron") {
                LiquidDominoRegla(
                    carriles: LiquidDominoReglaPreviewData.carriles(
                        temp: LiquidDominoReglaPreviewData.dentro,
                        resp: LiquidDominoReglaPreviewData.dentro),
                    etiquetas: ["anteanoche", "anoche"],
                    consecuencia: "dentro de tu patron",
                    encendida: false,
                    a11yLabel: "La regla: ambas senales dentro de tu patron")
            }

            // 2 · Una sola noche fuera en temperatura: hay ambar y aun asi no pasa nada.
            previewBloque(titulo: "Una fuera (no empuja)") {
                LiquidDominoRegla(
                    carriles: LiquidDominoReglaPreviewData.carriles(
                        temp: LiquidDominoReglaPreviewData.unaFuera,
                        resp: LiquidDominoReglaPreviewData.dentro),
                    etiquetas: ["anteanoche", "anoche"],
                    consecuencia: "dia mas leve",
                    encendida: false,
                    a11yLabel: "La regla: una senal fuera no empuja el dia")
            }

            // 3 · Pareja confirmada: cerco en las dos ultimas, pastilla encendida.
            previewBloque(titulo: "Juntas, dos noches") {
                LiquidDominoRegla(
                    carriles: LiquidDominoReglaPreviewData.carriles(
                        temp: LiquidDominoReglaPreviewData.juntasTemp,
                        resp: LiquidDominoReglaPreviewData.juntasResp),
                    cercoUltimas: 2,
                    etiquetas: ["anteanoche", "anoche"],
                    consecuencia: "dia mas leve",
                    encendida: true,
                    a11yLabel: "La regla: pareja fuera dos noches, dia mas leve")
            }

            // 4 · Ultima noche sin dato en ambos carriles.
            previewBloque(titulo: "Sin lectura anoche") {
                LiquidDominoRegla(
                    carriles: LiquidDominoReglaPreviewData.carriles(
                        temp: LiquidDominoReglaPreviewData.sinDato,
                        resp: LiquidDominoReglaPreviewData.sinDato),
                    etiquetas: ["anteanoche", "anoche"],
                    consecuencia: "dia mas leve",
                    encendida: false,
                    a11yLabel: "La regla: sin lectura anoche")
            }
        }
        .padding(LiquidSpace.s550)
    }
    .background(LiquidSheetFondo(tone: LiquidColor.ambar))
}

#Preview("Liquid · DominoRegla (reduce motion)") {
    // `accessibilityReduceMotion` es de solo lectura en el environment; el flag del
    // sistema Liquid que congela motion en previews/renders es `liquidMotionDisabled`
    // (mismo patron que LiquidCalibracionCard / LiquidChartCore).
    LiquidDominoRegla(
        carriles: LiquidDominoReglaPreviewData.carriles(
            temp: LiquidDominoReglaPreviewData.juntasTemp,
            resp: LiquidDominoReglaPreviewData.juntasResp),
        cercoUltimas: 2,
        etiquetas: ["anteanoche", "anoche"],
        consecuencia: "dia mas leve",
        encendida: true,
        a11yLabel: "La regla: pareja fuera dos noches, dia mas leve")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.ambar))
    .environment(\.liquidMotionDisabled, true)
}

@ViewBuilder
private func previewBloque<Content: View>(titulo: String,
                                          @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: LiquidSpace.s200) {
        Text(verbatim: titulo)
            .font(LiquidType.microEstado)
            .textCase(.uppercase)
            .foregroundStyle(LiquidColor.tinta500)
        content()
            .padding(LiquidSpace.s400)
            .frame(maxWidth: .infinity)
            .liquidGlass(.superficie) // token-exempt: preview, fuera de una hoja
    }
}
#endif
