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
// purpose: the design originally varied them by the hour (FER-132), but FER-398
// retired that engine — the app now uses the single `.base` daytime anchor at
// every hour. The instance shape stays (cheap, and keeps the door open). Nothing
// here touches the legacy palette or any screen.

/// The semantic color roles of the «Instrumento diurno» language, in one
/// instance so the hour engine (FER-132) can vary them. Inject with
/// `.instrumentoTheme(_:)`; read with `@Environment(\.instrumentoTheme)`.
public struct InstrumentoTheme: Equatable, Sendable {

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
    /// Forest green for oxygen / SpO₂ identity when a deeper green is needed (distinct from
    /// the blue `dataSpO2` metric hue and from recovery green). Does NOT re-map the SpO₂ metric.
    public let dataOxygen: Color
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
        dataSleep: Color, dataHrv: Color, dataHeart: Color, dataSpO2: Color,
        dataOxygen: Color, dataSteps: Color,
        verdict: Color, warning: Color, critical: Color
    ) {
        self.paper = paper; self.surface = surface
        self.hairline = hairline; self.hairlineStrong = hairlineStrong
        self.ink = ink; self.inkSecondary = inkSecondary; self.inkTertiary = inkTertiary
        self.dataRecovery = dataRecovery; self.dataStrain = dataStrain
        self.dataSleep = dataSleep; self.dataHrv = dataHrv; self.dataHeart = dataHeart
        self.dataSpO2 = dataSpO2; self.dataOxygen = dataOxygen; self.dataSteps = dataSteps
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
        dataOxygen:     Color(hex: "#3F7A5E"),
        dataSteps:      Color(hex: "#4C8998"),
        verdict:        Color(hex: "#0C8F62"),
        warning:        Color(hex: "#9C5E10"),
        critical:       Color(hex: "#BC3A34")
    )
}

public extension InstrumentoTheme {
    /// Color de la batería del strap por nivel de carga — fuente ÚNICA para toda la app (Hoy, Ajustes…):
    /// sana → `verdict` (verde); ≤20 % → `warning` (ámbar); ≤10 % → `critical` (rojo). El color vive solo
    /// en el dato (el glifo en Hoy, el número en Ajustes); el resto se queda en tinta.
    func batteryColor(forLevel pct: Double) -> Color {
        switch pct {
        case ...10: return critical   // ≤10 % — crítica
        case ...20: return warning    // ≤20 % — baja
        default:    return verdict    // sana
        }
    }
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

    // MARK: - Muscle-load ramp (FER-350 · warm mono-tone FER-781)

    /// The fresh→loaded color scale for the muscle-fatigue map, tuned to the «Instrumento» DNA rule that
    /// color lives ONLY in the datum: a single warm tone that RISES in intensity rather than shifting hue.
    /// The low stops are not green — they are tinted paper, so a fresh muscle almost disappears into the
    /// silhouette while a loaded one GRITA in the saturated `dataStrain` ember at the top (FER-781, the
    /// owner-approved body). A silhouette fill, not text, so AA-on-paper isn't required — the ranking and
    /// legend carry the meaning. The anchor top stop IS `dataStrain` (#C4631F), the system's heat.
    var muscleLoadRamp: [Color] {
        [Color(hex: "#E3DFD0"), Color(hex: "#E7B98E"), Color(hex: "#DB9A5A"),
         Color(hex: "#CE7B34"), Color(hex: "#C4631F")]
    }

    /// A color along `muscleLoadRamp` for a 0…1 load fraction (0 = fresh, 1 = most loaded), interpolated
    /// in OKLab so the sweep stays perceptually even. Clamps out of range. (FER-350)
    func muscleLoadColor(_ fraction: Double) -> Color {
        let ramp = muscleLoadRamp
        let f = min(max(fraction, 0), 1)
        let scaled = f * Double(ramp.count - 1)
        let i = min(Int(scaled), ramp.count - 2)
        return OKLab.mix(ramp[i], ramp[i + 1], scaled - Double(i))
    }

    // MARK: Tinted-text tokens — the data/state hues at SMALL size (FER-131 handoff · 02)
    //
    // The data/state hues (`verdict`/`dataRecovery`/… at 3.6:1, AA-LARGE) are sized for the
    // dominant numeral, where AA-large's 3:1 floor at ≥24pt applies. Any datum or DELTA set
    // BELOW 24pt — the metric tile's "↑ N vs media" at 12pt — needs the 4.5:1 normal-text
    // floor those saturated hues miss. `positiveText`/`negativeText` are the first-class
    // tokens for that case: a hue-preserving darkening that clears 4.5:1 against whatever
    // `paper` is live. The RULE: <24pt valence text uses these; the ≥24pt hero numeral keeps
    // the saturated hue. Both are computed (like `hrZoneRamp`) so they need no change to the
    // theme's init, and the `.base` paper can't silently break them.

