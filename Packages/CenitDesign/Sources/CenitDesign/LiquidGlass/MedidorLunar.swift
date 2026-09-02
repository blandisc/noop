import SwiftUI

/// FER-51 · El medidor lunar (§6 del requerimiento): anillo alrededor de una luna anclada,
/// arco marcado = «tu rango bueno», lunita = hoy. Lectura única: dentro del arco = en lo
/// tuyo; fuera = fíjate; la ALERTA formal llega calculada (el DS no juzga datos).
/// El lado «peor» es SIEMPRE la derecha: ángulo(p) = −90° + (p − 50) · 1.8°.
public struct MedidorLunar: View {

    /// Sabor del medidor — decide qué tramo de p cubre el arco de rango.
    public enum Sabor: Sendable, Equatable {
        /// Sueño: arco p 50–75 (el borde derecho ES el umbral de alerta).
        case progreso
        /// FC/resp/temp/VFC: arco p 25–75 (borde derecho = umbral de la señal).
        case desviacion
        /// Carga: arco p 40–65 = zona dulce; el umbral de alerta vive aparte en p 75
        /// (excepción declarada del §6).
        case zona
    }

    /// Severidad de la gramática §8 — se AÑADE como aro; jamás reemplaza el hue.
    public enum Alerta: Sendable, Equatable { case ninguna, atencion, alarma }

    /// Un «hoy» sobre el anillo. El par del guardián lleva dos.
    public struct Lunita: Sendable, Equatable {
        public let p: Double
        public let hue: Color
        public let alerta: Alerta
        public init(p: Double, hue: Color, alerta: Alerta = .ninguna) {
            self.p = p
            self.hue = hue
            self.alerta = alerta
        }
    }

    private let radioAnillo: CGFloat
    private let sabor: Sabor
    private let lunitas: [Lunita]
    private let punteado: Bool
    private let fantasma: Bool

    /// - Parameters:
    ///   - radioAnillo: radio EXPLÍCITO del anillo (§6: 22/21/17 pt antes del factor proporcional).
    ///   - punteado: VFC («sin voto») — anillo y arco con patrón 2-3.
    ///   - fantasma: calibrando/«conociéndote» — anillo punteado, SIN arco ni lunitas.
    public init(radioAnillo: CGFloat, sabor: Sabor, lunitas: [Lunita],
                punteado: Bool = false, fantasma: Bool = false) {
        self.radioAnillo = radioAnillo
        self.sabor = sabor
        self.lunitas = lunitas
        self.punteado = punteado
        self.fantasma = fantasma
    }

    private var rangoArco: ClosedRange<Double> {
        switch sabor {
        // Progreso (sueño): el borde derecho (p 75) es el umbral de alerta; el izquierdo (p 25)
        // es «dormiste de sobra» — el REQ §6 clampa p a [25,100] y pide que dormir de más NUNCA
        // salga del arco por la izquierda, así que el arco llega hasta 25, no hasta 50.
        case .progreso: return 25...75
        case .desviacion: return 25...75
        case .zona: return 40...65
        }
    }

    private static func angulo(_ p: Double) -> Angle { .degrees(-90 + (p - 50) * 1.8) }

    public var body: some View {
        let lado = (radioAnillo + 9) * 2
        Canvas { ctx, size in
            let centro = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = radioAnillo
            let trazoPunteado = punteado || fantasma

            var anillo = Path()
            anillo.addArc(center: centro, radius: r,
                          startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            let estiloAnillo = StrokeStyle(lineWidth: 1,
                                           dash: trazoPunteado ? [2, 3] : [])
            ctx.stroke(anillo, with: .color(LiquidColor.tinta900.opacity(0.12)), style: estiloAnillo)

            guard !fantasma else { return }

            var arco = Path()
            arco.addArc(center: centro, radius: r,
                        startAngle: Self.angulo(rangoArco.lowerBound),
                        endAngle: Self.angulo(rangoArco.upperBound), clockwise: false)
            let estiloArco = StrokeStyle(lineWidth: 2, lineCap: .round,
                                         dash: punteado ? [2, 3] : [])
            ctx.stroke(arco, with: .color(LiquidColor.tinta900.opacity(0.16)), style: estiloArco)

            for lunita in lunitas {
                let a = Self.angulo(min(max(lunita.p, 0), 100))
                let punto = CGPoint(x: centro.x + r * CGFloat(Foundation.cos(a.radians)),
                                    y: centro.y + r * CGFloat(Foundation.sin(a.radians)))
                let radioLunita: CGFloat = lunitas.count > 1 ? 1.9 : 2.2
                ctx.fill(Path(ellipseIn: CGRect(x: punto.x - radioLunita, y: punto.y - radioLunita,
                                                width: radioLunita * 2, height: radioLunita * 2)),
                         with: .color(lunita.hue))

                switch lunita.alerta {
                case .ninguna: break
                case .atencion:
                    aro(ctx, en: punto, radio: radioLunita + 2.4, color: LiquidColor.atencion)
                case .alarma:
                    aro(ctx, en: punto, radio: radioLunita + 2.4, color: LiquidColor.negativo)
                    aro(ctx, en: punto, radio: radioLunita + 4.6, color: LiquidColor.negativo)
                }
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }

    private func aro(_ ctx: GraphicsContext, en punto: CGPoint, radio: CGFloat, color: Color) {
        var p = Path()
        p.addArc(center: punto, radius: radio,
                 startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(p, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1))
    }
}

#Preview("Sabores · en rango") {
    HStack(spacing: 24) {
        MedidorLunar(radioAnillo: 22, sabor: .progreso,
                     lunitas: [.init(p: 48, hue: LiquidColor.indigo)])
        MedidorLunar(radioAnillo: 22, sabor: .desviacion,
                     lunitas: [.init(p: 52, hue: LiquidColor.rosa)])
        MedidorLunar(radioAnillo: 21, sabor: .zona,
                     lunitas: [.init(p: 56, hue: LiquidColor.verdePrimario)])
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}

#Preview("Alertas · atención y alarma") {
    HStack(spacing: 24) {
        MedidorLunar(radioAnillo: 22, sabor: .progreso,
                     lunitas: [.init(p: 88, hue: LiquidColor.indigo, alerta: .atencion)])
        MedidorLunar(radioAnillo: 17, sabor: .desviacion,
                     lunitas: [.init(p: 93, hue: LiquidColor.doradoTemp, alerta: .alarma),
                               .init(p: 84, hue: LiquidColor.azul, alerta: .alarma)])
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}

#Preview("VFC punteado y fantasma") {
    HStack(spacing: 24) {
        MedidorLunar(radioAnillo: 17, sabor: .desviacion,
                     lunitas: [.init(p: 55, hue: LiquidColor.cian)], punteado: true)
        MedidorLunar(radioAnillo: 22, sabor: .desviacion, lunitas: [], fantasma: true)
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}
