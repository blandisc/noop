// FER-95 · E14 — «Hoy: {rutina} · Empezar», the small home-screen widget.
//
// Reads `TrainWidgetSnapshot` from the App Group — nothing here computes a verdict or a routine
// assignment; both are already resolved by `AppModel`. «Instrumento diurno» on a system surface, same
// discipline as `RestLiveActivity`: warm paper, color only in the verdict word, no custom Grotesk face
// (it isn't registered in the widget extension — FER-817), fixed sizes from `HomeWidgetMetrics` rather
// than a Dynamic-Type promise WidgetKit can't keep.

import SwiftUI
import WidgetKit
import CenitDesign

/// `TrainWidgetSnapshot.VerdictTone` → `EntrenarHilo.Tone`, so the widget can call the REAL
/// `.word(theme)` — the same reading-tone Entrenar's own hilo shows — instead of re-deriving a color.
extension TrainWidgetSnapshot.VerdictTone {
    var strandTone: EntrenarHilo.Tone {
        switch self {
        case .clear:   return .clear
        case .caution: return .caution
        case .ease:    return .ease
        case .hollow:  return .hollow
        }
    }
}

struct TrainTodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TrainWidgetSnapshot?
}

struct TrainTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrainTodayEntry {
        TrainTodayEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrainTodayEntry) -> Void) {
        completion(TrainTodayEntry(date: Date(),
                                   snapshot: context.isPreview ? Self.sample : TrainWidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrainTodayEntry>) -> Void) {
        let entry = TrainTodayEntry(date: Date(), snapshot: TrainWidgetSnapshot.read())
        // The app reloads the timeline explicitly on every dashboard publish (`WidgetCenter.
        // reloadTimelines(ofKind:)`); this is only the fallback so a snapshot eventually reads as
        // stale even if the app never reopens to push a fresher one.
        let nextRefresh = Date().addingTimeInterval(4 * 60 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    static let sample = TrainWidgetSnapshot(
        writtenAt: Date(),
        today: .init(routineName: "Empuje", sessionLive: false),
        verdict: .init(tone: .clear, word: String(localized: "In range")),
        week: [])
}

struct TrainTodayWidgetView: View {
    let entry: TrainTodayEntry
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
                OpenAppBody(theme: theme)
            } else if let today = snapshot.today {
                RoutineBody(today: today, verdict: snapshot.verdict, theme: theme)
            } else {
                RestBody(verdict: snapshot.verdict, theme: theme)
            }
        } else {
            // Primera instalación: sin snapshot, nunca datos inventados. `redacted` es la única
            // decoración — el mismo layout que `RoutineBody` pintaría, opaco.
            RoutineBody(today: .init(routineName: "Empuje", sessionLive: false), verdict: nil, theme: theme)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        }
    }
}

/// Rutina asignada hoy: nombre + veredicto (si lo hay) + «Empezar»/«Continuar». Todo el bloque es el
/// botón — un solo toque abre Cénit directo en la sesión guiada (FER-95).
private struct RoutineBody: View {
    let today: TrainWidgetSnapshot.TodayPlan
    let verdict: TrainWidgetSnapshot.Verdict?
    let theme: InstrumentoTheme
    private typealias M = HomeWidgetMetrics

    var body: some View {
        Button(intent: StartTodayRoutineIntent()) {
            VStack(alignment: .leading, spacing: M.rowGap) {
                Text("Today")
                    .font(.system(size: M.overline, weight: .semibold))
                    .tracking(M.overlineTracking)
                    .foregroundStyle(theme.inkTertiary)
                Text(verbatim: today.routineName)
                    .font(.system(size: M.title, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let verdict {
                    Text(verbatim: verdict.word)
                        .font(.system(size: M.verdict, weight: .medium))
                        .foregroundStyle(verdict.tone.strandTone.word(theme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(today.sessionLive ? "Continue" : "Start")
                    .font(.system(size: M.cta, weight: .semibold))
                    .foregroundStyle(theme.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(Text("Opens today's guided session"))
        .accessibilityAddTraits(.isButton)
    }

    private var a11yLabel: Text {
        (today.sessionLive ? Text("Continue") : Text("Start routine"))
            + Text(verbatim: ", ") + Text(verbatim: today.routineName)
    }
}

/// Día de descanso: sin rutina asignada hoy, sin CTA de arrancar sesión (spec FER-95).
private struct RestBody: View {
    let verdict: TrainWidgetSnapshot.Verdict?
    let theme: InstrumentoTheme
    private typealias M = HomeWidgetMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: M.rowGap) {
            Text("Today")
                .font(.system(size: M.overline, weight: .semibold))
                .tracking(M.overlineTracking)
                .foregroundStyle(theme.inkTertiary)
            Text("Rest day")
                .font(.system(size: M.title, weight: .bold, design: .rounded))
                .foregroundStyle(theme.ink)
            if let verdict {
                Text(verbatim: verdict.word)
                    .font(.system(size: M.verdict, weight: .medium))
                    .foregroundStyle(verdict.tone.strandTone.word(theme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rest day"))
    }
}

/// Snapshot rancio: la app no ha publicado en el horizonte declarado. Nunca una rutina vieja
/// disfrazada de vigente — solo la invitación honesta a abrir la app (FER-95).
private struct OpenAppBody: View {
    let theme: InstrumentoTheme
    private typealias M = HomeWidgetMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: M.rowGap) {
            Text("Today")
                .font(.system(size: M.overline, weight: .semibold))
                .tracking(M.overlineTracking)
                .foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 0)
            Text("Open Cénit")
                .font(.system(size: M.title, weight: .bold, design: .rounded))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open Cénit"))
    }
}

struct TrainTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TrainWidgetSnapshot.trainTodayKind, provider: TrainTodayProvider()) { entry in
            TrainTodayWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Today's routine"))
        .description(Text("Today's routine, and start it in one tap."))
        .supportedFamilies([.systemSmall])
    }
}

#Preview("Con rutina", as: .systemSmall) {
    TrainTodayWidget()
} timeline: {
    TrainTodayEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: .init(routineName: "Empuje", sessionLive: false),
        verdict: .init(tone: .clear, word: String(localized: "In range")), week: []))
}

#Preview("Día de descanso", as: .systemSmall) {
    TrainTodayWidget()
} timeline: {
    TrainTodayEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: nil,
        verdict: .init(tone: .caution, word: String(localized: "Go light today")), week: []))
}

#Preview("Sesión ya viva", as: .systemSmall) {
    TrainTodayWidget()
} timeline: {
    TrainTodayEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now, today: .init(routineName: "Tirón", sessionLive: true),
        verdict: nil, week: []))
}

#Preview("Snapshot rancio", as: .systemSmall) {
    TrainTodayWidget()
} timeline: {
    TrainTodayEntry(date: .now, snapshot: TrainWidgetSnapshot(
        writtenAt: .now.addingTimeInterval(-60 * 60 * 24 * 5),
        today: .init(routineName: "Empuje", sessionLive: false), verdict: nil, week: []))
}

#Preview("Sin snapshot (primera instalación)", as: .systemSmall) {
    TrainTodayWidget()
} timeline: {
    TrainTodayEntry(date: .now, snapshot: nil)
}
