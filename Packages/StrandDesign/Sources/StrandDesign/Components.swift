import SwiftUI

// MARK: - Shared design-system primitives
//
// What survives the «Instrumento diurno» migration: the spacing/measure token scale
// (`NoopMetrics`), the one segmented pill control, and the source badge. The legacy card
// primitives (`NoopCard` / `StatTile` / `SectionHeader` / `ChartCard` / `ChartFooter`) were
// removed once the dark screens that used them went away (FER-444, tail of FER-413/FER-427).

public enum NoopMetrics {
    public static let cardRadius: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let gap: CGFloat = 12          // gap between cards
    public static let sectionGap: CGFloat = 28   // gap between sections
    public static let screenPadding: CGFloat = 24
    /// Top inset of a titled tab landing — the same distance from the safe area for «Patrones»,
    /// «Tendencias», «Entrenar» and «Ajustes» so their `InstrumentoTabHeader` lines up as you swipe
    /// between tabs. «Hoy» is exempt: it's the dial dashboard and keeps its tighter `space2` rhythm.
    public static let screenTop: CGFloat = 14

    // MARK: Fine spacing ramp (FER-206)
    // Named steps below `gap` (plus a compact section rhythm and two control radii) so
    // the «Instrumento» Today path stops using magic numbers — every spacing/radius
    // there snaps to one of these instead of an inline literal.
    public static let space1: CGFloat = 4              // finest step (tight icon↔text, a unit hugging a numeral)
    public static let space2: CGFloat = 8              // tight step, below gap = 12
    public static let sectionGapCompact: CGFloat = 16  // compact section rhythm on iPhone Today (FER-202)
    public static let controlRadius: CGFloat = 12      // buttons / CTAs
    public static let chipRadius: CGFloat = 8          // small inline chips / pills
    public static let tileRadius: CGFloat = 17         // «Hoy» metric tile corner (handoff «Hoy · Estados»)
    public static let ctaRadius: CGFloat = 14          // the ink CTA bar («Aplicar»/«Listo», FER-716 handoff)

    public static let sourceGlyph: CGFloat = 13  // point size of a data-source SF Symbol glyph
    public static let tileHeight: CGFloat = 104  // every metric tile is this tall
    public static let chartHeight: CGFloat = 220
    /// Clean band reserved below the area fill (via the Y-scale's bottom padding) so the X-axis
    /// hour/date labels never sit behind the fill and get tinted. (FER-82)
    public static let chartXLabelBand: CGFloat = 24
    /// Trailing inset on the X-scale so the rightmost date label renders in full instead of being
    /// truncated («jun…»). Sized for a «d MMM» label centered on the last tick. (FER-82 / Detalle de Vital)
    public static let chartXTrailingInset: CGFloat = 38
}

// MARK: - Range control (the ONE segmented pill control, used everywhere)

