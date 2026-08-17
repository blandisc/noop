import SwiftUI

// MARK: - TrainingCalendar + MuscleLoadRow (FER-83 · E2)
//
// El calendario de entrenamientos y la fila de carga por músculo: los dos módulos que leen el
// pasado. Los dos comparten una regla: UN solo hue por significado, y nada de semáforo.

/// Un día del calendario, ya resuelto por la app.
public struct EntrenarCalendarDay: Identifiable, Sendable, Hashable {
    public let id: String
    public let state: EntrenarCalendarState
    public init(id: String, state: EntrenarCalendarState) { self.id = id; self.state = state }
}

/// La retícula tipo contribuciones: cada celda un día, teñida por la FAMILIA que se entrenó.
///
/// No escala con Dynamic Type a propósito: es un gráfico, no texto — su unidad es el pixel de la
/// rejilla, y crecerla rompería la lectura de meses. Lo que sí escala es su resumen, y VoiceOver
/// lee ESE resumen en vez de noventa celdas sueltas.
public struct TrainingCalendar: View {
    public enum Size: Sendable { case mini, full }

    private let days: [EntrenarCalendarDay]
    private let size: Size
    private let columnsPerRow: Int
    private let summary: LocalizedStringKey
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(days: [EntrenarCalendarDay], size: Size, columnsPerRow: Int = 7,
                summary: LocalizedStringKey, action: (() -> Void)? = nil) {
        self.days = days; self.size = size; self.columnsPerRow = max(1, columnsPerRow)
        self.summary = summary; self.action = action
    }

    private var side: CGFloat {
        size == .mini ? EntrenarMetrics.calendarCellMini : EntrenarMetrics.calendarCell
    }

    public var body: some View {
        let grid = VStack(alignment: .leading, spacing: EntrenarMetrics.calendarGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: EntrenarMetrics.calendarGap) {
                    ForEach(row) { day in cell(day.state) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)

        if let action {
            Button(action: action) {
                grid.frame(minHeight: EntrenarMetrics.row, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(EntrenarPressStyle())
            .accessibilityAddTraits(.isButton)
        } else {
            grid
        }
    }

    private var rows: [[EntrenarCalendarDay]] {
        stride(from: 0, to: days.count, by: columnsPerRow).map {
            Array(days[$0 ..< min($0 + columnsPerRow, days.count)])
        }
    }

    private func cell(_ state: EntrenarCalendarState) -> some View {
        let shape = RoundedRectangle(cornerRadius: EntrenarMetrics.calendarRadius, style: .continuous)
        return shape
            .fill(state.fill(theme))
            .frame(width: side, height: side)
            .overlay {
                if let stroke = state.stroke(theme) { shape.strokeBorder(stroke, lineWidth: 1.5) }
            }
    }
}

/// Una fila del módulo «MÚSCULOS CARGADOS».
///
/// Un solo hue (ámbar) con la OPACIDAD llevando la recencia: más reciente, más opaco. «Fresco» NO
/// es verde — es el riel vacío y tinta secundaria. Un semáforo aquí convertiría una estimación en
/// un permiso, y el permiso lo da el veredicto, no el mapa.
public struct MuscleLoadRow: View {
    private let name: String
    private let load: Double
    private let recency: LocalizedStringKey
    private let sets: Int
    private let isFresh: Bool

    @Environment(\.instrumentoTheme) private var theme

    public init(name: String, load: Double, recency: LocalizedStringKey, sets: Int, isFresh: Bool) {
        self.name = name; self.load = max(0, min(1, load))
        self.recency = recency; self.sets = sets; self.isFresh = isFresh
    }

    public var body: some View {
        HStack(spacing: CenitMetrics.gap) {
            Text(verbatim: name)
                .font(StrandFont.subhead)
                .foregroundStyle(isFresh ? theme.inkSecondary : theme.ink)
                .frame(width: 96, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            rail
            Text(recency)
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .frame(width: 62, alignment: .trailing)
            Text(verbatim: "\(sets)")
                .font(InstrumentoType.groteskNumber(14, weight: .bold, relativeTo: .caption))
                .foregroundStyle(isFresh ? theme.inkTertiary : theme.ink)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(minHeight: EntrenarMetrics.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: name) + Text(verbatim: ", ") + Text(recency)
                            + Text(verbatim: ", ") + Text("\(sets) sets"))
    }

    private var rail: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                if !isFresh {
                    Capsule()
                        .fill(theme.dataStrain.opacity(0.35 + 0.65 * load))   // token-exempt: la opacidad ES el dato (recencia)
                        .frame(width: max(4, geo.size.width * load))
                }
            }
        }
        .frame(height: EntrenarMetrics.loadRail)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
private let demoDays: [EntrenarCalendarDay] = (0..<63).map { i in
    let state: EntrenarCalendarState
    switch i % 7 {
    case 0: state = .done(.push)
    case 2: state = .done(.pull)
    case 5: state = .done(.legs)
    case 6: state = i == 62 ? .today : .empty
    default: state = .empty
    }
    return EntrenarCalendarDay(id: "\(i)", state: state)
}

#Preview("TrainingCalendar · mini y full") {
    VStack(alignment: .leading, spacing: 28) {
        TrainingCalendar(days: demoDays, size: .mini, summary: "27 sessions in the last 9 weeks")
        TrainingCalendar(days: demoDays, size: .full, summary: "27 sessions in the last 9 weeks", action: {})
        TrainingCalendar(days: [], size: .full, summary: "no sessions yet")
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("MuscleLoadRow · estados") {
    VStack(spacing: 0) {
        MuscleLoadRow(name: "Quadriceps", load: 1.0, recency: "today", sets: 12, isFresh: false)
        Divider().overlay(InstrumentoTheme.base.hairline)
        MuscleLoadRow(name: "Back", load: 0.45, recency: "3 d ago", sets: 8, isFresh: false)
        Divider().overlay(InstrumentoTheme.base.hairline)
        MuscleLoadRow(name: "Chest", load: 0, recency: "fresh", sets: 0, isFresh: true)
        Divider().overlay(InstrumentoTheme.base.hairline)
        MuscleLoadRow(name: "Posterior deltoid", load: 0.2, recency: "6 d ago", sets: 2, isFresh: false)
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("Calendario y carga · xxxLarge") {
    VStack(alignment: .leading, spacing: 20) {
        TrainingCalendar(days: demoDays, size: .mini, summary: "27 sessions in the last 9 weeks")
        MuscleLoadRow(name: "Quadriceps", load: 1.0, recency: "today", sets: 12, isFresh: false)
        MuscleLoadRow(name: "Chest", load: 0, recency: "fresh", sets: 0, isFresh: true)
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
