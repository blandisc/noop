import SwiftUI

// MARK: - ConfirmCard — cristal El Eje (dialecto Entrenar de Liquid Glass; reskin FER-196)
//
// El reemplazo estilizado de `.confirmationDialog`: una tarjeta de VIDRIO anclada al borde
// inferior sobre un scrim de tinta — vidrio translúcido claro (`LiquidColor.vidrioSuperficie`
// + `.ultraThinMaterial`), canto hairline, highlight superior y una sombra que proyecta hacia
// ARRIBA. Piel El Eje sobre el mismo esqueleto de siempre: API pública y comportamiento
// intactos (FER-196, Ola 0 del épico «Entrenar en vidrio»). Tres reglas son LEY aquí, no
// convención:
//   • El overline nombra el CONTEXTO y lo que está en juego («SESIÓN · 23:41 EN CURSO»).
//   • El cuerpo dice la consecuencia CONCRETA de confirmar.
//   • Una acción destructiva se renderiza como contorno ROJO — nunca como el primario
//     relleno — y cada acción nombra lo que hace. «Cancelar»/«OK» no existen en este sistema.

/// One action inside an `instrumentoConfirm` card. Order in the array is render order
/// (primary usually first, the "stay safe" action last).
public struct InstrumentoConfirmAction: Identifiable {
    public enum Role {
        /// Verde El Eje (gradiente `verdeBotonAlto` → `verdePrimario`) — el camino
        /// seguro/principal. Nunca destructivo.
        case primary
        /// Vidrio OPACO (receta `.pastillaSolida`: borde hairline, relleno de papel —
        /// vidrio-sobre-vidrio no vale dentro de una hoja ya de cristal, ADN §11.1).
        case secondary
        /// Contorno rojo (`LiquidColor.negativo`). SIEMPRE contorno, nunca relleno.
        case destructive
    }

    public let id = UUID()
    public let title: String
    public let role: Role
    public let handler: () -> Void

    public init(_ title: String, role: Role = .secondary, handler: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.handler = handler
    }
}

public extension View {
    /// 1:1 replacement for `.confirmationDialog` in the cristal El Eje language (reskin FER-196
    /// de la spec 5b original).
    /// - Parameters:
    ///   - title: `LiquidType.displayS` — 22/700, escala con Dynamic Type.
    ///   - context: overline MAYÚSCULAS naming what is at stake («SESIÓN · 23:41 EN CURSO»).
    ///   - message: the concrete consequence of confirming — never a vague warning.
    ///   - actions: 2–3 actions; each copy names its action (never «Cancelar»/«OK»).
    func instrumentoConfirm(
        isPresented: Binding<Bool>,
        title: String,
        context: String,
        message: String? = nil,
        actions: [InstrumentoConfirmAction]
    ) -> some View {
        modifier(InstrumentoConfirmModifier(
            isPresented: isPresented, title: title, context: context,
            message: message, actions: actions
        ))
    }

    /// Nombre Liquid Glass del mismo modifier (FER-282). Misma implementación que
    /// `.instrumentoConfirm` — ConfirmCard ya es cristal El Eje (FER-196); el prefijo
    /// `instrumento*` es el nombre legado del call-site.
    func liquidConfirm(
        isPresented: Binding<Bool>,
        title: String,
        context: String,
        message: String? = nil,
        actions: [InstrumentoConfirmAction]
    ) -> some View {
        instrumentoConfirm(
            isPresented: isPresented, title: title, context: context,
            message: message, actions: actions
        )
    }
}

private struct InstrumentoConfirmModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let context: String
    let message: String?
    let actions: [InstrumentoConfirmAction]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if isPresented {
                        LiquidColor.tinta900.opacity(0.28)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture { isPresented = false }
                        ConfirmCard(
                            title: title, context: context, message: message,
                            actions: actions, isPresented: $isPresented
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(cardAnimation, value: isPresented)
            }
    }

    /// «Sin resorte» bajo Reduce Motion (FER-196): mismo `sheetDuration` (560 ms), pero
    /// `glassOut` en vez de `glassSpring` — la degradación queda DEFINIDA, no apagada.
    private var cardAnimation: Animation {
        reduceMotion || motionDisabled
            ? LiquidMotion.glassOut(LiquidMotion.sheetDuration)
            : LiquidMotion.sheet
    }
}

/// The card itself — exposed for previews/tests; screens use `.instrumentoConfirm`.
public struct ConfirmCard: View {
    let title: String
    let context: String
    let message: String?
    let actions: [InstrumentoConfirmAction]
    @Binding var isPresented: Bool

    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public init(title: String, context: String, message: String?,
                actions: [InstrumentoConfirmAction], isPresented: Binding<Bool>) {
        self.title = title
        self.context = context
        self.message = message
        self.actions = actions
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(context)
                .liquidRegla()
                .foregroundStyle(LiquidColor.tinta500)

            Text(title)
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .padding(.top, LiquidSpace.s200)

            if let message {
                Text(message)
                    .font(LiquidType.clausulaCampo)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, LiquidSpace.s150)
            }

