import SwiftUI

// MARK: - Liquid Glass · Recetas de vidrio (handoff §4.5)
//
// Cuatro recetas cerradas — velo / superficie / pastilla / lente — más la variante esférica
// (SignalOrb, dial). Cada capa de vidrio es un stack: (a) blur con fondo, (b) borde con
// inner-highlights, (c) opcional highlight especular. Se usan COMPLETAS, nunca blur suelto.
//
// Calibración nativa (§8 del handoff): el backdrop-filter de CSS se aproxima con materiales
// del sistema — `.ultraThinMaterial` para superficie/pastilla (blur 14–16) y `.thinMaterial`
// para el lente (blur 26, saturate 195 %) — más el relleno blanco de la receta encima. Los
// inner-shadows de CSS se aproximan con un trazo interior en degradado blanco.

/// Las recetas con forma. El velo (sin forma, con máscara de desvanecimiento) vive como
/// vista propia: `LiquidVeil`.
public enum LiquidGlassRecipe: Sendable {
    /// Tiles y tarjetas (MetricTile, ModeTile, tarjeta de lista). r/tarjeta + e/0.
    case superficie
    /// Barras (CargaBar), chips grandes, botón glass. r/pastilla + e/0.
    case pastilla
    /// Pastilla destacada (sugerencias). r/pastilla + e/1.
    case pastillaElevada
    /// Dock flotante (TabBar), elementos flotantes. r/pastilla + streak especular + e/3.
    case lente
}

public extension View {
    /// Aplica una receta de vidrio completa (blur + fondo + borde + inner-highlight +
    /// especular + sombra). La única puerta al vidrio: las pantallas jamás componen
    /// materiales/blur a mano.
    @ViewBuilder
    func liquidGlass(_ recipe: LiquidGlassRecipe) -> some View {
        switch recipe {
        case .superficie:
            modifier(LiquidGlassLayer(
                shape: RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous),
                material: .ultraThinMaterial,
                fill: LiquidColor.vidrioSuperficie,
                border: LiquidColor.vidrioBordeSuperficie,
                highlightTop: 0.8, highlightBottom: 0.35,
                streak: false,
                shadow: LiquidElevation.e0))
        case .pastilla:
            modifier(LiquidGlassLayer(
                shape: Capsule(),
                material: .ultraThinMaterial,
                fill: LiquidColor.vidrioPastilla,
                border: LiquidColor.vidrioBordePastilla,
                highlightTop: 0.8, highlightBottom: 0.0,
                streak: false,
                shadow: LiquidElevation.e0))
        case .pastillaElevada:
            modifier(LiquidGlassLayer(
                shape: Capsule(),
                material: .ultraThinMaterial,
                fill: LiquidColor.vidrioPastilla,
                border: LiquidColor.vidrioBordePastilla,
                highlightTop: 0.8, highlightBottom: 0.0,
                streak: false,
                shadow: LiquidElevation.e1))
        case .lente:
            modifier(LiquidGlassLayer(
                shape: Capsule(),
                material: .thinMaterial,
                fill: LiquidColor.papelDock,
                border: LiquidColor.vidrioBordePastilla,
                highlightTop: 0.95, highlightBottom: 0.3,
                streak: true,
                shadow: LiquidElevation.e3))
        }
    }
}

/// El stack genérico de una receta con forma.
private struct LiquidGlassLayer<S: InsettableShape>: ViewModifier {
    let shape: S
    let material: Material
    let fill: Color
    let border: Color
    /// Alfa superior/inferior del trazo interior que aproxima los inner-shadows de CSS.
    let highlightTop: Double
    let highlightBottom: Double
    let streak: Bool
    let shadow: [LiquidShadowLayer]

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            // Liquid Glass NATIVO (investigación /inject 2026-07-22, Cupertino): el sistema
            // aporta refracción, lensing y reactividad al toque reales — imposibles de
            // imitar con material + relleno. La elevación tonal sigue siendo nuestra
            // (silueta difuminada); el resto del stack queda como fallback para OS previos.
            content
                // `.regular` SIN `.interactive()` (decisión del dueño /inject: el clear se
                // sintió aguado y la reactividad táctil del vidrio competía con nuestro
                // press — la única gramática de toque es `.liquidPress`).
                .glassEffect(.regular, in: shape)
                .liquidShadow(shadow, silhouette: shape)
        } else {
            imitacion(content)
        }
    }

    /// El stack de imitación (< iOS 26): material del sistema + relleno blanco + bordes.
    private func imitacion(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(material)
                    shape.fill(fill)
                }
            }
            .overlay {
                // Inner-highlight: luz entrando por arriba-izquierda, se apaga hacia abajo.
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(highlightTop), location: 0),
                                .init(color: .white.opacity(highlightBottom), location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5)
                    .blur(radius: 0.5)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .overlay {
                if streak {
                    // Streak especular del lente: left/right 10 %, top 2.5, alto 34 %.
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(
                                colors: [LiquidColor.vidrioStreak, .clear],
                                startPoint: .top, endPoint: .bottom))
                            .frame(width: geo.size.width * 0.8, height: geo.size.height * 0.34)
                            .position(x: geo.size.width / 2, y: 2.5 + geo.size.height * 0.17)
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                shape.strokeBorder(border, lineWidth: 0.5).allowsHitTesting(false)
            }
            .clipShape(shape)
            // Elevación como GEOMETRÍA (silueta difuminada detrás): `.shadow` sobre material
            // proyecta el rectángulo de su capa de fondo, y compositingGroup no lo salva.
            .liquidShadow(shadow, silhouette: shape)
    }
}

