import SwiftUI

// MARK: - FER-51 · Cara B «Cosmos abierta» (Lane C)
//
// Modelo tonto + vista: señales ancladas con número y medidor lunar sobre arcos de anclaje.
// CERO derivación de datos aquí — el builder (`LiquidHoyBuilder.cosmosAbierto`) proyecta
// Preparedness/HoyGramatica a este modelo. La postura reunida y el gesto son F2.

// MARK: Model

/// Estado renderizable de la cara Cosmos abierta (§6 del REQ).
public struct CosmosAbiertoModel: Sendable {

    /// Severidad visual de la gramática §8 — se AÑADE (subrayado/aro); jamás reemplaza el hue.
    public enum Alerta: Sendable, Equatable {
        case ninguna, atencion, alarma
    }

    /// El héroe: orbe teñido por el veredicto + palabra debajo.
    public struct Heroe: Sendable {
        public let palabra: String
        /// Color de las partículas del orbe (familia `LiquidColor.particula*`).
        public let tonoOrbe: Color
        /// Color de la palabra del veredicto.
        public let tonoPalabra: Color
        public let confianza: String?
        public let a11y: String

        public init(palabra: String, tonoOrbe: Color, tonoPalabra: Color,
                    confianza: String? = nil, a11y: String) {
            self.palabra = palabra
            self.tonoOrbe = tonoOrbe
            self.tonoPalabra = tonoPalabra
            self.confianza = confianza
            self.a11y = a11y
        }
    }

    /// Fragmento de valor teñido (el par del guardián lleva dos: temp dorada + resp azul).
    public struct ValorParte: Sendable {
        public let texto: String
        public let hue: Color
        public init(texto: String, hue: Color) {
            self.texto = texto
            self.hue = hue
        }
    }

    /// Una lunita del medidor (p + hue + alerta de aro).
    public struct Lunita: Sendable {
        public let p: Double
        public let hue: Color
        public let alerta: Alerta
        public init(p: Double, hue: Color, alerta: Alerta = .ninguna) {
            self.p = p
            self.hue = hue
            self.alerta = alerta
        }
    }

    /// Configuración del `MedidorLunar` para esta ancla (`nil` = sin medidor: estrés/esfuerzo/pasos).
    public struct Medidor: Sendable {
        public let radioAnillo: CGFloat
        public let sabor: MedidorLunar.Sabor
        public let lunitas: [Lunita]
        public let punteado: Bool
        public let fantasma: Bool

        public init(radioAnillo: CGFloat, sabor: MedidorLunar.Sabor, lunitas: [Lunita],
                    punteado: Bool = false, fantasma: Bool = false) {
            self.radioAnillo = radioAnillo
            self.sabor = sabor
            self.lunitas = lunitas
            self.punteado = punteado
            self.fantasma = fantasma
        }
    }

    /// Una ancla: luna (+ medidor) + bloque de texto debajo.
    public struct Ancla: Sendable, Identifiable {
        public let id: String
        /// 1 = arco1 (vota), 2 = arco2 (contexto), 3 = horizonte (bitácora).
        public let grupo: Int
        public let lunaRadio: CGFloat
        /// Luna principal (sueño/FC/carga/…). El par del guardián usa `hueLuna` + `hueLuna2`.
        public let hueLuna: Color
        public let hueLuna2: Color?
        public let medidor: Medidor?
        public let valorPartes: [ValorParte]
        /// Tamaño tipográfico del numeral (pt del prototipo; escala con Dynamic Type vía relativeTo).
        public let valorSize: CGFloat
        public let sublabel: String?
        public let rotulo: String
        /// Subrayado de alerta bajo el numeral (el numeral CONSERVA su hue).
        public let alerta: Alerta
        public let a11y: String

        public init(id: String, grupo: Int, lunaRadio: CGFloat, hueLuna: Color,
                    hueLuna2: Color? = nil, medidor: Medidor? = nil,
                    valorPartes: [ValorParte], valorSize: CGFloat,
                    sublabel: String? = nil, rotulo: String, alerta: Alerta = .ninguna,
                    a11y: String) {
            self.id = id
            self.grupo = grupo
            self.lunaRadio = lunaRadio
            self.hueLuna = hueLuna
            self.hueLuna2 = hueLuna2
            self.medidor = medidor
            self.valorPartes = valorPartes
            self.valorSize = valorSize
            self.sublabel = sublabel
            self.rotulo = rotulo
            self.alerta = alerta
            self.a11y = a11y
        }

