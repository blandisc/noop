import SwiftUI

// MARK: - Shared design-system primitives
//
// What survives the «Instrumento diurno» migration: the spacing/measure token scale
// (`CenitMetrics`), the one segmented pill control, and the source badge. The legacy dark-theme
// card primitives were removed once the dark screens that used them went away (FER-444, tail of
// FER-413/FER-427) — see `docs/design-system/CATALOGO.md` for what replaced them.

public enum CenitMetrics {
    /// 16 — radio de `ChartWell` / wells Instrumento. Distinto de `LiquidRadius.tarjeta` (18);
    /// no hay token Liquid del mismo valor (FER-319).
    public static let cardRadius: CGFloat = 16
    /// 14 — radio de la barra CTA de tinta (`CenitCTAButton`). Sin `LiquidRadius` de 14 (FER-319).
    public static let ctaRadius: CGFloat = 14
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
    /// El ÚNICO radio de esquina para cualquier control-slab rectangular de la tarjeta (`PrimaryButton`,
    /// `PillButton`, `GlyphButton`) — FER-225: antes convivían 13 (`controlRadius`) y 11 (`pillRadius`)
    /// en la misma tarjeta de 12pt de padding sin razón visual. Regla escrita: un track que deba llegar
    /// a pastilla TOTALMENTE redonda (p. ej. `BarSlot`) SIEMPRE deriva su radio de su propia altura
    /// (`altura / 2`), nunca de una constante independiente — así el sistema solo tiene DOS radios: este
    /// token, y esa fórmula derivada.
    public static let controlRadius: CGFloat = 13
    /// Aire fino entre nombre y overline (`IdentityRow`) y entre el glifo de pulso y el número
    /// (`PulseChip`) — FER-225, antes un `spacing: 3` crudo en cada call site.
    public static let captionGap: CGFloat = 3
    /// Aire mínimo entre dos líneas de una pila muy compacta («Tope»+reloj en `IdentityRow.trailing`,
    /// etiqueta+valor en `ReturnBlock`) — FER-225, antes un `spacing: 2` crudo repetido en ambos sitios.
    public static let microGap: CGFloat = 2
    /// Aire entre el glifo de corazón y el número en `PulseHero` — FER-225, antes un `spacing: 6` crudo.
    public static let pulseIconGap: CGFloat = 6
    /// `Text(timerInterval:)` es GREEDY: reclama todo el ancho que se le ofrezca, lo que estiraba la
    /// isla compacta a lo ancho del recorte entero. Este multiplicador (× el tamaño de punto) topa el
    /// ancho a ~«10:00» — 5 dígitos/dos-puntos monoespaciados a la fuente redondeada cubren el peor caso
    /// de un descanso de hasta 99:59 — para que la píldora vuelva a abrazar su contenido. FER-225: antes
    /// un `size * 3` sin nombre en `RestTimerText`.
    public static let timerWidthMultiplier: CGFloat = 3
    public static let disabledOpacity: CGFloat = 0.4
    /// Iniciales del thumb cuando no hay miniatura (Lock Screen).
    public static let thumbInitials: CGFloat = 13
    // Dynamic Island — tamaños de fuente fijos de ActivityKit (FER-311). Familia propia:
    // no reusa `LiquidType` (Apple fija 12–13 compact/minimal; expanded es geometría de isla).
    // Gaps de isla reusan tokens ya existentes (`microGap`, `pulseIconGap`, `captionGap`, `LiquidSpace.s100`).
    /// Compact leading/trailing numeral (13).
    public static let islandCompact: CGFloat = 13
    /// Compact pause / secondary glyph (12).
    public static let islandCompactGlyph: CGFloat = 12
    /// Compact heart glyph beside the pulse (10).
    public static let islandCompactHeart: CGFloat = 10
    /// Compact rest timer numeral (15).
    public static let islandCompactTimer: CGFloat = 15
    /// Minimal region numeral (12).
    public static let islandMinimal: CGFloat = 12
    /// Minimal pause glyph (11).
    public static let islandMinimalGlyph: CGFloat = 11
    /// Expanded hero numeral (26).
    public static let islandExpandedHero: CGFloat = 26
    /// Expanded secondary («/ Y») (16).
    public static let islandExpandedSecondary: CGFloat = 16
    /// Expanded «On pause» (20).
    public static let islandExpandedPause: CGFloat = 20
    /// Expanded HR target beside the pulse (15).
    public static let islandExpandedTarget: CGFloat = 15
    /// Expanded heart glyph in the hero stack (14).
    public static let islandExpandedHeart: CGFloat = 14
    /// Expanded timer glyph beside the countdown (13).
    public static let islandExpandedTimerGlyph: CGFloat = 13
    /// Expanded trailing pulse numeral (16).
    public static let islandExpandedPulse: CGFloat = 16
    /// Expanded trailing pulse glyph (13).
    public static let islandExpandedPulseGlyph: CGFloat = 13
    /// Expanded «CAP» overline (9).
    public static let islandCapLabel: CGFloat = 9
    /// Expanded cap timer numeral (14).
    public static let islandCapTimer: CGFloat = 14
    /// Expanded bottom caption (12).
    public static let islandBottomCaption: CGFloat = 12
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
    /// Aire fino entre la overline «Today» y el título, y entre el veredicto y el CTA (`headerRow`) —
    /// FER-225, antes un `spacing: 2` crudo que no calzaba con `rowGap` (6pt, demasiado para esta pila).
    public static let microGap: CGFloat = 2
    /// Aire entre el token del día y su letra en `WeekStrip` — FER-225, antes un `spacing: 4` crudo.
    public static let dayTokenGap: CGFloat = 4
    /// Grosor del anillo «hoy» en `WeekStrip.token` — FER-225, antes un `lineWidth: 2` crudo.
    public static let ringToday: CGFloat = 2
    /// Grosor del anillo «próximo» — FER-225, antes un `lineWidth: 1.5` crudo.
    public static let ringUpcoming: CGFloat = 1.5
    /// Grosor del anillo punteado «descanso» — FER-225, antes un `lineWidth: 1` crudo.
    public static let ringRest: CGFloat = 1
    /// Patrón de punteado del anillo «descanso» — FER-225, antes un `dash: [2, 3]` crudo.
    public static let ringRestDash: [CGFloat] = [2, 3]
}

