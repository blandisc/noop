import SwiftUI

// MARK: - EntrenarCatalogView — el catálogo de la biblioteca (FER-83 · E2)
//
// Todos los componentes de Entrenar, en todos sus estados, en una sola pantalla. No es una pantalla
// de producto: es la evidencia con la que se revisa la biblioteca sin correr la app, y el lugar
// donde se ve de un jalón si un estado nuevo rompe el ritmo de los demás.
//
// Vive en el paquete (no en la app) para que exista aunque nadie haya cableado todavía una pantalla,
// que es justo el punto de E2: los cimientos van antes que los muros.

public struct EntrenarCatalogView: View {
    @Environment(\.instrumentoTheme) private var theme

    public init() {}

    private let weekLabels = ["L", "M", "X", "J", "V", "S", "D"]

    private var rows: [EntrenarSetRow] {
        [
            .init(id: "w", badge: "C", primary: "40", primaryState: .ghost, reps: "10", repsState: .ghost,
                  isWarmup: true),
            .init(id: "1", badge: "1", primary: "82,5", reps: "8", rpe: "8", done: true),
            .init(id: "2", badge: "2", primary: "82,5", primaryState: .ghost, reps: "8", repsState: .ghost,
                  isCurrent: true),
            .init(id: "3", badge: "3", primary: "82,5", primaryState: .ghost, reps: "8", repsState: .ghost),
        ]
    }

    private var calendarDays: [EntrenarCalendarDay] {
        (0..<63).map { i in
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
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                section("HILO DEL VEREDICTO · 6 VARIANTES") {
                    EntrenarHilo(tone: .clear, word: "In range", advice: "your plan for today, as it is") {}
                    EntrenarHilo(tone: .caution, word: "Go light today", advice: "don't add weight") {}
                    EntrenarHilo(tone: .ease, word: "Recover", advice: "easy today, or rest") {}
                    EntrenarHilo(tone: .hollow, word: "Getting to know you", advice: "no advice yet")
                    EntrenarHilo(tone: .hollow, word: "No reading today", advice: "sync in Today") {}
                    EntrenarHilo(tone: .hollow, word: "Connect Apple Health") {}
                }

                section("NIVELES") {
                    EntrenarNivel("Your week", value: "2 of 3") {}
                    EntrenarNivel("Loaded muscles", value: "estimate")
                    EntrenarNivel("Log")
                }

                section("CHIPS") {
                    HStack(spacing: CenitMetrics.space2) {
                        EntrenarChip(.rest, text: "2:30")
                        EntrenarChip(.progression, text: "2 of 2")
                        EntrenarChip(.warmup, text: "warm-up")
                    }
                }

                section("TABLA DE SERIES · PESO × REPS, CON RPE") {
                    SetTable(kind: .weightReps, rows: rows, showRPE: true,
                             onToggle: { _ in }, onTapCell: { _, _ in }, onDelete: { _ in })
                }

                section("TABLA DE SERIES · LOS OTROS TRES TIPOS") {
                    SetTable(kind: .bodyweight, rows: [
                        .init(id: "1", badge: "1", primary: "0", reps: "12", done: true),
                        .init(id: "2", badge: "2", primary: "5", primaryState: .ghost, reps: "12", repsState: .ghost,
                              isCurrent: true),
                    ], onToggle: { _ in }, onTapCell: { _, _ in })
                    SetTable(kind: .time, rows: [
                        .init(id: "1", badge: "1", primary: "1:00", isCurrent: true),
                    ], onToggle: { _ in }, onTapCell: { _, _ in })
                    SetTable(kind: .distance, rows: [
                        .init(id: "1", badge: "1", primary: "400 m", pairedTime: "1:32", isCurrent: true),
                    ], onToggle: { _ in }, onTapCell: { _, _ in })
                }

                section("BANDA DE DESCANSO") {
                    RestBand(kicker: "REST · SET 1 → 2",
                             mode: .heartRate(remainingBpm: 18, targetBpm: 110, currentBpm: 128),
                             trailing: "1:18",
                             note: "at 5 bpm I say «almost» · at 2:30 I let you go even if it hasn't dropped",
                             onSkip: {})
                    RestBand(kicker: "REST · SET 2 → 3",
                             mode: .heartRate(remainingBpm: 0, targetBpm: 110, currentBpm: 108),
                             trailing: "2:04", isReady: true, onSkip: {})
                    RestBand(kicker: "REST · SET 1 → 2", mode: .clock(elapsed: "1:18", target: "2:30"),
                             trailing: "2:30", onSkip: {})
                }

                section("EJERCICIO Y RECETA") {
                    ExerciseCard(family: .legs, name: "Back squat",
                                 meta: "rest by heart rate · cap 2:30", onMenu: {}, onTap: {})
                    ExerciseCard(family: .push, name: "Bench press", meta: "3 × 8 · 82.5 kg", onMenu: {})
                    RecetaLine("3 sets · 80 kg × 8", detail: "progression on", action: {})
                    RecetaLine("4 sets · 12 reps")
                }

                section("BARRA DE SESIÓN") {
                    SessionStatsBar(volume: "4,880", sets: "12", pulse: "128", onFocus: {})
                    SessionStatsBar(volume: "4,880", sets: "12", onFocus: {})
                    SessionStatsBar(volume: "12,480", sets: "24", pulse: "96", isPaused: true,
                                    onFocus: {})
                }

                section("SEMANA") {
                    WeekTokens(days: [.done(.push), .rest, .done(.pull), .rest, .rest,
                                      .today(isRest: false), .planned(.legs)],
                               labels: weekLabels, action: {})
                    WeekTokens(days: [.done(.push), .rest, .done(.pull), .rest, .rest,
                                      .today(isRest: true), .planned(.legs)],
                               labels: weekLabels)
                }

                section("CALENDARIO") {
                    TrainingCalendar(days: calendarDays, size: .mini,
                                     summary: "27 sessions in the last 9 weeks")
                    TrainingCalendar(days: calendarDays, size: .full,
                                     summary: "27 sessions in the last 9 weeks", action: {})
                }

                section("CARGA POR MÚSCULO") {
                    MuscleLoadRow(name: "Quadriceps", load: 1.0, recency: "today", sets: 12, isFresh: false)
                    MuscleLoadRow(name: "Back", load: 0.45, recency: "3 d ago", sets: 8, isFresh: false)
                    MuscleLoadRow(name: "Chest", load: 0, recency: "fresh", sets: 0, isFresh: true)
                }
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey,
                                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Rectangle().fill(theme.hairline).frame(height: 1)
            content()
        }
    }
}

#if DEBUG
#Preview("Catálogo de Entrenar") {
    EntrenarCatalogView().instrumentoTheme(.base)
}

#Preview("Catálogo · xxxLarge") {
    EntrenarCatalogView()
        .instrumentoTheme(.base)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
