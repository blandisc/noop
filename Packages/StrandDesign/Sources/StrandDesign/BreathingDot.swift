import SwiftUI

// MARK: - Punto que respira (handoff «Hoy» 2026-07 · FER-709)
//
// The one live marker of the evolved «Hoy» language: a data-colored dot sitting in a small
// "moat" of paper, with a halo that breathes on the shared physiological cadence
// (`StrandMotion.breathe`, 3.2 s). Movement is reserved for what is alive (the «now», a live
// BPM, the boundary of a rule) — everything else on the screen is still. Static under
// Reduce Motion.

public struct BreathingDot: View {
    /// The data color of the dot (the datum's own hue, never chrome).
    public var color: Color
    /// Dot radius in points; the halo breathes at ×2.4, the paper moat sits at ×1.55.
    public var radius: CGFloat
    /// False keeps the dot lit but still (e.g. a boundary marker on a settled day).
    public var breathes: Bool

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    public init(color: Color, radius: CGFloat = 3, breathes: Bool = true) {
        self.color = color; self.radius = radius; self.breathes = breathes
    }

    public var body: some View {
        let animating = breathes && !reduceMotion
        ZStack {
            if animating {
                Circle().fill(color)
                    .frame(width: radius * 4.8, height: radius * 4.8)
                    .scaleEffect(on ? 1.3 : 0.92)
                    .opacity(on ? 0.05 : 0.18)
                    .animation(StrandMotion.breathe, value: on)
            }
            Circle().fill(theme.paper)
                .frame(width: radius * 3.1, height: radius * 3.1)
            Circle().fill(color)
                .frame(width: radius * 2, height: radius * 2)
        }
        .frame(width: radius * 2, height: radius * 2)
        .onAppear { if animating { on = true } }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Punto que respira") {
    let t = InstrumentoTheme.base
    return HStack(spacing: 40) {
        BreathingDot(color: t.dataRecovery)
        BreathingDot(color: t.dataHeart, radius: 4)
        BreathingDot(color: t.dataSleep, radius: 3, breathes: false)
    }
    .padding(60)
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
