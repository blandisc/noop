import SwiftUI

// MARK: - Liquid Glass · SignalOrb (handoff §5.2)
//
// Orbe esférico de señal (fila superior de Hoy): esfera de vidrio 56 (inset 4 del lienzo
// 64) + anillo de progreso r29 sw3.5 + punto marcador en el extremo + icono 18 tinta/900,
// con label micro y caption de estado debajo.
//
// Geometría del anillo: arranca a −245° (las 7:30 de un velocímetro) y barre
// `progress × 360°` en sentido horario; el punto marcador viaja EN el extremo del arco
// («en el extremo del progreso», §5.2). El prototipo HTML rotaba el arco a −155° pero
// calculaba el punto con −245° — seguimos la fórmula documentada y la prosa, de modo que
// arco y punto coinciden (desviación anotada en docs/design-system/LIQUID-GLASS.md).
//
// Motion: progreso y punto se animan a su valor al entrar (ring progress · dur/gentle ·
// glass-out); bajo Reduce Motion aparecen ya colocados.

public struct LiquidSignalOrb: View {
    private let label: String
    private let caption: String
    private let progress: Double
    private let icon: LiquidIcon.Glyph
    private let state: LiquidSignalState
    private let action: (() -> Void)?

    @State private var shownProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public init(label: String, caption: String, progress: Double,
                icon: LiquidIcon.Glyph, state: LiquidSignalState,
                action: (() -> Void)? = nil) {
        self.label = label
        self.caption = caption
        self.progress = progress
        self.icon = icon
        self.state = state
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { column }.buttonStyle(.liquidPress)
        } else {
            column
        }
    }

    private var column: some View {
        VStack(spacing: 5) {
            orb
            Text(label).liquidMicro().foregroundStyle(LiquidColor.tinta900)
                .multilineTextAlignment(.center)
            Text(caption).font(LiquidType.microEstado).foregroundStyle(state.caption)
                .padding(.top, -3)
        }
        .onAppear {
            guard shownProgress == 0, !motionDisabled else { return }
            if reduceMotion {
                shownProgress = clamped
            } else {
                withAnimation(LiquidMotion.ringProgress) { shownProgress = clamped }
            }
        }
    }

    private var clamped: Double {
        min(1, max(0.02, progress))
    }

    private var orb: some View {
        // Con el motion congelado (previews/renders) el anillo se pinta ya en su valor.
        let displayed = motionDisabled ? clamped : shownProgress
        return ZStack {
            LiquidSphere(tone: state.tone)
                .padding(4)
                .liquidShadow(LiquidElevation.e2(tone: state.tone))
            // Track + progreso, r29 de un lienzo de 64 (relación 29/32 del radio medio).
            OrbRing().stroke(LiquidColor.tinta10, lineWidth: 3.5)
            OrbRing()
                .trim(from: 0, to: displayed)
                .stroke(state.ring, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(orbStartAngle))
            OrbMarkerDot(progress: displayed)
                .fill(LiquidColor.tinta900)
            OrbMarkerDot(progress: displayed)
                .stroke(Color.white, lineWidth: 1.4)
            LiquidIcon(icon, size: 18).foregroundStyle(LiquidColor.tinta900)
        }
        .frame(width: 64, height: 64)
    }
}

/// Arranque del arco: −245° desde las 3 en punto (≈ las 7:30 del dial).
private let orbStartAngle: Double = -245

/// El círculo del anillo a r = 29/32 del radio del lienzo (64 → 29).
private struct OrbRing: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 * (29.0 / 32.0)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// El punto marcador (r 3.4) viajando por el arco — Shape con `animatableData` para que
/// el punto recorra el anillo (no la cuerda) cuando el progreso anima.
private struct OrbMarkerDot: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2 * (29.0 / 32.0)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let angle = (orbStartAngle + progress * 360) * .pi / 180
        let center = CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
        let dotR: CGFloat = 3.4
        return Path(ellipseIn: CGRect(x: center.x - dotR, y: center.y - dotR,
                                      width: dotR * 2, height: dotR * 2))
    }
}

#if DEBUG
#Preview("Liquid · SignalOrb") {
    HStack(spacing: 53) {
        LiquidSignalOrb(label: "AUTONÓMICO", caption: "EN TU RANGO", progress: 0.35,
                        icon: .ondaSenal, state: .ok)
        LiquidSignalOrb(label: "SUEÑO", caption: "EN TU RANGO", progress: 0.43,
                        icon: .lunaSenal, state: .ok)
        LiquidSignalOrb(label: "TÉRMICO", caption: "FUERA DE RANGO", progress: 0.72,
                        icon: .termoSenal, state: .atencion)
    }
    .padding(LiquidSpace.s800)
    .background(LiquidColor.papelGradient)
}
#endif
