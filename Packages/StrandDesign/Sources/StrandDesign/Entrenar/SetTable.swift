import SwiftUI

// MARK: - SetTable — la tabla de registro (FER-83 · E2)
//
// La pieza más usada de la sección: la tabla tipo Hevy que la sesión en vivo y «Rutina» comparten.
// Es la razón de ser de E2 — hoy cada pantalla dibuja su propia versión de estas cinco columnas, y
// un cambio de altura o de estado hay que hacerlo dos veces.
//
// Cuatro tipos de ejercicio cambian la columna del dato, nunca la estructura: peso×reps, peso
// corporal, tiempo y distancia. La fila actual se marca con badge relleno + filo izquierdo (no con
// un fondo de color: el hue no rellena chrome). Las filas hechas bajan a tinta secundaria, NO se
// aclaran hasta desaparecer. El calentamiento lleva «C» punteada en vez de número.

/// El tipo de ejercicio, del lado del diseño: decide qué columna de dato se dibuja.
public enum EntrenarExerciseKind: String, Sendable, CaseIterable, Hashable {
    case weightReps, bodyweight, time, distance

    /// El rótulo de la columna del dato principal.
    var primaryColumn: LocalizedStringKey {
        switch self {
        case .weightReps: return "KG"
        case .bodyweight: return "REPS"
        case .time:       return "TIME"
        case .distance:   return "DIST"
        }
    }

    /// Si el tipo además captura repeticiones en su propia columna.
    var hasRepsColumn: Bool { self == .weightReps }
}

/// Una fila de la tabla. Todo llega ya formateado: el componente no sabe de unidades ni de sistemas
/// métricos, solo de jerarquía y estado.
public struct EntrenarSetRow: Identifiable, Sendable, Hashable {
    public let id: String
    /// Lo que se pinta en el badge: «1», «2»… o «C» para calentamiento.
    public let badge: String
    /// «la última vez» de esa serie, o nil si es la primera.
    public let previous: String?
    /// El dato principal ya formateado (kg, reps de peso corporal, «1:30», «400 m»).
    public let primary: String
    /// Las repeticiones, solo en peso×reps.
    public let reps: String?
    public let done: Bool
    public let isWarmup: Bool
    /// La serie en curso: badge relleno + filo izquierdo en el tinte de la rutina.
    public let isCurrent: Bool
    /// La serie objetivo de una subida ganada: ▲ verde a su lado.
    public let isRaiseTarget: Bool

    public init(id: String, badge: String, previous: String? = nil, primary: String,
                reps: String? = nil, done: Bool = false, isWarmup: Bool = false,
                isCurrent: Bool = false, isRaiseTarget: Bool = false) {
        self.id = id; self.badge = badge; self.previous = previous; self.primary = primary
        self.reps = reps; self.done = done; self.isWarmup = isWarmup
        self.isCurrent = isCurrent; self.isRaiseTarget = isRaiseTarget
    }
}

public struct SetTable: View {
    private let kind: EntrenarExerciseKind
    private let family: EntrenarFamily?
    private let rows: [EntrenarSetRow]
    private let onToggle: ((String) -> Void)?
    private let onTapCell: ((String) -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(kind: EntrenarExerciseKind, family: EntrenarFamily? = nil,
                rows: [EntrenarSetRow],
                onToggle: ((String) -> Void)? = nil,
                onTapCell: ((String) -> Void)? = nil) {
        self.kind = kind; self.family = family; self.rows = rows
        self.onToggle = onToggle; self.onTapCell = onTapCell
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(rows) { row in
                Divider().overlay(theme.hairline)
                line(row)
            }
        }
    }

    private var tint: Color { family?.tint(theme) ?? theme.ink }
    /// El relleno del badge en curso. Va en el tono de LECTURA de la familia, no en su hue: el
    /// numeral que lleva encima es texto chico, y papel sobre el hue saturado se queda en 3.6:1.
    private var badgeFill: Color { family?.reading(theme) ?? theme.ink }

    private var header: some View {
        HStack(spacing: EntrenarMetrics.columnGap) {
            Text("SET").instrumentoOverline().frame(width: EntrenarMetrics.badge, alignment: .leading)
            Text("PREV").instrumentoOverline().frame(maxWidth: .infinity, alignment: .leading)
            Text(kind.primaryColumn).instrumentoOverline().frame(maxWidth: .infinity, alignment: .trailing)
            if kind.hasRepsColumn {
                Text("REPS").instrumentoOverline().frame(maxWidth: .infinity, alignment: .trailing)
            }
            Color.clear.frame(width: EntrenarMetrics.row, height: 1)
        }
        .foregroundStyle(theme.inkTertiary)
        .padding(.bottom, CenitMetrics.space1)
        .accessibilityHidden(true)   // la fila ya se lee completa; los rótulos serían ruido
    }

