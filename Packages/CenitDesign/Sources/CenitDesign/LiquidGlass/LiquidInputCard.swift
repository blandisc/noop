import SwiftUI

// MARK: - LiquidInputCard — diálogo de texto El Eje (FER-292)
//
// Reemplazo de `.instrumentoInput` / `InputCard`: misma firma pública, piel de cristal
// El Eje (anatomía de `ConfirmCard`: regla · displayS · campo · botones pill). Tarjeta
// 310 centrada sobre scrim tinta900.28 — el teclado sube por debajo.

public extension View {
    /// Presenta un diálogo de texto centrado en cristal El Eje (misma firma que `.instrumentoInput`).
    func liquidInput(
        isPresented: Binding<Bool>,
        text: Binding<String>,
        title: String,
        context: String,
        placeholder: String = "",
        cta: String,
        dismissLabel: String = "Ahora no",
        onCommit: @escaping (String) -> Void
    ) -> some View {
        modifier(LiquidInputModifier(
            isPresented: isPresented, text: text, title: title, context: context,
            placeholder: placeholder, cta: cta, dismissLabel: dismissLabel, onCommit: onCommit
        ))
    }
}

private struct LiquidInputModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var text: String
    let title: String
    let context: String
    let placeholder: String
    let cta: String
    let dismissLabel: String
    let onCommit: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if isPresented {
                        LiquidColor.tinta900.opacity(0.28)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture { isPresented = false }
                        LiquidInputCard(
                            text: $text, title: title, context: context,
                            placeholder: placeholder, cta: cta, dismissLabel: dismissLabel,
                            isPresented: $isPresented, onCommit: onCommit
                        )
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
                .animation(cardAnimation, value: isPresented)
            }
    }

    private var cardAnimation: Animation {
        reduceMotion || motionDisabled
            ? LiquidMotion.glassOut(LiquidMotion.sheetDuration)
            : LiquidMotion.sheet
    }
}

/// La tarjeta misma — pantallas usan `.liquidInput`.
public struct LiquidInputCard: View {
    @Binding var text: String
    let title: String
    let context: String
    let placeholder: String
    let cta: String
    let dismissLabel: String
    @Binding var isPresented: Bool
    let onCommit: (String) -> Void

    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .footnote) private var fieldSize = LiquidType.lecturaHojaBase

    public init(text: Binding<String>, title: String, context: String,
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

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: fieldSize))
                .foregroundStyle(LiquidColor.tinta900)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
                .padding(.horizontal, LiquidSpace.s300)
                .frame(height: LiquidControl.hitTarget)
                .background(
                    RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                        .fill(LiquidColor.papelTarjeta)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                        .stroke(focused ? LiquidColor.tinta900 : LiquidColor.tinta10, lineWidth: 1.5)
                )
                .padding(.top, LiquidSpace.handoff14)

            HStack(spacing: LiquidSpace.s250) {
                LiquidGlassButton(dismissLabel, variant: .solida, expands: true) {
                    isPresented = false
                }
                LiquidGlassButton(cta, variant: .primary, expands: true, action: commit)
                    .disabled(trimmed.isEmpty)
                    .opacity(trimmed.isEmpty ? CenitOpacity.dim : 1)
            }
            .padding(.top, LiquidSpace.s400)
        }
        .padding(.horizontal, LiquidSpace.s600)
        .padding(.vertical, LiquidSpace.s550)
        .frame(width: 310)
        .liquidGlass(.dialogo)
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

#if DEBUG
#Preview("LiquidInput · vacía (CTA deshabilitada)") {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColor.fondoGradient)
        .liquidInput(
            isPresented: .constant(true),
            text: .constant(""),
            title: "Nueva carpeta",
            context: "TU PLAN",
            placeholder: "Nombre de la carpeta",
            cta: "Crear"
        ) { _ in }
}

#Preview("LiquidInput · con texto") {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColor.fondoGradient)
        .liquidInput(
            isPresented: .constant(true),
            text: .constant("Empuje y jalón"),
            title: "Renombrar carpeta",
            context: "TU PLAN",
            cta: "Renombrar"
        ) { _ in }
}
#endif
