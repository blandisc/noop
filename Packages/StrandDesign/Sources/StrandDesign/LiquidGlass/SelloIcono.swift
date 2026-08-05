import SwiftUI

/// FER-51 · Sello-ícono de sección en modo Matriz: orbe denso de partículas (mismo material
/// de los orbes del Cosmos) + glifo en color papel encima. `huesPar != nil` mezcla dos hues
/// en el orbe (escudo bicolor del guardián: dorado + azul).
public struct SelloIcono: View {

    public enum Glifo: Sendable {
        case luna, corazon, onda, escudo, montana, flama, rayo, huellas
    }

    private let glifo: Glifo
    private let hue: Color
    private let huesPar: (Color, Color)?
    private let radio: CGFloat

    public init(glifo: Glifo, hue: Color, huesPar: (Color, Color)? = nil, radio: CGFloat = 9) {
        self.glifo = glifo
        self.hue = hue
        self.huesPar = huesPar
        self.radio = radio
    }

    public var body: some View {
        let lado = radio * 2
        Canvas { ctx, size in
            let centro = CGPoint(x: size.width / 2, y: size.height / 2)
            dibujarOrbe(ctx: ctx, centro: centro, radio: radio)
            dibujarGlifo(ctx: ctx, centro: centro, radio: radio)
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }

    // MARK: Orbe de partículas (~40–52)

    private func dibujarOrbe(ctx: GraphicsContext, centro: CGPoint, radio: CGFloat) {
        let cuenta = 46
        let chartID = "sello-\(glifoKey)"
        // Ángulo áureo para empaquetar puntos en disco.
        let golden = Double.pi * (3 - sqrt(5))
        for i in 0..<cuenta {
            let s = MatrizDither.semilla(chartID: chartID, index: i)
            let p = MatrizDither.particula(s)
            // Disco de Fibonacci: r ∝ √(i/n).
            let t = Double(i) / Double(cuenta - 1)
            let rNorm = sqrt(t) * Double(radio) * 0.92
            let ang = golden * Double(i)
            let ox = cos(ang) * rNorm
            let oy = sin(ang) * rNorm
            let px = centro.x + CGFloat(ox) + CGFloat(p.dx) * 0.6
            let py = centro.y + CGFloat(oy) + CGFloat(p.dy) * 0.6
            let pr = (0.55 + 0.55 * (1 - t)) * CGFloat(p.dScale)
            // Más denso al centro; bordes más tenues.
            let densAlfa = (0.55 + 0.40 * (1 - t)) * p.dAlpha
            let color: Color
            if let par = huesPar {
                // Mitad por índice (determinista): bicolor sin degradado suave.
                color = (i % 2 == 0) ? par.0 : par.1
            } else {
                color = hue
            }
            ctx.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(color.opacity(densAlfa)))
        }
    }

    private var glifoKey: String {
        switch glifo {
        case .luna: return "luna"
        case .corazon: return "corazon"
        case .onda: return "onda"
        case .escudo: return "escudo"
        case .montana: return "montana"
        case .flama: return "flama"
        case .rayo: return "rayo"
        case .huellas: return "huellas"
        }
    }

    // MARK: Glifo en papel (Path)

    private func dibujarGlifo(ctx: GraphicsContext, centro: CGPoint, radio: CGFloat) {
        let scale = radio * 2 / 16  // paths en viewBox 16
        let origin = CGPoint(x: centro.x - radio, y: centro.y - radio)
        let path = glifoPath()
        let transform = CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
        let scaled = path.applying(transform)
        let estilo = StrokeStyle(lineWidth: max(1.1 * scale, 0.8),
                                 lineCap: .round, lineJoin: .round)
        // Relleno sutil + trazo en papel para legibilidad sobre el orbe denso.
        if glifo == .corazon || glifo == .escudo || glifo == .rayo || glifo == .luna {
            ctx.fill(scaled, with: .color(LiquidColor.papelMatriz.opacity(0.95)))
        }
        ctx.stroke(scaled, with: .color(LiquidColor.papelMatriz), style: estilo)
    }

    private func glifoPath() -> Path {
        // Coordenadas en viewBox 16×16 (mismas familias que LiquidIcon donde aplica).
        switch glifo {
        case .luna:
            return SVGPathData.path("M13.5 10.5A6 6 0 1 1 5.5 2.5a4.8 4.8 0 0 0 8 8z")
        case .corazon:
            return SVGPathData.path(
                "M8 13.5S2 9.8 2 5.9C2 3.7 3.7 2 5.7 2 7 2 7.8 2.7 8 3.2 8.2 2.7 9 2 10.3 2 12.3 2 14 3.7 14 5.9c0 3.9-6 7.6-6 7.6z")
        case .onda:
            return SVGPathData.path("M1 8h3l2-4 3 8 2-4h4")
        case .escudo:
            return SVGPathData.path(
                "M8 1.5l5.5 2v4.2c0 3.4-2.3 5.8-5.5 6.8-3.2-1-5.5-3.4-5.5-6.8V3.5z")
        case .montana:
            var p = Path()
            p.move(to: CGPoint(x: 1.5, y: 12.5))
            p.addLine(to: CGPoint(x: 5.5, y: 5))
            p.addLine(to: CGPoint(x: 8.5, y: 9))
            p.addLine(to: CGPoint(x: 11, y: 4))
            p.addLine(to: CGPoint(x: 14.5, y: 12.5))
            return p
        case .flama:
            return SVGPathData.path(
                "M8.5 1.5c.6 2.4-2.9 3.4-2.9 6a2.9 2.9 0 0 0 5.8 0c0-1.1-.5-1.8-1-2.5-.3 .8-.8 1.2-1.4 1.3.5-1.6.2-3.6-.5-4.8z")
        case .rayo:
            return SVGPathData.path("M8.5 1.5L4.5 9h3L6 14.5 11.5 7H8.5z")
        case .huellas:
            var p = Path()
            // Dos óvalos escalonados (huellas).
            p.addEllipse(in: CGRect(x: 3.2, y: 2.5, width: 3.6, height: 5.2))
            p.addEllipse(in: CGRect(x: 9.2, y: 8.2, width: 3.6, height: 5.2))
            return p
        }
    }
}

// MARK: - Previews

#Preview("Sellos · 8 glifos") {
    let items: [(SelloIcono.Glifo, Color, (Color, Color)?)] = [
        (.luna, LiquidColor.indigo, nil),
        (.corazon, LiquidColor.rosa, nil),
        (.onda, LiquidColor.cian, nil),
        (.escudo, LiquidColor.doradoTemp, (LiquidColor.doradoTemp, LiquidColor.azul)),
        (.montana, LiquidColor.verdePrimario, nil),
        (.flama, LiquidColor.teal, nil),
        (.rayo, LiquidColor.tinta900, nil),
        (.huellas, LiquidColor.tinta500, nil),
    ]
    HStack(spacing: 14) {
        ForEach(0..<items.count, id: \.self) { i in
            SelloIcono(glifo: items[i].0, hue: items[i].1, huesPar: items[i].2)
        }
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}

#Preview("Sello · tamaños") {
    HStack(spacing: 20) {
        SelloIcono(glifo: .luna, hue: LiquidColor.indigo, radio: 9)
        SelloIcono(glifo: .corazon, hue: LiquidColor.rosa, radio: 12)
        SelloIcono(glifo: .escudo, hue: LiquidColor.doradoTemp,
                   huesPar: (LiquidColor.doradoTemp, LiquidColor.azul), radio: 14)
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}