        /// ¿Esta ancla declara un medidor lunar? (tests de criterios 4/9).
        public var tieneMedidor: Bool { medidor != nil }
    }

    public let heroe: Heroe
    /// Orden canónico G1 → G2 → G3 (a11y y render).
    public let anclas: [Ancla]
    /// Tono del destello que recorre los arcos (clima del día).
    public let destelloTono: Color

    public init(heroe: Heroe, anclas: [Ancla], destelloTono: Color) {
        self.heroe = heroe
        self.anclas = anclas
        self.destelloTono = destelloTono
    }

    // MARK: Fixtures de preview / snapshot

    /// Día bueno: todo en rango, sin alertas.
    public static let previewDiaBueno = CosmosAbiertoModel(
        heroe: .init(palabra: "En rango", tonoOrbe: LiquidColor.particulaVerde,
                     tonoPalabra: LiquidColor.verdePrimario, a11y: "Veredicto: en rango"),
        anclas: [
            .init(id: "sleep", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.indigo,
                  medidor: .init(radioAnillo: 22, sabor: .progreso,
                                 lunitas: [.init(p: 48, hue: LiquidColor.indigo)]),
                  valorPartes: [.init(texto: "7:42", hue: LiquidColor.indigo)], valorSize: 26,
                  rotulo: "SUEÑO", a11y: "Sueño 7 horas 42 minutos"),
            .init(id: "guardian", grupo: 1, lunaRadio: 7, hueLuna: LiquidColor.doradoTemp,
                  hueLuna2: LiquidColor.azul,
                  medidor: .init(radioAnillo: 17, sabor: .desviacion,
                                 lunitas: [.init(p: 52, hue: LiquidColor.doradoTemp),
                                           .init(p: 48, hue: LiquidColor.azul)]),
                  valorPartes: [.init(texto: "+0.2°", hue: LiquidColor.doradoTemp),
                                .init(texto: " · ", hue: LiquidColor.tinta500),
                                .init(texto: "14.2", hue: LiquidColor.azul)],
                  valorSize: 16, rotulo: "GUARDIÁN", a11y: "Guardián más 0.2 grados, 14.2 respiración"),
            .init(id: "rhr", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.rosa,
                  medidor: .init(radioAnillo: 22, sabor: .desviacion,
                                 lunitas: [.init(p: 50, hue: LiquidColor.rosa)]),
                  valorPartes: [.init(texto: "52", hue: LiquidColor.rosa),
                                .init(texto: " lpm", hue: LiquidColor.tinta500)],
                  valorSize: 22, rotulo: "FC REPOSO", a11y: "FC reposo 52 latidos por minuto"),
            .init(id: "carga", grupo: 2, lunaRadio: 14, hueLuna: LiquidColor.verdePrimario,
                  medidor: .init(radioAnillo: 21, sabor: .zona,
                                 lunitas: [.init(p: 56, hue: LiquidColor.verdePrimario)]),
                  valorPartes: [.init(texto: "1.12", hue: LiquidColor.verdePrimario)], valorSize: 22,
                  sublabel: "estable", rotulo: "CARGA", a11y: "Carga 1.12, estable"),
            .init(id: "stress", grupo: 2, lunaRadio: 9, hueLuna: LiquidColor.tinta500,
                  valorPartes: [.init(texto: "bajo", hue: LiquidColor.tinta700)], valorSize: 15,
                  sublabel: "vs tus 7 días", rotulo: "ESTRÉS", a11y: "Estrés bajo contra tus 7 días"),
            .init(id: "hrv", grupo: 2, lunaRadio: 12, hueLuna: LiquidColor.cian,
                  medidor: .init(radioAnillo: 17, sabor: .desviacion,
                                 lunitas: [.init(p: 55, hue: LiquidColor.cian)], punteado: true),
                  valorPartes: [.init(texto: "68", hue: LiquidColor.cian),
                                .init(texto: " ms", hue: LiquidColor.tinta500)],
                  valorSize: 20, sublabel: "referencia", rotulo: "VFC", a11y: "VFC 68 milisegundos, referencia"),
            .init(id: "strain", grupo: 3, lunaRadio: 3.8, hueLuna: LiquidColor.teal,
                  valorPartes: [.init(texto: "11.2", hue: LiquidColor.tinta900)], valorSize: 18,
                  rotulo: "ESFUERZO", a11y: "Esfuerzo 11.2"),
            .init(id: "steps", grupo: 3, lunaRadio: 3.8, hueLuna: LiquidColor.tinta500,
                  valorPartes: [.init(texto: "8 432", hue: LiquidColor.tinta900)], valorSize: 18,
                  rotulo: "PASOS", a11y: "Pasos 8432"),
        ],
        destelloTono: LiquidColor.verdePrimario)

