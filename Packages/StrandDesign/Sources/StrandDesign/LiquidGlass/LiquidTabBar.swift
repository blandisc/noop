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
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: Glifos del dock (paths exactos del handoff, viewBox 23; círculos como arcos)

private struct TabGlyph: View {
    let tab: LiquidTab
    let color: Color
    let showDot: Bool

    private static let viewBox: CGFloat = 23

    /// (path, strokeWidth) por tab + posición del punto activo (cx, cy) con r 1.5.
    private var layers: [(d: String, width: CGFloat)] {
        switch tab {
        case .hoy:
            return [
                ("M19.5 11.5A8 8 0 1 0 3.5 11.5A8 8 0 1 0 19.5 11.5", 1.6),
                ("M11.5 3.5v1.7M11.5 17.8v1.7M3.5 11.5h1.7M17.8 11.5h1.7", 1.6),
            ]
        case .tendencias:
            return [
                ("M2.5 17C7 17 7.5 6 11.5 6s4.5 9 9 9", 1.8),
                ("M8.8 11A1.8 1.8 0 1 0 5.2 11A1.8 1.8 0 1 0 8.8 11", 1.5),
                ("M17.8 11.5A1.8 1.8 0 1 0 14.2 11.5A1.8 1.8 0 1 0 17.8 11.5", 1.5),
            ]
        case .entrenar:
            return [
                ("M13.5 4.5A2 2 0 1 0 9.5 4.5A2 2 0 1 0 13.5 4.5", 1.5),
                ("M5 10.5l4-2h5l4 4M11.5 8.5V14l-3 5M11.5 14l3.5 4.5", 1.5),
            ]
        case .ajustes:
            return [
                ("M14.7 11.5A3.2 3.2 0 1 0 8.3 11.5A3.2 3.2 0 1 0 14.7 11.5", 1.5),
                ("M11.5 2.8v2.6M11.5 17.6v2.6M2.8 11.5h2.6M17.6 11.5h2.6M5.3 5.3l1.9 1.9M15.8 15.8l1.9 1.9M17.7 5.3l-1.9 1.9M7.2 15.8l-1.9 1.9", 1.5),
            ]
        }
    }

    private var dotCenter: CGPoint {
        switch tab {
        case .hoy: return CGPoint(x: 16, y: 7)
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
                    TabGlyphPath(d: layer.d)
                        .stroke(color, style: StrokeStyle(
                            lineWidth: layer.width * s, lineCap: .round, lineJoin: .round))
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
