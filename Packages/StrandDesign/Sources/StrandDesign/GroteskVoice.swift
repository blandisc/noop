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

    // MARK: Scale (handoff «Hoy» 2026-07)

    /// The «Hoy» hero numeral — 124/700, tracking −6 (apply `groteskHeroTracking`). FIXED.
    static let groteskHero = groteskNumber(124)
    /// Tracking for the 124pt hero numeral.
    static let groteskHeroTracking: CGFloat = -6

    /// A sheet's hero numeral — 56/700, tracking −2. FIXED.
    static let groteskSheetNumeral = groteskNumber(56)
    /// Tracking for the 56pt sheet numeral.
    static let groteskSheetNumeralTracking: CGFloat = -2

    /// The verdict word next to the hero («Equilibrado») — 20/700, scales with `.title3`.
    static let groteskVerdict = grotesk(20, weight: .bold, relativeTo: .title3)

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

    /// The active-lane label over a chart («EQUILIBRADO · HOY») — 12/700, tracking 1.8.
    static let groteskLane = grotesk(12, weight: .bold)
    /// Tracking for lane labels.
    static let groteskLaneTracking: CGFloat = 1.8
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