    /// Día malo: sueño por eficiencia + carga en pico + par en alarma.
    public static let previewDiaMalo = CosmosAbiertoModel(
        heroe: .init(palabra: "Recupera", tonoOrbe: LiquidColor.particulaRoja,
                     tonoPalabra: LiquidColor.negativo, a11y: "Veredicto: recupera"),
        anclas: [
            .init(id: "sleep", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.indigo,
                  medidor: .init(radioAnillo: 22, sabor: .progreso,
                                 lunitas: [.init(p: 80, hue: LiquidColor.indigo, alerta: .atencion)]),
                  valorPartes: [.init(texto: "8:00", hue: LiquidColor.indigo)], valorSize: 26,
                  sublabel: "eficiencia 72 %", rotulo: "SUEÑO", alerta: .atencion,
                  a11y: "Sueño 8 horas, eficiencia 72 por ciento, atención"),
            .init(id: "guardian", grupo: 1, lunaRadio: 7, hueLuna: LiquidColor.doradoTemp,
                  hueLuna2: LiquidColor.azul,
                  medidor: .init(radioAnillo: 17, sabor: .desviacion,
                                 lunitas: [.init(p: 93, hue: LiquidColor.doradoTemp, alerta: .alarma),
                                           .init(p: 84, hue: LiquidColor.azul, alerta: .alarma)]),
                  valorPartes: [.init(texto: "+0.9°", hue: LiquidColor.doradoTemp),
                                .init(texto: " · ", hue: LiquidColor.tinta500),
                                .init(texto: "17.0", hue: LiquidColor.azul)],
                  valorSize: 16, rotulo: "GUARDIÁN", alerta: .alarma,
                  a11y: "Guardián alarma, más 0.9 grados, 17 respiración"),
            .init(id: "rhr", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.rosa,
                  medidor: .init(radioAnillo: 22, sabor: .desviacion,
                                 lunitas: [.init(p: 88, hue: LiquidColor.rosa, alerta: .atencion)]),
                  valorPartes: [.init(texto: "62", hue: LiquidColor.rosa),
                                .init(texto: " lpm", hue: LiquidColor.tinta500)],
                  valorSize: 22, rotulo: "FC REPOSO", alerta: .atencion,
                  a11y: "FC reposo 62, atención"),
            .init(id: "carga", grupo: 2, lunaRadio: 14, hueLuna: LiquidColor.verdePrimario,
                  medidor: .init(radioAnillo: 21, sabor: .zona,
                                 lunitas: [.init(p: 77.5, hue: LiquidColor.verdePrimario, alerta: .atencion)]),
                  valorPartes: [.init(texto: "1.55", hue: LiquidColor.verdePrimario)], valorSize: 22,
                  sublabel: "pico", rotulo: "CARGA", alerta: .atencion,
                  a11y: "Carga 1.55, pico, atención"),
            .init(id: "stress", grupo: 2, lunaRadio: 9, hueLuna: LiquidColor.tinta500,
                  valorPartes: [.init(texto: "alto", hue: LiquidColor.tinta700)], valorSize: 15,
                  sublabel: "vs tus 7 días", rotulo: "ESTRÉS", a11y: "Estrés alto"),
            .init(id: "hrv", grupo: 2, lunaRadio: 12, hueLuna: LiquidColor.cian,
                  medidor: .init(radioAnillo: 17, sabor: .desviacion,
                                 lunitas: [.init(p: 90, hue: LiquidColor.cian)], punteado: true),
                  valorPartes: [.init(texto: "32", hue: LiquidColor.cian),
                                .init(texto: " ms", hue: LiquidColor.tinta500)],
                  valorSize: 20, sublabel: "referencia", rotulo: "VFC",
                  a11y: "VFC 32 milisegundos, referencia"),
            .init(id: "strain", grupo: 3, lunaRadio: 3.8, hueLuna: LiquidColor.teal,
                  valorPartes: [.init(texto: "14.0", hue: LiquidColor.tinta900)], valorSize: 18,
                  rotulo: "ESFUERZO", a11y: "Esfuerzo 14"),
            .init(id: "steps", grupo: 3, lunaRadio: 3.8, hueLuna: LiquidColor.tinta500,
                  valorPartes: [.init(texto: "3 200", hue: LiquidColor.tinta900)], valorSize: 18,
                  rotulo: "PASOS", a11y: "Pasos 3200"),
        ],
        destelloTono: LiquidColor.negativo)

