import SwiftUI

// MARK: - «Instrumento» evolved type voice — Space Grotesk (FER-707/708)
//
// The 2026-07 «Hoy» redesign evolves the daytime language's voice: Space Grotesk
// (bundled, OFL) carries the numerals, sheet titles, overlines, lane labels, tabs and
// buttons; the system face (SF) keeps body copy and microcopy. Numerals are ALWAYS
// tabular. The serif verdict face is superseded by this voice and retires once the
// migration completes (FER-710).
//
// Sizing philosophy (same as the legacy scale): numerals embedded in geometry (the hero
// figure, sheet numerals, tile values) are FIXED — they scale with layout, not Dynamic
// Type. Reading text stays on SF with its Dynamic Type anchors. Overlines/labels are
// chrome, fixed like `tabTitle`.
//
// The faces are static instances referenced by PostScript name (the Google static builds
// ship weight-suffixed family names, so the PS name is the one stable identifier).

public enum GroteskWeight {
    case regular    // 400
    case medium     // 500
    case semibold   // 600 — instanced from the official variable font
    case bold       // 700

    var postScriptName: String {
        switch self {
        case .regular:  return "SpaceGrotesk-Regular"
        case .medium:   return "SpaceGrotesk-Medium"
        case .semibold: return "SpaceGrotesk-SemiBold"
        case .bold:     return "SpaceGrotesk-Bold"
        }
    }
}

public extension InstrumentoType {

    // MARK: Base face

    /// Space Grotesk at an arbitrary fixed size. For numerals pair with `.monospacedDigit()`
    /// via the `groteskNumber(_:weight:)` variant, which bakes it in.
    static func grotesk(_ size: CGFloat, weight: GroteskWeight = .regular) -> Font {
        StrandFont.ensureFontsRegistered()
        return .custom(weight.postScriptName, fixedSize: size)
    }

    /// Space Grotesk that scales with Dynamic Type relative to a text style — for the few
    /// grotesk tokens that are read as text (the verdict word, sheet headlines).
    static func grotesk(_ size: CGFloat, weight: GroteskWeight = .regular, relativeTo style: Font.TextStyle) -> Font {
        StrandFont.ensureFontsRegistered()
        return .custom(weight.postScriptName, size: size, relativeTo: style)
    }

    /// A tabular-digit Space Grotesk numeral at a fixed size. Every live value uses this so
    /// digits never reflow.
    static func groteskNumber(_ size: CGFloat, weight: GroteskWeight = .bold) -> Font {
        grotesk(size, weight: weight).monospacedDigit()
    }

    /// A tabular-digit numeral that scales with Dynamic Type (auditoría UX sesión de fuerza,
    /// 2026-07): las celdas de captura son texto que el usuario dimensiona — antes de AX1 los
    /// tamaños intermedios (L–xxxLarge) no movían ni un dato.
    static func groteskNumber(_ size: CGFloat, weight: GroteskWeight = .bold,
                              relativeTo style: Font.TextStyle) -> Font {
        grotesk(size, weight: weight, relativeTo: style).monospacedDigit()
    }

    // MARK: Scale (handoff «Hoy» 2026-07)

    /// The «Hoy» hero numeral — 102/700, tracking −4.5 (apply `groteskHeroTracking`).
    /// (FER-743 lo bajó de 124 a 96 para compactar SEÑALES sin scroll; FER-878 follow-up lo dejó en 98
    /// tras medir que 104 metía scroll. Ahora sube a 102 —dominante pero por debajo del 104 que scrolleó—
    /// y el alto EXTRA se reclama en TodayView subiendo `heroNumeralBottomInk` (descenso vacío) y bajando
    /// el margen inferior de los page dots, de modo que el neto de SEÑALES queda casi igual y sigue sin
    /// scroll. El numeral manda el alto de la fila del héroe, así que es lo que pesa contra el fit.)
    static let groteskHero = groteskNumber(102)
    /// Tracking for the hero numeral.
    static let groteskHeroTracking: CGFloat = -4.5

