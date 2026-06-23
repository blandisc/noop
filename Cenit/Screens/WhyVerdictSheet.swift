import SwiftUI
import StrandDesign
import StrandAnalytics

/// FER-113 — the "Why {verdict}?" sheet behind the verdict hero on iPhone. Explains *why* today reads
/// the way it does: the day's color, the reconciliation line, the full driver signals (brought to iOS
/// from the macOS-only readiness list), and a color legend that names the CONDITION behind each color
/// and marks where today lands. Mirrors `MetricInfoSheet`'s scaffold so the two explainers feel like one.
///
/// FER-167 — migrated to the light «Instrumento» theme so it matches the Today screen it opens from.
/// The theme is passed in explicitly (it does NOT propagate through `.sheet`'s fresh environment); the
/// level colours mirror `TodayView.verdictDataColor` so the hero and this sheet never disagree.
struct WhyVerdictSheet: View {
    let readiness: ReadinessEngine.Readiness
    /// The active «Instrumento diurno» theme, passed from `TodayView` (does not propagate through `.sheet`).
    var theme: InstrumentoTheme = .base
    /// Last night's sleep minutes (today's row), for the short-night caveat block — passed explicitly
    /// because `Readiness` doesn't carry it (FER-285). nil → the block says «menos de 6 h» without a figure.
    var sleepMinutes: Double? = nil
    /// Cuando NO hay lectura de hoy (estado `insufficient` / espera), una explicación honesta de POR QUÉ
    /// aún no hay veredicto (falta el sueño de la noche / el sync). `nil` → la hoja muestra el porqué del
    /// veredicto normal. La pasa `TodayView` según el estado, para no decir «¿Por qué preparación?» con un
    /// «día gris» que confunde cuando en realidad lo que falta es la lectura del día. (FER-475)
    var emptyStateExplanation: LocalizedStringKey? = nil
    /// FER-545 (A2): cuando el veredicto de hoy es un ESTIMADO de Apple (noche sin banda), esta hoja es el
    /// hogar del caveat científico SDNN-vs-RMSSD —antes vivía solo en el Detalle de recuperación—. `TodayView`
    /// lo enciende según `repo.isRecoveryEstimated`; la confianza da el grado del sello.
    var isRecoveryEstimated: Bool = false
    var recoveryConfidence: ScoreConfidence? = nil

    /// FER-545: el caveat del estimado de Apple, en UN solo lugar (este). El Detalle de recuperación lo
    /// referencia, así que «reubicar» no duplica el texto ni pierde una palabra del SDNN-vs-RMSSD.
    static func estimatedCaveat(coldStart: Bool) -> LocalizedStringKey {
        coldStart
        ? "This recovery is ESTIMATED from your Apple Watch HRV (SDNN) and sleep while your band is still calibrating its own baseline, compared with your own Apple-Health baseline. SDNN isn't the same measure as the band's HRV, so it's a lower-confidence proxy — read it as a guide, not a band reading. It switches to your band automatically once it's calibrated. Not a diagnosis."
        : "This recovery is ESTIMATED from your Apple Watch HRV (SDNN) and sleep on a night your band didn't record, compared with your own Apple-Health baseline. SDNN isn't the same measure as the band's HRV, so it's a lower-confidence proxy — read it as a guide, not a band reading. Not a diagnosis."
    }

