import SwiftUI
import StrandDesign

// MARK: - Custom numeric keypad for the strength session (FER-716)
//
// The «Flujo Entrenar v3» handoff replaces the system keyboard with a purpose-built pad: an accessory
// bar of session actions over a 3-column keycap grid. It edits the ACTIVE cell (weight / reps) directly,
// no modal «Foco». Keycaps calque UIKit — the ONE white surface the paper language allows (`keyCap`),
// each with a hairline-thin drop. The «Siguiente» accessory is the confirmation affordance (the ink
// keyboard idiom's blue «return»), so it carries the one accent (`dataRecovery`).

struct SessionKeypad: View {
    let theme: InstrumentoTheme
    /// Label for the ± quick-step pill (metric «±2,5», imperial «±5»).
    let stepLabel: String
    /// Whether «copiar anterior» is available (there's a «last time» to copy).
    let canCopyPrevious: Bool
    /// Whether the plate-math «⛓ discos» accessory is live (F5). Placeholder-disabled until then.
    var platesEnabled: Bool = false

    let onDigit: (Character) -> Void
    let onComma: () -> Void
    let onBackspace: () -> Void
    let onNext: () -> Void
    let onCopyPrevious: () -> Void
    let onStep: () -> Void
    /// Opens the RPE picker. nil until RPE capture lands (FER-815) → the «RPE ▾» accessory is hidden, not
    /// shown disabled (no dead buttons).
    var onRPE: (() -> Void)? = nil
    var onPlates: () -> Void = {}
    /// Hides the keypad without registering anything (canvas pass 2026-07-15) — every keystroke has
    /// already committed live to the model, so dismissing loses nothing.
    var onHide: () -> Void = {}
    /// Pausa/reanuda sin cerrar el teclado (FER-86). El teclado OCUPA el sitio de la barra de estado,
    /// que es donde vive la pausa; sin este accesorio, el control desaparece justo mientras registras
    /// una serie — que es cuando te interrumpen. `nil` lo oculta, nunca lo deshabilita.
    var onPause: (() -> Void)? = nil
    /// Qué cara pone el accesorio: ❚❚ para pausar, ▶ para reanudar.
    var isPaused: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            accessoryBar
            Rectangle().fill(theme.hairline).frame(height: 1)
            keys
        }
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: Accessory bar

    private var accessoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Hide-keyboard at the far LEFT (mirror of «Next»), subordinated ink — never reads as
                // «register». VoiceOver: «Hide keyboard», not «Done»/«Close».
                Button(action: onHide) {
                    Image(systemName: "chevron.down")
                        .font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.inkSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hide keyboard"))
                if let onPause {
                    Button(action: onPause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(StrandFont.glyph(.inline, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPaused ? Text("Resume session") : Text("Pause session"))
                }
                pill(String(localized: "copy last"), enabled: canCopyPrevious, action: onCopyPrevious)
                pill(stepLabel, action: onStep)
                // FER-815: each accessory appears only when its function exists — never a permanent
                // disabled placeholder. RPE shows once a handler is wired; plates once the math is on.
                if let onRPE { pill("RPE ▾", action: onRPE) }
                // r16: fuera el glifo «⛓» (tofu en Grotesk) — la pastilla queda en el puro «discos».
                if platesEnabled { pill(String(localized: "plates"), action: onPlates) }
                Spacer(minLength: 4)
                Button(action: onNext) {
                    Text("Next").font(StrandFont.subhead).fontWeight(.semibold)
                        .foregroundStyle(theme.dataRecovery)
                        .padding(.horizontal, 12).frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Next field"))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func pill(_ text: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(text).font(StrandFont.caption)
                .foregroundStyle(enabled ? theme.ink : theme.inkMuted)
                .padding(.horizontal, 11).frame(height: 34)
                .background(Capsule().fill(Color.clear))
                .overlay(Capsule().strokeBorder(enabled ? theme.hairlineStrong : theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Keys

    private var keys: some View {
        VStack(spacing: 6) {
            ForEach(keyRows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 22)   // bottom respects the home indicator
    }

    private var keyRows: [[String]] {
        [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [",", "0", "⌫"]]
    }

    @ViewBuilder private func keyButton(_ key: String) -> some View {
        switch key {
        case ",":
            flatKey(",") { onComma() }
        case "⌫":
            flatKey("⌫", size: 17) { onBackspace() }
        default:
            Button { if let c = key.first { onDigit(c) } } label: {
                Text(key)
                    .font(.system(size: 20)).foregroundStyle(theme.ink) // token-exempt: numeral de tecla del keypad
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.keyCap)) // token-exempt: geometría de dato
                    .shadow(color: theme.ink.opacity(0.08), radius: 0, x: 0, y: 1) // token-exempt: sombra sutil <0.10
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(key))
        }
    }

    private func flatKey(_ glyph: String, size: CGFloat = 20, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: size)).foregroundStyle(theme.inkSecondary) // token-exempt: tamaño de tecla derivado (parámetro)
                .frame(maxWidth: .infinity).frame(height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(glyph == "⌫" ? "Delete" : glyph))
    }
}

#if DEBUG
#Preview("SessionKeypad") {
    let t = InstrumentoTheme.base
    return VStack {
        Spacer()
        SessionKeypad(theme: t, stepLabel: "±2,5", canCopyPrevious: true,
                      onDigit: { _ in }, onComma: {}, onBackspace: {}, onNext: {},
                      onCopyPrevious: {}, onStep: {})
    }
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
