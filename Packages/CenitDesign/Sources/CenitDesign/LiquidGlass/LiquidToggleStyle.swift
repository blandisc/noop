import SwiftUI

// MARK: - LiquidToggleStyle (FER-293)
//
// Gemelo Liquid de `InstrumentoToggleStyle`: misma geometría 51×31 / knob 27, hit ≥44, pero
// con tokens El Eje (`tinta900` on / `tinta10` off / knob `papelTarjeta`). Es cromo — sin
// color de acento — para que el dato con color de la hoja no compita con el switch.
// Call sites: `.toggleStyle(.liquid)`.

public struct LiquidToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        LiquidToggleBody(configuration: configuration)
    }
}

public extension ToggleStyle where Self == LiquidToggleStyle {
    static var liquid: LiquidToggleStyle { LiquidToggleStyle() }
}

private struct LiquidToggleBody: View {
    let configuration: ToggleStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackW: CGFloat = 51
    private let trackH: CGFloat = 31
    private let knobD: CGFloat = 27

    var body: some View {
        let on = configuration.isOn
        HStack(spacing: LiquidSpace.s200) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(on ? LiquidColor.tinta900 : LiquidColor.tinta10)
                    .frame(width: trackW, height: trackH)
                Circle()
                    .fill(LiquidColor.papelTarjeta)
                    .shadow(color: LiquidColor.tinta900.opacity(0.20), radius: 1, x: 0, y: 1)
                    .frame(width: knobD, height: knobD)
                    .offset(x: on ? trackW - knobD - 2 : 2)
            }
            .frame(width: trackW, height: trackH)
            .opacity(isEnabled ? 1 : CenitOpacity.dim)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: on)
            .frame(height: LiquidControl.hitTarget)
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        }
    }
}

#if DEBUG
#Preview("LiquidToggleStyle") {
    struct Demo: View {
        @State private var on = true
        @State private var off = false
        var body: some View {
            VStack(spacing: LiquidSpace.s400) {
                Toggle(isOn: $on) {
                    Text("Progresión automática").font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta900)
                }
                .toggleStyle(.liquid)
                Toggle(isOn: $off) {
                    Text("Guardar en la rutina").font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta900)
                }
                .toggleStyle(.liquid)
                Toggle(isOn: .constant(false)) {
                    Text("No disponible").font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta900)
                }
                .toggleStyle(.liquid)
                .disabled(true)
            }
            .padding(LiquidSpace.s600)
            .background(LiquidColor.fondoGradient)
        }
    }
    return Demo()
}
#endif