    /// Calibrando: medidores fantasma, valores ausentes, sin alertas.
    public static let previewCalibrando = CosmosAbiertoModel(
        heroe: .init(palabra: "Conociéndote", tonoOrbe: LiquidColor.particulaNeutra,
                     tonoPalabra: LiquidColor.tinta500, a11y: "Conociéndote"),
        anclas: [
            .init(id: "sleep", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.indigo,
                  medidor: .init(radioAnillo: 22, sabor: .progreso, lunitas: [], fantasma: true),
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 26,
                  sublabel: "conociéndote", rotulo: "SUEÑO", a11y: "Sueño, conociéndote"),
            .init(id: "guardian", grupo: 1, lunaRadio: 7, hueLuna: LiquidColor.doradoTemp,
                  hueLuna2: LiquidColor.azul,
                  medidor: .init(radioAnillo: 17, sabor: .desviacion, lunitas: [], fantasma: true),
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 16,
                  sublabel: "conociéndote", rotulo: "GUARDIÁN", a11y: "Guardián, conociéndote"),
            .init(id: "rhr", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.rosa,
                  medidor: .init(radioAnillo: 22, sabor: .desviacion, lunitas: [], fantasma: true),
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 22,
                  sublabel: "conociéndote", rotulo: "FC REPOSO", a11y: "FC reposo, conociéndote"),
            .init(id: "carga", grupo: 2, lunaRadio: 14, hueLuna: LiquidColor.verdePrimario,
                  medidor: .init(radioAnillo: 21, sabor: .zona, lunitas: [], fantasma: true),
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 22,
                  sublabel: "calibrando", rotulo: "CARGA", a11y: "Carga, calibrando"),
            .init(id: "stress", grupo: 2, lunaRadio: 9, hueLuna: LiquidColor.tinta500,
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 15,
                  sublabel: "vs tus 7 días", rotulo: "ESTRÉS", a11y: "Estrés sin dato"),
            .init(id: "hrv", grupo: 2, lunaRadio: 12, hueLuna: LiquidColor.cian,
                  medidor: .init(radioAnillo: 17, sabor: .desviacion, lunitas: [],
                                 punteado: true, fantasma: true),
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 20,
                  sublabel: "conociéndote", rotulo: "VFC", a11y: "VFC, conociéndote"),
            .init(id: "strain", grupo: 3, lunaRadio: 3.8, hueLuna: LiquidColor.teal,
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 18,
                  rotulo: "ESFUERZO", a11y: "Esfuerzo sin dato"),
            .init(id: "steps", grupo: 3, lunaRadio: 3.8, hueLuna: LiquidColor.tinta500,
                  valorPartes: [.init(texto: "—", hue: LiquidColor.tinta500)], valorSize: 18,
                  rotulo: "PASOS", a11y: "Pasos sin dato"),
        ],
        destelloTono: LiquidColor.tinta500)
}

// MARK: - Face

/// Vista de la cara Cosmos abierta. Hitboxes ≥ 44 pt por ancla; a11y = veredicto → G1 → G2 → G3.
public struct CosmosAbiertoFace: View {
    private let model: CosmosAbiertoModel
    private let onTapAncla: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lienzo de referencia (revisión del dueño en vivo): la cara ya NO trae héroe propio —
    /// el héroe de la pantalla es el ecosistema de partículas que vive arriba. Solo anclas.
    private static let refW: CGFloat = 390
    private static let refH: CGFloat = 445

    /// Posiciones de ancla (x, y) pt sobre 390×560.
    private static let pos: [String: CGPoint] = [
        "sleep":    CGPoint(x: 99,  y: 74),
        "guardian": CGPoint(x: 195, y: 81),
        "rhr":      CGPoint(x: 291, y: 74),
        "carga":    CGPoint(x: 84,  y: 211),
        "stress":   CGPoint(x: 195, y: 221),
        "hrv":      CGPoint(x: 306, y: 211),
        "strain":   CGPoint(x: 110, y: 333),
        "steps":    CGPoint(x: 280, y: 333),
    ]

    public init(model: CosmosAbiertoModel, onTapAncla: @escaping (String) -> Void = { _ in }) {
        self.model = model
        self.onTapAncla = onTapAncla
    }

    public var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / Self.refW
            let sy = geo.size.height / Self.refH
            let s = min(sx, sy)
            let stack = shouldStack(width: geo.size.width)

