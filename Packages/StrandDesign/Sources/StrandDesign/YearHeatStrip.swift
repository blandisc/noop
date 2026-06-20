import SwiftUI

// MARK: - Year Heat Strip (§9.4 Trends)
//
// A GitHub-style year grid: columns = weeks, rows = weekdays. Each cell is tinted
// by that day's recovery score via the signature recovery gradient. Empty days
// (no data) render as a faint inset square. Hover shows a tooltip via SwiftUI's
// built-in help.

/// A day's recovery datum for the heat strip.
public struct RecoveryDay: Identifiable, Sendable {
    public let id = UUID()
    public var date: Date
    /// Recovery 0...100, or nil if no data for that day.
    public var score: Double?

    public init(date: Date, score: Double?) {
        self.date = date
        self.score = score
    }
}

public struct YearHeatStrip: View {

    public var days: [RecoveryDay]
    public var cellSize: CGFloat
    public var spacing: CGFloat
    public var showsMonthLabels: Bool
    /// Whether hovering a cell highlights it with a ring and shows a tooltip
    /// (date + score + recovery state word). Defaults on.
    public var showsHover: Bool
    /// Tints a day's cell from its recovery score. Defaults to the dark-system recovery gradient so
    /// the shipped (dark) Trends caller is unchanged; the light «Instrumento» detail passes a warm
    /// band-color closure instead, so the calendar reads on warm paper. (FER-225)
    public var tint: (Double) -> Color
    /// Fill for an in-range day that has no data. Defaults to the dark `surfaceInset`; the light
    /// detail passes a warm hairline so empty days don't render as near-black squares on paper. (FER-225)
    public var emptyFill: Color
    /// Hairline stroke around an empty-but-in-range day. (FER-225)
    public var emptyStroke: Color
    /// Color of the month + weekday gutter labels. Defaults to the dark `textTertiary`; the light
    /// detail passes warm `inkTertiary`. (FER-225)
    public var labelColor: Color
    /// When set, tapping a day calls this with the tapped `RecoveryDay` — touch-friendly selection, since
    /// `onContinuousHover` never fires on touch (iPhone). The tapped cell gets a selection ring, and the
    /// caller shows the day's read-out. Default `nil` keeps the shipped (dark, hover-only) behavior, so
    /// the Trends caller is unchanged. (FER-235)
    public var onSelect: ((RecoveryDay) -> Void)?
    /// Color of the tap-selection ring. Defaults to the dark `hairlineStrong`; the light detail passes
    /// warm ink. (FER-235)
    public var selectionColor: Color
    /// Formats a day's score for the tooltip's bold line.
    public var valueFormat: (Double) -> String

    public init(
        days: [RecoveryDay],
        cellSize: CGFloat = 12,
        spacing: CGFloat = 3,
        showsMonthLabels: Bool = true,
        showsHover: Bool = true,
        tint: @escaping (Double) -> Color = { StrandPalette.recoveryColor($0) },
        emptyFill: Color = StrandPalette.surfaceInset,
        emptyStroke: Color = StrandPalette.hairline.opacity(0.6),
        labelColor: Color = StrandPalette.textTertiary,
        onSelect: ((RecoveryDay) -> Void)? = nil,
        selectionColor: Color = StrandPalette.hairlineStrong,
        valueFormat: @escaping (Double) -> String = { "Recovery \(Int($0.rounded()))" }
    ) {
        self.days = days.sorted { $0.date < $1.date }
        self.cellSize = cellSize
        self.spacing = spacing
        self.showsMonthLabels = showsMonthLabels
        self.showsHover = showsHover
        self.tint = tint
        self.emptyFill = emptyFill
        self.emptyStroke = emptyStroke
        self.labelColor = labelColor
        self.onSelect = onSelect
        self.selectionColor = selectionColor
        self.valueFormat = valueFormat
    }

    /// The number of week columns the grid will draw for `days` (Monday-first weeks). Exposed so a
    /// caller that wants the grid to fill a known width can size `cellSize` to it without duplicating
    /// the bucketing. Returns 0 for an empty set. (FER-225)
    public static func weekColumns(for days: [RecoveryDay]) -> Int {
        let sorted = days.sorted { $0.date < $1.date }
        guard let first = sorted.first?.date else { return 0 }
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        let wd = c.component(.weekday, from: first)
        let firstRow = (wd + 5) % 7                       // Monday-first 0…6
        return Int(ceil(Double(firstRow + sorted.count) / 7.0))
    }

    // The grid layout constants used both for drawing and hover hit-testing.
    private let gutterWidth: CGFloat = 24
    private let monthLabelHeight: CGFloat = 10

