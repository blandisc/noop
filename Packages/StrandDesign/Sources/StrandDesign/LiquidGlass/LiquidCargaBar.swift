import SwiftUI

// MARK: - Liquid Glass · CargaBar (handoff §5.5)
//
// Pastilla de balance de carga: vidrio/pastilla + e/0, fila [label · barra · status].
// La barra son 4 segmentos pill (40 / 25 / 10 / resto, gap 2); solo el segmento activo
// (`zone`) lleva el gradiente del estado; el knob (blanco, borde tinta/900) marca `pos` %.
// Motion: knob y segmento activo se animan a su posición al entrar (dur/gentle).

public struct LiquidCargaBar: View {
    private let label: String
    private let pos: Double
    private let zone: Int
    private let status: String
    private let state: LiquidSignalState

    @State private var shownPos: Double = 50
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// - Parameters:
    ///   - pos: posición del knob, 0–100.
    ///   - zone: segmento activo, 0–3.
    public init(label: String = "CARGA", pos: Double, zone: Int, status: String,
                state: LiquidSignalState = .ok) {
        self.label = label
        self.pos = pos
        self.zone = zone
        self.status = status
        self.state = state
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(label)
                .font(LiquidType.cargaLabel).tracking(LiquidType.cargaLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            bar
            Text(status)
                .font(LiquidType.cargaStatus).tracking(LiquidType.cargaStatusTracking)
                .foregroundStyle(state.status)
                .lineLimit(1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, LiquidSpace.s400)
        .liquidGlass(.pastilla)
        .onAppear {
            guard !entered, !motionDisabled else { return }
            entered = true
            if reduceMotion {
                shownPos = clampedPos
            } else {
                withAnimation(LiquidMotion.ringProgress) { shownPos = clampedPos }
            }
        }
    }

    private var clampedPos: Double {
        min(100, max(0, pos))
    }

    private var bar: some View {
        // Con el motion congelado (previews/renders) knob y segmento van ya a su lugar.
        let effectivePos = motionDisabled ? clampedPos : shownPos
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: LiquidSpace.s050) {
                    segment(0).frame(width: w * 0.40)
                    segment(1).frame(width: w * 0.25)
                    segment(2).frame(width: w * 0.10)
                    segment(3)
                }
                .padding(.vertical, 3)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(LiquidColor.tinta900, lineWidth: 2))
                    .frame(width: 10, height: 10)
                    .offset(x: w * effectivePos / 100 - 5)
            }
        }
        .frame(height: 10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func segment(_ index: Int) -> some View {
        let active = index == zone && (entered || motionDisabled)
        Capsule()
            .fill(active
                  ? AnyShapeStyle(LinearGradient(
                        colors: [state.tone.opacity(0.9), state.tone.opacity(0.65)],
                        startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(LiquidColor.tinta7))
            .overlay(Capsule().strokeBorder(
                Color.white.opacity(active ? 0.5 : 0.4), lineWidth: 0.5))
            .shadow(color: active ? state.tone.opacity(0.35) : .clear, radius: 5)
            .animation(reduceMotion || motionDisabled ? nil : LiquidMotion.ringProgress,
                       value: entered)
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Liquid · CargaBar") {
    VStack(spacing: LiquidSpace.s400) {
        LiquidCargaBar(pos: 51.5, zone: 1, status: "EN EQUILIBRIO · 1.03")
        LiquidCargaBar(pos: 84, zone: 3, status: "SOBRECARGA · 1.62", state: .atencion)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
