import SwiftUI

// MARK: - InputCard — «Instrumento» text prompt (handoff entrenamiento-v4 · 5c, FER-836)
//
// The styled replacement for a text-field `.alert` (Nueva carpeta / Renombrar carpeta):
// a centered 310pt paper card over an ink scrim, so the keyboard rises underneath it.
// Same copy law as ConfirmCard: the CTA names the action, the dismiss is «Ahora no» —
// never «Cancelar»/«OK». The CTA is disabled while the field is empty.

public extension View {
    /// Presents a centered «Instrumento» input card (spec 5c).
    /// - Parameters:
    ///   - text: the edited value; prefill for a rename, empty for a create.
    ///   - context: ALL-CAPS overline naming the context («MIS RUTINAS»).
    ///   - cta: the confirming action's name («Crear», «Renombrar»).
    ///   - dismissLabel: the safe exit — defaults to «Ahora no».
    ///   - onCommit: called with the trimmed text when the CTA fires.
    func instrumentoInput(
        isPresented: Binding<Bool>,
        text: Binding<String>,
        title: String,
        context: String,
        placeholder: String = "",
        cta: String,
        dismissLabel: String = "Ahora no",
        onCommit: @escaping (String) -> Void
    ) -> some View {
        modifier(InstrumentoInputModifier(
            isPresented: isPresented, text: text, title: title, context: context,
            placeholder: placeholder, cta: cta, dismissLabel: dismissLabel, onCommit: onCommit
        ))
    }
}

private struct InstrumentoInputModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var text: String
    let title: String
    let context: String
    let placeholder: String
    let cta: String
    let dismissLabel: String
    let onCommit: (String) -> Void

    @Environment(\.instrumentoTheme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if isPresented {
                        theme.ink.opacity(0.28)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture { isPresented = false }
                        InputCard(
                            text: $text, title: title, context: context,
                            placeholder: placeholder, cta: cta, dismissLabel: dismissLabel,
                            isPresented: $isPresented, onCommit: onCommit
                        )
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
                .animation(StrandMotion.interactive, value: isPresented)
            }
    }
}

/// The card itself — exposed for previews/tests; screens use `.instrumentoInput`.
struct InputCard: View {
    @Binding var text: String
    let title: String
    let context: String
    let placeholder: String
    let cta: String
    let dismissLabel: String
    @Binding var isPresented: Bool
    let onCommit: (String) -> Void

    @Environment(\.instrumentoTheme) private var theme
    @FocusState private var focused: Bool

    init(text: Binding<String>, title: String, context: String,
                placeholder: String, cta: String, dismissLabel: String,
                isPresented: Binding<Bool>, onCommit: @escaping (String) -> Void) {
        self._text = text
        self.title = title
        self.context = context
        self.placeholder = placeholder
        self.cta = cta
        self.dismissLabel = dismissLabel
        self._isPresented = isPresented
        self.onCommit = onCommit
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(context)
                .font(InstrumentoType.groteskOverline)
                .tracking(InstrumentoType.groteskOverlineTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.inkTertiary)

            Text(title)
                .font(InstrumentoType.grotesk(20, weight: .bold))
                .foregroundStyle(theme.ink)
                .padding(.top, 8)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(StrandFont.scaled(15))
                .foregroundStyle(theme.ink)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.paper))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focused ? theme.ink : theme.hairlineStrong, lineWidth: 1.5)
                )
                .padding(.top, 14)

            HStack(spacing: 10) {
                Button(dismissLabel) { isPresented = false }
                    .buttonStyle(InputCardButtonStyle(kind: .outline, theme: theme))
                Button(cta, action: commit)
                    .buttonStyle(InputCardButtonStyle(kind: .filled, theme: theme))
                    .disabled(trimmed.isEmpty)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 310)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.surface)
                .strandElevation(.modal, ink: theme.ink)
        )
        .onAppear { focused = true }
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        // onCommit BEFORE dismissing: item-style `isPresented` bindings often clear the state
        // the commit handler reads (e.g. the folder being renamed).
        onCommit(trimmed)
        isPresented = false
    }
}

private struct InputCardButtonStyle: ButtonStyle {
    enum Kind { case filled, outline }
    let kind: Kind
    let theme: InstrumentoTheme

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(InstrumentoType.grotesk(14, weight: .bold))
            .foregroundStyle(kind == .filled ? theme.surface : theme.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(kind == .filled ? theme.ink : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(kind == .outline ? theme.hairlineStrong : .clear, lineWidth: 1.5)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : StrandOpacity.dim)
    }
}

// MARK: - Previews

#Preview("InputCard · vacía (CTA deshabilitada)") {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstrumentoTheme.base.paper)
        .instrumentoInput(
            isPresented: .constant(true),
            text: .constant(""),
            title: "Nueva carpeta",
            context: "MIS RUTINAS",
            placeholder: "Nombre de la carpeta",
            cta: "Crear"
        ) { _ in }
}

#Preview("InputCard · con texto") {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(InstrumentoTheme.base.paper)
        .instrumentoInput(
            isPresented: .constant(true),
            text: .constant("Empuje y jalón"),
            title: "Renombrar carpeta",
            context: "MIS RUTINAS",
            cta: "Renombrar"
        ) { _ in }
}
