import SwiftUI

// MARK: - Readiness gauge bar (0–100)
//
// A thin horizontal gauge for the Today verdict hero: a track with a colored fill to `score`, the
// current value floating above the fill end with a downward tick, a neutral "typical" marker, and
// 0 / 100 scale ends. The fill draws in with the house `drawIn` curve and honors Reduce Motion.
//
// This is the flat-gauge analogue of `RecoveryRing` — same draw-in language, no circle — built for
// dense verdict-first layouts. Tokens-only; reusable across the redesign.

public struct ReadinessGaugeBar: View {
    public let score: Int
    public var accent: Color
    /// Position (0…1) of the neutral "typical" marker — the prototype pins it at 60%.
    public var typical: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    public init(score: Int, accent: Color = StrandPalette.accent, typical: Double = 0.6) {
        self.score = score
        self.accent = accent
        self.typical = typical
    }

    public var body: some View {
        let frac = max(0, min(1, Double(score) / 100))
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let x = w * (drawn ? frac : 0)
                let labelX = min(max(x, 12), w - 12)   // keep the value label fully on-screen
                ZStack(alignment: .topLeading) {
                    // Current value + downward tick, centered over the fill end.
                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(StrandFont.number(13, weight: .bold))
                            .foregroundStyle(accent)
                        Rectangle().fill(accent).frame(width: 1.5, height: 5)
                    }
                    .position(x: labelX, y: 11)

                    // Track.
                    Capsule().fill(StrandPalette.textPrimary.opacity(0.10))
                        .frame(width: w, height: 4)
                        .position(x: w / 2, y: 24)
                    // Neutral "typical" marker.
                    Rectangle().fill(StrandPalette.textSecondary)
                        .frame(width: 1.5, height: 10)
                        .position(x: w * typical, y: 24)
                    // Fill.
                    Capsule().fill(accent)
                        .frame(width: x, height: 4)
                        .position(x: x / 2, y: 24)
                }
            }
            .frame(height: 30)

            HStack {
                Text(verbatim: "0").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                Spacer()
                Text(verbatim: "100").font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .onAppear {
            if reduceMotion { drawn = true }
            else { withAnimation(StrandMotion.drawIn) { drawn = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Readiness"))
        .accessibilityValue(Text("\(score) out of 100"))
    }
}

#if DEBUG
#Preview("ReadinessGaugeBar") {
    VStack(spacing: 28) {
        ReadinessGaugeBar(score: 72, accent: StrandPalette.accent)
        ReadinessGaugeBar(score: 31, accent: StrandPalette.statusWarning)
        ReadinessGaugeBar(score: 9, accent: StrandPalette.metricRose)
    }
    .padding(28)
    .frame(width: 340, height: 280)
    .background(StrandPalette.surfaceRaised)
    .preferredColorScheme(.dark)
}
#endif
