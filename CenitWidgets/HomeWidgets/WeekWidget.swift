// FER-95 · E14 — the week's plan, the medium home-screen widget.
//
// Redraws the 7-day strip with the SAME pure semantics `WeeklySplit`/`WeekTokens` already define
// (done/today/upcoming/rest — via `TrainWidgetSnapshot.WeekDayState`, already resolved by the app), but
// as its own WidgetKit view: `WeekTokens` (CenitDesign) is a SwiftUI `View` built for the app's live
// theme environment, not something a widget extension can reuse verbatim. No family tint here (out of
// scope — decisión #13 del épico, resuelta en otra rama): a filled token means «trained», not «which
// routine». Liquid Glass · El Eje (DECISIONS 2026-09-03): `LiquidColor.fondoAlto` + tinta Liquid.

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
    private typealias M = HomeWidgetMetrics

    var body: some View {
        content
            .padding(M.padding)
            .containerBackground(LiquidColor.fondoAlto, for: .widget)
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
            WeekStrip(days: snapshot.week)
        }
    }

    private var staleHeader: some View {
        VStack(alignment: .leading, spacing: M.rowGap) {
            Text("This week")
                .font(LiquidType.unidad.weight(.semibold))
                .tracking(M.overlineTracking)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: 0)
            Text("Open Cénit")
                .font(.system(size: M.title, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidColor.tinta900)
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
                    .font(LiquidType.unidad.weight(.semibold))
                    .tracking(M.overlineTracking)
                    .foregroundStyle(LiquidColor.tinta500)
                title
                    .font(.system(size: M.title, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: LiquidSpace.s200)
            VStack(alignment: .trailing, spacing: M.microGap) {
                if let verdict {
                    Text(verbatim: verdict.word)
                        .font(LiquidType.cuerpoBanner.weight(.medium))
                        .foregroundStyle(verdict.tone.liquidWord)
                        .lineLimit(1)
                }
                if let cta {
                    Text(cta)
                        .font(LiquidType.cuerpoBanner.weight(.semibold))
                        .foregroundStyle(LiquidColor.tinta900)
                }
            }
        }
    }
}

/// The 7-day strip: one SQUARE tesela per day, label INSIDE — the same tesela grammar
/// `EntrenarHubSemana.tesela(_:label:action:)` draws in the app (no more circle-with-label-below).
/// Geometry/font tokens copied 1:1 from `EntrenarHubMetrics` (the app's own tesela tokens); box size
/// stays `HomeWidgetMetrics.dayToken` (20pt, unchanged) — the widget's box, not the app's 26pt, per the
/// "don't enlarge the widget" constraint. No family tint here still applies (out of scope — decisión
/// #13 del épico, ya documentada arriba): `.done` stays a flat `tinta900` fill and `.upcoming` a flat
/// `tinta500` dashed outline rather than the app's per-family tint — `TrainWidgetSnapshot.WeekDay`
/// carries no family, so these two are the closest equivalent, not an exact one.
private struct WeekStrip: View {
    let days: [TrainWidgetSnapshot.WeekDay]
    private typealias M = HomeWidgetMetrics
    private typealias T = EntrenarHubMetrics

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                tesela(day.state, label: day.label)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(a11yLabel(day))
            }
        }
    }

    /// Same case grammar as the app: `.done` fills, everyone else outlines the shape; `.today` is a
    /// SOLID ring, `.upcoming`/`.rest` are DASHED — only color/opacity tells those two apart, exactly
    /// like `EntrenarDayToken.planned`/`.rest` do.
    @ViewBuilder private func tesela(_ state: TrainWidgetSnapshot.WeekDayState, label: String) -> some View {
        let side = M.dayToken
        let shape = RoundedRectangle(cornerRadius: T.teselaRadius, style: .continuous)
        ZStack {
            switch state {
            case .done:
                shape.fill(LiquidColor.tinta900)
            case .today:
                shape.strokeBorder(LiquidColor.tinta900, lineWidth: T.teselaHoyLineWidth)
            case .upcoming:
                shape.strokeBorder(LiquidColor.tinta500,
                                    style: StrokeStyle(lineWidth: T.teselaOffLineWidth, dash: [2, 2]))
            case .rest:
                shape.strokeBorder(LiquidColor.tinta900.opacity(T.teselaOffAlfa),
                                    style: StrokeStyle(lineWidth: T.teselaOffLineWidth, dash: [2, 2]))
            }
            Text(verbatim: label)
                .font(T.teselaLabel)
                .foregroundStyle(state == .done ? LiquidColor.papelTarjeta : LiquidColor.tinta500)
        }
        .frame(width: side, height: side)
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
