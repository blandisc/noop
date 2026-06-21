import SwiftUI

// MARK: - The locked component system
//
// Every screen composes ONLY these. Fixed dimensions + one spacing scale guarantee
// the uniform, instrument-grade look from the reference. Do not invent ad-hoc cards.

public enum NoopMetrics {
    public static let cardRadius: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let gap: CGFloat = 12          // gap between cards
    public static let sectionGap: CGFloat = 28   // gap between sections
    public static let screenPadding: CGFloat = 24

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

    public static let sourceGlyph: CGFloat = 13  // point size of a data-source SF Symbol glyph
    public static let tileHeight: CGFloat = 104  // every metric tile is this tall
    public static let chartHeight: CGFloat = 220
    /// Clean band reserved below the area fill (via the Y-scale's bottom padding) so the X-axis
    /// hour/date labels never sit behind the fill and get tinted. (FER-82)
    public static let chartXLabelBand: CGFloat = 24
    /// Trailing inset on the X-scale so the rightmost label renders in full inside ChartCard's
    /// `.clipped()` frame instead of being truncated. (FER-82)
    public static let chartXTrailingInset: CGFloat = 26
}

// MARK: - Surface

/// The one card surface. All cards use this — same radius, border, fill.
public struct NoopCard<Content: View>: View {
    private let padding: CGFloat
    @ViewBuilder private let content: () -> Content
    @State private var hover = false
    public init(padding: CGFloat = NoopMetrics.cardPadding, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding; self.content = content
    }
    public var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InstrumentoTheme.base.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(hover ? InstrumentoTheme.base.hairlineStrong : InstrumentoTheme.base.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(hover ? 0.25 : 0), radius: 10, y: 4)
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.16), value: hover)
    }
}

// MARK: - Section header

public struct SectionHeader: View {
    let overline: LocalizedStringKey?; let title: LocalizedStringKey; let trailing: String?
    public init(_ title: LocalizedStringKey, overline: LocalizedStringKey? = nil, trailing: String? = nil) {
        self.title = title; self.overline = overline; self.trailing = trailing
    }
    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let overline { Text(overline).strandOverline() }
                Text(title).font(StrandFont.title2).foregroundStyle(InstrumentoTheme.base.ink)
            }
            Spacer()
            if let trailing {
                Text(trailing).font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkSecondary)
            }
        }
    }
}

// MARK: - Metric tile (UNIFORM fixed height)

public struct StatTile: View {
    let label: LocalizedStringKey, value: String
    var caption: String? = nil
    var accent: Color = InstrumentoTheme.base.ink
    var delta: String? = nil
    var deltaColor: Color = InstrumentoTheme.base.inkTertiary
    var sparkline: [Double]? = nil
    var sparkColor: Color = StrandPalette.accent

    public init(label: LocalizedStringKey, value: String, caption: String? = nil,
                accent: Color = InstrumentoTheme.base.ink, delta: String? = nil,
                deltaColor: Color = InstrumentoTheme.base.inkTertiary,
                sparkline: [Double]? = nil, sparkColor: Color = StrandPalette.accent) {
        self.label = label; self.value = value; self.caption = caption; self.accent = accent
        self.delta = delta; self.deltaColor = deltaColor; self.sparkline = sparkline; self.sparkColor = sparkColor
    }

    public var body: some View {
        NoopCard(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                // Cap at two lines and let a long name shrink rather than overflow the fixed
                // tile height — a run-on label (e.g. a workout sport) used to push the value
                // out of the 104pt frame and collide with it. (FER-76)
                Text(label).strandOverline()
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(value).font(StrandFont.number(26)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6)
                if let sparkline, sparkline.count > 1 {
                    Sparkline(values: sparkline).frame(height: 22).padding(.top, 4)
                }
                HStack(spacing: 6) {
                    if let caption { Text(caption).font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary).lineLimit(1) }
                    Spacer(minLength: 0)
                    if let delta { Text(delta).font(StrandFont.captionNumber).foregroundStyle(deltaColor) }
                }
                .padding(.top, 2)
            }
        }
        // FER-394: minHeight (not a fixed height) so the tile grows instead of clipping text at
        // large Dynamic Type; at the default size the content fits, so the tile == tileHeight.
        .frame(minHeight: NoopMetrics.tileHeight)
    }
}

// MARK: - Chart card (UNIFORM: header + fixed chart body + footer)

