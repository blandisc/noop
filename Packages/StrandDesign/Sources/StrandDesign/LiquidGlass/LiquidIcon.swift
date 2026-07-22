import SwiftUI

// MARK: - Liquid Glass · Iconografía (handoff §10)
//
// Sin librería de iconos: cada glifo es el path SVG exacto del handoff (stroke 1.4–1.8,
// round caps/joins), parseado por `SVGPathData`. El color lo pone el caller vía
// `.foregroundStyle` (los tiles pintan el tono del dato, los orbes tinta/900).

/// Un glifo del sistema, dibujado a su `size` con el grosor de trazo de su spec.
public struct LiquidIcon: View {
    public enum Glyph: String, CaseIterable, Sendable {
        // Métricas (MetricTile, gotas) — viewBox 16, stroke 1.6.
        case luna, onda, corazon, llama, pasos, termo, resp, estres
        // Señales (SignalOrb) — viewBox 16, stroke 1.5.
        case ondaSenal, lunaSenal, termoSenal
        // Modos de entrenamiento (ModeTile) — viewBox 16, stroke 1.5.
        case rayo, envivo, intervalo, movilidad, respira
        // Chevron de fila (ListRow) — viewBox 12, stroke 1.8.
        case chevron
    }

    private let glyph: Glyph
    private let size: CGFloat

    public init(_ glyph: Glyph, size: CGFloat) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        let spec = glyph.spec
        LiquidIconShape(glyph: glyph)
            .stroke(style: StrokeStyle(
                lineWidth: spec.strokeWidth * size / spec.viewBox,
                lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// La forma cruda del glifo (escala el path del viewBox al rect). Úsala directo solo si
/// necesitas un trazo no estándar; el punto de entrada normal es `LiquidIcon`.
public struct LiquidIconShape: Shape {
    public let glyph: LiquidIcon.Glyph

    public init(glyph: LiquidIcon.Glyph) {
        self.glyph = glyph
    }

    public func path(in rect: CGRect) -> Path {
        let spec = glyph.spec
        var combined = Path()
        for d in spec.paths {
            combined.addPath(SVGPathData.path(d))
        }
        let scale = min(rect.width, rect.height) / spec.viewBox
        return combined.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: scale, y: scale))
    }
}

extension LiquidIcon.Glyph {
    struct Spec {
        let viewBox: CGFloat
        let strokeWidth: CGFloat
        let paths: [String]
    }

    /// Paths EXACTOS del handoff (MetricTile / SignalOrb / ModeTile / ListRow .dc.html).
    var spec: Spec {
        switch self {
        // MARK: Métricas (viewBox 16, sw 1.6)
        case .luna:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M13.5 10.5A6 6 0 1 1 5.5 2.5a4.8 4.8 0 0 0 8 8z",
            ])
        case .onda:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M1 8h3l2-4 3 8 2-4h4",
            ])
        case .corazon:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M8 13.5S2 9.8 2 5.9C2 3.7 3.7 2 5.7 2 7 2 7.8 2.7 8 3.2 8.2 2.7 9 2 10.3 2 12.3 2 14 3.7 14 5.9c0 3.9-6 7.6-6 7.6z",
            ])
        case .llama:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M8.5 1.5c.6 2.4-2.9 3.4-2.9 6a2.9 2.9 0 0 0 5.8 0c0-1.1-.5-1.8-1-2.5-.3 .8-.8 1.2-1.4 1.3.5-1.6.2-3.6-.5-4.8zM5.6 7.5c-.9 .9-1.6 2-1.6 3.3a4 4 0 0 0 8 .2",
            ])
        case .pasos:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M5 1a2.2 3 0 1 0 .01 0M11 7a2.2 3 0 1 0 .01 0",
                "M4 9v1.5M12 2.5V4",
            ])
        case .termo:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M8 1.5v8m0 0a2.6 2.6 0 1 0 .01 0",
                "M6.5 4.5h3",
            ])
        case .resp:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M2 5h8a2 2 0 1 0-2-2.5M2 8.5h11a2 2 0 1 1-2 2.5M2 12h5a1.8 1.8 0 1 1-1.8 2",
            ])
        case .estres:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M2.5 11a6 6 0 0 1 11 0",
                "M8 11L10.8 7",
            ])

        // MARK: Señales (viewBox 16, sw 1.5)
        case .ondaSenal:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M1.5 8 C3 4.6, 4.6 4.6, 6 8 S8.6 11.4, 10 8 S12.4 5.2, 14 6.6",
            ])
        case .lunaSenal:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M13.8 9.9A5.6 5.6 0 1 1 6.1 2.2 4.5 4.5 0 0 0 13.8 9.9z",
            ])
        case .termoSenal:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M8 1.5v8m0 0a2.6 2.6 0 1 0 .01 0M6.5 4.5h3",
            ])

        // MARK: Modos (viewBox 16, sw 1.5)
        case .rayo:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M8.5 1.5L4.5 9h3L6 14.5 11.5 7H8.5z",
            ])
        case .envivo:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M5.6 10.4a3.4 3.4 0 0 1 0-4.8M10.4 5.6a3.4 3.4 0 0 1 0 4.8M3.5 12.5a6.4 6.4 0 0 1 0-9M12.5 3.5a6.4 6.4 0 0 1 0 9",
                "M8 6.8a1.2 1.2 0 1 0 .01 0",
            ])
        case .intervalo:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M8 3.5a5.5 5.5 0 1 0 .01 0M6.3 1.5h3.4",
                "M8 6v3.2l2.2 1.6",
            ])
        case .movilidad:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M10.5 2.2a1.5 1.5 0 1 0 .01 0",
                "M2.5 13.5l4.5-6.5 3.5 1.5 3-2.5M7.5 8.5L6 14",
            ])
        case .respira:
            return Spec(viewBox: 16, strokeWidth: 1.5, paths: [
                "M2 5h8a2 2 0 1 0-2-2.5M2 8.5h11a2 2 0 1 1-2 2.5M2 12h5a1.8 1.8 0 1 1-1.8 2",
            ])

        // MARK: Chevron (viewBox 12, sw 1.8)
        case .chevron:
            return Spec(viewBox: 12, strokeWidth: 1.8, paths: [
                "M4 2l4 4-4 4",
            ])
        }
    }
}

#if DEBUG
#Preview("Liquid · Iconos") {
    let all = LiquidIcon.Glyph.allCases
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
        ForEach(all, id: \.rawValue) { glyph in
            VStack(spacing: 6) {
                LiquidIcon(glyph, size: 26).foregroundStyle(LiquidColor.tinta900)
                Text(glyph.rawValue).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            }
        }
    }
    .padding(24)
    .background(LiquidColor.papelGradient)
}
#endif