    private func line(_ row: EntrenarSetRow) -> some View {
        HStack(spacing: EntrenarMetrics.columnGap) {
            badge(row)
            Text(verbatim: row.previous ?? "—")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .minimumScaleFactor(0.8)
            primaryCell(row)
            if kind.hasRepsColumn {
                cell(row.reps ?? "—", row: row)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            check(row)
        }
        .padding(.leading, EntrenarMetrics.currentEdge + CenitMetrics.space2)
        .frame(minHeight: EntrenarMetrics.tableRow)
        .overlay(alignment: .leading) {
            if row.isCurrent {
                Rectangle().fill(tint).frame(width: EntrenarMetrics.currentEdge)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowLabel(row))
    }

    private func badge(_ row: EntrenarSetRow) -> some View {
        Text(verbatim: row.badge)
            .font(InstrumentoType.groteskNumber(12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(row.isCurrent ? theme.paper : theme.inkSecondary)
            .frame(width: EntrenarMetrics.badge, height: EntrenarMetrics.badge)
            .background {
                if row.isCurrent {
                    Circle().fill(badgeFill)
                } else if row.isWarmup {
                    Circle().strokeBorder(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                } else {
                    Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1)
                }
            }
    }

    private func primaryCell(_ row: EntrenarSetRow) -> some View {
        HStack(spacing: CenitMetrics.space1) {
            if row.isRaiseTarget {
                StrandIcon.up.image
                    .font(StrandFont.glyph(.chevron, weight: .bold))
                    .foregroundStyle(theme.positiveText)
            }
            cell(row.primary, row: row)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func cell(_ text: String, row: EntrenarSetRow) -> some View {
        let content = Text(verbatim: text)
            .font(InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(row.done ? theme.inkSecondary : theme.ink)
            .minimumScaleFactor(0.75)
            .lineLimit(1)
        return Group {
            if let onTapCell {
                Button { onTapCell(row.id) } label: {
                    // El blanco táctil es la CELDA, no el texto: un «82.5» mide 34 pt de ancho y
                    // 18 de alto, y esta celda es un campo de captura que se toca todo el tiempo.
                    content
                        .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.row, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EntrenarPressStyle())
            } else {
                content
            }
        }
    }

    private func check(_ row: EntrenarSetRow) -> some View {
        Button { onToggle?(row.id) } label: {
            Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: EntrenarMetrics.check))
                .foregroundStyle(row.done ? theme.positiveText : theme.inkTertiary)
                // La celda ENTERA es tocable, aunque el glifo mida 24 (HIG).
                .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .disabled(onToggle == nil)
        .accessibilityLabel(row.done ? Text("Done") : Text("Mark set done"))
    }

    private func rowLabel(_ row: EntrenarSetRow) -> Text {
        var t = row.isWarmup ? Text("Warm-up set") : Text("Set \(row.badge)")
        t = t + Text(verbatim: ", ") + Text(verbatim: row.primary)
        if let reps = row.reps { t = t + Text(verbatim: " × ") + Text(verbatim: reps) }
        if row.done { t = t + Text(verbatim: ", ") + Text("done") }
        return t
    }
}

#if DEBUG
private let demoRows: [EntrenarSetRow] = [
    .init(id: "w", badge: "C", previous: "40 kg × 10", primary: "40", reps: "10",
          done: true, isWarmup: true),
    .init(id: "1", badge: "1", previous: "80 kg × 8", primary: "82.5", reps: "8", done: true),
    .init(id: "2", badge: "2", previous: "80 kg × 8", primary: "82.5", reps: "8",
          isCurrent: true, isRaiseTarget: true),
    .init(id: "3", badge: "3", previous: "80 kg × 8", primary: "82.5", reps: "8"),
]

#Preview("SetTable · peso × reps") {
    SetTable(kind: .weightReps, family: .legs, rows: demoRows, onToggle: { _ in }, onTapCell: { _ in })
        .padding(24)
        .background(InstrumentoTheme.base.paper)
        .instrumentoTheme(.base)
}

#Preview("SetTable · los otros tres tipos") {
    VStack(alignment: .leading, spacing: 28) {
        SetTable(kind: .bodyweight, family: .pull, rows: [
            .init(id: "1", badge: "1", previous: "12", primary: "12", done: true),
            .init(id: "2", badge: "2", previous: "12", primary: "12", isCurrent: true),
        ], onToggle: { _ in })
        SetTable(kind: .time, family: .push, rows: [
            .init(id: "1", badge: "1", previous: "0:45", primary: "1:00", isCurrent: true),
        ], onToggle: { _ in })
        SetTable(kind: .distance, family: .fullBody, rows: [
            .init(id: "1", badge: "1", primary: "400 m", isCurrent: true),
        ], onToggle: { _ in })
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("SetTable · vacía y xxxLarge") {
    VStack(alignment: .leading, spacing: 28) {
        SetTable(kind: .weightReps, rows: [])
        SetTable(kind: .weightReps, family: .legs, rows: Array(demoRows.prefix(3)), onToggle: { _ in })
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
