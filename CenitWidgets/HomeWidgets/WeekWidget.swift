// FER-95 · E14 — the week's plan, the medium home-screen widget.
//
// Redraws the 7-day strip with the SAME pure semantics `WeeklySplit`/`WeekTokens` already define
// (done/today/upcoming/rest — via `TrainWidgetSnapshot.WeekDayState`, already resolved by the app), but
// as its own WidgetKit view: `WeekTokens` (CenitDesign) is a SwiftUI `View` built for the app's live
// theme environment, not something a widget extension can reuse verbatim. No family tint here (out of
// scope — decisión #13 del épico, resuelta en otra rama): a filled token means «trained», not «which
// routine».

import SwiftUI
import WidgetKit
import CenitDesign

struct WeekEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainWidgetSnapshot?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekEntry(date: Date(),
                             snapshot: context.isPreview ? Self.sample : TrainWidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let entry = WeekEntry(date: Date(), snapshot: TrainWidgetSnapshot.read())
        let nextRefresh = Date().addingTimeInterval(4 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static let sample = TrainWidgetSnapshot(
        writtenAt: Date(),
        today: .init(routineName: "Empuje", sessionLive: false),
        verdict: .init(tone: .clear, word: String(localized: "In range")),
        week: [
            .init(weekday: 2, state: .done, label: "L"), .init(weekday: 3, state: .rest, label: "M"),
            .init(weekday: 4, state: .done, label: "X"), .init(weekday: 5, state: .rest, label: "J"),
            .init(weekday: 6, state: .today, label: "V"), .init(weekday: 7, state: .upcoming, label: "S"),
            .init(weekday: 1, state: .rest, label: "D"),
        ])
}

struct WeekWidgetView: View {
    let entry: WeekEntry
    private let theme = InstrumentoTheme.base
    private typealias M = HomeWidgetMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.paper
            content.padding(M.padding)
        }
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot {
            if snapshot.isStale(asOf: entry.date) {
                staleHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                body(snapshot: snapshot)
            }
        } else {
            body(snapshot: WeekProvider.sample)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func body(snapshot: TrainWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: M.weekGap) {
            header(snapshot: snapshot)
            WeekStrip(days: snapshot.week, theme: theme)
        }
    }

    private var staleHeader: some View {
        VStack(alignment: .leading, spacing: M.rowGap) {
            Text("This week")
                .font(.system(size: M.overline, weight: .semibold))
                .tracking(M.overlineTracking)
                .foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 0)
            Text("Open Cénit")
                .font(.system(size: M.title, weight: .bold, design: .rounded))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open Cénit"))
    }

    @ViewBuilder private func header(snapshot: TrainWidgetSnapshot) -> some View {
        if let today = snapshot.today {
            Button(intent: StartTodayRoutineIntent()) {
                headerRow(title: Text(verbatim: today.routineName), verdict: snapshot.verdict,
                          cta: today.sessionLive ? "Continue" : "Start")
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((today.sessionLive ? Text("Continue") : Text("Start routine"))
                + Text(verbatim: ", ") + Text(verbatim: today.routineName))
            .accessibilityHint(Text("Opens today's guided session"))
            .accessibilityAddTraits(.isButton)
        } else {
            headerRow(title: Text("Rest day"), verdict: snapshot.verdict, cta: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Rest day"))
        }
    }

    private func headerRow(title: Text, verdict: TrainWidgetSnapshot.Verdict?, cta: LocalizedStringKey?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: M.microGap) {
                Text("Today")
                    .font(.system(size: M.overline, weight: .semibold))
                    .tracking(M.overlineTracking)
                    .foregroundStyle(theme.inkTertiary)
                title
                    .font(.system(size: M.title, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: M.microGap) {
                if let verdict {
                    Text(verbatim: verdict.word)
                        .font(.system(size: M.verdict, weight: .medium))
                        .foregroundStyle(verdict.tone.strandTone.word(theme))
                        .lineLimit(1)
                }
                if let cta {
                    Text(cta)
                        .font(.system(size: M.cta, weight: .semibold))
                        .foregroundStyle(theme.ink)
                }
            }
        }
    }
}

/// The 7-day strip: one token + label per day, in the order the snapshot already carries them
/// (Monday-first, matching the app's `orderedWeekdays`).
private struct WeekStrip: View {
    let days: [TrainWidgetSnapshot.WeekDay]
    let theme: InstrumentoTheme
    private typealias M = HomeWidgetMetrics

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: M.dayTokenGap) {
                    token(day.state)
                    Text(verbatim: day.label)
                        .font(.system(size: M.dayLabel, weight: .medium))
                        .foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(a11yLabel(day))
            }
        }
    }

    @ViewBuilder private func token(_ state: TrainWidgetSnapshot.WeekDayState) -> some View {
        let side = M.dayToken
        switch state {
        case .done:
            Circle().fill(theme.ink).frame(width: side, height: side)
        case .today:
            Circle().strokeBorder(theme.ink, lineWidth: M.ringToday).frame(width: side, height: side)
        case .upcoming:
            Circle().strokeBorder(theme.hairlineStrong, lineWidth: M.ringUpcoming).frame(width: side, height: side)
        case .rest:
            Circle().strokeBorder(theme.inkTertiary, style: StrokeStyle(lineWidth: M.ringRest, dash: M.ringRestDash))
                .frame(width: side, height: side)
        }
    }

    private func a11yLabel(_ day: TrainWidgetSnapshot.WeekDay) -> Text {
        let name = Text(verbatim: day.label) + Text(verbatim: ", ")
        switch day.state {
        case .done:     return name + Text("trained")
        case .today:    return name + Text("today") + Text(verbatim: ", ") + Text("training day")
        case .upcoming: return name + Text("planned")
        case .rest:     return name + Text("rest day")
        }
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrainWidgetSnapshot.weekKind, provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("This week"))
        .description(Text("Your week's plan, and today's routine in one tap."))
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Con rutina", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: WeekProvider.sample)
}

#Preview("Día de descanso", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: nil,
        verdict: .init(tone: .hollow, word: String(localized: "Getting to know you")),
        week: WeekProvider.sample.week))
}

#Preview("Sesión ya viva", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: .init(routineName: "Tirón", sessionLive: true),
        verdict: nil, week: WeekProvider.sample.week))
}

#Preview("Snapshot rancio", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now.addingTimeInterval(-60 * 60 * 24 * 5),
        today: .init(routineName: "Empuje", sessionLive: false), verdict: nil,
        week: WeekProvider.sample.week))
}

#Preview("Sin snapshot (primera instalación)", as: .systemMedium) {
    WeekWidget()
} timeline: {
    WeekEntry(date: .now, snapshot: nil)
}