// MARK: - Watch geometry (FER-225)
//
// `WatchLiveFaceView`/`WatchSummaryView` had NO shared geometry token before this — every touch height
// and hero size was a raw literal, independently invented per screen. This enum only NAMES what the
// audit found; it does NOT unify the values, since collapsing them (e.g. 38→44) is a real layout change
// past this issue's ≤2pt geometry-snap budget. The finding stands as a reported inconsistency, not a
// silent fix: FOUR different heights exist for equivalent buttons — `ctaHeight` (the wrist «Registrar
// serie»), `pillHeight` (±30/Saltar), `controlHeight` (the control-page's Saltar/Registrar/Terminar),
// `summarySecondaryHeight`/`summaryPrimaryHeight` (the end-of-session sheet) — alongside
// `LiquidControl.hitTarget` (44pt), which `WatchSessionRootView` already uses on its own primary CTA.
public enum WatchMetrics {
    public static let ctaHeight: CGFloat = 38
    public static let pillHeight: CGFloat = 30
    public static let controlHeight: CGFloat = 40
    public static let summarySecondaryHeight: CGFloat = 40
    public static let summaryPrimaryHeight: CGFloat = 44

    // Hero numerals — four raw sizes with no shared scale before this.
    public static let heroPulse: CGFloat = 52
    public static let heroRestCountdown: CGFloat = 44
    public static let heroReadiness: CGFloat = 36
    public static let heroSummaryDuration: CGFloat = 40
}

// MARK: - Range control (the ONE segmented pill control, used everywhere)

public struct SegmentedPillControl<T: Hashable>: View {
    let items: [T]
    let label: (T) -> String
    @Binding var selection: T
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
    /// - Parameter theme: ignored for painting (LiquidColor). Kept for call-site compatibility (FER-316).
    public init(_ items: [T], selection: Binding<T>, theme: InstrumentoTheme = .base,
                inkThumb: Bool = false, tall: Bool = false, squared: Bool = false,
                thumbTint: Color? = nil, icon: @escaping (T) -> String? = { _ in nil },
                label: @escaping (T) -> String) {
        self.items = items; self._selection = selection
        _ = theme
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
        // El Eje: el track deja el papel beige (`patternBlock`) por la pastilla sólida de vidrio del
        // sistema — el thumb ink/tinta sigue destacando sobre ella (mismo gesto que los chips migrados).
        .liquidGlass(.pastillaSolida)
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
        .foregroundStyle(sel ? LiquidColor.papelTarjeta : LiquidColor.tinta500)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: tall ? 44 : 34)
        .background {
            if sel {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(thumbTint ?? LiquidColor.tinta900)
            }
        }
        .contentShape(Rectangle())
    }

}

// MARK: - TroquelChip (sesión de fuerza · propuesta B 2026-07)

public extension View {
    /// Chip «troquel»: papel hundido dentro de una tarjeta — padding fijo, esquina
    /// `chipRadius`, borde tinta. El único hue permitido vive en el ICONO del contenido
    /// (excepción nombrada en DESIGN.md §8.7); el valor va en tinta.
    /// - Parameter theme: ignored for painting (LiquidColor). Kept for call-site compatibility (FER-316).
    func troquelChip(_ theme: InstrumentoTheme = .base) -> some View {
        _ = theme
        return self
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(LiquidColor.fondoAlto, in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous)
                .strokeBorder(LiquidColor.tinta10, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
    }
}

#if DEBUG
#Preview("TroquelChip") {
    HStack(spacing: 8) {
        HStack(spacing: 6) {
            Image(systemName: "clock").foregroundStyle(LiquidColor.ambar)
            Text("90 s").font(StrandFont.caption.weight(.medium)).foregroundStyle(LiquidColor.tinta900)
        }
        .troquelChip()
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil").foregroundStyle(LiquidColor.cian)
            Text("Nota").font(StrandFont.caption).foregroundStyle(LiquidColor.tinta700)
        }
        .troquelChip()
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}
#endif
