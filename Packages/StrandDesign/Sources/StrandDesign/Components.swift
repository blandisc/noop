import SwiftUI

// MARK: - Shared design-system primitives
//
// What survives the «Instrumento diurno» migration: the spacing/measure token scale
// (`CenitMetrics`), the one segmented pill control, and the source badge. The legacy card
// primitives (`NoopCard` / `StatTile` / `SectionHeader` / `ChartCard` / `ChartFooter`) were
// removed once the dark screens that used them went away (FER-444, tail of FER-413/FER-427).

public enum CenitMetrics {
    public static let cardRadius: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let gap: CGFloat = 12          // gap between cards
    public static let cardGap: CGFloat = 4       // distancia ÚNICA entre elementos tipo tarjeta en toda la app (dueño 2026-08-29): apúntale desde cada pantalla, no repitas literales
    public static let sectionGap: CGFloat = 28   // gap between sections
    public static let screenPadding: CGFloat = 24
    /// Top inset of a titled tab landing — the same distance from the safe area for «Patrones»,
    /// «Tendencias», «Entrenar» and «Ajustes» so their `InstrumentoTabHeader` lines up as you swipe
    /// between tabs. «Hoy» is exempt: it's the dial dashboard and keeps its tighter `space2` rhythm.
    public static let screenTop: CGFloat = 14

    /// Alto de la hoja «En vivo»: overline + reloj de 56pt + Ritmo/Prom/Máx + «Terminar». Es un
    /// grabador, no una pantalla — con `.medium` (media pantalla) quedaba medio lienzo vacío. Este alto
    /// es el que el contenido pide de verdad; la hoja conserva `.large` como segundo detent y su
    /// `ScrollView`, así que con Dynamic Type grande se sube y nada se recorta.
    public static let liveSheetHeight: CGFloat = 320

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
    public static let touchTarget: CGFloat = 44        // área táctil mínima (HIG) — el glifo visible puede ser menor
    public static let rowVPad: CGFloat = 10          // padding vertical de una fila de lista «Instrumento» (handoff Biblioteca — absorbe 9/10/11/13)
    public static let receiptPadding: CGFloat = 14     // padding interno de la tarjeta-recibo de la sesión de fuerza (canvas 2026-07, decisión del dueño — entre gap 12 y cardPadding 16)

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
// Lock Screen a 160 pt, sin scroll). Por eso NO reusa `CenitMetrics`.
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

// MARK: - Home-screen widget metrics (FER-95 · E14)
//
// `TrainTodayWidget` (`.systemSmall`) and `WeekWidget` (`.systemMedium`) — WidgetKit's own fixed
// canvases, not a screen that reflows with Dynamic Type (see the epic's «Dynamic Type» note: these
// sizes are deliberately fixed, not a promise of xxxLarge/AX5 scaling). Sits beside `WidgetMetrics`
// for the same reason that one does: it's Live-Activity/widget-extension infrastructure, not a token
// of any one screen, so it lives outside `Entrenar/`.
public enum HomeWidgetMetrics {
    public static let padding: CGFloat = 16
    public static let overline: CGFloat = 11
    public static let overlineTracking: CGFloat = 1.2
    public static let title: CGFloat = 20           // el nombre de la rutina / «Hoy descansas» / «Abre Cénit»
    public static let cta: CGFloat = 13
    public static let verdict: CGFloat = 13
    public static let dayToken: CGFloat = 20
    public static let dayLabel: CGFloat = 10
    public static let rowGap: CGFloat = 6
    public static let weekGap: CGFloat = 10
}

// MARK: - Range control (the ONE segmented pill control, used everywhere)

public struct SegmentedPillControl<T: Hashable>: View {
    let items: [T]
    let label: (T) -> String
    @Binding var selection: T
    /// The «Instrumento diurno» theme. Renders an iOS-native segmented look on warm paper: a quiet
    /// track, an active segment that's a subtle ink capsule (no bright green), and ink labels. (FER-211;
    /// FER-902 retired the legacy dark `theme == nil` branch — every live screen passes a theme.)
    let theme: InstrumentoTheme
    /// «Ink thumb» variant (FER-716 handoff «Entrenar»): a `patternBlock` track with an `ink` active
    /// capsule and `paper` Grotesk label — the bolder segmented look the session's editor uses. Only
    /// meaningful with a `theme`; the default (`false`) keeps the quiet surface-thumb look.
    var inkThumb: Bool = false
    /// «Tall» variant (handoff v2 landing, FER-830): the themed segment grows to a 44pt touch height
    /// (iOS HIG minimum) instead of the compact 28pt — used for the Tendencias landing selector. Only
    /// meaningful with a `theme`; default keeps the compact height.
    var tall: Bool = false
    /// «Squared» (handoff FER-951) kept for call-site compat — the selector is now ALWAYS the
    /// rounded-RECT look (owner call 2026-07-15: one rectangular grammar everywhere), so the flag is
    /// accepted but no longer changes the shape. `thumbTint` paints the active segment in a data hue.
    var squared: Bool = false
    var thumbTint: Color? = nil
    /// SF Symbol opcional por segmento (r7: «♥» como carácter era tofu en Grotesk — el ícono va real).
    var icon: (T) -> String? = { _ in nil }
    public init(_ items: [T], selection: Binding<T>, theme: InstrumentoTheme,
                inkThumb: Bool = false, tall: Bool = false, squared: Bool = false,
                thumbTint: Color? = nil, icon: @escaping (T) -> String? = { _ in nil },
                label: @escaping (T) -> String) {
        self.items = items; self._selection = selection; self.theme = theme
        self.inkThumb = inkThumb; self.tall = tall; self.squared = squared
        self.thumbTint = thumbTint; self.icon = icon; self.label = label
    }
    public var body: some View {
        HStack(spacing: squared ? 3 : 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let sel = item == selection
                Button { withAnimation(StrandMotion.interactive) { selection = item } } label: {
                    segment(item, sel)
                }
                .buttonStyle(InstrumentoPressStyle())
                // VoiceOver announces which segment is active (FER-914).
                .accessibilityAddTraits(sel ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(trackFill))
    }

    /// One segment. Instrumento: the active «thumb» HUGS the label to the WIDTH (content-width, centered in
    /// the equal-width tap segment) but FILLS the track's HEIGHT — the capsule wraps a fixed-height frame, so
    /// it no longer floats small inside a taller groove. The thumb is 28pt tall, inset 3pt from the track
    /// edge like a slim iOS segmented control — a quiet secondary control, deliberately tighter than the
    /// 44pt min (the full segment width stays the tap target). (FER-439 / Detalle de Vital fix)
    @ViewBuilder private func segment(_ item: T, _ sel: Bool) -> some View {
        // Handoff v2 PeriodSelector: the active thumb is an INK capsule with PAPER text (Grotesk),
        // not the old quiet surface thumb — the bolder look the CompactTrendToggle already uses. The
        // «tall» variant grows to a 44pt touch height for the landing. (FER-835 unified the themed
        // active pill to the ink look; the `inkThumb` flag is now moot for themed selectors.)
        // r7 (owner): el thumb LLENA su segmento SIEMPRE (frame antes del background) y el ícono es
        // un SF Symbol real — «♥» como carácter era tofu en Grotesk.
        HStack(spacing: 5) {
            if let symbol = icon(item) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            }
            Text(label(item))
                .font(InstrumentoType.grotesk(12, weight: sel ? .bold : .medium))
                .tracking(0.6)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .foregroundStyle(sel ? theme.paper : theme.inkTertiary)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: tall ? 44 : 34)
        .background {
            if sel {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(thumbTint ?? theme.ink)
            }
        }
        .contentShape(Rectangle())
    }

