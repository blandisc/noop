import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - «Instrumento» native-control styling (FER-408)
//
// The system switch reads as «chrome blanco suelto» on the warm Instrumento paper: a pure-white
// knob and a green/blue `.tint` that only paints the ON track. This `ToggleStyle` re-skins the
// switch in the theme's INK + warm paper so it looks of-the-house and never competes with the datum
// («color solo en el dato»): ON track = `ink`, OFF track = `hairlineStrong`, knob = `surface` (warm
// paper, never pure white). It reads `\.instrumentoTheme`, so it stays correct under any injected
// theme (the app now anchors to `.base` at every hour — FER-398).
//
// Accessibility: a custom `ToggleStyle` keeps the underlying `Toggle`'s switch semantics — VoiceOver
// still announces the label + on/off and toggles on activate; the visual just slides the knob. The
// hit area is padded to ≥44pt tall.
//
// The segmented control is tinted via `configureInstrumentoControlAppearance()` (UIKit appearance —
// `.pickerStyle(.segmented)` ignores SwiftUI `.tint`). Steppers keep the native `.tint`,
// standardized to `inkSecondary`.

#if canImport(UIKit) && os(iOS)
/// Re-skins the native `UISegmentedControl` to warm paper/ink (FER-408). Call once at app launch.
/// Lives in StrandDesign so the app shell never spells `InstrumentoTheme` at the call site (FER-282).
@MainActor public func configureInstrumentoControlAppearance() {
    let t = InstrumentoTheme.base
    let seg = UISegmentedControl.appearance()
    seg.selectedSegmentTintColor = UIColor(t.surface)        // warm pill, never pure white
    seg.backgroundColor = UIColor(t.hairline)                // warm track behind the segments
    seg.setTitleTextAttributes([.foregroundColor: UIColor(t.inkSecondary)], for: .normal)
    seg.setTitleTextAttributes([.foregroundColor: UIColor(t.ink)], for: .selected)
}
#endif

public struct InstrumentoToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        InstrumentoToggleBody(configuration: configuration)
    }
}

/// Convenience so call sites read `.toggleStyle(.instrumento)`.
public extension ToggleStyle where Self == InstrumentoToggleStyle {
    static var instrumento: InstrumentoToggleStyle { InstrumentoToggleStyle() }
}

private struct InstrumentoToggleBody: View {
    let configuration: ToggleStyle.Configuration
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    // Standard iOS switch measures, so the re-skin sits exactly where the native one did.
    private let trackW: CGFloat = 51
    private let trackH: CGFloat = 31
    private let knobD: CGFloat = 27

    var body: some View {
        let on = configuration.isOn
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(on ? theme.ink : theme.hairlineStrong)
                    .frame(width: trackW, height: trackH)
                Circle()
                    .fill(theme.surface)
                    // A hairline ring on the OFF knob, where knob (paper) and track (warm grey) are
                    // close in lightness; ON the dark ink track gives plenty of contrast on its own.
                    .overlay(Circle().strokeBorder(theme.hairline, lineWidth: on ? 0 : 0.5))
                    .frame(width: knobD, height: knobD)
                    .offset(x: on ? trackW - knobD - 2 : 2)
            }
            .frame(width: trackW, height: trackH)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: on)
            .frame(height: 44)               // ≥44pt tap target without growing the visual
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        }
    }
}

#if DEBUG
#Preview("InstrumentoToggleStyle") {
    struct Demo: View {
        @State private var on = true
        @State private var off = false
        var body: some View {
            VStack(spacing: 18) {
                Toggle(isOn: $on) { Text("Guardar en Salud").font(StrandFont.body) }
                    .toggleStyle(.instrumento)
                Toggle(isOn: $off) { Text("Sondas 5/MG").font(StrandFont.body) }
                    .toggleStyle(.instrumento)
                Toggle(isOn: .constant(false)) { Text("Opción no disponible").font(StrandFont.body) }
                    .toggleStyle(.instrumento)
                    .disabled(true)
            }
            .padding(20)
            .foregroundStyle(InstrumentoTheme.base.ink)
            .background(InstrumentoTheme.base.paper)
            .instrumentoTheme(.base)
        }
    }
    return Demo()
}
#endif