    /// Hovered cell as (weekIndex, row), or nil.
    @State private var hoverCell: (week: Int, row: Int)? = nil
    /// Tapped day's id, for the touch-selection ring. (FER-235)
    @State private var selectedID: UUID? = nil

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday-first columns read nicely
        return c
    }

    // Group days into week columns. weekday 0 = Monday ... 6 = Sunday.
    private struct Week: Identifiable {
        let id = UUID()
        var cells: [RecoveryDay?] // length 7, indexed by weekday row
        var monthLabel: String?
    }

    private func buildWeeks() -> [Week] {
        guard let first = days.first?.date else { return [] }
        var weeks: [Week] = []
        var current = Week(cells: Array(repeating: nil, count: 7), monthLabel: nil)
        var lastMonth = -1
        // Pad the first week so the first day lands on its weekday row.
        let firstRow = weekdayRow(first)
        var filledThisWeek = 0
        for _ in 0..<firstRow { filledThisWeek += 1 }

        for day in days {
            let row = weekdayRow(day.date)
            if row == 0 && filledThisWeek > 0 {
                weeks.append(current)
                current = Week(cells: Array(repeating: nil, count: 7), monthLabel: nil)
                filledThisWeek = 0
            }
            current.cells[row] = day
            // tag month label at the first cell of a new month
            let month = calendar.component(.month, from: day.date)
            if month != lastMonth {
                current.monthLabel = monthShort(day.date)
                lastMonth = month
            }
            filledThisWeek += 1
        }
        if filledThisWeek > 0 { weeks.append(current) }
        return weeks
    }

    private func weekdayRow(_ date: Date) -> Int {
        // Map Calendar weekday (1=Sun...7=Sat) to Monday-first 0...6.
        let wd = calendar.component(.weekday, from: date)
        return (wd + 5) % 7
    }

    private func monthShort(_ date: Date) -> String {
        let f = DateFormatterCache.month
        return f.string(from: date)
    }

    // Localized weekday gutter. `shortWeekdaySymbols` is always Sunday-indexed
    // regardless of locale, so pick Mon(1)/Wed(3)/Fri(5)/Sun(0); the grid rows are
    // Monday-first (see rowIndex), independent of the locale's firstWeekday.
    private var rowLabels: [String] {
        let s = Calendar.current.shortWeekdaySymbols
        return [s[1], "", s[3], "", s[5], "", s[0]]
    }

    public var body: some View {
        let weeks = buildWeeks()
        // Total drawn size, so the hover overlay can be laid over the grid and
        // a tooltip can be clamped within bounds.
        let gridWidth = gridOriginX + CGFloat(weeks.count) * (cellSize + spacing) - spacing
        let gridHeight = gridOriginY + 7 * (cellSize + spacing) - spacing

        VStack(alignment: .leading, spacing: spacing) {
            if showsMonthLabels {
                HStack(spacing: spacing) {
                    // align with the weekday-label gutter
                    Color.clear.frame(width: gridOriginX - spacing, height: monthLabelHeight)
                    ForEach(weeks) { week in
                        Text(week.monthLabel ?? "")
                            .font(.system(size: 8))
                            .foregroundStyle(labelColor)
                            .frame(width: cellSize, alignment: .leading)
                    }
                }
            }
            HStack(alignment: .top, spacing: spacing) {
                // weekday gutter
                VStack(alignment: .trailing, spacing: spacing) {
                    ForEach(0..<7, id: \.self) { r in
                        Text(rowLabels[r])
                            .font(.system(size: 8))
                            .foregroundStyle(labelColor)
                            .frame(width: gutterWidth, height: cellSize, alignment: .trailing)
                    }
                }
                // week columns
                ForEach(Array(weeks.enumerated()), id: \.element.id) { weekIndex, week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(week.cells[row], isHovered: isHovered(weekIndex, row))
                        }
                    }
                }
            }
        }
        .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
        .overlay(hoverOverlay(weeks: weeks, gridSize: CGSize(width: gridWidth, height: gridHeight)))
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard showsHover else { return }
            switch phase {
            case .active(let location):
                hoverCell = cellIndex(at: location, weekCount: weeks.count)
            case .ended:
                hoverCell = nil
            }
        }
    }

    // MARK: Grid geometry

    /// x of the first week column (after the weekday gutter + HStack spacing).
    private var gridOriginX: CGFloat { gutterWidth + spacing }
    /// y of the first cell row (below the optional month-label row).
    private var gridOriginY: CGFloat { showsMonthLabels ? monthLabelHeight + spacing : 0 }

    private func isHovered(_ week: Int, _ row: Int) -> Bool {
        guard let h = hoverCell else { return false }
        return h.week == week && h.row == row
    }

    /// Map a local cursor location to a (week, row) cell, or nil if outside the
    /// grid or in the inter-cell gaps.
    private func cellIndex(at point: CGPoint, weekCount: Int) -> (week: Int, row: Int)? {
        let stride = cellSize + spacing
        let lx = point.x - gridOriginX
        let ly = point.y - gridOriginY
        guard lx >= 0, ly >= 0 else { return nil }
        let week = Int(lx / stride)
        let row = Int(ly / stride)
        guard week >= 0, week < weekCount, row >= 0, row < 7 else { return nil }
        // Reject hits in the spacing gutter between cells.
        let withinX = lx - CGFloat(week) * stride
        let withinY = ly - CGFloat(row) * stride
        guard withinX <= cellSize, withinY <= cellSize else { return nil }
        return (week, row)
    }

    /// Centre of a cell in local coordinates.
    private func cellCenter(week: Int, row: Int) -> CGPoint {
        let stride = cellSize + spacing
        return CGPoint(
            x: gridOriginX + CGFloat(week) * stride + cellSize / 2,
            y: gridOriginY + CGFloat(row) * stride + cellSize / 2
        )
    }

    // MARK: Hover overlay (ring + tooltip)

    @ViewBuilder
    private func hoverOverlay(weeks: [Week], gridSize: CGSize) -> some View {
        if showsHover, let h = hoverCell, h.week < weeks.count,
           let day = weeks[h.week].cells[h.row], let score = day.score {
            let center = cellCenter(week: h.week, row: h.row)
            ZStack(alignment: .topLeading) {
                // subtle highlight ring on the hovered cell
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(StrandPalette.hairlineStrong, lineWidth: 1.5)
                    .frame(width: cellSize + 3, height: cellSize + 3)
                    .position(center)
                PositionedTooltip(
                    anchor: center,
                    container: gridSize,
                    tooltip: ChartTooltip(
                        value: valueFormat(score),
                        label: "\(DateFormatterCache.day.string(from: day.date)) · \(StrandPalette.recoveryState(score))",
                        accent: tint(score)
                    )
                )
            }
            .animation(StrandMotion.fade, value: h.week)
            .animation(StrandMotion.fade, value: h.row)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func cell(_ day: RecoveryDay?, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5)
        let isSelected = day.map { $0.id == selectedID } ?? false
        Group {
            if let day, let score = day.score {
                shape
                    .fill(tint(score))
                    .frame(width: cellSize, height: cellSize)
                    .opacity(isHovered ? 1.0 : (hoverCell == nil ? 1.0 : 0.78))
                    .help("\(DateFormatterCache.day.string(from: day.date)) · recovery \(Int(score.rounded()))")
            } else if day != nil {
                shape
                    .fill(emptyFill)
                    .overlay(shape.stroke(emptyStroke, lineWidth: 0.5))
                    .frame(width: cellSize, height: cellSize)
            } else {
                shape
                    .fill(Color.clear)
                    .frame(width: cellSize, height: cellSize)
            }
        }
        .overlay {
            // Selection ring for touch (FER-235). Only ever shows after a tap, which only the selectable
            // path enables — so it's inert for the hover-only Trends caller.
            if isSelected {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(selectionColor, lineWidth: 2)
                    .frame(width: cellSize + 4, height: cellSize + 4)
            }
        }
        .modifier(SelectableCell(
            enabled: onSelect != nil && day != nil,
            label: day.map(cellAccessibilityLabel) ?? Text(""),
            action: { if let day { selectedID = day.id; onSelect?(day) } }))
    }

    /// VoiceOver label for a selectable cell: its date + score, or "no reading" for an in-range gap. (FER-235)
    private func cellAccessibilityLabel(_ day: RecoveryDay) -> Text {
        let date = DateFormatterCache.day.string(from: day.date)
        if let score = day.score {
            return Text("\(date) · recovery \(Int(score.rounded()))")
        }
        return Text("\(date) · no reading")
    }
}

/// Adds tap selection + a VoiceOver button only when `enabled` (a calendar day with `onSelect` set), so
/// the hover-only Trends caller's cells stay exactly as before — no tap target, no extra a11y element. (FER-235)
private struct SelectableCell: ViewModifier {
    let enabled: Bool
    let label: Text
    let action: () -> Void
    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

// Small cached formatters (creating DateFormatter is expensive).
private enum DateFormatterCache {
    static let month: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
}

#if DEBUG
private func sampleYear() -> [RecoveryDay] {
    let cal = Calendar.current
    let today = Date()
    return (0..<365).map { i in
        let date = cal.date(byAdding: .day, value: -(364 - i), to: today)!
        // Some gaps + a wavy recovery profile.
        let gap = (i % 23 == 0)
        let v = 55 + 28 * sin(Double(i) / 11.0) + Double((i * 31) % 17) - 8
        return RecoveryDay(date: date, score: gap ? nil : max(2, min(99, v)))
    }
}

#Preview("YearHeatStrip") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Recovery — past year").strandOverline()
        Text("Hover a cell: ring + date, score and recovery-state tooltip.")
            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        YearHeatStrip(days: sampleYear())
    }
    .padding(28)
    .frame(width: 900, height: 240)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