    /// The dominant numeral at an *arbitrary* size — the evolved-voice successor to the retired
    /// SF Mono `hero(_:)` (FER-900: Space Grotesk canonized as the protagonist-numeral voice).
    /// Detail screens set their hero at many sizes (26…90); pair with `groteskHeroTrackingScaled(_:)`.
    static func groteskHeroNumeral(_ size: CGFloat = 72, weight: GroteskWeight = .bold) -> Font {
        groteskNumber(size, weight: weight)
    }
    /// Size-aware negative tracking for `groteskHeroNumeral(_:)`. Grotesk sets tighter than Mono, so the
    /// fixed 102pt hero uses −4.5 (≈ −0.044·size); this mirrors that ratio and, like the old
    /// `heroTracking`, relaxes to ~0 below 28pt so small figures don't crowd. (FER-900)
    static func groteskHeroTrackingScaled(_ size: CGFloat) -> CGFloat {
        size >= 28 ? -size * 0.044 : 0
    }

    /// A sheet's hero numeral — 56/700, tracking −2. FIXED.
    static let groteskSheetNumeral = groteskNumber(56)
    /// Tracking for the 56pt sheet numeral.
    static let groteskSheetNumeralTracking: CGFloat = -2

    /// The live-monitor BPM numeral in «Latidos» — 52/700 tabular, tracking −1.5. Slightly quieter than
    /// a scored sheet's hero (the ECG is the hero here). FIXED (geometry-driven). (FER-729)
    static let groteskLiveBpm = groteskNumber(52)
    /// Tracking for the live BPM numeral.
    static let groteskLiveBpmTracking: CGFloat = -1.5

    /// The verdict word next to the hero («Equilibrado») — 22/700, scales with `.title3`.
    static let groteskVerdict = grotesk(22, weight: .bold, relativeTo: .title3)

    /// An in-screen headline — the Grotesk successor to the retired `StrandFont.serif(_:)` (FER-901:
    /// the serif title voice retires). Medium (500), not bold, so it keeps the airy editorial presence
    /// the serif had rather than reading as a loud datum; scales with Dynamic Type relative to `.title2`.
    /// Verdict *phrases* (the datum) stay on `groteskVerdict` (Bold). (FER-901)
    static func groteskHeadline(_ size: CGFloat) -> Font {
        grotesk(size, weight: .medium, relativeTo: .title2)
    }

    /// A sheet title — 12/700, tracking 2.4, ALL-CAPS (`groteskSheetTitle(_: )` on `Text` bakes
    /// the case + tracking in). FIXED chrome.
    static let groteskSheetTitle = grotesk(12, weight: .bold)
    /// Tracking for sheet titles.
    static let groteskSheetTitleTracking: CGFloat = 2.4

    /// The evolved overline — 10/600, tracking 2, ALL-CAPS. Quieter partner: 9/600 via
    /// `groteskOverlineSmall`. FIXED chrome.
    static let groteskOverline = grotesk(10, weight: .semibold)
    /// The smallest overline (group labels inside instruments) — 9/600.
    static let groteskOverlineSmall = grotesk(9, weight: .semibold)
    /// Tracking for the grotesk overlines (1.6…2.4 in the handoff; 2 is the anchor).
    static let groteskOverlineTracking: CGFloat = 2

    /// A metric tile's value — 21/700, tabular. FIXED (geometry-driven).
    static let groteskTileValue = groteskNumber(21)

    /// Pager tabs («SEÑALES / BRIEF») — 11/700, tracking 2, ALL-CAPS. FIXED chrome.
    static let groteskTab = grotesk(11, weight: .bold)
    /// Tracking for pager tabs.
    static let groteskTabTracking: CGFloat = 2

    /// The tab/landing wordmark («Entrenar» / «Tendencias» / «Patrones» / «Ajustes») — 21/600,
    /// tracking −0.5. Same size/weight as the retired SF `tabTitle` so the lockup keeps its height
    /// and baseline across tabs (FER-557); Grotesk sets wider, hence the softer negative tracking.
    /// FIXED chrome (same no-Dynamic-Type criterion as `tabTitle`). FER-944.
    static let groteskTabTitle = grotesk(21, weight: .semibold)
    /// Tracking for the tab wordmark.
    static let groteskTabTitleTracking: CGFloat = -0.5

    /// The active-lane label over a chart («EQUILIBRADO · HOY») — 12/700, tracking 1.8.
    static let groteskLane = grotesk(12, weight: .bold)
    /// Tracking for lane labels.
    static let groteskLaneTracking: CGFloat = 1.8

    // MARK: Entrenar v3 session (FER-716) — sizes from the «Flujo Entrenar v3» handoff. All FIXED
    // (geometry-driven numerals / chrome), all tabular where they carry a live value.

    /// The strength session's running clock («23:41») — 27/700 tabular, tracking −1. FIXED.
    static let groteskSessionClock = groteskNumber(27)
    static let groteskSessionClockTracking: CGFloat = -1

