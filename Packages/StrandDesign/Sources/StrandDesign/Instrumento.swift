import SwiftUI

// MARK: - «Instrumento diurno» — the daytime design language (FER-131)
//
// A second visual language that lives ALONGSIDE the dark, instrument-grade
// `StrandPalette` (which every shipped screen still uses). Where the legacy
// system is a near-black instrument panel, this one reads like a precision
// instrument printed on warm paper:
//
//   • Light mode, warm paper — calm off-white, never pure white.
//   • One dominant number — a screen has a single hero figure; everything else
//     is subordinate (see the hierarchy rules below).
//   • Color ONLY in the datum — saturated hue appears on the measured value
//     (recovery / strain / verdict), never as chrome. Labels are ink, not color.
//   • Hierarchy by space, not by boxes — no card-in-card; whitespace separates,
//     hairlines divide, surfaces are used sparingly.
//   • AA at every hour — every text/background pair clears WCAG AA.
//
// The roles are an instance `struct` (not static like `StrandPalette`) on
// purpose: the by-the-hour theme engine (FER-132) produces dawn/day/dusk/night
// variants by interpolating these same roles. `.base` is the neutral daytime
// anchor that engine starts from. FER-131 ships only `.base`; nothing here
// touches the legacy palette or any screen.

/// The semantic color roles of the «Instrumento diurno» language, in one
/// instance so the hour engine (FER-132) can vary them. Inject with
/// `.instrumentoTheme(_:)`; read with `@Environment(\.instrumentoTheme)`.
public struct InstrumentoTheme: Equatable {

    // MARK: Surfaces — warm paper
    /// App canvas — warm bone paper (never pure white).
    public let paper: Color
    /// A sparingly-used raised surface (sheets / the rare contained group).
    public let surface: Color
    /// 1px divider — a faint warm rule.
    public let hairline: Color
    /// 1px divider on emphasis / hover.
    public let hairlineStrong: Color

    // MARK: Ink — warm grays (warm dark advances, cooler light recedes)
    /// Primary text & the hero numeral.
    public let ink: Color
    /// Supporting copy and labels.
    public let inkSecondary: Color
    /// Overlines, captions, axis — the quietest ink, still AA.
    public let inkTertiary: Color

    // MARK: Data accents — color lives ONLY on the measured value
    /// Recovery / "good" data hue (deep health green, AA on paper at numeral size).
    public let dataRecovery: Color
    /// Strain / "output" data hue (deep ember-orange).
    public let dataStrain: Color
    /// Sleep trend hue (per-metric chart color). FER-147.
    public let dataSleep: Color
    /// HRV trend hue. FER-147.
    public let dataHrv: Color
    /// Heart-rate trend hue — shared by Heart Rate and Resting HR. FER-147.
    public let dataHeart: Color
    /// Blood-oxygen trend hue. FER-147.
    public let dataSpO2: Color
    /// Steps trend hue. FER-147.
    public let dataSteps: Color

    // MARK: Verdict / state
    /// The day's verdict accent (defaults to the positive green).
    public let verdict: Color
    /// Caution / "strained".
    public let warning: Color
    /// Depleted / error — a contained brick red (red is reserved for genuine
    /// alert in an analytical context, never used as chrome).
    public let critical: Color

    public init(
        paper: Color, surface: Color, hairline: Color, hairlineStrong: Color,
        ink: Color, inkSecondary: Color, inkTertiary: Color,
        dataRecovery: Color, dataStrain: Color,
        dataSleep: Color, dataHrv: Color, dataHeart: Color, dataSpO2: Color, dataSteps: Color,
        verdict: Color, warning: Color, critical: Color
    ) {
        self.paper = paper; self.surface = surface
        self.hairline = hairline; self.hairlineStrong = hairlineStrong
        self.ink = ink; self.inkSecondary = inkSecondary; self.inkTertiary = inkTertiary
        self.dataRecovery = dataRecovery; self.dataStrain = dataStrain
        self.dataSleep = dataSleep; self.dataHrv = dataHrv; self.dataHeart = dataHeart
        self.dataSpO2 = dataSpO2; self.dataSteps = dataSteps
        self.verdict = verdict; self.warning = warning; self.critical = critical
    }

