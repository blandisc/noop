#if canImport(SwiftUI)
import SwiftUI

// MARK: - SleepStageBar — the «ANOCHE» stage bar from the 2026-07 «Hoy» redesign (FER-707/710)
//
// A single rounded bar that shows how last night split across its stages (deep / REM / light / awake),
// each segment's width ∝ its share of the night, with a legend of label + duration underneath. It's the
// sleep sheet's one bespoke visual: the shape of the night, not a second number.
//
// Generic on purpose — the caller (the sleep summary sheet) passes the stage minutes + their indigo
// tones + localized labels, so `StrandDesign` stays free of `StrandAnalytics`. Colour lives only in the
// segments; the legend text is quiet ink.

public struct SleepStageBar: View {
    /// One stage of the night: its duration in minutes, its colour, and its localized label.
    public struct Stage: Identifiable {
        public let id = UUID()
        public let minutes: Double
        public let color: Color
        public let label: String

        public init(minutes: Double, color: Color, label: String) {
            self.minutes = minutes
            self.color = color
            self.label = label
        }
    }

    let stages: [Stage]
    let theme: InstrumentoTheme

    private let gap: CGFloat = 2

    public init(stages: [Stage], theme: InstrumentoTheme = .base) {
        self.stages = stages
        self.theme = theme
    }

    /// «1:31» from minutes — hours:minutes, minutes always two digits. Rounds to the nearest minute.
    private func hm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    private func widths(in total: CGFloat) -> [CGFloat] {
        let sum = stages.reduce(0) { $0 + $1.minutes }
        guard sum > 0 else { return stages.map { _ in 0 } }
        let usable = max(0, total - gap * CGFloat(stages.count - 1))
        return stages.map { CGFloat($0.minutes / sum) * usable }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = widths(in: geo.size.width)
                HStack(spacing: gap) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { i, s in
                        Rectangle().fill(s.color).frame(width: w[i])
                    }
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 10) {
                ForEach(stages) { s in
                    HStack(spacing: 4) {
                        Text(s.label)
                            .font(InstrumentoType.grotesk(9, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.inkTertiary)
                        Text(hm(s.minutes))
                            .font(InstrumentoType.groteskNumber(9, weight: .medium))
                            .foregroundStyle(theme.inkSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

#if DEBUG
#Preview("SleepStageBar · anoche") {
    let t = InstrumentoTheme.base
    // Deep → REM → Light as one indigo graded by opacity (no new tokens); awake in quiet ink.
    return SleepStageBar(
        stages: [
            .init(minutes: 91,  color: t.dataSleep,                 label: "Deep"),
            .init(minutes: 104, color: t.dataSleep.opacity(0.78),   label: "REM"),
            .init(minutes: 190, color: t.dataSleep.opacity(0.52),   label: "Light"),
            .init(minutes: 47,  color: t.hairlineStrong,            label: "Awake"),
        ],
        theme: t
    )
    .padding(24)
    .background(t.paper)
}
#endif
#endif
