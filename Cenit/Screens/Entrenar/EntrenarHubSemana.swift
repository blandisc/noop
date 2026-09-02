#if os(iOS)
import SwiftUI
import CenitDesign

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
                    Spacer(minLength: LiquidSpace.s200)
                    semVal
                }
                // Teselas de ancho FIJO con gap chico (mock `.semRow{gap:8px}`) — no `WeekTokens`, cuya
                // tira sí reparte 1/7 del ancho por columna. «EDITAR ›» se empuja al filo con un
                // `Spacer` (mock `.editar{margin-left:auto}`), absorbiendo el resto del ancho.
                HStack(spacing: EntrenarHubMetrics.semRowGap) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        tesela(day, label: i < labels.count ? labels[i] : "",
                              action: i == todayIndex ? onTapToday : onTapOtherDay)
                    }
                    Spacer(minLength: LiquidSpace.s200)
                    EntrenarCapsulaPuerta(String(localized: "Edit").uppercased(), action: onEdit)
                }
                .padding(.top, LiquidSpace.s200)
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
            // `Text.textCase(_:)` devuelve `some View`, no `Text` — rompe la concatenación `+` de más
            // abajo. Mayúsculas sobre el STRING ya resuelto, no sobre la vista (mismo patrón que
            // `EntrenarCapsulaPuerta` con «Edit»).
            (Text(verbatim: "\(sessionsDone)")
                .font(EntrenarHubMetrics.semValNumeral).tracking(EntrenarHubMetrics.semValTracking)
             + Text(verbatim: " ")
             + Text(verbatim: String(localized: "of \(sessionsPlanned)").uppercased())
                .font(EntrenarHubMetrics.semValCalificativo).tracking(EntrenarHubMetrics.semValCalificativoTracking))
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
                    .font(EntrenarHubMetrics.teselaLabel)
                    .foregroundStyle(teselaTextColor(day))
            }
            .frame(width: EntrenarHubMetrics.teselaSize, height: EntrenarHubMetrics.teselaSize)
        }
        .buttonStyle(.liquidPress)
        // Ronda 2 · O3 + Ronda 3 (anexo Grok r2, misfire real): el DIBUJO se queda en 26×26 — lo que
        // crece es el ÁREA DE TOQUE, pero NO simétrica. Vertical: inset `teselaToque` (44, sin vecino
        // en ese eje dentro de la fila). Horizontal: inset `teselaToqueInsetH` (4 por lado → 34 pt =
        // el PITCH exacto entre teselas — 44 simétrico traslapaba ~10 pt con la vecina y el canto del
        // toque caía en el día equivocado, HOY abriendo el editor de otro día). `Path`, no
        // `Rectangle().inset(by:)`: ese método solo acepta un inset uniforme.
        .contentShape(Path(CGRect(
            x: -EntrenarHubMetrics.teselaToqueInsetH,
            y: -(EntrenarHubMetrics.teselaToque - EntrenarHubMetrics.teselaSize) / 2,
            width: EntrenarHubMetrics.teselaSize + 2 * EntrenarHubMetrics.teselaToqueInsetH,
            height: EntrenarHubMetrics.teselaToque
        )))
        .accessibilityLabel(accessibilityLabel(day, dayName: label))
    }

    private func teselaTextColor(_ day: EntrenarDayToken) -> Color {
        switch day {
        case .done: return .white
        default:    return LiquidColor.tinta500
        }
    }

    private func accessibilityLabel(_ day: EntrenarDayToken, dayName: String) -> Text {
        let name = Text(verbatim: dayName) + Text(verbatim: ", ")
        switch day {
        // Ronda 2 · D3: clave PROPIA — «trained» es «entrenadas» (de «horas entrenadas»), un
        // adjetivo plural que no concuerda con un día suelto («L, entrenadas, Empuje»).
        case .done(let f):       return name + Text("trained day") + Text(verbatim: ", ") + Text(f.label)
        case .today(let isRest): return name + Text("today") + Text(verbatim: ", ")
                                       + (isRest ? Text("rest day") : Text("training day"))
        case .planned(let f):    return name + Text("planned") + Text(verbatim: ", ") + Text(f.label)
        case .rest:               return name + Text("rest day")
        }
    }
}
#endif