public struct ChartCard<ChartBody: View, Footer: View>: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    var trailing: String? = nil
    /// Optional source badge shown in the header (e.g. "Apple Health"). (FER-62)
    var badge: SourceBadge? = nil
    var height: CGFloat = NoopMetrics.chartHeight
    @ViewBuilder let chart: () -> ChartBody
    @ViewBuilder let footer: () -> Footer

    public init(title: LocalizedStringKey, subtitle: String? = nil, trailing: String? = nil,
                badge: SourceBadge? = nil,
                height: CGFloat = NoopMetrics.chartHeight,
                @ViewBuilder chart: @escaping () -> ChartBody,
                @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing; self.badge = badge
        self.height = height; self.chart = chart; self.footer = footer
    }

    public var body: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).strandOverline()
                        if let subtitle { Text(subtitle).font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary) }
                    }
                    Spacer()
                    if let badge { badge }
                    if let trailing { Text(trailing).font(StrandFont.bodyNumber).foregroundStyle(InstrumentoTheme.base.ink) }
                }
                chart().frame(height: height).clipped()  // contain any mark overshoot to the plot frame so it never bleeds onto the footer
                let f = footer()
                if !(f is EmptyView) {
                    Divider().overlay(InstrumentoTheme.base.hairline)
                    f
                }
            }
        }
    }
}

/// A footer row of small "label / value" stats for ChartCard.
public struct ChartFooter: View {
    let items: [(LocalizedStringKey, String)]
    public init(_ items: [(LocalizedStringKey, String)]) { self.items = items }
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.0).textCase(.uppercase).font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
                    Text(it.1).font(StrandFont.captionNumber).foregroundStyle(InstrumentoTheme.base.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
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
    public init(_ items: [T], selection: Binding<T>, theme: InstrumentoTheme? = nil, label: @escaping (T) -> String) {
        self.items = items; self._selection = selection; self.theme = theme; self.label = label
    }
    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let sel = item == selection
                Button { withAnimation(StrandMotion.interactive) { selection = item } } label: {
                    Text(label(item))
                        // Instrumento reads a step larger (13 vs 12) and the active label gains weight, so
                        // the selector isn't a tiny strip; legacy keeps the compact mono caption. (FER-439)
                        .font(theme == nil ? StrandFont.captionNumber : StrandFont.subhead)
                        .fontWeight(sel && theme != nil ? .semibold : nil)
                        .lineLimit(1)                  // never wrap a pill label onto a 2nd line…
                        .minimumScaleFactor(0.8)       // …shrink a tight label (e.g. «TODO») instead (FER-275)
                        .foregroundStyle(segmentText(sel))
                        .frame(minWidth: 32, maxWidth: theme == nil ? nil : .infinity)
                        .padding(.vertical, theme == nil ? 6 : 8).padding(.horizontal, 11)
                        .background(segmentBackground(sel))
                        // ≥44pt touch target (the capsule stays compact, centered) — iOS minimum (FER-131 · 10).
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(trackFill, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(trackStroke, lineWidth: 1))
    }

    // Legacy (theme == nil) keeps the exact dark-palette values; the Instrumento variant maps to
    // paper-friendly tokens — active = a raised surface «thumb», not a faint tint.
    private func segmentText(_ sel: Bool) -> Color {
        guard let theme else { return sel ? InstrumentoTheme.base.paper : InstrumentoTheme.base.inkSecondary }
        return sel ? theme.ink : theme.inkSecondary
    }

    /// The per-segment background. Instrumento: the active segment is an iOS-native raised «thumb» —
    /// a `surface`-filled capsule with a hairline border that pops off the recessed `hairline` track
    /// (clear when unselected). Much clearer than the old `ink.opacity(0.08)` tint. (FER-439)
    @ViewBuilder private func segmentBackground(_ sel: Bool) -> some View {
        if let theme {
            Capsule(style: .continuous)
                .fill(sel ? theme.surface : Color.clear)
                .overlay {
                    if sel { Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1) }
                }
        } else {
            Capsule(style: .continuous).fill(sel ? StrandPalette.accent : Color.clear)
        }
    }

    // Instrumento track is a recessed `hairline` groove (so the lighter thumb reads as raised); legacy
    // keeps its original fill. The border stays for both.
    private var trackFill: Color { theme?.hairline ?? InstrumentoTheme.base.hairline }
    private var trackStroke: Color { theme?.hairlineStrong ?? InstrumentoTheme.base.hairline }
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