    // Instrumento track is a recessed `hairline` groove (so the lighter thumb reads as raised); the border stays.
    private var trackFill: Color { theme.patternBlock }
    private var trackStroke: Color { .clear }
}

// MARK: - Badges

public struct SourceBadge: View {
    let text: LocalizedStringKey; var tint: Color = StrandPalette.accent
    public init(_ text: LocalizedStringKey, tint: Color = StrandPalette.accent) { self.text = text; self.tint = tint }
    public var body: some View {
        Text(text).textCase(.uppercase).font(StrandFont.scaled(10, weight: .semibold)).tracking(0.5)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
            .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
    }
}

// MARK: - In-screen title + ⓘ (FER-581 · «Instrumento» detail-screen identity)

/// The detail-screen headline: a Grotesk headline title (`groteskHeadline`, Medium — the serif voice
/// was retired in FER-901) with an optional ⓘ that toggles an inline plain-language explanation. One
/// source of truth so every detail sheet titles identically. The numeral, range bar and blocks live
/// BELOW this, unchanged. (FER-581)
public struct InstrumentoScreenTitle: View {
    let title: LocalizedStringKey
    var size: CGFloat
    var theme: InstrumentoTheme
    var explanation: LocalizedStringKey?
    /// When set, the title renders as the §8.7 overline (metric icon in its hue + ALL-CAPS grotesk)
    /// instead of the plain Grotesk headline — the standardized «Tendencias v2» header. Provenance is
    /// NOT here; it lives in the `OriginStamp` at the foot.
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
                        .font(InstrumentoType.groteskHeadline(size))
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

// MARK: - TroquelChip (sesión de fuerza · propuesta B 2026-07)

public extension View {
    /// Chip «troquel»: papel hundido dentro de una tarjeta `surface` — padding fijo, esquina
    /// `chipRadius`, borde `hairlineStrong`. El único hue permitido vive en el ICONO del contenido
    /// (excepción nombrada en DESIGN.md §8.7); el valor va en tinta.
    func troquelChip(_ theme: InstrumentoTheme) -> some View {
        self
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(theme.paper, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
    }
}

// MARK: - PresetPill (editor de descanso / RPE — gramática rectangular FER-951)

/// Preset rectangular «Instrumento»: thumb de TINTA al seleccionar, contorno `hairlineStrong` en
/// reposo. Una sola gramática para todos los presets de las hojas de la sesión (auditoría UI O2).
public struct PresetPill: View {
    let text: String
    let selected: Bool
    let theme: InstrumentoTheme
    let action: () -> Void

    public init(_ text: String, selected: Bool, theme: InstrumentoTheme, action: @escaping () -> Void) {
        self.text = text; self.selected = selected; self.theme = theme; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text).font(StrandFont.caption).monospacedDigit()
                .foregroundStyle(selected ? theme.paper : theme.inkSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .fill(selected ? theme.ink : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .strokeBorder(selected ? Color.clear : theme.hairlineStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("TroquelChip · PresetPill") {
    let t = InstrumentoTheme.base
    return VStack(spacing: 20) {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock").foregroundStyle(t.dataStrain)
                Text("90 s").font(StrandFont.caption.weight(.medium)).foregroundStyle(t.ink)
            }
            .troquelChip(t)
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil").foregroundStyle(t.dataHrv)
                Text("Nota").font(StrandFont.caption).foregroundStyle(t.inkSecondary)
            }
            .troquelChip(t)
        }
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        HStack(spacing: 8) {
            PresetPill("Sin descanso", selected: false, theme: t) {}
            PresetPill("1:00", selected: true, theme: t) {}
            PresetPill("2:00", selected: false, theme: t) {}
        }
    }
    .padding(24)
    .background(t.paper)
}
#endif