    /// AA-at-text-size POSITIVE green for a positive signal on SMALL (<24pt) text — the
    /// Today tile's "↑ N vs media" delta (12pt). Darkens `verdict` in OKLab, keeping its hue,
    /// only as far as needed to reach 5.0:1 against the CURRENT (already hour-interpolated)
    /// `paper`. The handoff's hi-fi value is `#0A6B45` / ~5.0:1 on the `.base` day paper; the
    /// 5.0 target (vs the bare 4.5 text floor) both lands on that value and balances it against
    /// `negativeText` (= critical, 4.9:1), so ↑ and ↓ deltas read at the same weight. Computed
    /// (not a fixed hex) so it stays WCAG-AA across the whole 24h sweep. (FER-131 handoff · 02)
    var positiveText: Color {
        OKLab.darkened(verdict, toContrast: 5.0, against: paper)
    }

    /// AA-at-text-size NEGATIVE red for a negative signal on SMALL (<24pt) text — the Today
    /// tile's "↓ N vs objetivo" delta (12pt). Equal to `critical` (`#BC3A34`), which already
    /// clears the 4.5:1 normal-text floor (≈4.9:1 on day paper, ≥4.5:1 even on the dimmer
    /// night paper), so no darkening is needed — but it is a NAMED token (not a raw `critical`
    /// reference) so a negative delta reads as a first-class data role, paired with
    /// `positiveText`. (FER-131 · 02)
    var negativeText: Color { critical }

    // MARK: Paper gradient — warm-paper depth for the «Hoy» canvas (handoff «Hoy · Estados»)
    //
    // The daytime «Hoy» canvas reads as paper with a faint pool of light near the
    // top-centre that deepens to a slightly warmer rim — a radial gradient, not a flat
    // fill. Rather than store two more roles, the two stops are DERIVED from the LIVE
    // `paper` in OKLab (the `positiveText` technique generalized): `paperHi` lightens
    // toward white, `paperLo` deepens toward the warm `hairline`. Both stops stay in
    // the bone-paper family (never a cool white at the centre), so rule 3's "warm paper,
    // never pure white" still holds at the surface. Computed (like `hrZoneRamp`), so the
    // theme's `Equatable` is untouched.

    /// Gradient highlight — the lighter pool of light near the top-centre of the paper.
    var paperHi: Color { OKLab.mix(paper, Color(.sRGB, red: 1, green: 1, blue: 1), 0.5) }
    /// Gradient rim — the paper deepening slightly toward its warm rule at the edge.
    var paperLo: Color { OKLab.mix(paper, hairline, 0.5) }

    /// Muted ink for NO-DATA cells — the «—» placeholder and its metric glyph when there's no reading
    /// (handoff «Hoy · Estados»). A faded warm gray, derived from `inkTertiary` toward the live `paper`
    /// in OKLab (like `paperHi`/`paperLo`), tracking the live `.base` paper. INTENTIONALLY
    /// low-contrast — it signals "nothing here yet", so it is NOT held to the AA text floor (unlike the
    /// ink roles); never use it for information the user must read.
    var inkDim: Color { OKLab.mix(inkTertiary, paper, 0.5) }

    // MARK: Evolved-language tokens — handoff «Hoy» 2026-07 (FER-707/708)
    //
    // The «Hoy» redesign's hi-fi handoff adds a small set of fixed roles on top of the
    // `.base` anchor. Computed (like `hrZoneRamp`) so the theme's init/Equatable stay
    // untouched. All are chrome/fill roles except `dataRecoveryDeep` (a text-tier green);
    // none of the fills are held to the AA text floor.