            ZStack(alignment: .top) {
                // Sin fondo propio ni héroe propio: la cara es transparente sobre el suelo
                // vivo de Hoy y el héroe es el ecosistema que ya vive arriba.

                // Arcos de anclaje (detrás de las anclas).
                arcos(sx: sx, sy: sy)
                    .allowsHitTesting(false)

                if stack {
                    anclasApiladas(sx: sx, s: s)
                } else {
                    ForEach(Array(model.anclas.enumerated()), id: \.element.id) { idx, ancla in
                        anclaView(ancla, s: s)
                            .position(posicion(ancla.id, sx: sx, sy: sy))
                            .accessibilitySortPriority(Double(90 - idx))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Arcos

    private func arcos(sx: CGFloat, sy: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                dibujarArco(ctx,
                            a: CGPoint(x: 24 * sx, y: 58 * sy),
                            b: CGPoint(x: 195 * sx, y: 96 * sy),
                            c: CGPoint(x: 366 * sx, y: 58 * sy),
                            t: t, fase: 0)
                dibujarArco(ctx,
                            a: CGPoint(x: 10 * sx, y: 192 * sy),
                            b: CGPoint(x: 195 * sx, y: 234 * sy),
                            c: CGPoint(x: 380 * sx, y: 192 * sy),
                            t: t, fase: 3)
                dibujarArco(ctx,
                            a: CGPoint(x: 24 * sx, y: 338 * sy),
                            b: CGPoint(x: 195 * sx, y: 315 * sy),
                            c: CGPoint(x: 366 * sx, y: 338 * sy),
                            t: t, fase: 6)
            }
        }
    }

    private func dibujarArco(_ ctx: GraphicsContext, a: CGPoint, b: CGPoint, c: CGPoint,
                             t: TimeInterval, fase: Double) {
        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: c, control: b)
        ctx.stroke(path, with: .color(LiquidColor.tinta900.opacity(0.10)),
                   style: StrokeStyle(lineWidth: 1, lineCap: .round))

        // Destello que recorre el arco cada ~9 s.
        let ciclo = (t + fase).truncatingRemainder(dividingBy: 9) / 9
        let p = puntoEnCuadratica(a: a, b: b, c: c, u: ciclo)
        let destello = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
        ctx.fill(destello, with: .color(model.destelloTono.opacity(0.55)))
    }

