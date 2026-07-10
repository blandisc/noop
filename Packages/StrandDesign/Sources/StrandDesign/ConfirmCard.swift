import SwiftUI

// MARK: - ConfirmCard — «Instrumento» confirmation (handoff entrenamiento-v4 · 5b, FER-836)
//
// The styled replacement for `.confirmationDialog`: a paper card anchored to the
// bottom edge over an ink scrim. Three rules are LAW here, not convention:
//   • The overline names the CONTEXT and what is at stake («SESIÓN · 23:41 EN CURSO»).
//   • The body states the CONCRETE consequence of confirming.
//   • A destructive action renders as a red OUTLINE — never as the filled primary —
//     and every action names what it does. «Cancelar»/«OK» do not exist in this system.

/// One action inside an `instrumentoConfirm` card. Order in the array is render order
/// (primary usually first, the "stay safe" action last).
public struct InstrumentoConfirmAction: Identifiable {
    public enum Role {
        /// Filled ink button — the safe / main path. Never destructive.
        case primary
        /// Outline button on `hairlineStrong`.
        case secondary
        /// Red outline on `critical`. ALWAYS an outline, never filled.
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
    /// 1:1 replacement for `.confirmationDialog` in the «Instrumento» language (spec 5b).
    /// - Parameters:
    ///   - title: Space Grotesk 22/700 headline.
    ///   - context: ALL-CAPS overline naming what is at stake («SESIÓN · 23:41 EN CURSO»).
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
}

private struct InstrumentoConfirmModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let context: String
    let message: String?
    let actions: [InstrumentoConfirmAction]

    @Environment(\.instrumentoTheme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if isPresented {
                        theme.ink.opacity(0.28)
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
                .animation(StrandMotion.interactive, value: isPresented)
            }
    }
}

/// The card itself — exposed for previews/tests; screens use `.instrumentoConfirm`.
public struct ConfirmCard: View {
    let title: String
    let context: String
    let message: String?
    let actions: [InstrumentoConfirmAction]
    @Binding var isPresented: Bool

    @Environment(\.instrumentoTheme) private var theme

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
                .font(InstrumentoType.groteskOverline)
                .tracking(InstrumentoType.groteskOverlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.inkTertiary)

            Text(title)
                .font(InstrumentoType.grotesk(22, weight: .bold))
                .foregroundStyle(theme.ink)
                .padding(.top, 8)

            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }

            VStack(spacing: 10) {
                ForEach(actions) { action in
                    Button {
                        isPresented = false
                        action.handler()
                    } label: {
                        Text(action.title)
                            .font(InstrumentoType.grotesk(15, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(ConfirmActionStyle(role: action.role, theme: theme))
                }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(theme.surface)
                .shadow(color: theme.ink.opacity(0.18), radius: 20, y: -12)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .stroke(theme.hairline, lineWidth: 1)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct ConfirmActionStyle: ButtonStyle {
    let role: InstrumentoConfirmAction.Role
    let theme: InstrumentoTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(role == .primary ? theme.ink : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(border, lineWidth: role == .primary ? 0 : 1.5)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var foreground: Color {
        switch role {
        case .primary:     return theme.surface
        case .secondary:   return theme.ink
        case .destructive: return theme.critical
        }
    }

    private var border: Color {
        role == .destructive ? theme.critical : theme.hairlineStrong
    }
}

// MARK: - Previews

#Preview("ConfirmCard · 3 acciones (destructiva)") {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstrumentoTheme.base.paper)
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
        .background(InstrumentoTheme.base.paper)
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
