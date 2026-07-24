import SwiftUI

// MARK: - Liquid Glass · CargaBar (handoff §5.5 · FER-1045)
//
// Pastilla de balance de carga: vidrio/pastilla + e/0, fila [label · barra · status].
// La barra son 4 segmentos pill (40 / 25 / 10 / resto, gap 2); solo el segmento activo
// (`zone`) lleva el gradiente del estado; el knob (blanco, borde tinta/900) marca `pos` %.
// Motion: knob y segmento activo se animan a su posición al entrar (dur/gentle).
//
// `.calibrando` (FER-1045): sin knob, 4 segmentos inactivos, status en tinta/500 — el
// motor todavía no tiene ACWR para este usuario.

/// El modo de la barra: con medición (knob en `pos` 0–100, banda activa `zone` 0–3) o
/// calibrando (sin knob ni banda).
public enum LiquidCargaModo: Sendable, Equatable {
    case medida(pos: Double, zone: Int)
    case calibrando
}

public struct LiquidCargaBar: View {
    private let label: String
    private let modo: LiquidCargaModo
    private let status: String
    private let ratio: String?
    private let state: LiquidSignalState
    private let hint: String?
    private let action: (() -> Void)?

    @State private var shownPos: Double = 50
    @State private var entered = false
    @State private var haloOut = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// `ratio` es el DATO («1.03») separado del rótulo (`status` = «EN EQUILIBRIO»):
    /// jerarquía de dato de la pasada UI /inject.
    public init(label: String = "CARGA", modo: LiquidCargaModo, status: String,
                ratio: String? = nil, state: LiquidSignalState = .ok,
                hint: String? = nil, action: (() -> Void)? = nil) {
        self.label = label
        self.modo = modo
        self.status = status
        self.ratio = ratio
        self.state = state
        self.hint = hint
        self.action = action
    }

    /// Conveniencia con la firma del contrato del handoff (modo medido).
    public init(label: String = "CARGA", pos: Double, zone: Int, status: String,
                state: LiquidSignalState = .ok, action: (() -> Void)? = nil) {
        self.init(label: label, modo: .medida(pos: pos, zone: zone), status: status,
                  ratio: nil, state: state, action: action)
    }

    public var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.liquidPress)
                .accessibilityLabel(Self.a11yLabel(label: label, status: status, ratio: ratio))
                .accessibilityHint(Text(verbatim: hint ?? ""))
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.a11yLabel(label: label, status: status, ratio: ratio))
        }
    }

    /// «{label}: {status}[, {ratio}]» — el contrato de VoiceOver de la barra: el ratio
    /// es el dato protagonista y también se ESCUCHA (revote /inject).
    static func a11yLabel(label: String, status: String, ratio: String? = nil) -> String {
        ratio.map { "\(label): \(status), \($0)" } ?? "\(label): \(status)"
    }

    private var row: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(label)
                .font(LiquidType.cargaLabel).tracking(LiquidType.cargaLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            bar
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                // Rótulo en tinta; el NÚMERO es el dato y lleva el tono (pasada UI).
                Text(status)
                    .font(LiquidType.cargaStatus).tracking(LiquidType.cargaStatusTracking)
                    .foregroundStyle(calibrando ? LiquidColor.tinta500 : LiquidColor.tinta700)
                    // «EN EQUILIBRIO» + ratio no caben a 402 pt: el rótulo cede tamaño
                    // antes que truncarse con elipsis (defecto visto en render /inject).
                    .minimumScaleFactor(0.8)
                if let ratio {
                    Text(ratio)
                        .font(LiquidType.cargaRatio)
                        .foregroundStyle(state.status)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, LiquidSpace.s400)
        .liquidGlass(.pastilla)
        // Área tocable ≥ 44 pt sin engordar el vidrio (pasada UX).
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onAppear {
            guard case .medida = modo, !entered, !motionDisabled else { return }
            entered = true
            if reduceMotion {
                shownPos = clampedPos
                haloOut = true
            } else {
                withAnimation(LiquidMotion.ringProgress) { shownPos = clampedPos }
                withAnimation(LiquidMotion.glassOut(LiquidMotion.gentle)
                    .delay(LiquidMotion.gentle)) { haloOut = true }
            }
        }
    }

    private var calibrando: Bool {
        modo == .calibrando
    }

    private var clampedPos: Double {
        guard case .medida(let pos, _) = modo else { return 50 }
        return min(100, max(0, pos))
    }

    private var zone: Int? {
        guard case .medida(_, let zone) = modo else { return nil }
        return zone
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
                if !calibrando {
                    // Halo de llegada (detalle fino /inject): un pulso único al asentarse.
                    // Revote /inject: el halo habla en el tono del ESTADO, no siempre verde.
                    Circle()
                        .stroke(state.tone, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                        .scaleEffect(haloOut ? 2.6 : 0.8)
                        .opacity(haloOut ? 0 : 0.55)
                        .offset(x: w * effectivePos / 100 - 5)
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(LiquidColor.tinta900, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .offset(x: w * effectivePos / 100 - 5)
                }
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
            // Glow del segmento como geometría (regla del sistema: nada de .shadow a mano).
            .liquidShadow(active ? [.init(color: state.tone.opacity(0.35), radius: 5, y: 0)] : [],
                          silhouette: Capsule())
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
        LiquidCargaBar(modo: .calibrando, status: "CALIBRANDO")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