    /// The neutral daytime anchor. Every hex below clears WCAG AA on `paper`
    /// (ink 14.8:1 · secondary 6.5:1 · tertiary 4.9:1; data accents ≥3.6:1 at
    /// numeral size where AA-large is 3:1; critical 4.9:1). Verified in
    /// `InstrumentoSnapshotTests`.
    public static let base = InstrumentoTheme(
        paper:          Color(hex: "#F4F1E8"),
        surface:        Color(hex: "#FBF9F2"),
        hairline:       Color(hex: "#E6E0D2"),
        hairlineStrong: Color(hex: "#D8D0BD"),
        ink:            Color(hex: "#221D16"),
        inkSecondary:   Color(hex: "#5C5648"),
        inkTertiary:    Color(hex: "#6F6857"),
        dataRecovery:   Color(hex: "#0C8F62"),
        dataStrain:     Color(hex: "#C4631F"),
        dataSleep:      Color(hex: "#5D5A9E"),
        dataHrv:        Color(hex: "#147C8C"),   // FER-206: cian, distinguible del verde-veredicto (4.33:1 AA)
        dataHeart:      Color(hex: "#B85068"),
        dataSpO2:       Color(hex: "#3B6FA0"),
        dataSteps:      Color(hex: "#4C8998"),
        verdict:        Color(hex: "#0C8F62"),
        warning:        Color(hex: "#9C5E10"),
        critical:       Color(hex: "#BC3A34")
    )
}

// MARK: - HR-zone ramp (workout detail)

public extension InstrumentoTheme {
    /// The five heart-rate-zone colors for the «Instrumento» language (Z1 calm → Z5 intense), used by
    /// the workout-session detail's zone bar. The legacy `StrandPalette.hrZoneColor` is tuned for the
    /// dark system (bright hues on near-black) and muddies on warm paper, so the daytime detail uses
    /// this warm ramp instead — cool-calm at the bottom, rising into the ember `dataStrain` family at
    /// the top. Computed (not stored) so it needs no change to the theme's init or the hour engine. A
    /// bar fill, not text, so AA-on-paper isn't required; the zone % carries the meaning. (FER-261)
    var hrZoneRamp: [Color] {
        [Color(hex: "#8FA98C"), Color(hex: "#C8A24A"), Color(hex: "#D98A3D"),
         Color(hex: "#C4631F"), Color(hex: "#9C3D14")]
    }

    /// An AA-at-text-size positive green, for the rare case a POSITIVE signal must ride
    /// SMALL text (the Today metric tile's "↑ N vs media" delta, 12pt) rather than a large
    /// numeral. `verdict` is tuned for AA-LARGE (3:1 at ≥18pt where the dominant numerals
    /// live); at 12pt body text needs 4.5:1, which `verdict` misses at every hour (3.6:1 on
    /// day paper, ~3.2:1 on the dimmer night paper). This darkens `verdict` in OKLab —
    /// keeping its hue — only as far as needed to clear 4.5:1 against the CURRENT (already
    /// hour-interpolated) `paper`, so the positive delta stays WCAG-AA across the whole 24h
    /// sweep with no hand-tuned hex per anchor. `critical` already clears 4.5:1 (≈4.6:1 even
    /// at night), so the negative delta keeps using it directly. Computed (like `hrZoneRamp`)
    /// so it needs no change to the theme's init or the hour engine. (Auditoría Hoy · P1)
    var positiveText: Color {
        OKLab.darkened(verdict, toContrast: 4.5, against: paper)
    }
}

// MARK: - Environment injection

private struct InstrumentoThemeKey: EnvironmentKey {
    static let defaultValue = InstrumentoTheme.base
}

public extension EnvironmentValues {
    /// The active «Instrumento diurno» theme. Defaults to `.base`; the hour
    /// engine (FER-132) overrides it per time of day.
    var instrumentoTheme: InstrumentoTheme {
        get { self[InstrumentoThemeKey.self] }
        set { self[InstrumentoThemeKey.self] = newValue }
    }
}

public extension View {
    /// Inject an «Instrumento diurno» theme for this subtree.
    func instrumentoTheme(_ theme: InstrumentoTheme) -> some View {
        environment(\.instrumentoTheme, theme)
    }
}

// MARK: - Type voice
//
// «Instrumento diurno» mostly reuses SF Pro with tabular digits (the legacy
// `StrandFont`). It adds only the two moves the language is opinionated about: the
// protagonist numeral and a quieter overline. The hero numeral is set in SF Mono
// (FER-206) so the dominant figure reads like an instrument's printed read-out, not
// the system font blown up — the rest of the scale stays SF Pro.

public enum InstrumentoType {

