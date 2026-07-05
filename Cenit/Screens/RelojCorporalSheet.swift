import SwiftUI
import StrandDesign
import StrandAnalytics

// RelojCorporalSheet.swift — «Tu reloj corporal» (FER-712 F1), the experimental, NON-CLINICAL body-clock
// reading, presented as a light «Instrumento» sheet from the Experimental section of Ajustes. The one
// dominant datum is the TENDENCY word (Alondra / Búho / Alineado) in verdict serif; a small clock glyph
// carries the only spot of color. Below it: the suggested sleep window (always "~"/approximate, never the
// raw temp-minimum), the confidence note, and a always-on method line. No condition is ever named, no
// diagnosis, no drug. Copy is es-MX (experimental, es-only, like «Ritmo»). All numbers come from the
// persisted phase record via `CircadianPhaseProvider`; this view adds no science.

struct RelojCorporalSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository

    @State private var read: CircadianPhaseRead? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text("RELOJ CORPORAL")
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.top, NoopMetrics.screenPadding)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
        }
        .background(theme.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .task { if read == nil { read = await CircadianPhaseProvider.load(from: repo) } }
    }

    @ViewBuilder
    private var content: some View {
        switch read {
        case .none:
            LoadingStateView().frame(maxWidth: .infinity).padding(.top, 80)
        case .needsBand:
            EmptyStateView(
                systemImage: "applewatch.slash",
                title: "Necesitas tu banda",
                message: "Esta lectura se alimenta del patrón de actividad de tu banda WHOOP.")
                .padding(.top, 40)
        case .notReadable:
            EmptyStateView(
                systemImage: "clock.badge.questionmark",
                title: "Aún no podemos leer tu reloj",
                message: "Tu ritmo es difícil de leer ahora mismo. Sigue usándola unos días más para verlo con claridad.")
                .padding(.top, 40)
        case let .reading(r):
            reading(r)
        }
    }

    // MARK: - The reading

    private func reading(_ r: CircadianReading) -> some View {
        let t = Self.tendencyCopy(r.tendency)
        return VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            // Hero: the tendency word (the datum) + the single spot of color (the clock glyph).
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(theme.dataHrv)
                    .accessibilityHidden(true)
                Text(verbatim: t.word)
                    .font(StrandFont.serif(48, relativeTo: .largeTitle))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if r.confidence == .wide {
                StatePill("Preliminar", tone: .warning, showsDot: false)
            }
            Text(verbatim: t.explanation)
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let bedtime = r.bedtimeHour {
                Divider().overlay(theme.hairline)
                Text("VENTANA SUGERIDA")
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(verbatim: Self.windowText(bedtime: bedtime, confidence: r.confidence))
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(verbatim: Self.confidenceNote(r.confidence))
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: Self.methodLine)
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.voiceOverLabel(r))
    }

    // MARK: - Copy (es-MX; experimental, es-only, like «Ritmo»)

    private static let methodLine =
        "Es una estimación a partir de tu patrón de actividad diaria, no una medición exacta. No es un diagnóstico."

    private static func tendencyCopy(_ t: CircadianTendency) -> (word: String, explanation: String) {
        switch t {
        case .lark:
            return ("Alondra",
                    "Tu cuerpo tiende a adelantarse: pide dormir y despertar más temprano que tu horario.")
        case .owl:
            return ("Búho",
                    "Tu cuerpo tiende a atrasarse: pide dormir y despertar más tarde que tu horario.")
        case .aligned:
            return ("Alineado",
                    "Tu cuerpo va a la par de tu horario: ni se adelanta ni se atrasa mucho.")
        }
    }

    private static func confidenceNote(_ c: CircadianEngine.PhaseConfidence) -> String {
        switch c {
        case .solid: return "Lectura estable, basada en tus últimas dos semanas."
        case .wide:  return "Lectura preliminar: aún con pocos días, tómala con reserva. Se afina conforme sigas usándola."
        case .unreadable: return "Tu ritmo es difícil de leer ahora mismo."
        }
    }

    /// The suggested-window sentence. Always approximate ("~"); a wide reading shows a ±30 min range.
    private static func windowText(bedtime: Double, confidence: CircadianEngine.PhaseConfidence) -> String {
        if confidence == .wide {
            let lo = clockString(bedtime - 0.5), hi = clockString(bedtime + 0.5)
            return "Tu cuerpo pide dormir entre las ~\(lo) y las ~\(hi), más o menos."
        }
        return "Tu cuerpo pide dormir alrededor de las ~\(clockString(bedtime))."
    }

    /// Format a clock hour (0..<24) as a locale short time (e.g. "11:20 p.m.").
    private static func clockString(_ hour: Double) -> String {
        let wrapped = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        var comps = DateComponents()
        comps.hour = Int(wrapped)
        comps.minute = Int((wrapped - Double(Int(wrapped))) * 60)
        let date = Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 0)
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
        return f.string(from: date)
    }

    private static func voiceOverLabel(_ r: CircadianReading) -> String {
        let t = tendencyCopy(r.tendency)
        var parts = ["Tu reloj corporal: \(t.word).", t.explanation]
        if let bed = r.bedtimeHour { parts.append(windowText(bedtime: bed, confidence: r.confidence)) }
        parts.append(confidenceNote(r.confidence))
        return parts.joined(separator: " ")
    }
}
