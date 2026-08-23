import Foundation
import WidgetKit
import StrandAnalytics
import StrandTraining

/// FER-95 · E14 — builds `TrainWidgetSnapshot` and writes it to the App Group, so
/// `TrainTodayWidget`/`WeekWidget` always show what the app already computed. `AppModel` fetches the
/// split/routines/sessions once per dashboard publish and hands them here — this type never touches the
/// store itself, so its one impure entry point (`publish`) is still cheap to call often.
///
/// The verdict crossing into the snapshot is the SAME `LiquidHoyBuilder.hiloEntrenar` call Entrenar's
/// own hilo makes (FER-82's «un solo oráculo») — never a re-derivation from `Preparedness` on its own.
enum TrainWidgetPublisher {

    /// Monday-first display order, the same convention `EntrenarView` uses.
    static let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

    // MARK: - Pure

    /// The 7-day week strip, from the same `WeeklySplit.weekStates` StrandAnalytics already exposes.
    static func week(split: [Int: String], completedWeekdays: Set<Int>, todayWeekday: Int,
                     orderedWeekdays: [Int] = orderedWeekdays,
                     labels: [String]) -> [TrainWidgetSnapshot.WeekDay] {
        WeeklySplit.weekStates(split: split, completedWeekdays: completedWeekdays,
                              todayWeekday: todayWeekday, orderedWeekdays: orderedWeekdays)
            .enumerated().map { i, status in
                TrainWidgetSnapshot.WeekDay(weekday: status.weekday, state: .init(status.state),
                                            label: i < labels.count ? labels[i] : "")
            }
    }

    /// The whole snapshot, from already-resolved primitives — no store/HealthKit access here, so this
    /// is the part `TrainWidgetPublisherTests` exercises directly.
    static func snapshot(todayRoutineName: String?, sessionLive: Bool,
                         verdict: TrainWidgetSnapshot.Verdict?,
                         week: [TrainWidgetSnapshot.WeekDay], now: Date) -> TrainWidgetSnapshot {
        let today = todayRoutineName.map { TrainWidgetSnapshot.TodayPlan(routineName: $0, sessionLive: sessionLive) }
        return TrainWidgetSnapshot(writtenAt: now, today: today, verdict: verdict, week: week)
    }

    /// The weekdays (Calendar convention) THIS week that already have a completed session — the same
    /// `TrainingStreak.completedDayStarts` bucketing Entrenar's own streak reads, so the widget's
    /// «trained» dots can never disagree with the app's.
    static func thisWeekCompletedWeekdays(sessions: [StrengthSession], now: Date,
                                          calendar: Calendar = .current) -> Set<Int> {
        // La tira se DIBUJA lunes→domingo; la semana se CUENTA igual, gane o no el locale
        // (es_MX/en_US empiezan en domingo: la sesión del domingo pasado caía en la «D» del final,
        // que se lee como el domingo próximo — FER-128 r14).
        guard let weekStart = Self.semanaLunes(calendar).dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let done = TrainingStreak.completedDayStarts(sessions, calendar: calendar)
        var out: Set<Int> = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            if done.contains(day) { out.insert(calendar.component(.weekday, from: day)) }
        }
        return out
    }

    /// El mismo calendario con la semana empezando en LUNES, como la tira (`orderedWeekdays` = 2…7,1)
    /// y el Calendario 90 del Detalle de Sueño (`firstWeekday = 2`).
    static func semanaLunes(_ calendar: Calendar) -> Calendar {
        var c = calendar; c.firstWeekday = 2; return c
    }

    /// The day's initial, localized — same call `EntrenarView.weekdayLetter` already makes.
    static func weekdayLetter(_ weekday: Int, calendar: Calendar = .current) -> String {
        guard (1...7).contains(weekday) else { return "" }
        return calendar.veryShortWeekdaySymbols[(weekday - 1) % 7].uppercased()
    }

    // MARK: - Effect

    /// Builds the snapshot from already-fetched inputs, writes the App Group, and reloads both widgets
    /// once. No store access — the caller (`AppModel`) fetches split/routines/sessions once and can
    /// reuse them for `TrainingDayReminder.reschedule` too, so one dashboard publish costs one store trip.
    static func publish(split: [Int: String], routineNames: [String: String], sessions: [StrengthSession],
                        sessionLive: Bool, prep: Preparedness.Read?, fullyLoaded: Bool, healthConnected: Bool,
                        now: Date = Date(), calendar: Calendar = .current) {
        let todayWeekday = calendar.component(.weekday, from: now)
        let labels = orderedWeekdays.map { weekdayLetter($0, calendar: calendar) }
        let completed = thisWeekCompletedWeekdays(sessions: sessions, now: now, calendar: calendar)
        let weekDays = week(split: split, completedWeekdays: completed, todayWeekday: todayWeekday, labels: labels)

        let todayRoutineId = WeeklySplit.todayRoutineId(split: split, todayWeekday: todayWeekday)
        let todayRoutineName = todayRoutineId.flatMap { routineNames[$0] }

        let hilo = LiquidHoyBuilder.hiloEntrenar(prep: prep, nights: prep?.autonomicNights ?? 0,
                                                 healthConnected: healthConnected,
                                                 verdictPending: prep == nil && !fullyLoaded,
                                                 hasPlan: todayRoutineId != nil)
        let verdict = hilo.map { TrainWidgetSnapshot.Verdict(tone: .init($0.tono), word: $0.palabra) }

        let snap = snapshot(todayRoutineName: todayRoutineName, sessionLive: sessionLive,
                            verdict: verdict, week: weekDays, now: now)
        TrainWidgetSnapshot.write(snap)
        WidgetCenter.shared.reloadTimelines(ofKind: TrainWidgetSnapshot.trainTodayKind)
        WidgetCenter.shared.reloadTimelines(ofKind: TrainWidgetSnapshot.weekKind)
    }
}

// MARK: - Mapeos
//
// Internal (not `private`): `TrainWidgetPublisherTests` (`@testable import Cenit`) fixes these two
// mappings directly, so a future new `WeeklySplit.DayState`/`HiloEntrenar.Tono` case that falls through
// a default branch fails loud instead of silently mis-mapping.

extension TrainWidgetSnapshot.WeekDayState {
    init(_ state: WeeklySplit.DayState) {
        switch state {
        case .done:     self = .done
        case .today:    self = .today
        case .upcoming: self = .upcoming
        case .rest:     self = .rest
        }
    }
}

extension TrainWidgetSnapshot.VerdictTone {
    init(_ tono: LiquidHoyBuilder.HiloEntrenar.Tono) {
        switch tono {
        case .claro:    self = .clear
        case .atencion: self = .caution
        case .alerta:   self = .ease
        case .hueco:    self = .hollow
        }
    }
}