    private func puntoEnCuadratica(a: CGPoint, b: CGPoint, c: CGPoint, u: Double) -> CGPoint {
        let t = CGFloat(u)
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * a.x + 2 * mt * t * b.x + t * t * c.x,
            y: mt * mt * a.y + 2 * mt * t * b.y + t * t * c.y)
    }

    // MARK: Anclas

    private func posicion(_ id: String, sx: CGFloat, sy: CGFloat) -> CGPoint {
        let p = Self.pos[id] ?? CGPoint(x: 195, y: 400)
        // El bloque de texto cuelga debajo de la luna; el centro del hitbox es la luna.
        return CGPoint(x: p.x * sx, y: p.y * sy)
    }

    private func anclaView(_ ancla: CosmosAbiertoModel.Ancla, s: CGFloat) -> some View {
        let hit: CGFloat = max(44, ancla.lunaRadio * 2 * s + 20)
        return Button {
            onTapAncla(ancla.id)
        } label: {
            VStack(spacing: 4 * s) {
                ZStack {
                    if let med = ancla.medidor {
                        MedidorLunar(
                            radioAnillo: med.radioAnillo * s,
                            sabor: med.sabor,
                            lunitas: med.lunitas.map {
                                .init(p: $0.p, hue: $0.hue, alerta: mapAlerta($0.alerta))
                            },
                            punteado: med.punteado,
                            fantasma: med.fantasma)
                    }
                    lunaCentro(ancla, s: s)
                }
                valorBlock(ancla, s: s)
                if let sub = ancla.sublabel {
                    Text(sub)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Text(ancla.rotulo)
                    .font(InstrumentoType.grotesk(11 * s, weight: .medium, relativeTo: .caption2))
                    .tracking(0.6)
                    .foregroundStyle(LiquidColor.tinta500)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Columna fija ≤ separación entre anclas (~96 pt): el texto envuelve DENTRO
            // de su ancla, nunca sobre la vecina.
            .frame(width: 94 * s)
            .frame(minHeight: hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ancla.a11y)
        .accessibilityAddTraits(.isButton)
    }

    private func lunaCentro(_ ancla: CosmosAbiertoModel.Ancla, s: CGFloat) -> some View {
        let r = ancla.lunaRadio * s
        return ZStack {
            if let h2 = ancla.hueLuna2 {
                // Binaria del guardián: dos lunitas pequeñas de partículas.
                LunaParticulas(radio: r * 0.7, hue: ancla.hueLuna, chartID: "luna-\(ancla.id)-a")
                    .offset(x: -r * 0.55)
                LunaParticulas(radio: r * 0.7, hue: h2, chartID: "luna-\(ancla.id)-b")
                    .offset(x: r * 0.55)
            } else {
                LunaParticulas(radio: r, hue: ancla.hueLuna, chartID: "luna-\(ancla.id)")
            }
        }
        .accessibilityHidden(true)
    }

    private func valorBlock(_ ancla: CosmosAbiertoModel.Ancla, s: CGFloat) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(ancla.valorPartes.enumerated()), id: \.offset) { _, parte in
                    Text(parte.texto)
                        .font(InstrumentoType.groteskNumber(ancla.valorSize * s,
                                                            relativeTo: .title3))
                        .foregroundStyle(parte.hue)
                }
            }
            // Subrayado de alerta: 18×2 pt; el numeral conserva su hue.
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(colorAlerta(ancla.alerta))
                .frame(width: 18 * s, height: 2 * s)
                .opacity(ancla.alerta == .ninguna ? 0 : 1)
                .accessibilityHidden(true)
        }
    }

    private func anclasApiladas(sx: CGFloat, s: CGFloat) -> some View {
        // Breakpoint §1: apilar por grupo en filas verticales.
        let g1 = model.anclas.filter { $0.grupo == 1 }
        let g2 = model.anclas.filter { $0.grupo == 2 }
        let g3 = model.anclas.filter { $0.grupo == 3 }
        return VStack(spacing: 28 * s) {
            Spacer().frame(height: 24 * s)
            grupoFila(g1, s: s)
            grupoFila(g2, s: s)
            grupoFila(g3, s: s)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func grupoFila(_ anclas: [CosmosAbiertoModel.Ancla], s: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12 * s) {
            ForEach(anclas) { ancla in
                anclaView(ancla, s: s)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    private func shouldStack(width: CGFloat) -> Bool {
        // ~96 pt por bloque × 3 en un arco; bajo eso, o Dynamic Type AX, apilar.
        width < 300
    }

    private func mapAlerta(_ a: CosmosAbiertoModel.Alerta) -> MedidorLunar.Alerta {
        switch a {
        case .ninguna: return .ninguna
        case .atencion: return .atencion
        case .alarma: return .alarma
        }
    }

    private func colorAlerta(_ a: CosmosAbiertoModel.Alerta) -> Color {
        switch a {
        case .ninguna: return .clear
        case .atencion: return LiquidColor.atencion
        case .alarma: return LiquidColor.negativo
        }
    }
}

// MARK: - Luna de partículas (revisión del dueño: nada de bolas planas)

/// Luna de MATERIA de partículas — la MISMA receta del héroe (`EcosistemaSimulacion`:
/// esfera de Fibonacci proyectada con tamaño/alfa por profundidad). Todos los cuerpos
/// del Cosmos están hechos de lo mismo. `huePar` alterna por índice (binaria del guardián).
struct LunaParticulas: View {
    let radio: CGFloat
    let hue: Color
    let chartID: String
    var huePar: Color? = nil

    var body: some View {
        let lado = radio * 2.5
        Canvas { ctx, size in
            let centro = CGPoint(x: size.width / 2, y: size.height / 2)
            // Densidad ∝ área; el héroe usa ~0.5 pt²/partícula. Tope por rendimiento.
            let cuenta = min(260, max(44, Int(0.62 * radio * radio)))
            // Rotación estable por identidad (cada luna mira distinto, siempre igual).
            let rot = Double(MatrizDither.semilla(chartID: chartID, index: 0) % 628) / 100.0
            for i in 0..<cuenta {
                let dir = EcosistemaSimulacion.direccion(i, de: cuenta)
                let p = EcosistemaSimulacion.particula(
                    dir: dir, indice: i, centro: centro, radio: radio,
                    rotacion: rot, jitterAmp: 0, t: 0, alfaK: 1.55)
                let pr = p.tamano * (0.55 + radio / 60)
                let color = (huePar != nil && i % 2 == 1) ? huePar! : hue
                ctx.fill(Path(ellipseIn: CGRect(x: p.pos.x - pr, y: p.pos.y - pr,
                                                width: pr * 2, height: pr * 2)),
                         with: .color(color.opacity(min(1, p.alfa))))
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }
}

// MARK: - FER-51 Fase 2 · Cara Cosmos REUNIDA (el gesto de tocar el cielo)

/// La postura REUNIDA (§5 del REQ): todas las señales orbitan el héroe en tres anillos
/// (por grupo: vota / contexto / bitácora), sin números. Responde «¿todo bien?» de un
/// vistazo — color y órbitas. Lo que se sale de tu tendencia (`alerta != .ninguna`) se
/// SALE de su órbita con una estela y un halo. Toca el cielo para abrirla (lo maneja el host).
/// Canvas + TimelineView; estática bajo Reduce Motion.
public struct CosmosReunidoFace: View {
    private let model: CosmosAbiertoModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: CosmosAbiertoModel) { self.model = model }

    /// Anillo por grupo (radios del prototipo, sin escalar; se escalan con `s`).
    private static func anillo(_ grupo: Int) -> CGFloat {
        switch grupo { case 1: return 86; case 2: return 116; default: return 146 }
    }
    /// Velocidad angular por grupo (rad/s); anillos contrarrotantes como el mock.
    private static func omega(_ grupo: Int) -> Double {
        switch grupo { case 1: return 0.12; case 2: return -0.09; default: return 0.07 }
    }

    public var body: some View {
        GeometryReader { geo in
            let s: CGFloat = min(geo.size.width / 390, geo.size.height / 445)
            let cx: CGFloat = geo.size.width / 2
            let cy: CGFloat = geo.size.height / 2
            // Sin palabra propia: el héroe de la pantalla (arriba) ya dice el veredicto.
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { tl in
                let t: Double = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, _ in dibujaEscena(&ctx, t: t, cx: cx, cy: cy, s: s) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.heroe.a11y)
    }

    /// Todo el dibujo del reunido, aislado del inferidor de `some View` (evita el
    /// type-check timeout de un Canvas grande con loops + Dictionary inline).
    private func dibujaEscena(_ ctx: inout GraphicsContext, t: Double,
                              cx: CGFloat, cy: CGFloat, s: CGFloat) {
        // Anillos guía tenues.
        for g in 1...3 {
            let r: CGFloat = Self.anillo(g) * s
            let ry: CGFloat = r * 0.94
            let rect = CGRect(x: cx - r, y: cy - ry, width: r * 2, height: ry * 2)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(LiquidColor.tinta900.opacity(0.08)),
                       style: StrokeStyle(lineWidth: 1))
        }
        // Regla de tormenta (§5, criterio 14): con ≥ 3 alertas el héroe carga el drama
        // (su orbe ya está teñido del veredicto) y cada luna conserva SOLO su halo —
        // sin salir de órbita ni estela— para no volverse árbol de navidad.
        let tormenta: Bool = model.anclas.filter { $0.alerta != .ninguna }.count >= 3
        // Lunas: reparte cada grupo en su anillo por fase estable (índice).
        let porGrupo = Dictionary(grouping: model.anclas, by: { $0.grupo })
        for (g, anclas) in porGrupo {
            let base: CGFloat = Self.anillo(g) * s
            for (i, a) in anclas.enumerated() {
                dibujaLunaOrbital(&ctx, a: a, i: i, count: anclas.count, g: g,
                                  base: base, t: t, cx: cx, cy: cy, s: s, tormenta: tormenta)
            }
        }
        // El héroe al centro.
        dibujaLuna(ctx, CGPoint(x: cx, y: cy), 46 * s, model.heroe.tonoOrbe, nil, t: t)
    }

    private func dibujaLunaOrbital(_ ctx: inout GraphicsContext, a: CosmosAbiertoModel.Ancla,
                                   i: Int, count: Int, g: Int, base: CGFloat, t: Double,
                                   cx: CGFloat, cy: CGFloat, s: CGFloat, tormenta: Bool) {
        let fase: Double = Double(i) / Double(max(count, 1)) * 2 * .pi
        let ang: Double = fase + t * Self.omega(g)
        let alertada: Bool = a.alerta != .ninguna
        // En tormenta la luna NO se sale de órbita (fuera = 0 ⇒ sin estela); solo su halo.
        let fuera: CGFloat = (alertada && !tormenta) ? a.lunaRadio * s : 0
        let r: CGFloat = base + fuera
        let cosA: CGFloat = CGFloat(cos(ang))
        let sinA: CGFloat = CGFloat(sin(ang))
        let x: CGFloat = cx + cosA * r
        let y: CGFloat = cy + sinA * r * 0.94
        let p = CGPoint(x: x, y: y)
        if alertada, fuera > 2 {
            let bx: CGFloat = cx + cosA * base
            let by: CGFloat = cy + sinA * base * 0.94
            var estela = Path()
            estela.move(to: CGPoint(x: bx, y: by))
            estela.addLine(to: p)
            ctx.stroke(estela, with: .color(colorAlerta(a.alerta).opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1))
        }
        if alertada {
            let pulso: CGFloat = reduceMotion ? 0 : CGFloat(0.9 * sin(t * 1.1))
            let hr: CGFloat = a.lunaRadio * s + 4 + pulso
            aro(ctx, p, hr, colorAlerta(a.alerta))
            if a.alerta == .alarma { aro(ctx, p, hr + 3.5, colorAlerta(a.alerta)) }
        }
        dibujaLuna(ctx, p, a.lunaRadio * s, a.hueLuna, a.hueLuna2, t: t)
    }

    private func colorAlerta(_ a: CosmosAbiertoModel.Alerta) -> Color {
        a == .alarma ? LiquidColor.negativo : LiquidColor.atencion
    }
    private func aro(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: Color) {
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(color.opacity(0.55)), style: StrokeStyle(lineWidth: 1))
    }
    /// Cuerpo de MATERIA de partículas — la receta del héroe (`EcosistemaSimulacion`),
    /// con rotación lenta propia. `color2` alterna por índice (binaria del guardián).
    private func dibujaLuna(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat,
                            _ color: Color, _ color2: Color?, t: Double = 0) {
        let cuenta = min(300, max(40, Int(0.6 * r * r)))
        let rot = t * 0.10
        for i in 0..<cuenta {
            let dir = EcosistemaSimulacion.direccion(i, de: cuenta)
            let p = EcosistemaSimulacion.particula(
                dir: dir, indice: i, centro: c, radio: r,
                rotacion: rot, jitterAmp: 0, t: 0, alfaK: 1.55)
            let pr = p.tamano * (0.55 + r / 60)
            let hue = (color2 != nil && i % 2 == 1) ? color2! : color
            ctx.fill(Path(ellipseIn: CGRect(x: p.pos.x - pr, y: p.pos.y - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(hue.opacity(min(1, p.alfa))))
        }
    }
}

// MARK: - Orbe compacto (sin lunas; el orbe teñido del veredicto)

/// Orbe estático de partículas para la postura abierta (F1: sin Metal extra; Canvas puro).
struct CosmosOrbeCompacto: View {
    let radio: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            // Halo suave.
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(
                        Gradient(colors: [color.opacity(0.35), color.opacity(0.08), .clear]),
                        center: c, startRadius: 0, endRadius: r))
            // Núcleo.
            let rn = r * 0.72
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rn, y: c.y - rn, width: rn * 2, height: rn * 2)),
                     with: .radialGradient(
                        Gradient(colors: [color.opacity(0.85), color.opacity(0.45)]),
                        center: CGPoint(x: c.x - rn * 0.2, y: c.y - rn * 0.25),
                        startRadius: 0, endRadius: rn))
            // Especular.
            let rs = r * 0.28
            let foco = CGPoint(x: c.x - r * 0.28, y: c.y - r * 0.32)
            ctx.fill(Path(ellipseIn: CGRect(x: foco.x - rs, y: foco.y - rs, width: rs * 2, height: rs * 2)),
                     with: .color(LiquidColor.particulaBlanca.opacity(0.45)))
        }
        .frame(width: radio * 2, height: radio * 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Cosmos · día bueno") {
    CosmosAbiertoFace(model: .previewDiaBueno)
        .frame(width: 390, height: 820)
}

#Preview("Cosmos · día malo") {
    CosmosAbiertoFace(model: .previewDiaMalo)
        .frame(width: 390, height: 820)
}

#Preview("Cosmos · calibrando") {
    CosmosAbiertoFace(model: .previewCalibrando)
        .frame(width: 390, height: 820)
}

#Preview("Cosmos REUNIDO · día bueno") {
    CosmosReunidoFace(model: .previewDiaBueno)
        .frame(width: 390, height: 820)
        .background(LiquidColor.fondoGradient)
}

#Preview("Cosmos REUNIDO · día malo (fuera de órbita)") {
    CosmosReunidoFace(model: .previewDiaMalo)
        .frame(width: 390, height: 820)
        .background(LiquidColor.fondoGradient)
}