public struct SegmentedPillControl<T: Hashable>: View {
    let items: [T]
    let label: (T) -> String
    @Binding var selection: T
    /// Optional «Instrumento diurno» theme. When `nil` (the default) the control renders the
    /// legacy dark `StrandPalette` look used by the 9 shipped screens — UNCHANGED. When a theme
    /// is passed (the light Detalle de Métrica, FER-211), it renders an iOS-native segmented look
    /// on warm paper: a quiet track, an active segment that's a subtle ink-tinted capsule (no
    /// bright green), and ink labels. (FER-211)
    var theme: InstrumentoTheme?
    /// «Ink thumb» variant (FER-716 handoff «Entrenar»): a `patternBlock` track with an `ink` active
    /// capsule and `paper` Grotesk label — the bolder segmented look the session's editor uses. Only
    /// meaningful with a `theme`; the default (`false`) keeps the quiet surface-thumb look.
    var inkThumb: Bool = false
    public init(_ items: [T], selection: Binding<T>, theme: InstrumentoTheme? = nil,
                inkThumb: Bool = false, label: @escaping (T) -> String) {
        self.items = items; self._selection = selection; self.theme = theme
        self.inkThumb = inkThumb; self.label = label
    }
    public var body: some View {
        HStack(spacing: theme == nil ? 4 : 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let sel = item == selection
                Button { withAnimation(StrandMotion.interactive) { selection = item } } label: {
                    segment(item, sel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(trackFill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(trackStroke, lineWidth: 1))
    }

    /// One segment. Instrumento: the active «thumb» HUGS the label to the WIDTH (content-width, centered in
    /// the equal-width tap segment) but FILLS the track's HEIGHT — the capsule wraps a fixed-height frame, so
    /// it no longer floats small inside a taller groove. The thumb is 28pt tall, inset 3pt from the track
    /// edge like a slim iOS segmented control — a quiet secondary control, deliberately tighter than the
    /// 44pt min (the full segment width stays the tap target). Legacy (theme == nil) keeps the exact
    /// dark-palette look — UNCHANGED. (FER-439 / Detalle de Vital fix)
    @ViewBuilder private func segment(_ item: T, _ sel: Bool) -> some View {
        if let theme, inkThumb {
            // Ink-thumb: bolder handoff look — Grotesk label, ink capsule / paper text when active.
            Text(label(item))
                .font(InstrumentoType.grotesk(12, weight: sel ? .bold : .medium))
                .lineLimit(1).minimumScaleFactor(0.85)
                .foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    if sel { Capsule(style: .continuous).fill(theme.ink) }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        } else if let theme {
            Text(label(item))
                .font(StrandFont.subhead)
                .fontWeight(sel ? .semibold : .regular)
                .lineLimit(1).minimumScaleFactor(0.85)
                .foregroundStyle(sel ? theme.ink : theme.inkSecondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    if sel {
                        Capsule(style: .continuous).fill(theme.surface)
                            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        } else {
            Text(label(item))
                .font(StrandFont.captionNumber)
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(sel ? InstrumentoTheme.base.paper : InstrumentoTheme.base.inkSecondary)
                .frame(minWidth: 32)
                .padding(.vertical, 6).padding(.horizontal, 11)
                .background(Capsule(style: .continuous).fill(sel ? StrandPalette.accent : Color.clear))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    // Instrumento track is a recessed `hairline` groove (so the lighter thumb reads as raised); legacy
    // keeps its original fill. The border stays for both.
    private var trackFill: Color {
        if inkThumb, let theme { return theme.patternBlock }
        return theme?.hairline ?? InstrumentoTheme.base.hairline
    }
    private var trackStroke: Color {
        if inkThumb { return .clear }
        return theme?.hairlineStrong ?? InstrumentoTheme.base.hairline
    }
}

// MARK: - Badges

public struct SourceBadge: View {
    let text: LocalizedStringKey; var tint: Color = StrandPalette.accent
    public init(_ text: LocalizedStringKey, tint: Color = StrandPalette.accent) { self.text = text; self.tint = tint }
    public var body: some View {
        Text(text).textCase(.uppercase).font(.system(size: 10, weight: .semibold)).tracking(0.5)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
            .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - In-screen serif title + ⓘ (FER-581 · «Instrumento» detail-screen identity)

/// The detail-screen headline: an `Instrument Serif` title (the handoff reserves serif for in-screen
/// headlines, never numbers or tab names) with an optional ⓘ that toggles an inline plain-language
/// explanation. One source of truth so every detail sheet titles identically. The numeral, range bar
/// and blocks live BELOW this, unchanged. (FER-581)
public struct InstrumentoScreenTitle: View {
    let title: LocalizedStringKey
    var size: CGFloat
    var theme: InstrumentoTheme
    var explanation: LocalizedStringKey?
    @State private var open = false

    public init(_ title: LocalizedStringKey, size: CGFloat = 23,
                theme: InstrumentoTheme, explanation: LocalizedStringKey? = nil) {
        self.title = title
        self.size = size
        self.theme = theme
        self.explanation = explanation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(StrandFont.serif(size))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if explanation != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("What this means"))
                }
            }
            if open, let explanation {
                Text(explanation)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Dynamic period-average caption (FER-587 · handoff «Media · … vs previo»)

/// The handoff's one-line period average under a trend: «Average · {window} · {value} · {Δ%} vs previous»,
/// with the Δ coloured by the metric's good direction, plus an optional small «Range {lo–hi}» line so the
/// min–max stays visible (the owner's option ii). The host computes the figures (it owns the full series);
/// this is presentation only. Hidden Δ when `pctChange` is nil (no previous period). (FER-587)
public struct DynamicAverageCaption: View {
    let windowName: String
    let average: String
    let unit: String?
    let pctChange: Double?
    let polarity: TrendStatSummary.Polarity
    let rangeText: String?
    let theme: InstrumentoTheme

    public init(windowName: String, average: String, unit: String? = nil, pctChange: Double?,
                polarity: TrendStatSummary.Polarity, rangeText: String? = nil, theme: InstrumentoTheme) {
        self.windowName = windowName
        self.average = average
        self.unit = unit
        self.pctChange = pctChange
        self.polarity = polarity
        self.rangeText = rangeText
        self.theme = theme
    }

    private var deltaColor: Color {
        guard let v = pctChange, Int(abs(v).rounded()) != 0 else { return theme.inkSecondary }
        switch polarity {
        case .neutral:        return theme.inkSecondary
        case .higherIsBetter: return v > 0 ? theme.verdict : theme.warning
        case .lowerIsBetter:  return v < 0 ? theme.verdict : theme.warning
        }
    }

    public var body: some View {
        let unitSuffix = unit.map { " \($0)" } ?? ""
        let head = Text("Average") + Text(verbatim: " · \(windowName) · \(average)\(unitSuffix)")
        return VStack(alignment: .leading, spacing: 3) {
            Group {
                if let pct = pctChange {
                    let rounded = Int(abs(pct).rounded())
                    let arrow = rounded == 0 ? "" : (pct >= 0 ? "▲ " : "▼ ")
                    head
                        + Text(verbatim: " · \(arrow)\(rounded)% ").foregroundColor(deltaColor)
                        + Text("vs previous")
                } else {
                    head
                }
            }
            .font(StrandFont.footnote)
            .foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            if let rangeText {
                (Text("Range") + Text(verbatim: " \(rangeText)"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
