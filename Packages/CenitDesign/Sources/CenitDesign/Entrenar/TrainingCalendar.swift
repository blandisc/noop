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
    private let onTapDay: ((EntrenarCalendarDay) -> Void)?
    private let monthLabels: [Int: LocalizedStringKey]

    @Environment(\.instrumentoTheme) private var theme

    /// - Parameters:
    ///   - onTapDay: toque POR CELDA (solo en días `.done`) — distinto de `action`, que es un único
    ///     toque para TODA la rejilla. Los dos son mutuamente exclusivos en la práctica (un call site
    ///     usa uno u otro); nada en el componente los excluye por contrato, pero pasar los dos envolvería
    ///     cada celda en un Button DENTRO de otro Button, que iOS no anida — no lo hagas.
    ///   - monthLabels: rótulo opcional por FILA (row-index → «jul»/«ago»), dibujado en una columna
    ///     angosta de ancho fijo antes del `HStack` de esa fila — el mismo ancho en toda fila (con o
    ///     sin rótulo) para que las filas se alineen. Vacío (default) reproduce el layout de hoy.
    public init(days: [EntrenarCalendarDay], size: Size, columnsPerRow: Int = 7,
                summary: LocalizedStringKey, action: (() -> Void)? = nil,
                onTapDay: ((EntrenarCalendarDay) -> Void)? = nil,
                monthLabels: [Int: LocalizedStringKey] = [:]) {
        self.days = days; self.size = size; self.columnsPerRow = max(1, columnsPerRow)
        self.summary = summary; self.action = action
        self.onTapDay = onTapDay; self.monthLabels = monthLabels
    }

    private var side: CGFloat {
        size == .mini ? EntrenarMetrics.calendarCellMini : EntrenarMetrics.calendarCell
    }

    /// Ancho fijo de la columna de rótulo de mes — «es un gráfico, no texto» (mismo criterio que las
    /// celdas), así que no escala con Dynamic Type. Cero cuando `monthLabels` está vacío: el layout de
    /// los call sites existentes no se mueve un punto.
    private var monthLabelWidth: CGFloat { monthLabels.isEmpty ? 0 : 20 }

    public var body: some View {
        let grid = VStack(alignment: .leading, spacing: EntrenarMetrics.calendarGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: EntrenarMetrics.calendarGap) {
                    if !monthLabels.isEmpty { monthLabel(rowIndex) }
                    ForEach(row) { day in cell(day) }
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

    @ViewBuilder
    private func monthLabel(_ rowIndex: Int) -> some View {
        Group {
            if let key = monthLabels[rowIndex] { Text(key) } else { Text(verbatim: "") }
        }
        .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
        .frame(width: monthLabelWidth, alignment: .leading)
        // Decorativo: el resumen (VoiceOver, arriba) ya dice cuántas sesiones y en qué ventana; un
        // rótulo de mes suelto sin la celda que lo acompaña sería ruido.
        .accessibilityHidden(true)
    }

    private var rows: [[EntrenarCalendarDay]] {
        stride(from: 0, to: days.count, by: columnsPerRow).map {
            Array(days[$0 ..< min($0 + columnsPerRow, days.count)])
        }
    }

    @ViewBuilder
    private func cell(_ day: EntrenarCalendarDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: EntrenarMetrics.calendarRadius, style: .continuous)
        let box = shape
            .fill(day.state.fill(theme))
            .frame(width: side, height: side)
            .overlay {
                if let stroke = day.state.stroke(theme) { shape.strokeBorder(stroke, lineWidth: 1.5) }
            }
        // Solo un día CON sesión reacciona — el resto queda plano, sin `Button` (Alcance punto 2). El
        // toque por celda es un ATAJO visual, nunca el camino accesible: la rejilla entera sigue siendo
        // UN accessibilityElement con `summary` (arriba), así que envolver la celda en un Button no
        // expone 91 elementos sueltos a VoiceOver.
        if let onTapDay, case .done = day.state {
            Button { onTapDay(day) } label: { box }
                .buttonStyle(EntrenarPressStyle())
        } else {
            box
        }
    }
}

