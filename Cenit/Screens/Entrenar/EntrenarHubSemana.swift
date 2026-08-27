#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Entrenar · SEMANA del hub v18 (FER-171 · Parte B)
//
// «Tu semana»: la regla + «N DE M», 7 teselas cuadradas (26×26, radio 8, la inicial del día ADENTRO
// — mock `.dia`, no la receta circular-con-letra-debajo de `WeekTokens`) y «EDITAR ›» hacia Tu Plan.
// Reusa el MISMO dato que ya alimentaba la tira vieja (`EntrenarDayToken`, de `weekTokenDays` en
// `EntrenarLanding`) — solo cambia el DIBUJO, nunca una segunda derivación de qué día está
// hecho/hoy/planeado/descanso.

struct EntrenarHubSemana: View {
    let days: [EntrenarDayToken]
    let labels: [String]
    let sessionsDone: Int
    let sessionsPlanned: Int
    /// `true` cuando ningún día tiene rutina asignada todavía — el valor dice «toca un día» (mismo
    /// literal que `EntrenarLanding.semanaValor` ya usaba).
    let noPlanYet: Bool
    let todayIndex: Int?
    let onTapToday: () -> Void
    let onTapOtherDay: () -> Void
    let onEdit: () -> Void

    var body: some View {
        EntrenarModulo(tono: .neutro) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your week").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                    Spacer(minLength: CenitMetrics.space2)
                    semVal
                }
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        tesela(day, label: i < labels.count ? labels[i] : "",
                              action: i == todayIndex ? onTapToday : onTapOtherDay)
                            .frame(maxWidth: .infinity)
                    }
                    EntrenarCapsulaPuerta(String(localized: "Edit").uppercased(), action: onEdit)
                }
                .padding(.top, CenitMetrics.space2)
            }
        }
        .liquidEntrada(index: 1)
    }

    @ViewBuilder private var semVal: some View {
        if noPlanYet {
            Text("Tap a day")
                .font(EntrenarHubMetrics.semValNumeral).tracking(EntrenarHubMetrics.semValTracking)
                .foregroundStyle(LiquidColor.tinta900)
        } else {
            (Text(verbatim: "\(sessionsDone)")
                .font(EntrenarHubMetrics.semValNumeral).tracking(EntrenarHubMetrics.semValTracking)
             + Text(verbatim: " ")
             + Text("of \(sessionsPlanned)")
                .font(EntrenarHubMetrics.semValCalificativo).tracking(EntrenarHubMetrics.semValCalificativoTracking)
                .textCase(.uppercase))
                .foregroundStyle(LiquidColor.tinta900)
        }
    }

    private func tesela(_ day: EntrenarDayToken, label: String, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: EntrenarHubMetrics.teselaRadius, style: .continuous)
        return Button(action: action) {
            ZStack {
                switch day {
                case .done(let family):
                    shape.fill(family.tono.tesela)
                case .today:
                    shape.strokeBorder(LiquidColor.tinta900, lineWidth: EntrenarHubMetrics.teselaHoyLineWidth)
                case .planned(let family):
                    shape.strokeBorder(family.tono.base,
                                       style: StrokeStyle(lineWidth: EntrenarHubMetrics.teselaOffLineWidth, dash: [2, 2]))
                case .rest:
                    shape.strokeBorder(LiquidColor.tinta900.opacity(EntrenarHubMetrics.teselaOffAlfa),
                                       style: StrokeStyle(lineWidth: EntrenarHubMetrics.teselaOffLineWidth, dash: [2, 2]))
                }
                Text(verbatim: label)
                    .font(entrenarWeekDayLabelFont)
                    .foregroundStyle(teselaTextColor(day))
            }
            .frame(width: EntrenarHubMetrics.teselaSize, height: EntrenarHubMetrics.teselaSize)
        }
        .buttonStyle(.liquidPress)
        .accessibilityLabel(accessibilityLabel(day, dayName: label))
    }

    /// El mismo tamaño que `entrenarWeekDayLabel()` (10.5/600/tracking 1.4) — la inicial dentro de
    /// la tesela, no debajo (mock `.dia{font-size:9.5px;font-weight:700}`, un punto más chico y más
    /// bold que el rótulo compartido; se declara aquí porque solo esta tesela lo necesita).
    private var entrenarWeekDayLabelFont: Font { InstrumentoType.grotesk(9.5, weight: .bold, relativeTo: .caption2) }

    private func teselaTextColor(_ day: EntrenarDayToken) -> Color {
        switch day {
        case .done: return .white
        default:    return LiquidColor.tinta500
        }
    }

    private func accessibilityLabel(_ day: EntrenarDayToken, dayName: String) -> Text {
        let name = Text(verbatim: dayName) + Text(verbatim: ", ")
        switch day {
        case .done(let f):       return name + Text("trained") + Text(verbatim: ", ") + Text(f.label)
        case .today(let isRest): return name + Text("today") + Text(verbatim: ", ")
                                       + (isRest ? Text("rest day") : Text("training day"))
        case .planned(let f):    return name + Text("planned") + Text(verbatim: ", ") + Text(f.label)
        case .rest:               return name + Text("rest day")
        }
    }
}
#endif
