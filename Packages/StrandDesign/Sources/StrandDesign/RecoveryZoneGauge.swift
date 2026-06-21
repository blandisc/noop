import SwiftUI

// MARK: - Recovery zone gauge — «Instrumento diurno» instrument cluster (FER-292 v2)
//
// The Coach decision hero's protagonist instrument: a full-circle gauge printed on warm paper. An
// OUTER ring of three fixed zone arcs (red / amber / green) is the reference scale — the recovery
// bands `RecoveryScorer` uses (red < 34, amber 34–67, green ≥ 67). An INNER value ring sweeps from
// the top to `score%`, colored by the band the score lands in, over a faint track. The centre carries
// the SF-Mono hero numeral and a quiet label.
//
// This is the paper-language sibling of the dark `RecoveryRing` (which blooms on black): no glow,
// flat fills, tokens only, driven by an injected `InstrumentoTheme` like the rest of the Bucle. When
// `score` is nil (calibrating / awaiting today's read) the value ring is empty and the numeral reads
// «—» in the no-data ink — an honest "nothing to gauge yet".

public struct RecoveryZoneGauge: View {

    /// Recovery 0…100, or nil while there's no reading to gauge.
    public var score: Double?
    /// The quiet label under the numeral (e.g. «RECUPERACIÓN»).
    public var label: String
    public var theme: InstrumentoTheme
    public var diameter: CGFloat

    public init(score: Double?, label: String, theme: InstrumentoTheme, diameter: CGFloat = 128) {
        self.score = score
        self.label = label
        self.theme = theme
        self.diameter = diameter
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    /// The two recovery-band thresholds, shared with `RecoveryScorer` (red < 34, amber 34–67, green ≥ 67).
    private let redMax = 34.0
    private let yellowMax = 67.0

    private var scale: CGFloat { diameter / 128 }
    private var fraction: Double { min(max((score ?? 0) / 100, 0), 1) }

    /// The value-arc hue: the band the score falls in, so a low recovery reads red, not a misleading green.
    private var valueColor: Color {
        guard let s = score else { return theme.inkDim }
        if s < redMax { return theme.critical }
        if s < yellowMax { return theme.warning }
        return theme.dataRecovery
    }

    // Outer zone arcs as trim fractions of the full circle, with a small gap between bands.
    private let gap = 0.006

    public var body: some View {
        ZStack {
            zoneRing
            valueRing
            centerLabel
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { drawn = true }
            else { withAnimation(StrandMotion.drawIn) { drawn = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(score.map { "\(Int($0.rounded()))" } ?? "—"))
    }

    // MARK: Outer zone scale (fixed reference)

    private var zoneRing: some View {
        let d = diameter * (112.0 / 128.0)
        let w = 4 * scale
        return ZStack {
            zoneArc(from: 0, to: redMax / 100, color: theme.critical, w: w)
            zoneArc(from: redMax / 100, to: yellowMax / 100, color: theme.warning, w: w)
            zoneArc(from: yellowMax / 100, to: 1.0, color: theme.dataRecovery, w: w)
        }
        .frame(width: d, height: d)
    }

    private func zoneArc(from: Double, to: Double, color: Color, w: CGFloat) -> some View {
        Circle()
            .trim(from: from + gap, to: to - gap)
            .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: w, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    // MARK: Inner value ring

    private var valueRing: some View {
        let d = diameter * (94.0 / 128.0)
        let w = 9 * scale
        return ZStack {
            Circle().stroke(theme.hairline, lineWidth: w)
            if score != nil {
                Circle()
                    .trim(from: 0, to: drawn ? fraction : 0)
                    .stroke(valueColor, style: StrokeStyle(lineWidth: w, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: d, height: d)
    }

    // MARK: Centre read-out

    private var centerLabel: some View {
        VStack(spacing: 3 * scale) {
            if let s = score {
                Text("\(Int(s.rounded()))")
                    .instrumentoHero(38 * scale)
                    .foregroundStyle(theme.ink)
                    .contentTransition(.numericText())
            } else {
                Text("—").instrumentoHero(38 * scale).foregroundStyle(theme.inkDim)
            }
            Text(label)
                .font(.system(size: 9 * scale, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(theme.inkTertiary)
        }
    }
}

#if DEBUG
#Preview("RecoveryZoneGauge") {
    let t = InstrumentoTheme.base
    return HStack(spacing: 24) {
        RecoveryZoneGauge(score: 82, label: "RECUPERACIÓN", theme: t)
        RecoveryZoneGauge(score: 48, label: "RECUPERACIÓN", theme: t)
        VStack(spacing: 18) {
            RecoveryZoneGauge(score: 18, label: "RECUPERACIÓN", theme: t, diameter: 96)
            RecoveryZoneGauge(score: nil, label: "RECUPERACIÓN", theme: t, diameter: 96)
        }
    }
    .padding(40)
    .background(t.paper)
}
#endif
