import SwiftUI

// MARK: - Contribution bars (FER-145)
//
// A signed, diverging bar chart for a score breakdown: each factor pushes left (rejuvenates — green)
// or right (ages you — amber) from a central zero axis, on a SHARED horizontal scale so "one year"
// reads the same length on every row. The marks are bar length + side-of-axis + the signed number —
// three channels, so the reading survives colour-blindness (the side already encodes the sign).
//
// This is the breakdown of `VitalityEngine.contributions` ("what's driving this"), diverging-from-zero
// rather than a one-sided ranking because zero here is a real anchor: "average for your age".
// Cleveland-McGill (position on a common axis) + Tufte (one surface, no per-row rules). Color lives
// ONLY on the bars + their values; the axis and pole labels stay in ink. User-facing text (pole labels,
// per-row accessibility) is caller-provided — CenitDesign has no string catalog, so the app localizes
// it. Tokens-only; reads `InstrumentoTheme`. Pass the items already ordered by |years| descending.

public struct ContributionBars: View {
    /// One factor's contribution, in YEARS: negative rejuvenates (subtracts age), positive ages you.
    /// `accessibilityValue` is the localized spoken value (e.g. "rejuvenates you by 1.8 years").
    public struct Item: Identifiable {
        public var id: String { label }
        public let label: String
        public let years: Double
        public let accessibilityValue: String
        public init(label: String, years: Double, accessibilityValue: String) {
            self.label = label
            self.years = years
            self.accessibilityValue = accessibilityValue
        }
    }

    public let items: [Item]
    /// Localized pole captions, shown once above the bars (e.g. "← rejuvenates you" / "ages you →").
    public var leftPole: String
    public var rightPole: String
    public var animated: Bool

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    public init(items: [Item], leftPole: String, rightPole: String, animated: Bool = true) {
        self.items = items
        self.leftPole = leftPole
        self.rightPole = rightPole
        self.animated = animated
    }

    private var maxAbs: Double { max(items.map { abs($0.years) }.max() ?? 1, 0.001) }

    public var body: some View {
        let maxAbs = self.maxAbs
        return VStack(alignment: .leading, spacing: 11) {
            // Pole labels — once, in ink (orientation, not data).
            HStack(spacing: 8) {
                Text(verbatim: leftPole).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Text(verbatim: rightPole).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }

            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text(verbatim: item.label)
                        .font(InstrumentoType.grotesk(11, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(width: 96, alignment: .leading)
                    track(for: item, max: maxAbs)
                    Text(signed(item.years))
                        .font(StrandFont.captionNumber).foregroundStyle(color(for: item.years))
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: item.label))
                .accessibilityValue(Text(verbatim: item.accessibilityValue))
            }
        }
        .onAppear {
            if animated && !reduceMotion { withAnimation(StrandMotion.drawIn) { drawn = true } }
            else { drawn = true }
        }
    }

    private func track(for item: Item, max maxAbs: Double) -> some View {
        GeometryReader { geo in
            let halfW = geo.size.width / 2
            let frac = min(1, abs(item.years) / maxAbs)
            let barW = halfW * (drawn ? frac : 0)
            let cy = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                // Central zero axis (= average for your age), in ink.
                Rectangle().fill(theme.hairlineStrong)
                    .frame(width: 1, height: 16).position(x: halfW, y: cy)
                // The bar, growing from the axis toward its pole.
                Capsule().fill(color(for: item.years))
                    .frame(width: barW, height: 14)
                    .position(x: item.years < 0 ? halfW - barW / 2 : halfW + barW / 2, y: cy)
            }
        }
        .frame(height: 22)
    }

    private func color(for years: Double) -> Color {
        // dataRejuvenates (#2E7D57): deeper than dataRecovery so «rejuvenece» reads as longevity.
        if years < -0.05 { return theme.dataRejuvenates } // rejuvenates
        if years > 0.05 { return theme.warning }          // ages you
        return theme.inkTertiary                          // ~neutral
    }

    private func signed(_ years: Double) -> String { String(format: "%+.1f", years) }
}

#if DEBUG
#Preview("ContributionBars") {
    let t = InstrumentoTheme.base
    return ContributionBars(items: [
        .init(label: "VO₂max", years: -1.8, accessibilityValue: "rejuvenates you by 1.8 years"),
        .init(label: "Resting HR", years: -1.4, accessibilityValue: "rejuvenates you by 1.4 years"),
        .init(label: "HRV", years: -0.6, accessibilityValue: "rejuvenates you by 0.6 years"),
        .init(label: "Sleep", years: -0.1, accessibilityValue: "neutral"),
        .init(label: "Steps", years: 0.3, accessibilityValue: "ages you by 0.3 years"),
        .init(label: "Regularity", years: 0.9, accessibilityValue: "ages you by 0.9 years"),
    ], leftPole: "← rejuvenates you", rightPole: "ages you →", animated: false)
    .padding(24)
    .frame(width: 360)
    .background(t.paper)
    .environment(\.instrumentoTheme, t)
}
#endif