    /// Measured natural height of the content, so the sheet opens exactly as tall as it needs to be —
    /// all of the explanation is visible without dragging the sheet up. Capped at `.large`.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let exp = emptyStateExplanation, readiness.level == .insufficient {
                    // Sin lectura de hoy (FER-475): explica POR QUÉ aún no hay veredicto, en vez del
                    // genérico «¿Por qué preparación?» con el chip gris. La leyenda se queda para que el
                    // usuario igual entienda los niveles que verá cuando sí haya lectura.
                    noReadingBlock(exp)
                    legendSection
                } else {
                    Text("Why \(readiness.headline.lowercased())?")
                        .font(StrandFont.title2)
                        .foregroundStyle(theme.ink)
                    colorChip
                    if isRecoveryEstimated { estimatedBlock }   // FER-545: el caveat del estimado de Apple
                    if let bridge = readiness.bridge {
                        Text(bridge)
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if readiness.confidenceLow { shortNightBlock }   // FER-285
                    if !readiness.signals.isEmpty { signalsSection }
                    legendSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: WhySheetHeightKey.self, value: g.size.height)
            })
        }
        .onPreferenceChange(WhySheetHeightKey.self) { contentHeight = $0 }
        .background(theme.paper)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.large])
        .presentationDragIndicator(.visible)
        .modifier(WhySheetBackground(paper: theme.paper))
    }

    /// El bloque de «aún no hay lectura de hoy» (FER-475): título honesto + la explicación de por qué
    /// falta (la pasa `TodayView` según el estado: te falta dormir/sincronizar, o calibrar más noches).
    private func noReadingBlock(_ explanation: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aún no hay lectura de hoy")
                .font(StrandFont.title2)
                .foregroundStyle(theme.ink)
            Text(explanation)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Today your day is amber — Strained" — makes the color the explicit subject (the user's
    /// original confusion was "why is it this color?").
    private var colorChip: some View {
        let c = levelColor(readiness.level)
        return HStack(spacing: 8) {
            Circle().fill(c).frame(width: 11, height: 11)
            Text("Today your day is \(colorName(readiness.level)) — \(readiness.headline)")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(c.opacity(0.30), lineWidth: 0.5))
    }

    /// FER-545 — el caveat del veredicto ESTIMADO de Apple: el sello «estimado · confianza X» + la
    /// explicación honesta SDNN-vs-RMSSD (reubicada aquí desde el Detalle de recuperación). En tinta Apple
    /// (azul), distinta del bloque ámbar de noche corta.
    private var estimatedBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch").font(.system(size: 12)).foregroundStyle(theme.dataSpO2)
                Text(RecoveryDetailScreen.confidenceLabel(recoveryConfidence))
                    .font(StrandFont.subhead).fontWeight(.semibold)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Self.estimatedCaveat(coldStart: false))
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.dataSpO2.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.dataSpO2.opacity(0.28), lineWidth: 0.5))
    }

    /// FER-285 — the short-night caveat, explained. Surfaces *why* a night under 6 h lowers confidence
    /// (it suppresses HRV / inflates resting HR regardless of true recovery), with last night's real
    /// hours when we have them. The Hero shows only the short line; this is where the reasoning lives.
    private var shortNightBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 12)).foregroundStyle(theme.warning)
                Text("Confianza baja — noche corta")
                    .font(StrandFont.subhead).fontWeight(.semibold)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(shortNightExplanation)
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.warning.opacity(0.28), lineWidth: 0.5))
    }

    /// The caveat copy, with last night's real hours when available (else «menos de 6 h»). Built as a
    /// `LocalizedStringKey` so the hours interpolate into a `%@` placeholder the catalog can localize.
    private var shortNightExplanation: LocalizedStringKey {
        guard let mins = sleepMinutes, mins > 0 else {
            return "Anoche dormiste menos de 6 h. Una noche corta deprime tu HRV e infla tu frecuencia en reposo aunque tu recuperación real sea mejor — así que hoy el número se lee con menos certeza. No es que estés peor: una noche corta se mide con menos confianza."
        }
        let dur = "\(Int(mins) / 60) h \(Int(mins) % 60) min"
        return "Anoche dormiste \(dur), por debajo de las 6 h. Una noche corta deprime tu HRV e infla tu frecuencia en reposo aunque tu recuperación real sea mejor — así que hoy el número se lee con menos certeza. No es que estés peor: una noche corta se mide con menos confianza."
    }

    /// The full driver list — this is what was macOS-only before; FER-113 brings it to the phone.
    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Your signals today")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.inkTertiary)
            ForEach(readiness.signals, id: \.key) { s in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(flagColor(s.flag)).frame(width: 7, height: 7).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(StrandFont.caption).foregroundStyle(theme.ink)
                        Text(s.detail).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The legend explains the CONDITION behind each color (not just its name) and marks where today
    /// lands — answering "why is it amber / green / …?".
    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What each color means")
                .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.inkTertiary)
                .padding(.bottom, 6)
            legendRow(.primed, "Primed", "signals aligned, load supported")
            legendRow(.balanced, "Balanced", "nothing flagging")
            legendRow(.strained, "Strained", "one signal needs care")
            legendRow(.rundown, "Run down", "several signals down")
        }
    }

    private func legendRow(_ level: ReadinessEngine.Level, _ name: LocalizedStringKey,
                           _ condition: LocalizedStringKey) -> some View {
        let here = readiness.level == level
        let c = levelColor(level)
        return HStack(spacing: 9) {
            Circle().fill(c).frame(width: 9, height: 9)
            Text(name).font(StrandFont.caption).foregroundStyle(theme.ink)
                .frame(width: 96, alignment: .leading)
            Text(condition).font(StrandFont.footnote)
                .foregroundStyle(here ? c : theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if here {
                Text("TODAY").font(.system(size: 9, weight: .semibold)).foregroundStyle(c)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(c.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(here ? c.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: color maps (mirror TodayView.verdictDataColor so the hero and sheet never disagree, FER-167)

    private func levelColor(_ l: ReadinessEngine.Level) -> Color {
        switch l {
        case .primed, .balanced: return theme.verdict
        case .strained:          return theme.warning
        case .rundown:           return theme.critical
        case .insufficient:      return theme.inkTertiary
        }
    }

    private func flagColor(_ f: ReadinessEngine.Flag) -> Color {
        switch f {
        case .good:    return theme.verdict
        case .neutral: return theme.inkTertiary
        case .watch:   return theme.warning
        case .bad:     return theme.critical
        }
    }

    /// The colour NAME shown in the chip — must track `levelColor` (which mirrors the theme's verdict
    /// roles): primed & balanced both read green, strained amber, rundown red, insufficient gray. (FER-167)
    private func colorName(_ l: ReadinessEngine.Level) -> String {
        switch l {
        case .primed:       return String(localized: "green")
        case .balanced:     return String(localized: "green")
        case .strained:     return String(localized: "amber")
        case .rundown:      return String(localized: "red")
        case .insufficient: return String(localized: "gray")
        }
    }
}

/// Carries the sheet content's measured natural height up so the detent fits it exactly.
private struct WhySheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct WhySheetBackground: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(macOS 13.3, iOS 16.4, *) {
            content.presentationBackground(paper)
        } else { content }
    }
}
