import SwiftUI

// MARK: - Body-age band (FER-145)
//
// A horizontal "your age on a ruler" gauge for the longevity detail. Unlike a 0–100 fill gauge, the
// reading is a RANGE: a body age sits inside a ±N-year band, with the chronological age marked as a
// reference tick. The band, not the point, is the honest read — it shows the model's uncertainty
// (`VitalityEngine.bandYears` = 5).
//
// Color lives ONLY on the body-age marker + its value, tinted by the SIGN of the delta (the caller
// passes the same hue as the hero). The ruler, band, reference tick and labels stay in ink (§8.4 rule
// 2). The visible scale ALWAYS includes the chronological age, so when the body drifts more than ±N
// years the "you" tick never falls off the ruler.
//
// User-facing text (the "you" tick, the accessibility sentence) is caller-provided — StrandDesign has
// no string catalog, so the app (which owns the es/de catalog) localizes it, the same way `MetricRow`
// takes its label. The marker slides from the chronological age to the body age on appear (`drawIn`);
// honors Reduce Motion. Tokens-only; reads `InstrumentoTheme`. The flat-ruler cousin of `ReadinessGaugeBar`.

public struct BodyAgeBand: View {
    public let bodyAge: Double
    public let chronoAge: Double
    public var bandYears: Double
    /// Marker + value tint — the same sign-driven hue the hero uses (the caller decides).
    public var color: Color
    /// Localized word for "you" shown on the chronological-age tick (e.g. "tú").
    public var youLabel: String
    /// Localized accessibility label + value (the caller builds the sentence; StrandDesign has no catalog).
    public var accessibilityLabelText: String
    public var accessibilityValueText: String
    public var animated: Bool

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    public init(bodyAge: Double, chronoAge: Double, bandYears: Double = 5, color: Color,
                youLabel: String, accessibilityLabelText: String, accessibilityValueText: String,
                animated: Bool = true) {
        self.bodyAge = bodyAge
        self.chronoAge = chronoAge
        self.bandYears = bandYears
        self.color = color
        self.youLabel = youLabel
        self.accessibilityLabelText = accessibilityLabelText
        self.accessibilityValueText = accessibilityValueText
        self.animated = animated
    }

    private var bandLo: Double { bodyAge - bandYears }
    private var bandHi: Double { bodyAge + bandYears }
    // The visible scale spans both the ±N band and the chronological age, so the "you" tick is always
    // on-ruler even when the body drifts far.
    private var scaleLo: Double { min(bandLo, chronoAge) }
    private var scaleHi: Double { max(bandHi, chronoAge) }

    public var body: some View {
        let inset: CGFloat = 18
        GeometryReader { geo in
            let w = geo.size.width
            let markerX = xFor(drawn ? bodyAge : chronoAge, width: w, inset: inset)
            let loX = xFor(bandLo, width: w, inset: inset)
            let hiX = xFor(bandHi, width: w, inset: inset)
            let chronoX = xFor(chronoAge, width: w, inset: inset)
            ZStack(alignment: .topLeading) {
                // Marker value, centered above the marker (the one coloured number).
                Text("\(Int(bodyAge.rounded()))")
                    .font(StrandFont.number(13, weight: .bold))
                    .foregroundStyle(color)
                    .position(x: markerX, y: 9)

                // Ruler.
                Capsule().fill(theme.hairline)
                    .frame(width: w - 2 * inset, height: 3)
                    .position(x: w / 2, y: 28)
                // The ±N band — the reading (in ink, not a data hue).
                Capsule().fill(theme.hairlineStrong)
                    .frame(width: max(0, hiX - loX), height: 7)
                    .position(x: (loX + hiX) / 2, y: 28)
                // Chronological-age reference tick (dotted, ink).
                DottedTick()
                    .stroke(theme.inkTertiary, style: StrokeStyle(lineWidth: 1.3, dash: [2, 2]))
                    .frame(width: 1.3, height: 18)
                    .position(x: chronoX, y: 28)
                // Body-age marker (the one coloured mark).
                Circle().fill(color)
                    .frame(width: 11, height: 11)
                    .position(x: markerX, y: 28)

                // Band ends + the "you" reference, all in tertiary ink.
                Text("\(Int(bandLo.rounded()))").font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .position(x: loX, y: 48)
                Text("\(Int(bandHi.rounded()))").font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .position(x: hiX, y: 48)
                Text(verbatim: "\(youLabel) \(Int(chronoAge.rounded()))").font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .position(x: chronoX, y: 48)
            }
        }
        .frame(height: 58)
        .onAppear {
            if animated && !reduceMotion { withAnimation(StrandMotion.drawIn) { drawn = true } }
            else { drawn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabelText))
        .accessibilityValue(Text(verbatim: accessibilityValueText))
    }

    private func xFor(_ age: Double, width w: CGFloat, inset: CGFloat) -> CGFloat {
        guard scaleHi > scaleLo else { return w / 2 }
        let f = (age - scaleLo) / (scaleHi - scaleLo)
        return inset + CGFloat(f) * (w - 2 * inset)
    }
}

/// A single vertical line centred in its frame — the chronological-age reference tick.
private struct DottedTick: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

#if DEBUG
#Preview("BodyAgeBand · por signo") {
    let t = InstrumentoTheme.base
    // FER-978: the nested helper builds a `@MainActor` View, so it must be main-actor itself —
    // otherwise the `BodyAgeBand` init is called from a nonisolated context (targeted warning).
    @MainActor func band(_ body: Double, _ color: Color) -> some View {
        BodyAgeBand(bodyAge: body, chronoAge: 34, color: color, youLabel: "you",
                    accessibilityLabelText: "Body age",
                    accessibilityValueText: "\(Int(body)) years", animated: false)
    }
    return VStack(alignment: .leading, spacing: 28) {
        band(31, t.dataRecovery)   // rejuvenates
        band(34, t.ink)            // neutral
        band(38, t.warning)        // ages
        band(44, t.critical)       // far (age falls outside the band)
    }
    .padding(28)
    .frame(width: 360)
    .background(t.paper)
    .environment(\.instrumentoTheme, t)
}
#endif