    /// The compact v21 header clock — the same running datum sat inline beside the BPM in the 2-row
    /// header (Sesión v21), one size down from the dominant clock — 22/700 tabular, shares the −1 tracking.
    static let groteskSessionClockInline = groteskNumber(22)

    /// The rest card's live datum — the pulse dropping toward the threshold, or the time countdown
    /// («116» / «1:12») — 38/600 tabular, tracking −0.8. FIXED.
    static let groteskRestPulse = groteskNumber(38, weight: .semibold)
    static let groteskRestPulseTracking: CGFloat = -0.8

    /// A push-screen title inside the session («Descanso al terminar») — 25/700, tracking −0.9. FIXED.
    static let groteskScreenTitle = grotesk(25, weight: .bold)
    static let groteskScreenTitleTracking: CGFloat = -0.9

    /// The receipt's editorial headline («Pierna, hecha.») — 26/700, tracking −1. FIXED (read as a
    /// title, but sized to the layout like the other grotesk headlines).
    static let groteskReceiptHeadline = grotesk(26, weight: .bold)
    static let groteskReceiptHeadlineTracking: CGFloat = -1

    /// A receipt metric's value (duration / volume / strain / kcal) — 22/700 tabular, tracking −0.8. FIXED.
    static let groteskReceiptStat = groteskNumber(22)
    static let groteskReceiptStatTracking: CGFloat = -0.8
}

// MARK: - Text helpers

public extension Text {
    /// The «Hoy» hero numeral: 124/700 tabular with its negative tracking. Color it with a
    /// *data* role; everything else stays ink.
    func groteskHero() -> Text {
        self.font(InstrumentoType.groteskHero)
            .tracking(InstrumentoType.groteskHeroTracking)
    }

    /// A sheet's hero numeral: 56/700 tabular with its negative tracking.
    func groteskSheetNumeral() -> Text {
        self.font(InstrumentoType.groteskSheetNumeral)
            .tracking(InstrumentoType.groteskSheetNumeralTracking)
    }

    /// An evolved ALL-CAPS overline (10/600, +2 tracking). Tertiary ink by default — pass a
    /// tint only when the overline itself is the datum.
    func groteskOverline(small: Bool = false) -> some View {
        self.font(small ? InstrumentoType.groteskOverlineSmall : InstrumentoType.groteskOverline)
            .tracking(InstrumentoType.groteskOverlineTracking)
            .textCase(.uppercase)
    }

    /// A sheet title: 12/700, +2.4 tracking, ALL-CAPS.
    func groteskSheetTitle() -> some View {
        self.font(InstrumentoType.groteskSheetTitle)
            .tracking(InstrumentoType.groteskSheetTitleTracking)
            .textCase(.uppercase)
    }
}

#if DEBUG
#Preview("Grotesk · especímenes") {
    let t = InstrumentoTheme.base
    return ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            Text("74").groteskHero().foregroundStyle(t.dataRecovery)
            Text("Equilibrado").font(InstrumentoType.groteskVerdict).foregroundStyle(t.dataRecovery)
            Text("56").groteskSheetNumeral().foregroundStyle(t.dataSleep)
            Text("Recuperación").groteskSheetTitle().foregroundStyle(t.ink)
            Text("Por qué 74").groteskOverline().foregroundStyle(t.inkTertiary)
            Text("El largo es el peso").groteskOverline(small: true).foregroundStyle(t.inkTertiary)
            HStack(spacing: 16) {
                Text("SEÑALES").font(InstrumentoType.groteskTab).tracking(InstrumentoType.groteskTabTracking).foregroundStyle(t.ink)
                Text("BRIEF").font(InstrumentoType.groteskTab).tracking(InstrumentoType.groteskTabTracking).foregroundStyle(t.inkMuted)
            }
            Text("Entrenar").font(InstrumentoType.groteskTabTitle).tracking(InstrumentoType.groteskTabTitleTracking).foregroundStyle(t.ink)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("7:12").font(InstrumentoType.groteskTileValue).foregroundStyle(t.dataSleep)
                Text("h").font(StrandFont.footnote).foregroundStyle(t.inkTertiary)
            }
            Text("Equilibrado · Hoy").font(InstrumentoType.groteskLane).tracking(InstrumentoType.groteskLaneTracking).textCase(.uppercase).foregroundStyle(t.dataRecovery)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
