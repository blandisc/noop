import SwiftUI

// MARK: - CompactTrendToggle — media móvil ⇄ rangos (handoff v2)
//
// A tiny two-segment pill that sits INLINE to the right of a trend block's summary line (not a
// full-width row). It flips the history view between the moving-average line («Media») and the
// population lanes («Rangos»). Active segment is the ink chip on warm paper — «color solo en el dato»,
// so the toggle itself stays monochrome. Pure SwiftUI; no UIKit/AppKit.
//
// Accessibility: exposed as a two-option picker to VoiceOver (each segment is a button announcing its
// selected state); the whole control is a ≥44pt tap target per segment.

/// Which history view the trend block shows.
public enum TrendMode: String, Sendable, CaseIterable {
    /// The 7-day moving-average line.
    case media
    /// The population-lane ranges.
    case rangos

    /// Segment label. English keys resolve against the app bundle (es: Media / Rangos).
    var label: String {
        switch self {
        case .media:  return String(localized: "Mean", bundle: .main)
        case .rangos: return String(localized: "Ranges", bundle: .main)
        }
    }
}

public struct CompactTrendToggle: View {
    @Binding private var mode: TrendMode
    private let theme: InstrumentoTheme

    public init(mode: Binding<TrendMode>, theme: InstrumentoTheme) {
        self._mode = mode
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(TrendMode.allCases, id: \.self) { m in
                segment(m)
            }
        }
        .padding(3)
        .background(theme.trackWarm, in: Capsule())
    }

    private func segment(_ m: TrendMode) -> some View {
        let active = mode == m
        return Text(verbatim: m.label)
            .font(InstrumentoType.grotesk(10, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(active ? theme.paper : theme.inkTertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .frame(minHeight: 34)
            .background { if active { Capsule().fill(theme.ink) } }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(StrandMotion.interactive) { mode = m }
            }
            .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }
}

#if DEBUG
#Preview("CompactTrendToggle") {
    struct Demo: View {
        @State private var mode: TrendMode = .media
        var body: some View {
            let t = InstrumentoTheme.base
            return HStack {
                Text("52").font(InstrumentoType.groteskNumber(20)).foregroundStyle(t.dataHrv)
                Spacer()
                CompactTrendToggle(mode: $mode, theme: t)
            }
            .padding(18)
            .background(t.paper)
        }
    }
    return Demo()
}
#endif