    /// The quietest chrome ink — inactive tabs, unlit rule marks, the computed-origin dot.
    /// INTENTIONALLY below the AA text floor (like `inkDim`); never for copy the user must read.
    var inkMuted: Color { Color(hex: "#AFAA9D") }
    /// Background of the «patrón / conexión» block (with a data-color bar on its left edge).
    var patternBlock: Color { Color(hex: "#EFEAE0") }
    /// The personal-range band behind a trend line.
    var rangeBand: Color { Color(hex: "#EDE8DB") }
    /// The dotted personal-median line inside `rangeBand`.
    var rangeMidline: Color { Color(hex: "#C9C2AF") }
    /// The day/sun arc on the dial seal (context, not a datum).
    var dataSun: Color { Color(hex: "#D79567") }
    /// The accent on the ink CTA bar («EMPEZAR →») — only ever on `ink`, never on paper.
    var ctaAccent: Color { Color(hex: "#2FE6A8") }
    /// The «moderado» lane hue (gauge segments, lane squares) — a fill, not text.
    var moderate: Color { Color(hex: "#E8C24B") }
    // (The handoff's deep favorable-delta green `#00774B` is exactly what `positiveText`
    // already computes on `.base` paper — use that token, no new role.)
    /// Deep-sleep stage fill (stage bars / hypnogram).
    var dataSleepDeep: Color { Color(hex: "#3F3C78") }
    /// Light-sleep stage fill.
    var dataSleepLight: Color { Color(hex: "#8E8BC4") }
    /// Lightest-sleep stage fill (handoff «Detalle de Tendencias Final» / Sueño).
    var dataSleepLightest: Color { Color(hex: "#A9A6D4") }
    /// Awake stage fill on the sleep hypnogram (warm paper-adjacent, not a risk red).
    var dataSleepAwake: Color { Color(hex: "#C9C2AF") }
    /// A keycap on the session's custom numeric keypad (FER-716) — the ONE white surface the paper
    /// language allows, calqued from the UIKit keycap over `surface` (with its own hairline + 1px
    /// shadow). Not a canvas; never used as a background elsewhere.
    var keyCap: Color { Color(hex: "#FFFFFF") }

    // Data-origin dots (6px): where a reading comes from, always visible. Aliases of
    // existing roles so origin and metric hues can never drift apart.
    /// Origin dot — the strap/band.
    var originBand: Color { dataRecovery }
    /// Origin dot — Apple Salud.
    var originApple: Color { dataSpO2 }
    /// Origin dot — computed on-device.
    var originComputed: Color { inkMuted }

    /// Warm track behind compact segmented pills (`CompactTrendToggle`) — one step warmer than
    /// `surface` so the active ink chip riding on it reads.
    var trackWarm: Color { Color(hex: "#EFEAE0") }

    // MARK: Handoff «Detalle de Tendencias Final» (FER-856) — chart chrome + deep lanes

    /// The «tu base» mark on a chart: the dashed personal-reference line, the center tick of a
    /// divergent bar, and the gray point-line in the RANGOS mode. Chart chrome, not text — never
    /// held to the AA text floor.
    var baseMark: Color { Color(hex: "#B0A78F") }
    /// The deepest depleted lane («Agotado», recovery < 25) in a range chart — one step darker
    /// than `critical` so the two red lanes stay distinguishable. A fill/point hue, not text.
    var criticalDeep: Color { Color(hex: "#82231E") }
    /// The deep positive-lane green («Pleno», recovery ≥ 88) — the same deep green
    /// `positiveText` computes on `.base` paper, as a fixed lane fill.
    var verdictDeep: Color { Color(hex: "#00774B") }
    /// Deep «rejuvenates» green for `ContributionBars` (and body-age poles): deeper than
    /// `dataRecovery` (`#0C8F62`) so left-of-zero bars read as longevity, not recovery. No prior
    /// fitness-age/longevity token existed at this hex.
    var dataRejuvenates: Color { Color(hex: "#2E7D57") }

    // MARK: Handoff «Detalle de Tendencias Final» — Esfuerzo (FER-859)

    /// Esfuerzo mid ramp lane fill («Duro», the second-highest strain lane) — one step lighter than
    /// `dataStrain`. A fill/point hue, not text.
    var strainRampMid: Color { Color(hex: "#DC9A72") }
    /// Esfuerzo low ramp lane fill («Reposo y ligero») — the lightest strain lane.
    var strainRampLow: Color { Color(hex: "#EBC7AF") }
    /// Esfuerzo deep lane fill («Extremo», strain ≥18) — one step darker than `dataStrain`.
    var strainDeep: Color { Color(hex: "#8F4413") }

    // MARK: Tinte por opacidad — helpers de la escala `StrandOpacity` (auditoría jul-2026, H4)
    //
    // Azúcar sobre `StrandOpacity` para el patrón más común: modular un color de dato/estado a
    // opacidad de tinte. Preferir estos en el call site (`theme.tint(theme.warning)`) sobre el
    // literal (`theme.warning.opacity(0.12)`).

