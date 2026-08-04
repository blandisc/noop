import SwiftUI

// MARK: - Liquid Glass · Recetas de vidrio (handoff §4.5)
//
// Recetas de vidrio — superficie / pastilla / lente — más variantes OPACAS
// (superficieSolida / pastillaSolida) y la esférica (SignalOrb, dial). Cada capa de
// vidrio es un stack: (a) blur con fondo, (b) borde con inner-highlights, (c) opcional
// highlight especular. Se usan COMPLETAS, nunca blur suelto. Las sólidas omiten (a):
// papel opaco + el mismo chrome (borde, highlight, sombra, radio).
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
    /// Superficie OPACA (papel, sin blur ni glassEffect). Mismo radio/borde/highlight/sombra
    /// que `.superficie`. Para tarjetas *dentro* de una hoja de vidrio: el vidrio-sobre-vidrio
    /// muestreaba el backdrop y, al arrastrar la hoja, saltaba de gris a blanco (revisión
    /// /inject del dueño). El vidrio real se reserva para la hoja, el dock y el orbe.
    case superficieSolida
    /// Pastilla OPACA (papel, sin blur ni glassEffect). Mismo chrome que `.pastilla`.
    /// Misma razón que `.superficieSolida` — p. ej. «Ver más» dentro de la hoja de detalle.
    case pastillaSolida
}

public extension View {
    /// Aplica una receta de vidrio completa (blur + fondo + borde + inner-highlight +
    /// especular + sombra) o su variante opaca. La única puerta al vidrio: las pantallas
    /// jamás componen materiales/blur a mano.
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
        case .superficieSolida:
            // OPACO a propósito: sin material ni glassEffect (vidrio interno en hoja
            // saltaba de gris a blanco al arrastrar — /inject dueño).
            modifier(LiquidSolidLayer(
                shape: RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous),
                // #inject r3 · Blanco puro del mock (`.card{background:#FFFFFF}`), no el
                // papel cálido de pantalla — pedido del dueño («se ven cálidos»).
                fill: LiquidColor.papelTarjeta,
                border: LiquidColor.vidrioBordeSuperficie,
                highlightTop: 0.8, highlightBottom: 0.35,
                shadow: LiquidElevation.e0))
        case .pastillaSolida:
            // OPACO a propósito: sin material ni glassEffect (misma razón que superficieSolida).
            modifier(LiquidSolidLayer(
                shape: Capsule(),
                // #inject r3 · Mismo blanco de tarjeta que `.superficieSolida` (mock
                // `.vermas{background:#FFFFFF}`).
                fill: LiquidColor.papelTarjeta,
                border: LiquidColor.vidrioBordePastilla,
                highlightTop: 0.8, highlightBottom: 0.0,
                shadow: LiquidElevation.e0))
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
                // El relleno de la receta TAMBIÉN va en el camino nativo: sin él la
                // superficie es 100 % backdrop y cambia de valor según dónde esté en
                // pantalla (las tablas de las hojas «se encendían» al scrollear bajo
                // el canto claro del fondo — revisión de usuario en simulador).
                .background { shape.fill(fill) }
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

