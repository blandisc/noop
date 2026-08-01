import SwiftUI

// MARK: - Liquid Glass · TabBar (handoff §5.3)
//
// Dock flotante: vidrio/lente + e/3, r/pastilla. 4 items a partes iguales; el activo pinta
// icono+label en tinta/900 peso 600 y un punto verde 1.5r en la esquina del icono.
// Posición en pantalla: left/right 16, bottom 14 (LiquidSpace.dockSide / .dockBottom).

public enum LiquidTab: String, CaseIterable, Sendable {
    case hoy, tendencias, entrenar, ajustes

    public var titulo: String {
        switch self {
        case .hoy: return "Hoy"
        case .tendencias: return "Tendencias"
        case .entrenar: return "Entrenar"
        case .ajustes: return "Ajustes"
        }
    }
}

public struct LiquidTabBar: View {
    private let active: LiquidTab
    private let onSelect: ((LiquidTab) -> Void)?

    /// El selector de vidrio que se desliza a la pestaña activa (patrón nativo iOS).
    @Namespace private var seleccion

    public init(active: LiquidTab, onSelect: ((LiquidTab) -> Void)? = nil) {
        self.active = active
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(LiquidTab.allCases, id: \.rawValue) { tab in
                Button {
                    onSelect?(tab)
                } label: {
                    item(tab)
                }
                .buttonStyle(.liquidPress)
            }
        }
        .padding(.top, LiquidSpace.s200)
        .padding(.horizontal, LiquidSpace.s150)
        .padding(.bottom, LiquidSpace.s150)
        .liquidGlass(.lente)
        // El selector se desliza con carácter (glass-spring · quick). Reduce Motion / renders
        // congelados: sin animación, la pastilla salta directo a la pestaña activa.
        .animation(reduceMotion || motionDisabled ? nil : LiquidMotion.selector, value: active)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// La pastilla de vidrio del ítem activo: nativa en iOS 26, imitación antes
    /// (y también en renders congelados — el glassEffect no rasteriza en ImageRenderer).
    @ViewBuilder
    private var selectorPill: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
            Color.clear.glassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.35)))
                .overlay(Capsule().strokeBorder(LiquidColor.vidrioBordePastilla, lineWidth: 0.5))
        }
    }

    private func item(_ tab: LiquidTab) -> some View {
        let isActive = tab == active
        let color = isActive ? LiquidColor.tinta900 : LiquidColor.tinta500
        return VStack(spacing: 3) {
            TabGlyph(tab: tab, color: color, showDot: isActive)
                .frame(width: 22, height: 22)
            Text(tab.titulo)
                .font(LiquidType.tab(active: isActive))
                .foregroundStyle(color)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background {
            if isActive {
                selectorPill
                    .matchedGeometryEffect(id: "seleccion", in: seleccion)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: Glifos del dock (paths exactos del handoff, viewBox 23; círculos como arcos)

private struct TabGlyph: View {
    let tab: LiquidTab
    let color: Color
    let showDot: Bool

    private static let viewBox: CGFloat = 23

    /// Capas del glifo: trazo (con grosor) o RELLENO. Familia elegida por el dueño en la
    /// sesión /inject: Hoy = dial-sello (H2) · Tendencias = curva con nodos (A) ·
    /// Entrenar = mancuerna (A) · Ajustes = perilla mínima (J3).
    private var layers: [(d: String, width: CGFloat, filled: Bool)] {
        switch tab {
        case .hoy:
            return [
                ("M19 11.5A7.5 7.5 0 1 0 4 11.5A7.5 7.5 0 1 0 19 11.5", 1.6, false),
                ("M5.7 6.7A7.5 7.5 0 0 1 17.3 6.7", 2.2, false),
                ("M11.5 2.6v1.4", 1.6, false),
                ("M18.5 15.2A1.5 1.5 0 1 0 15.5 15.2A1.5 1.5 0 1 0 18.5 15.2", 0, true),
            ]
        case .tendencias:
            return [
                ("M2.5 17C7 17 7.5 6 11.5 6s4.5 9 9 9", 1.8, false),
                ("M8.6 11A1.6 1.6 0 1 0 5.4 11A1.6 1.6 0 1 0 8.6 11", 0, true),
                ("M17.6 11.5A1.6 1.6 0 1 0 14.4 11.5A1.6 1.6 0 1 0 17.6 11.5", 0, true),
            ]
        case .entrenar:
            return [
                ("M4.2 9.8v3.4M6.6 8.2v7M16.4 8.2v7M18.8 9.8v3.4M6.6 11.5h9.8", 1.6, false),
            ]
        case .ajustes:
            return [
                ("M18.7 11.5A7.2 7.2 0 1 0 4.3 11.5A7.2 7.2 0 1 0 18.7 11.5", 1.6, false),
                ("M11.5 11.5 L15.5 7.5", 2.2, false),
                ("M12.7 11.5A1.2 1.2 0 1 0 10.3 11.5A1.2 1.2 0 1 0 12.7 11.5", 0, true),
            ]
        }
    }

    private var dotCenter: CGPoint {
        switch tab {
        case .hoy: return CGPoint(x: 19.5, y: 4)
        case .tendencias: return CGPoint(x: 19, y: 4.5)
        case .entrenar: return CGPoint(x: 19, y: 4.5)
        case .ajustes: return CGPoint(x: 19.5, y: 4)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / Self.viewBox
            ZStack(alignment: .topLeading) {
                ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                    if layer.filled {
                        TabGlyphPath(d: layer.d).fill(color)
                    } else {
                        TabGlyphPath(d: layer.d)
                            .stroke(color, style: StrokeStyle(
                                lineWidth: layer.width * s, lineCap: .round, lineJoin: .round))
                    }
                }
                if showDot {
                    Circle()
                        .fill(LiquidColor.verdePrimario)
                        .frame(width: 3 * s, height: 3 * s)
                        .position(x: dotCenter.x * s, y: dotCenter.y * s)
                }
            }
        }
    }
}

private struct TabGlyphPath: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 23
        return SVGPathData.path(d).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: s, y: s))
    }
}

#if DEBUG
#Preview("Liquid · TabBar") {
    struct Demo: View {
        @State private var active: LiquidTab = .hoy
        var body: some View {
            VStack {
                Spacer()
                LiquidTabBar(active: active) { active = $0 }
                    .padding(.horizontal, LiquidSpace.dockSide)
                    .padding(.bottom, LiquidSpace.dockBottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidColor.papelGradient)
        }
    }
    return Demo()
}
#endif
