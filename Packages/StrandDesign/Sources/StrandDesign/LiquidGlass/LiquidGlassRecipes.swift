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

    @Environment(\.liquidMotionDisabled) private var motionDisabled

    func body(content: Content) -> some View {
        // Renders/previews congelados (`liquidMotionDisabled`): el glassEffect nativo se
        // traga el contenido bajo ImageRenderer (sin backdrop real) — ahí se usa SIEMPRE
        // el stack de imitación, que es rasterizable. En device el nativo manda.
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
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
    /// Acento del ambiente del día (elevación /inject): tiñe el velo un 4 % para que el
    /// clima respire también en el chrome superior. `nil` = velo neutro.
    private let tone: Color?

    public init(tone: Color? = nil) {
        self.tone = tone
    }

    public var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay {
                // Neutro (adiós beige, /inject): el velo tiñe con el fondo claro, no papel.
                LinearGradient(
                    colors: [LiquidColor.fondoAlto.opacity(0.5), LiquidColor.fondoAlto.opacity(0)],
                    startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                if let tone {
                    LinearGradient(colors: [tone.opacity(0.04), tone.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                }
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

// MARK: - vidrio/hoja (fondo de sheet de resumen — épico hoja Liquid, F0)

/// El fondo de una hoja de resumen Liquid: degradado del fondo claro con un suspiro del
/// tono del clima/métrica arriba (4 %, mismo lenguaje que el velo) — pensado para
/// `presentationBackground`. El grip lo pone el sistema (`presentationDragIndicator`).
public struct LiquidSheetFondo: View {
    private let tone: Color?

    /// En renders/previews congelados el `glassEffect` nativo no rasteriza: ahí se usa
    /// el material, igual que el resto de las recetas.
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public init(tone: Color? = nil) {
        self.tone = tone
    }

    public var body: some View {
        ZStack {
            // VIDRIO DE VERDAD (pedido del dueño /inject, 2ª ronda): en iOS 26 el vidrio
            // NATIVO — refracción y lensing reales del sistema, lo mismo que usan el dock
            // y los tiles. Antes era material + un velo casi opaco (0.82) que lo mataba.
            if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
                Color.clear.glassEffect(.regular, in: Rectangle())
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
            // El velo baja a la mitad: sostiene el contraste del texto sin tapar el vidrio.
            LinearGradient(colors: [LiquidColor.fondoAlto.opacity(0.46),
                                    LiquidColor.fondoBajo.opacity(0.34)],
                           startPoint: .top, endPoint: .bottom)
            if let tone {
                // El acento del tono, apagándose hacia el pie para que el dato mande.
                // Transición SUAVE (pedido del dueño /inject): más paradas y el apagado
                // repartido a lo largo de toda la hoja — antes moría a un tercio y el
                // corte contra el blanco se veía duro a la altura de la gráfica.
                LinearGradient(stops: [
                    .init(color: tone.opacity(0.15), location: 0),
                    .init(color: tone.opacity(0.115), location: 0.22),
                    .init(color: tone.opacity(0.075), location: 0.45),
                    .init(color: tone.opacity(0.04), location: 0.68),
                    .init(color: tone.opacity(0.015), location: 0.86),
                    .init(color: tone.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            // Reflejo especular en el canto superior: el gesto que delata al cristal
            // (misma gramática que la receta `lente` del dock).
            VStack(spacing: 0) {
                LinearGradient(stops: [
                    .init(color: LiquidColor.vidrioStreak, location: 0),
                    .init(color: LiquidColor.vidrioStreak.opacity(0.35), location: 0.45),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
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

    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public var body: some View {
        // «LENTE» (elevación /inject 2026-07-22, camino 1 del dueño): disco de vidrio
        // PLANO — el Liquid Glass real nunca simula volumen. La burbuja esférica del
        // handoff (radial blanco + especular) se retiró: el arco y la joya brillan solos
        // sobre vidrio honesto, con apenas un suspiro del tono del estado.
        ZStack {
            if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
                Circle().glassEffect(.regular.tint(tone.opacity(0.10)), in: Circle())
            } else {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(tone.opacity(0.06))
                Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.75)
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
