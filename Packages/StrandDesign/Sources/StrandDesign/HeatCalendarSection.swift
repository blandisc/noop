import SwiftUI

// MARK: - HeatCalendarSection — the 90-day calendar shared by Recovery/Strain/Sleep (FER-975)
//
// Recovery/Strain/Sleep detail screens each carried a near-identical `calendarContent` + `heatGrid` +
// `heatReadout`: the 90-day `Calendario90` grid, a read-out row for the tapped day (date · value · state
// word, or an honest "no reading"), and the `HeatLegend`. Promoted here with flat data — the screen
// still builds its own `[RecoveryDay]`, tint closure, value/word formatters and legend; this component
// owns the shared shape, spacing and the read-out's date format + a11y + empty-hint copy.
//
// `StressDetailScreen` is DELIBERATELY NOT a consumer here (FER-975): its calendar read-out reuses
// `chipDateFormatter`, which anchors to an EXPLICIT UTC time zone (also shared with two other stress
// chip read-outs that parse UTC-midnight day-keys directly) — unlike Recovery/Strain/Sleep's read-out
// formatter, which has no explicit time zone. Folding Stress into this component's fixed internal
// formatter would silently drop that UTC anchor. Left as-is; the caller (the human running this task)
// will note it as a reported, non-forced gap.

/// The 90-day calendar section: grid + tapped-day read-out + legend, spacing and copy shared across the
/// «Instrumento diurno» trend detail screens that share one date-formatting convention. The caller
/// supplies its own data, tint and formatters — this component stays data-plain (no engine types).
public struct HeatCalendarSection: View {
    private let days: [RecoveryDay]
    @Binding private var selected: RecoveryDay?
    private let tint: (Double) -> Color
    private let readoutValue: (Double) -> String
    private let readoutWord: (Double) -> LocalizedStringKey
    private let emptyHint: LocalizedStringKey
    private let legend: [(Color, String)]
    private let theme: InstrumentoTheme

    public init(days: [RecoveryDay],
                selected: Binding<RecoveryDay?>,
                tint: @escaping (Double) -> Color,
                readoutValue: @escaping (Double) -> String,
                readoutWord: @escaping (Double) -> LocalizedStringKey,
                emptyHint: LocalizedStringKey,
                legend: [(Color, String)],
                theme: InstrumentoTheme) {
        self.days = days
        self._selected = selected
        self.tint = tint
        self.readoutValue = readoutValue
        self.readoutWord = readoutWord
        self.emptyHint = emptyHint
        self.legend = legend
        self.theme = theme
    }

    /// «EEE d MMM» in the current locale — the tapped day's date in the read-out. Verified identical
    /// (`setLocalizedDateFormatFromTemplate("EEEdMMM")`, no explicit time zone) across Recovery, Strain
    /// and Sleep before promotion (FER-975).
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Calendario90(days: days, tint: tint, onSelect: { selected = $0 }, theme: theme)
            readout
            HeatLegend(legend, theme: theme)
        }
    }

    /// The read-out under the calendar: the tapped day's date + value (in its tint color) + state word,
    /// or an honest "no reading" for an in-range gap; a quiet hint until the user taps a day.
    @ViewBuilder private var readout: some View {
        if let day = selected {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.dateFmt.string(from: day.date))
                    .groteskOverline()
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if let score = day.score {
                    Text(readoutValue(score))
                        .font(InstrumentoType.groteskTileValue)
                        .foregroundStyle(tint(score))
                    Text(readoutWord(score))
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                } else {
                    Text("—")
                        .font(InstrumentoType.groteskTileValue)
                        .foregroundStyle(theme.inkTertiary)
                    Text("no reading")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(emptyHint)
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("HeatCalendarSection") {
    let t = InstrumentoTheme.base
    let days: [RecoveryDay] = (0..<90).map { i in
        RecoveryDay(date: Date().addingTimeInterval(Double(i - 89) * 86_400),
                    score: i % 7 == 0 ? nil : Double((i * 13) % 100))
    }
    ScrollView {
        HeatCalendarSection(
            days: days,
            selected: .constant(days.last),
            tint: { $0 >= 67 ? t.verdict : ($0 >= 34 ? t.warning : t.critical) },
            readoutValue: { "\(Int($0.rounded()))" },
            readoutWord: { $0 >= 67 ? "Ready" : ($0 >= 34 ? "Recovering" : "Low") },
            emptyHint: "Tap a day to see its recovery.",
            legend: [(t.verdict, "ready"), (t.warning, "recovering"), (t.critical, "low"), (t.rangeBand, "no data")],
            theme: t)
        .padding(20)
    }
    .background(t.paper)
}
#endif