            VStack(spacing: LiquidSpace.s250) {
                ForEach(actions) { action in
                    Button {
                        isPresented = false
                        action.handler()
                    } label: {
                        actionLabel(action)
                    }
                    .buttonStyle(.liquidPress)
                }
            }
            .padding(.top, LiquidSpace.s400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LiquidSpace.s600)
        .padding(.top, LiquidSpace.s550)
        .padding(.bottom, LiquidSpace.s550)
        .background(cardGlassBackground)
        .overlay(alignment: .top) {
            cardShape
                .stroke(LiquidColor.vidrioBordeSuperficie, lineWidth: 0.5)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Esquinas SOLO arriba (hoja anclada abajo) — `LiquidRadius.hoja` (28), el radio
    /// reservado del sistema para sheets y modales.
    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: LiquidRadius.hoja, topTrailingRadius: LiquidRadius.hoja)
    }

    /// El cristal + su sombra, sobre la forma de esquinas parciales que `.liquidGlass(_:)` no
    /// expone: mismo split nativo-vs-imitación que `LiquidModulo`/`LiquidTabBar` (vidrio NATIVO
    /// en iOS 26 con refracción/lensing reales; `.ultraThinMaterial` + relleno + highlight
    /// superior 0.8→0.35 antes, y en renders/previews congelados). La sombra usa la silueta
    /// pública `liquidShadow(_:silhouette:)` — un `.shadow` sobre el contenido proyectaría el
    /// rectángulo del material, no la silueta (mismo defecto documentado en
    /// `LiquidGlassRecipes.swift`) — con `y` NEGATIVA porque esta hoja proyecta hacia ARRIBA
    /// (token-exempt: `LiquidElevation` solo modela sombras hacia abajo).
    private var cardGlassBackground: some View {
        cardGlassFill
            .liquidShadow([.init(color: LiquidColor.tinta900.opacity(0.18), radius: 20, y: -12)],
                          silhouette: cardShape)
            .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var cardGlassFill: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
            Color.clear
                .background { cardShape.fill(LiquidColor.vidrioSuperficie) }
                .glassEffect(.regular, in: cardShape)
        } else {
            ZStack {
                cardShape.fill(.ultraThinMaterial)
                cardShape.fill(LiquidColor.vidrioSuperficie)
            }
            .overlay {
                cardShape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.8), location: 0),
                                .init(color: .white.opacity(0.35), location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5)
                    .blur(radius: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: InstrumentoConfirmAction) -> some View {
        let text = Text(action.title)
            .font(LiquidType.boton)
            .tracking(LiquidType.botonTracking)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LiquidSpace.s550)
            .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget)

        switch action.role {
        case .primary:
            text
                .foregroundStyle(LiquidColor.tintaSobreVerde)
                .background {
                    Capsule().fill(LinearGradient(
                        colors: [LiquidColor.verdeBotonAlto, LiquidColor.verdePrimario],
                        startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    // inset 0 1px 1px blanco .35 — la luz entrando por el canto superior
                    // (misma receta que `LiquidGlassButton.primary`).
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.35), location: 0),
                                    .init(color: .white.opacity(0), location: 0.5),
                                ],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .clipShape(Capsule())
                .liquidShadow([.init(color: LiquidColor.verdePrimario.opacity(0.30), radius: 7, y: 5)])
        case .secondary:
            text
                .foregroundStyle(LiquidColor.tinta900)
                // OPACO a propósito (no-sheet-glass, ADN §11.1): la ConfirmCard YA es una
                // hoja de vidrio — un botón de vidrio adentro sería vidrio-sobre-vidrio.
                .liquidGlass(.pastillaSolida)
        case .destructive:
            text
                .foregroundStyle(LiquidColor.negativo)
                .overlay {
                    Capsule().strokeBorder(LiquidColor.negativo, lineWidth: 1.5)
                }
        }
    }
}

// MARK: - Previews

#Preview("ConfirmCard · 3 acciones (destructiva)") {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColor.papelGradient)
        .instrumentoConfirm(
            isPresented: .constant(true),
            title: "¿Terminar la sesión?",
            context: "SESIÓN · 23:41 EN CURSO",
            message: "Se guardan las 8 series registradas. Las 9 que faltan no cuentan.",
            actions: [
                .init("Guardar y terminar", role: .primary),
                .init("Seguir entrenando", role: .secondary),
                .init("Descartar la sesión", role: .destructive)
            ]
        )
}

#Preview("ConfirmCard · 2 acciones") {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColor.papelGradient)
        .instrumentoConfirm(
            isPresented: .constant(true),
            title: "¿Salir sin guardar?",
            context: "RUTINA · CAMBIOS SIN GUARDAR",
            message: "Los 3 cambios de hoy se pierden al salir.",
            actions: [
                .init("Seguir editando", role: .primary),
                .init("Salir sin guardar", role: .destructive)
            ]
        )
}
