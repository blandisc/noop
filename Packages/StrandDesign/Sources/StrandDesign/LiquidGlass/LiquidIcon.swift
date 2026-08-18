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
        // Carga de entrenamiento (hoja de Carga) — se dibuja como SF Symbol (pesa).
        case carga
        // Guardián (cabecera de la hoja) — SF Symbol `shield`, path de catálogo.
        case escudo
        // Señales (SignalOrb) — viewBox 16, stroke 1.5.
        case ondaSenal, lunaSenal, termoSenal
        // Modos de entrenamiento (ModeTile) — viewBox 16, stroke 1.5.
        case rayo, envivo, intervalo, movilidad, respira
        // Chevron de fila (ListRow) — viewBox 12, stroke 1.8.
        case chevron
        // Enlace a Tendencias (LiquidVerMas) — viewBox 23, stroke 1.8. Mismo arte que la
        // pestaña del dock (curva + dos nodos rellenos): el pie promete la pantalla a la
        // que lleva, con el mismo dibujo que el usuario ya toca abajo.
        case tendencias
    }

    private let glyph: Glyph
    private let size: CGFloat
    private let color: Color

    /// El color va EXPLÍCITO en el trazo (no por `foregroundStyle`): el device no dibuja
    /// el `stroke(style:)` sin contenido — los glifos del TabBar (trazo con color) siempre
    /// se vieron; estos no. Sesión /inject 2026-07-22.
    public init(_ glyph: Glyph, size: CGFloat, color: Color = LiquidColor.tinta900) {
        self.glyph = glyph
        self.size = size
        self.color = color
    }

    /// Los 8 glifos de MÉTRICA se dibujan como el SF Symbol que ya ancla su hoja de
    /// resumen (decisión del dueño, /inject 2026-07-22: mismos iconos arriba y abajo —
    /// el tile promete exactamente lo que la hoja entrega). El resto sigue con los paths
    /// custom del handoff.
    private var sfName: String? {
        switch glyph {
        case .luna: "moon"
        case .onda: "waveform.path.ecg"
        case .corazon: "heart"
        // `llama` dibujaba un RAYO. El nombre decía una cosa y el símbolo otra desde siempre;
        // al volver a los símbolos del sistema (decisión del dueño 2026-08-17) se corrige.
        case .llama: "flame"
        case .pasos: "figure.walk"
        case .termo: "thermometer.medium"
        case .resp: "lungs"
        // El estrés se lee como un MEDIDOR, no como otra onda: tres señales de Hoy ya son
        // ondas y a 20 pt no se distinguían entre sí.
        case .estres: "gauge.with.needle"
        case .carga: "dumbbell"
        case .escudo: "shield"
        default: nil
        }
    }

    public var body: some View {
        if let sfName {
            Image(systemName: sfName)
                .font(LiquidType.iconSF(size: size))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            custom
        }
    }

    @ViewBuilder private var custom: some View {
        // Geometría RELLENA (el contorno del trazo convertido a path con `strokedPath` y
        // luego `fill`): el render de trazos de glifos chicos se comió dos hipótesis en
        // device — el relleno de geometría pura no depende de ese camino.
        let spec = glyph.spec
        ZStack {
            if !spec.paths2.isEmpty {
                LiquidIconShape(glyph: glyph, strokedWidth: spec.strokeWidth * size / spec.viewBox,
                                secondary: true)
                    .fill(color.opacity(0.45))
            }
            LiquidIconShape(glyph: glyph,
                            strokedWidth: spec.strokeWidth * size / spec.viewBox)
                .fill(color)
            // Capa de geometría YA rellena (nodos de la curva de Tendencias): va ENCIMA del
            // trazo, en el mismo orden que el dock. Sin ella los nodos saldrían como anillos
            // finos — arte equivocado.
            if !spec.pathsFilled.isEmpty {
                LiquidIconShape(glyph: glyph, relleno: true).fill(color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// La forma cruda del glifo (escala el path del viewBox al rect). `strokedWidth` no-nil
/// devuelve el CONTORNO del trazo ya convertido a geometría (para rellenar); nil devuelve
/// el path crudo para trazos custom.
public struct LiquidIconShape: Shape {
    public let glyph: LiquidIcon.Glyph
    public var strokedWidth: CGFloat?
    /// `true` = dibuja la capa secundaria tenue del glifo (paths2).
    public var secondary: Bool = false
    /// `true` = dibuja la capa de geometría YA rellena del glifo (`pathsFilled`, los nodos
    /// de la curva de Tendencias). Ignora `strokedWidth`: el path se rellena tal cual.
    public var relleno: Bool = false

    public init(glyph: LiquidIcon.Glyph, strokedWidth: CGFloat? = nil,
                secondary: Bool = false, relleno: Bool = false) {
        self.glyph = glyph
        self.strokedWidth = strokedWidth
        self.secondary = secondary
        self.relleno = relleno
    }

    public func path(in rect: CGRect) -> Path {
        let spec = glyph.spec
        var combined = Path()
        let fuente = relleno ? spec.pathsFilled : (secondary ? spec.paths2 : spec.paths)
        for d in fuente {
            combined.addPath(SVGPathData.path(d))
        }
        let scale = min(rect.width, rect.height) / spec.viewBox
        let scaled = combined.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: scale, y: scale))
        guard !relleno, let strokedWidth else { return scaled }
        return scaled.strokedPath(StrokeStyle(lineWidth: strokedWidth,
                                              lineCap: .round, lineJoin: .round))
    }
}

extension LiquidIcon.Glyph {
    struct Spec {
        let viewBox: CGFloat
        let strokeWidth: CGFloat
        let paths: [String]
        /// Capa secundaria TENUE (45 %) — la segunda onda del glifo autonómico.
        var paths2: [String] = []
        /// Capa RELLENA a color pleno (sin trazo) — los nodos de la curva de Tendencias.
        var pathsFilled: [String] = []
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
        // `.carga` se dibuja como SF Symbol (`sfName`), igual que las otras métricas; el
        // path custom (pesa: placas + barra) mantiene el invariante del catálogo — todo
        // glifo parsea a un path no vacío dentro de su viewBox (LiquidGlassTests).
        case .carga:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M3 5.5v5M5.5 4v8M10.5 4v8M13 5.5v5",
                "M1.5 8h1.5M5.5 8h5M13 8h1.5",
            ])
        // `.escudo` se dibuja como SF Symbol (`shield`); el path mantiene el invariante
        // del catálogo (path no vacío en viewBox) para LiquidGlassTests.
        case .escudo:
            return Spec(viewBox: 16, strokeWidth: 1.6, paths: [
                "M8 1.5l5.5 2v4.2c0 3.4-2.3 5.8-5.5 6.8-3.2-1-5.5-3.4-5.5-6.8V3.5z",
            ])

        // MARK: Señales (viewBox 16, sw 1.8) — familia FINAL elegida por el dueño
        // (/inject 2026-07-22): Autonómico = doble onda entrelazada («ondas finas») ·
        // Sueño = luna con satélite · Térmico = brasa (núcleo + halos + puntos cardinales).
        case .ondaSenal:
            return Spec(viewBox: 16, strokeWidth: 1.8, paths: [
                "M2 9.4 C3.6 6.2, 5.4 6.2, 7 9.4 C8.6 12.6, 10.4 12.6, 12 9.4 C12.9 7.7, 13.5 7.2, 14 7.5",
            ], paths2: [
                "M2 6.6 C3.6 9.8, 5.4 9.8, 7 6.6 C8.6 3.4, 10.4 3.4, 12 6.6",
            ])
        case .lunaSenal:
            return Spec(viewBox: 16, strokeWidth: 1.8, paths: [
                "M13.8 9.9A5.6 5.6 0 1 1 6.1 2.2 4.5 4.5 0 0 0 13.8 9.9z",
                "M13.6 3.6A0.8 0.8 0 1 0 12 3.6A0.8 0.8 0 1 0 13.6 3.6",
            ])
        case .termoSenal:
            return Spec(viewBox: 16, strokeWidth: 1.8, paths: [
                "M9.5 8A1.5 1.5 0 1 0 6.5 8A1.5 1.5 0 1 0 9.5 8",
                "M8.6 8A0.6 0.6 0 1 0 7.4 8A0.6 0.6 0 1 0 8.6 8",
                "M8 3.4A4.6 4.6 0 0 1 12.6 8",
                "M8 12.6A4.6 4.6 0 0 1 3.4 8",
                "M8 1v1M8 14v1M1 8h1M14 8h1",
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

        // MARK: Tendencias (viewBox 23, sw 1.8) — paths IDÉNTICOS a los de la pestaña
        // «Tendencias» del dock (LiquidTabBar.TabGlyph, que es privado): curva trazada +
        // dos nodos rellenos. Si alguno cambia allá, cámbialo aquí.
        case .tendencias:
            return Spec(viewBox: 23, strokeWidth: 1.8, paths: [
                "M2.5 17C7 17 7.5 6 11.5 6s4.5 9 9 9",
            ], pathsFilled: [
                "M8.6 11A1.6 1.6 0 1 0 5.4 11A1.6 1.6 0 1 0 8.6 11",
                "M17.6 11.5A1.6 1.6 0 1 0 14.4 11.5A1.6 1.6 0 1 0 17.6 11.5",
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
                LiquidIcon(glyph, size: 26, color: LiquidColor.tinta900)
                Text(glyph.rawValue).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            }
        }
    }
    .padding(24)
    .background(LiquidColor.papelGradient)
}
#endif
