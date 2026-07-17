import SwiftUI

// MARK: - Impact rows — the «vs your base» signal row shared by Recovery's Detalle and the metric
// summary sheet (FER-975)
//
// RecoveryDetailScreen's `levelSignalRow`/`impactBar`/`levelLegend` and MetricInfoSheet's
// `impactRow`/`impactBar`/`impactLegend` carried near-identical implementations that their own comments
// called "IDENTICAL", though a couple of tokens had quietly drifted (label tracking 1.2 vs the generic
// `groteskOverline()`'s 2, the center-mark color `baseMark` vs `hairlineStrong`, and only the Detalle's
// bar carried the `recGrow` entrance). Promoted here using the Detalle's implementation as canonical —
// both call sites now converge on it. The driver label / band word / flag→color mapping (which reads
// `ReadinessEngine`/`RecoveryImpact`, engine types) stays app-side and is handed in as plain data.

/// One signal row: overline label · position word (tinted) · «· N%» weight, and the divergent
/// contribution bar below. `index` staggers the bar's `recGrow` entrance when several rows animate in
/// sequence.
public struct ImpactSignalRow: View {
    private let label: LocalizedStringKey
    private let word: LocalizedStringKey
    private let weightPct: Int
    private let contribution: Double
    private let color: Color
    private let index: Int
    private let theme: InstrumentoTheme

    public init(label: LocalizedStringKey, word: LocalizedStringKey, weightPct: Int,
                contribution: Double, color: Color, index: Int = 0, theme: InstrumentoTheme) {
        self.label = label
        self.word = word
        self.weightPct = weightPct
        self.contribution = contribution
        self.color = color
        self.index = index
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(InstrumentoType.grotesk(10, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Text(word)
                    .font(InstrumentoType.grotesk(12))
                    .foregroundStyle(color)
                Text(verbatim: "· \(weightPct)%")
                    .font(InstrumentoType.groteskNumber(12, weight: .regular))
                    .foregroundStyle(theme.inkMuted)
            }
            ImpactDivergentBar(contribution: contribution, color: color, index: index, theme: theme)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The divergent «vs your base» bar: a full-width track with a shaded central «tu base» zone, a capsule
/// extending right (holds it up) or left (holds it back) sized to |contribution| (clamped at ~1.5
/// composite-z units), and a center base-mark tick. `index` staggers the entrance (`recGrow`).
public struct ImpactDivergentBar: View {
    private let contribution: Double
    private let color: Color
    private let index: Int
    private let theme: InstrumentoTheme

    public init(contribution: Double, color: Color, index: Int = 0, theme: InstrumentoTheme) {
        self.contribution = contribution
        self.color = color
        self.index = index
        self.theme = theme
    }

    public var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let maxC: CGFloat = 1.5
            let mag = Swift.max(4, Swift.min(abs(CGFloat(contribution)) / maxC, 1.0) * half)
            let trackH: CGFloat = 12
            let baseZoneW = geo.size.width * 0.24
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.trackWarm)
                    .frame(width: geo.size.width, height: trackH)
                RoundedRectangle(cornerRadius: 2, style: .continuous)  // token-exempt: geometría de dato
                    .fill(theme.hairline)
                    .frame(width: baseZoneW, height: trackH)
                    .offset(x: half - baseZoneW / 2)
                Capsule()
                    .fill(color)
                    .frame(width: mag, height: 6)
                    .offset(x: contribution >= 0 ? half : half - mag)
                    .recGrow(index: index, origin: contribution >= 0 ? .leading : .trailing)
                Rectangle()
                    .fill(theme.baseMark)
                    .frame(width: 1.5, height: 16)
                    .offset(x: half - 0.75)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 16)
    }
}

/// The unified axis legend: «◀ holds it back · your base · holds it up ▶» — decorative, hidden from
/// VoiceOver.
public struct ImpactAxisLegend: View {
    private let theme: InstrumentoTheme

    public init(theme: InstrumentoTheme) {
        self.theme = theme
    }

    public var body: some View {
        HStack {
            Text("◀ holds it back").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer()
            Text("your base").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer()
            Text("holds it up ▶").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Impact rows") {
    let t = InstrumentoTheme.base
    VStack(alignment: .leading, spacing: 16) {
        ImpactSignalRow(label: "HRV", word: "Well above your base", weightPct: 55,
                        contribution: 0.9, color: t.verdictDeep, index: 0, theme: t)
        ImpactSignalRow(label: "Resting HR", word: "Below your base", weightPct: 25,
                        contribution: -0.4, color: t.critical, index: 1, theme: t)
        ImpactAxisLegend(theme: t)
    }
    .padding(20)
    .background(t.paper)
}
#endif