    /// Fondo tintado de chip/badge (`StrandOpacity.tintFill`, 0.10).
    func tint(_ c: Color) -> Color       { c.opacity(StrandOpacity.tintFill) }
    /// Tinte enfatizado (`StrandOpacity.tintFillStrong`, 0.14).
    func tintStrong(_ c: Color) -> Color { c.opacity(StrandOpacity.tintFillStrong) }
    /// Borde tintado suave (`StrandOpacity.strokeSoft`, 0.30).
    func softStroke(_ c: Color) -> Color { c.opacity(StrandOpacity.strokeSoft) }
}

// MARK: - Environment injection

private struct InstrumentoThemeKey: EnvironmentKey {
    static let defaultValue = InstrumentoTheme.base
}

private struct InstrumentoFlatKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// The active «Instrumento diurno» theme. Defaults to `.base`; the hour
    /// engine (FER-132) overrides it per time of day.
    var instrumentoTheme: InstrumentoTheme {
        get { self[InstrumentoThemeKey.self] }
        set { self[InstrumentoThemeKey.self] = newValue }
    }

    /// True inside the «Instrumento diurno» light language: chart accents render FLAT — no
    /// glow / bloom / colored halo. Glow is a black-screen effect; on warm paper it only
    /// muddies the glyph's edge, so the daytime language drops it (FER-131 handoff · 03).
    /// Defaults to `false` so the legacy DARK system keeps its glow untouched; it flips to
    /// `true` automatically wherever `.instrumentoTheme(_:)` is applied — i.e. exactly the
    /// views rendered on paper.
    var instrumentoFlat: Bool {
        get { self[InstrumentoFlatKey.self] }
        set { self[InstrumentoFlatKey.self] = newValue }
    }
}

public extension View {
    /// Inject an «Instrumento diurno» theme for this subtree. Also marks the subtree as the
    /// light language (`\.instrumentoFlat`), so shared chart components drop their dark-system
    /// glow/bloom on paper (FER-131 handoff · 03).
    func instrumentoTheme(_ theme: InstrumentoTheme) -> some View {
        environment(\.instrumentoTheme, theme)
            .environment(\.instrumentoFlat, true)
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

    /// One step up from `overline` (14pt medium) for a section header that should
    /// read a touch louder — e.g. the Today verdict's «EL VEREDICTO DE HOY». Bigger,
    /// not heavier (medium, not semibold), so it stays clearly subordinate to the hero
    /// numeral (rule 1). Same tracking as `overline`. (FER-283/284)
    public static let overlineProminent = Font.system(size: 14, weight: .medium)
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

    /// Like `instrumentoOverline` but a touch more prominent (13pt semibold) for a
    /// section header that should read louder — still subordinate to the hero numeral.
    /// Color it with a tint only when the overline itself is the datum. (FER-283)
    func instrumentoOverlineProminent() -> some View {
        self.font(InstrumentoType.overlineProminent)
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
            // overline normal vs prominente (FER-283/284): la prominente sube a 14/medium, tinta secundaria.
            VStack(alignment: .leading, spacing: 4) {
                Text("El veredicto de hoy").instrumentoOverline().foregroundStyle(t.inkTertiary)
                Text("El veredicto de hoy").instrumentoOverlineProminent().foregroundStyle(t.inkSecondary)
            }
            Divider().overlay(t.hairline)
            swatches("Papel", [("paper", t.paper), ("surface", t.surface), ("hairline", t.hairline), ("strong", t.hairlineStrong)], t)
            swatches("Tinta", [("ink", t.ink), ("secondary", t.inkSecondary), ("tertiary", t.inkTertiary)], t)
            swatches("Dato / estado", [("recovery", t.dataRecovery), ("strain", t.dataStrain), ("warning", t.warning), ("critical", t.critical)], t)
            swatches("Métricas", [("sleep", t.dataSleep), ("hrv", t.dataHrv), ("heart", t.dataHeart), ("spo2", t.dataSpO2), ("oxygen", t.dataOxygen), ("steps", t.dataSteps)], t)
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

#Preview("Instrumento · carga muscular") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 16) {
        Text("RAMPA DE CARGA").instrumentoOverline().foregroundStyle(t.inkTertiary)
        HStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { i in
                Rectangle().fill(t.muscleLoadColor(Double(i) / 23))
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        HStack {
            Text("Fresco").font(StrandFont.caption).foregroundStyle(t.inkSecondary)
            Spacer()
            Text("Cargado").font(StrandFont.caption).foregroundStyle(t.inkSecondary)
        }
    }
    .padding(28)
    .background(t.paper)
}
#endif
