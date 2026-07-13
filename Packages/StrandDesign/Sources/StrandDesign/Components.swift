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
    public static let insetRadius: CGFloat = 10        // sub-tarjeta anidada dentro de otra tarjeta (auditoría jul-2026, H3 — absorbe 9/10/11)

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

// MARK: - Live Activity metrics (auditoría jul-2026, H5)
//
// La escala de la tarjeta de Live Activity («Descanso»/sesión, `CenitWidgets/RestLiveActivity.swift`).
// Vive en el paquete —no como enum local del widget— para que sea parte del sistema de diseño y el
// linter de deriva no la marque. Tamaños FIJOS a propósito: geometría del Dynamic Island / Lock Screen,
// EXENTA de Dynamic Type (una Live Activity es más apretada que una pantalla y ActivityKit recorta el
// Lock Screen a 160 pt, sin scroll). Por eso NO reusa `NoopMetrics`.
//
// Disciplina de altura: los zones apilados + paddings deben sumar ≤ 160 pt o la fila de acciones se
// corta en silencio: 2·12 pad + 34 identidad + 8 + 34 hero + 8 + 4 barra + 8 + 44 acciones = 156 pt.
// Si tocas un valor aquí, re-corre esa suma.
public enum WidgetMetrics {
    public static let cardPadding: CGFloat = 12
    public static let hero: CGFloat = 28            // el único numeral dominante, en cada estado (decisión del dueño)
    public static let heroSlot: CGFloat = 34        // altura fija del hero-zone → altura de tarjeta constante entre estados
    public static let pulse: CGFloat = 17
    public static let name: CGFloat = 15            // ≤ hero, para que el hero siga siendo el único numeral dominante
    public static let overline: CGFloat = 11        // subtítulo de identidad + etiquetas «Al volver/Sigue/Tope»
    public static let overlineTracking: CGFloat = 1.4
    public static let returnValue: CGFloat = 15     // el «Serie N · peso × reps» que responde «¿qué sigue?»
    public static let thumb: CGFloat = 34
    public static let control: CGFloat = 44         // ≥44pt touch target (HIG)
    public static let glyph: CGFloat = 19
    public static let pillLabel: CGFloat = 13
    public static let bar: CGFloat = 4
    public static let segmentGap: CGFloat = 3
    public static let headerGap: CGFloat = 10
    public static let heroTopGap: CGFloat = 8
    public static let barTopGap: CGFloat = 8
    public static let actionsTopGap: CGFloat = 8
    public static let pillGap: CGFloat = 8
    public static let pillRadius: CGFloat = 11
    public static let controlRadius: CGFloat = 13
    public static let disabledOpacity: CGFloat = 0.4
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
    /// «Tall» variant (handoff v2 landing, FER-830): the themed segment grows to a 44pt touch height
    /// (iOS HIG minimum) instead of the compact 28pt — used for the Tendencias landing selector. Only
    /// meaningful with a `theme`; default keeps the compact height.
    var tall: Bool = false
    public init(_ items: [T], selection: Binding<T>, theme: InstrumentoTheme? = nil,
                inkThumb: Bool = false, tall: Bool = false, label: @escaping (T) -> String) {
        self.items = items; self._selection = selection; self.theme = theme
        self.inkThumb = inkThumb; self.tall = tall; self.label = label
    }
    public var body: some View {
        HStack(spacing: 4) {
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
        if let theme {
            // Handoff v2 PeriodSelector: the active thumb is an INK capsule with PAPER text (Grotesk),
            // not the old quiet surface thumb — the bolder look the CompactTrendToggle already uses. The
            // «tall» variant grows to a 44pt touch height for the landing. (FER-835 unified the themed
            // active pill to the ink look; the `inkThumb` flag is now moot for themed selectors.)
            Text(label(item))
                .font(InstrumentoType.grotesk(11, weight: sel ? .bold : .medium))
                .tracking(1.6)
                .lineLimit(1).minimumScaleFactor(0.85)
                .foregroundStyle(sel ? theme.paper : theme.inkTertiary)
                .padding(.horizontal, 12)
                .frame(height: tall ? 44 : 34)
                .background {
                    if sel { Capsule(style: .continuous).fill(theme.ink) }
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
        guard let theme else { return InstrumentoTheme.base.hairline }
        return theme.patternBlock
    }
    private var trackStroke: Color {
        theme == nil ? InstrumentoTheme.base.hairline : .clear
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
    /// When set, the title renders as the §8.7 overline (metric icon in its hue + ALL-CAPS grotesk)
    /// instead of the legacy serif — the standardized «Tendencias v2» header. Provenance is NOT here;
    /// it lives in the `OriginStamp` at the foot.
    var glyph: MetricGlyph?
    @State private var open = false

    public init(_ title: LocalizedStringKey, size: CGFloat = 23,
                theme: InstrumentoTheme, explanation: LocalizedStringKey? = nil,
                glyph: MetricGlyph? = nil) {
        self.title = title
        self.size = size
        self.theme = theme
        self.explanation = explanation
        self.glyph = glyph
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: glyph == nil ? .firstTextBaseline : .center, spacing: 6) {
                if let glyph {
                    Image(systemName: glyph.sfSymbol)
                        .font(.system(size: 12))
                        .foregroundStyle(glyph.hue(theme))
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(InstrumentoType.grotesk(12, weight: .bold))
                        .tracking(2.4)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                } else {
                    Text(title)
                        .font(StrandFont.serif(size))
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