    /// The protagonist numeral — large, semibold, monospaced (SF Mono, inherently
    /// tabular) so the dominant figure reads like an instrument read-out. Pair with
    /// `heroTracking(_:)` so big figures read tight, not loose.
    public static func hero(_ size: CGFloat = 72) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Negative tracking for a hero numeral. Large type set at default spacing
    /// reads loose; pulling it in (~-1.6pt at 72) makes the figure feel like one
    /// machined object. Scales with size; ~0 below 28pt.
    public static func heroTracking(_ size: CGFloat) -> CGFloat {
        size >= 28 ? -size * 0.022 : 0
    }

    /// A moderate overline — medium (not semibold), gentler tracking than the
    /// legacy 0.8. Loud enough to label, quiet enough not to compete with data.
    public static let overline = Font.system(size: 12, weight: .medium)
    /// Recommended tracking for `overline`.
    public static let overlineTracking: CGFloat = 0.6
}

// MARK: - Text helpers

public extension Text {
    /// The dominant numeral: tabular hero font + size-aware negative tracking.
    /// Color it with a *data* role (`dataRecovery` / `dataStrain` / `verdict`);
    /// leave everything else in ink.
    func instrumentoHero(_ size: CGFloat = 72) -> Text {
        self.font(InstrumentoType.hero(size))
            .tracking(InstrumentoType.heroTracking(size))
            .monospacedDigit()
    }

    /// A moderate, uppercased overline. Tertiary ink by default — pass a tint
    /// only when the overline itself is the datum.
    func instrumentoOverline() -> some View {
        self.font(InstrumentoType.overline)
            .tracking(InstrumentoType.overlineTracking)
            .textCase(.uppercase)
    }
}

// MARK: - Hierarchy rules (documentation, enforced by review)
//
// The language is four rules. They are not tokens — they are how the tokens are
// allowed to combine. `/qa` and the design doc check screens against them.
//
//  1. ONE DOMINANT ELEMENT. Each screen has a single hero (usually the recovery
//     or strain numeral). Nothing else may match its size/weight; rivals are
//     demoted in size, weight, or to ink.
//  2. COLOR ONLY IN THE DATUM. Saturated hue (`dataRecovery`/`dataStrain`/
//     `verdict`/`warning`/`critical`) appears on a measured value, never on
//     chrome, labels, icons-as-decoration, or backgrounds.
//  3. HIERARCHY BY SPACE, NOT BOXES. Group with whitespace and hairlines.
//     No card-in-card; `surface` is the exception, used sparingly and never
//     nested.
//  4. MODERATE OVERLINE. Labels are quiet (`instrumentoOverline`, tertiary ink).
//     They orient; they do not announce.

#if DEBUG
#Preview("Instrumento · tokens") {
    let t = InstrumentoTheme.base
    return ScrollView {
        VStack(alignment: .leading, spacing: 28) {
            // Rule 1 + 2: one dominant numeral, colored because it's the datum.
            VStack(alignment: .leading, spacing: 4) {
                Text("RECUPERACIÓN").instrumentoOverline().foregroundStyle(t.inkTertiary)
                Text("82").instrumentoHero(88).foregroundStyle(t.dataRecovery)
                Text("Listo para un día fuerte").font(StrandFont.subhead).foregroundStyle(t.inkSecondary)
            }
            Divider().overlay(t.hairline)
            swatches("Papel", [("paper", t.paper), ("surface", t.surface), ("hairline", t.hairline), ("strong", t.hairlineStrong)], t)
            swatches("Tinta", [("ink", t.ink), ("secondary", t.inkSecondary), ("tertiary", t.inkTertiary)], t)
            swatches("Dato / estado", [("recovery", t.dataRecovery), ("strain", t.dataStrain), ("warning", t.warning), ("critical", t.critical)], t)
            swatches("Métricas", [("sleep", t.dataSleep), ("hrv", t.dataHrv), ("heart", t.dataHeart), ("spo2", t.dataSpO2), ("steps", t.dataSteps)], t)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(t.paper)
}

@ViewBuilder
private func swatches(_ title: String, _ items: [(String, Color)], _ t: InstrumentoTheme) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title).instrumentoOverline().foregroundStyle(t.inkTertiary)
        HStack(spacing: 10) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .frame(width: 64, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(t.hairlineStrong, lineWidth: 1))
                    Text(name).font(.system(size: 9)).foregroundStyle(t.inkSecondary)
                }
            }
        }
    }
}
#endif