/// Una fila del módulo «MÚSCULOS CARGADOS».
///
/// Un solo hue (ámbar): la carga se dibuja en el LARGO de la barra y se refuerza con la opacidad —
/// las dos salen del mismo número, que ya trae la recencia dentro (la carga decae a la mitad cada
/// dos días). «Fresco» NO es verde: es el riel vacío y tinta secundaria. Un semáforo aquí
/// convertiría una estimación en un permiso, y el permiso lo da el veredicto, no el mapa.
///
/// Crecida en FER-91 (E10) para su primer consumidor real: `action` abre el detalle del músculo
/// (opcional — sin ella la fila es de solo lectura, como en el catálogo), `sets` pasó de `Int` a
/// `Double` porque un músculo secundario carga a medias (`Exercise.secondaryWeight = 0.5`) y
/// truncar 8.5 a 8 perdía el dato; `name` pasó de `String` a `LocalizedStringKey` porque su primer
/// consumidor real alimenta nombres de `MuscleAtlas.name(_:)`, que SÍ están tras el catálogo de
/// localización — `Text(verbatim:)` los habría mostrado siempre en inglés.
public struct MuscleLoadRow: View {
    private let name: LocalizedStringKey
    private let load: Double
    private let recency: LocalizedStringKey
    private let sets: Double
    private let isFresh: Bool
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(name: LocalizedStringKey, load: Double, recency: LocalizedStringKey, sets: Double,
                isFresh: Bool, action: (() -> Void)? = nil) {
        self.name = name; self.load = max(0, min(1, load))
        self.recency = recency; self.sets = sets; self.isFresh = isFresh
        self.action = action
    }

    /// El mismo formato que `MuscleFatigueMap.formattedSets` (StrandAnalytics): entero cuando el
    /// valor es entero, un decimal si no. Duplicado a propósito — este paquete es la raíz del grafo
    /// (cero dependencias, ni siquiera StrandAnalytics) — así que mantener las dos fórmulas
    /// idénticas es responsabilidad de la prueba, no de un import.
    static func formattedSets(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(v == v.rounded() ? 0 : 1)))
    }

    public var body: some View {
        if let action {
            Button(action: action) { rowContent }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityHint(Text("Opens the full detail"))
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: LiquidSpace.s300) {
            // Anchos RELATIVOS, no fijos: con Dynamic Type grande los 96/62/28 de antes dejaban al
            // conteo de series fuera de su columna. El nombre manda, el riel cede, y los dos datos
            // de la derecha se dimensionan por su contenido.
            Text(name)
                .font(StrandFont.subhead)
                .foregroundStyle(isFresh ? theme.inkSecondary : theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            rail.frame(maxWidth: 120)
            Text(recency)
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: Self.formattedSets(sets))
                .font(InstrumentoType.groteskNumber(14, weight: .bold, relativeTo: .caption))
                .foregroundStyle(isFresh ? theme.inkTertiary : theme.ink)
                .fixedSize(horizontal: true, vertical: false)
            if action != nil {
                CenitIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(name) + Text(verbatim: ", ") + Text(recency)
                            + Text(verbatim: ", ") + Text("\(Self.formattedSets(sets)) sets"))
    }

    private var rail: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LiquidColor.tinta10)
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

/// Rótulos de mes de ejemplo para el caso `onTapDay` + `monthLabels`: `demoDays` no tiene fechas reales
/// (son índices, no días del calendario), así que aquí solo se ilustra QUE el mecanismo dibuja la
/// columna angosta en las filas marcadas — fila 0 y una fila intermedia, como pediría un cambio de mes.
private let demoMonthLabels: [Int: LocalizedStringKey] = [0: "jul", 5: "ago"]

#Preview("TrainingCalendar · mini y full") {
    VStack(alignment: .leading, spacing: 28) {
        TrainingCalendar(days: demoDays, size: .mini, summary: "27 sessions in the last 9 weeks")
        TrainingCalendar(days: demoDays, size: .full, summary: "27 sessions in the last 9 weeks", action: {})
        TrainingCalendar(days: demoDays, size: .full, summary: "27 sessions in the last 9 weeks",
                          onTapDay: { _ in }, monthLabels: demoMonthLabels)
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
        Divider().overlay(InstrumentoTheme.base.hairline)
        // FER-91 (E10): decimal series (un músculo secundario carga a 0.5) y la variante con `action`.
        MuscleLoadRow(name: "Shoulders", load: 0.7, recency: "1 d ago", sets: 8.5, isFresh: false, action: {})
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