// MARK: - vidrio/velo (status bar, scrims)

/// El velo del status bar: blur + degradado de papel que se desvanece con máscara.
/// Colócalo con `.overlay(alignment: .top)` a alto `LiquidSpace.s1400` (56).
public struct LiquidVeil: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                // Neutro (adiós beige, /inject): el velo tiñe con el fondo claro, no papel.
                LinearGradient(
                    colors: [LiquidColor.fondoAlto.opacity(0.5), LiquidColor.fondoAlto.opacity(0)],
                    startPoint: .top, endPoint: .bottom)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Esfera (SignalOrb / dial) — variante esférica del vidrio

/// El fondo esférico de vidrio: radial blanco → tinte del tono, borde blanco, inner-highlights
/// y elipse especular arriba-izquierda. El anillo de progreso y el icono los pone el componente.
public struct LiquidSphere: View {
    /// Tono que tiñe el fondo del cuadrante inferior-derecho (al 22 %) y el inner-shadow (14 %).
    public let tone: Color

    public init(tone: Color) {
        self.tone = tone
    }

    public var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                // Esfera de vidrio NATIVO en iOS 26 (más cristal, pedido del dueño);
                // el radial especular de abajo la corona en ambos caminos.
                if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
                    Circle().glassEffect(.regular.tint(tone.opacity(0.14)), in: Circle())
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
                Circle().fill(
                    RadialGradient(
                        stops: [
                            .init(color: .white.opacity(0.55), location: 0),
                            .init(color: .white.opacity(0.12), location: 0.4),
                            .init(color: tone.opacity(0.22), location: 1),
                        ],
                        center: UnitPoint(x: 0.32, y: 0.24),
                        startRadius: 0, endRadius: d * 0.8))
                // Inner-highlights: blanco fuerte arriba-izquierda, tinte abajo-derecha.
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.95), location: 0),
                                .init(color: tone.opacity(0.14), location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2)
                    .blur(radius: 1)
                    .clipShape(Circle())
                Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.75)
                // Highlight especular: elipse en left 16 % / top 7 %, 44 % × 26 %.
                // Especular chico y suave (pasada de elegancia): un beso de luz, no un foco.
                Ellipse()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.7), .white.opacity(0)],
                        center: .center, startRadius: 0, endRadius: d * 0.17))
                    .frame(width: d * 0.34, height: d * 0.20)
                    .position(x: d * 0.20 + d * 0.17, y: d * 0.10 + d * 0.10)
            }
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Liquid · Vidrio") {
    ZStack {
        LiquidColor.papelGradient
        Circle().fill(LiquidColor.verdeAurora.opacity(0.3)).frame(width: 260).blur(radius: 40)
            .offset(x: -60, y: -160)
        VStack(spacing: 22) {
            Text("vidrio/superficie")
                .font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                .padding(24).frame(maxWidth: .infinity)
                .liquidGlass(.superficie)
            Text("vidrio/pastilla")
                .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.vertical, 12).frame(maxWidth: .infinity)
                .liquidGlass(.pastilla)
            Text("vidrio/lente")
                .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.vertical, 18).frame(maxWidth: .infinity)
                .liquidGlass(.lente)
            HStack(spacing: 24) {
                LiquidSphere(tone: LiquidColor.verdePrimario).frame(width: 64, height: 64)
                LiquidSphere(tone: LiquidColor.ambar).frame(width: 64, height: 64)
                LiquidSphere(tone: LiquidColor.indigo).frame(width: 64, height: 64)
            }
            Spacer().frame(height: 0)
        }
        .padding(28)
        VStack { LiquidVeil().frame(height: LiquidSpace.s1400); Spacer() }.ignoresSafeArea()
    }
}
#endif