/// Stack OPACO: papel sólido + el mismo chrome que el vidrio (borde, inner-highlight,
/// sombra). Sin `.ultraThinMaterial`, sin `glassEffect`, sin muestreo de backdrop —
/// el valor no cambia al arrastrar la hoja de detalle (F1a /inject dueño).
private struct LiquidSolidLayer<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    let border: Color
    let highlightTop: Double
    let highlightBottom: Double
    let shadow: [LiquidShadowLayer]

    func body(content: Content) -> some View {
        content
            .background { shape.fill(fill) }
            .overlay {
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
                shape.strokeBorder(border, lineWidth: 0.5).allowsHitTesting(false)
            }
            .clipShape(shape)
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

/// El fondo de una hoja de resumen Liquid: vidrio nativo + plasta monocroma del tono de
/// la métrica (dos masas desenfocadas detrás del héroe) + velo neutro de papel
/// (`fondoAlto`/`fondoBajo`) + reflejo especular del canto. Pensado para
/// `presentationBackground`. El grip lo pone el sistema (`presentationDragIndicator`).
///
/// La plasta NO es el lavado estático de color que cubría toda la hoja (ese se retiró
/// por pedido del dueño: ensuciaba el papel). Son dos masas concentradas, muy
/// desenfocadas, que respiran detrás del héroe, del tono de la métrica. Aprobada en
/// los prototipos canónicos (LIQUID-GLASS §11.3, DESIGN §8.9). `tone == nil` o
/// `plasta: false` la omiten; el velo pasa por encima y la suaviza como luz bajo el papel.
public struct LiquidSheetFondo: View {
    private let tone: Color?
    /// Si es `false`, la hoja no pinta plasta aunque haya `tone` (escotilla de escape).
    private let plasta: Bool

    /// En renders/previews congelados el `glassEffect` nativo no rasteriza: ahí se usa
    /// el material, igual que el resto de las recetas. También congela la plasta.
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tone: Color? = nil, plasta: Bool = true) {
        self.tone = tone
        self.plasta = plasta
    }

    public var body: some View {
        ZStack {
            // PAPEL DEL MOCK (#inject r2, decisión del dueño 2026-08-04 — revierte el
            // «vidrio de verdad» de la ronda anterior): el fondo de la hoja es papel
            // sólido con degradado, como el mock canónico (`sheet-sueno.html` §.sheet:
            // linear-gradient #FEFEFD→#F3F4F2). El vidrio vivo re-muestreaba la pantalla
            // en movimiento al arrastrar la hoja y las tarjetas opacas no lo seguían —
            // esa des-sincronía se leía como una «sombra» barata. Papel opaco = artefacto
            // imposible por construcción; la profundidad la siguen dando plasta, velo y
            // filo especular.
            LinearGradient(colors: [LiquidColor.fondoAlto, LiquidColor.fondoBajo],
                           startPoint: .top, endPoint: .bottom)
            // Plasta monocroma: DESPUÉS del vidrio, ANTES del velo. El velo la suaviza
            // como luz bajo el papel (no mancha encima). Compuesta aquí (no reusa
            // `LiquidPlasta`: esa es el fondo completo de Hoy, 4 masas + suelo + viñeta).
            if plasta, let tone {
                sheetPlasta(tone: tone)
            }
            // El velo suaviza la PLASTA (sobre el papel liso es un no-op: mismo color a
            // mismo color). Sostiene el contraste del texto donde la mancha de tono vive.
            // El velo NO adelgaza hacia abajo (pasada UI H1): el acento ya se apaga solo,
            // y sumar los dos dejaba el pie —lista de niveles y notas de 10.5— con el
            // suelo de blanco más delgado de la hoja.
            LinearGradient(colors: [LiquidColor.fondoAlto.opacity(0.46),
                                    LiquidColor.fondoBajo.opacity(0.50)],
                           startPoint: .top, endPoint: .bottom)
            // Reflejo especular en el canto superior: el gesto que delata al cristal
            // (misma gramática que la receta `lente` del dock).
            VStack(spacing: 0) {
                // Filo de cristal, no niebla (pasada UI H6): 140 pt de blanco cubrían el
                // header y blanqueaban el acento justo donde se calibró.
                LinearGradient(stops: [
                    .init(color: LiquidColor.vidrioStreak, location: 0),
                    .init(color: LiquidColor.vidrioStreak.opacity(0.25), location: 0.35),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: LiquidSpace.s800)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// Dos masas del tono de la métrica: principal (late 9 s) arriba-centro detrás del
    /// héroe; secundaria (deriva 26 s) más chica, abajo-izquierda al primer tercio.
    /// Misma gramática que la plasta de Hoy (blur 52, coseno, freeze en t = 0).
    @ViewBuilder
    private func sheetPlasta(tone: Color) -> some View {
        let still = reduceMotion || motionDisabled
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente, paused: still)) { context in
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                // Latido 1 → driftScaleMax → 1 en un ciclo de `plastaLatidoPeriod`.
                let pulse: CGFloat = still
                    ? 1
                    : 1 + (LiquidMotion.driftScaleMax - 1) * 0.5
                        * (1 - cos(2 * .pi * t / LiquidMotion.plastaLatidoPeriod))
                // Deriva: `driftProgress` usa medio ciclo; periodo = ciclo completo / 2.
                let u = still
                    ? 0
                    : LiquidMotion.driftProgress(
                        time: t,
                        period: LiquidMotion.plastaDerivaPeriod / 2)
                let dx = Self.plastaDerivaX * u
                let dy = Self.plastaDerivaY * u

                ZStack {
                    // Principal: ~300 pt, opacidad baja, anclada arriba y centrada;
                    // asoma un poco por el borde superior (centro cerca del top + blur).
                    Circle()
                        .fill(tone.opacity(Self.plastaPrincipalAlpha))
                        .frame(width: Self.plastaPrincipalSize, height: Self.plastaPrincipalSize)
                        .scaleEffect(pulse)
                        .blur(radius: Self.plastaBlur)
                        .position(
                            x: geo.size.width / 2,
                            y: Self.plastaPrincipalTop + Self.plastaPrincipalSize / 2)

                    // Secundaria: ~210 pt, borde izquierdo, altura del primer tercio.
                    Circle()
                        .fill(tone.opacity(Self.plastaSecundariaAlpha))
                        .frame(width: Self.plastaSecundariaSize, height: Self.plastaSecundariaSize)
                        .blur(radius: Self.plastaBlur)
                        .position(
                            x: Self.plastaSecundariaLeft + Self.plastaSecundariaSize / 2 + dx,
                            y: Self.plastaSecundariaTop + Self.plastaSecundariaSize / 2 + dy)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Geometría de la plasta de hoja (canónica: sheet-generica-final.html).
    private static let plastaBlur: CGFloat = 52
    private static let plastaPrincipalSize: CGFloat = 300
    private static let plastaPrincipalAlpha: Double = 0.16
    private static let plastaPrincipalTop: CGFloat = 14
    private static let plastaSecundariaSize: CGFloat = 210
    private static let plastaSecundariaAlpha: Double = 0.09
    private static let plastaSecundariaLeft: CGFloat = -40
    private static let plastaSecundariaTop: CGFloat = 104
    private static let plastaDerivaX: CGFloat = 26
    private static let plastaDerivaY: CGFloat = 36
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
                .liquidGlass(.superficie) // token-exempt: preview, fuera de una hoja
            Text("papel/superficieSolida")
                .font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                .padding(24).frame(maxWidth: .infinity)
                .liquidGlass(.superficieSolida)
            Text("vidrio/pastilla")
                .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.vertical, 12).frame(maxWidth: .infinity)
                .liquidGlass(.pastilla) // token-exempt: preview, fuera de una hoja
            Text("papel/pastillaSolida")
                .font(LiquidType.boton).tracking(LiquidType.botonTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.vertical, 12).frame(maxWidth: .infinity)
                .liquidGlass(.pastillaSolida)
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

#Preview("Liquid · SheetFondo (cian + indigo + sin plasta)") {
    HStack(spacing: 0) {
        ZStack {
            LiquidSheetFondo(tone: LiquidColor.cian)
            VStack {
                Text("cian")
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                Spacer()
            }
            .padding(24)
        }
        ZStack {
            LiquidSheetFondo(tone: LiquidColor.indigo)
            VStack {
                Text("indigo")
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                Spacer()
            }
            .padding(24)
        }
        ZStack {
            LiquidSheetFondo(tone: LiquidColor.cian, plasta: false)
            VStack {
                Text("plasta: false")
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                Spacer()
            }
            .padding(24)
        }
    }
    .environment(\.liquidMotionDisabled, true)
}
#endif
