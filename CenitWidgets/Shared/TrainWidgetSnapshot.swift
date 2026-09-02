// FER-95 · E14 — the read-only picture of «Entrenar» the two home-screen widgets read.
//
// Shared source: compiled into BOTH the app and the widget extension, same discipline as
// `RestActivityBridge`. `AppModel` builds and writes a fresh snapshot after every dashboard publish;
// `TrainTodayWidget` and `WeekWidget` only ever READ it. The widgets never compute a verdict or a
// routine assignment themselves — `today`/`verdict`/`week` below are already resolved by the app (the
// verdict specifically comes from `LiquidHoyBuilder.hiloEntrenar`, the SAME builder Entrenar's own
// hilo calls — FER-82's «un solo oráculo» — so a widget can never contradict the app it mirrors).
import Foundation

public struct TrainWidgetSnapshot: Codable, Equatable, Sendable {

    /// The `Widget.kind` for each widget, declared ONCE here rather than as a literal repeated in the
    /// widget's own `StaticConfiguration(kind:)` AND in the app's `reloadTimelines(ofKind:)` call —
    /// the same lesson `AppGroup.suiteName` already documents for the App-Group name: two independent
    /// literals drift, and an unentitled/mismatched one fails silently.
    public static let trainTodayKind = "TrainTodayWidget"
    public static let weekKind = "WeekWidget"

    /// How long a written snapshot stays trusted. Past this, the widgets show «Abre Cénit» rather than
    /// a routine name that may no longer be true — the app hasn't run in a while, and nothing else is
    /// watching to correct the display. Three days: shorter than `TrainingDayReminder.horizonteDias`
    /// (a week), on purpose — a STALE display is the worse failure of the two. A missed reminder is a
    /// silent nothing; a stale widget sits on the home screen actively lying every time it's glanced at.
    public static let staleAfter: TimeInterval = 60 * 60 * 24 * 3

    public let writtenAt: Date
    /// Today's plan, resolved. `nil` = rest day (no routine assigned for today) — never a stale name.
    public let today: TodayPlan?
    /// The verdict's tone + word, already resolved. `nil` = nothing to say yet (verdict still pending,
    /// or genuinely no usable read) — the widget then shows no verdict line, never a guess.
    public let verdict: Verdict?
    /// The 7 days of the week, Monday-first (`orderedWeekdays` convention the app already uses).
    public let week: [WeekDay]

    public init(writtenAt: Date, today: TodayPlan?, verdict: Verdict?, week: [WeekDay]) {
        self.writtenAt = writtenAt
        self.today = today
        self.verdict = verdict
        self.week = week
    }

    /// Whether this snapshot is too old to trust — see `staleAfter`.
    public func isStale(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(writtenAt) > Self.staleAfter
    }

    public struct TodayPlan: Codable, Equatable, Sendable {
        public let routineName: String
        /// A strength session for today is already live — the CTA reads «Continuar», not «Empezar».
        public let sessionLive: Bool
        public init(routineName: String, sessionLive: Bool) {
            self.routineName = routineName
            self.sessionLive = sessionLive
        }
    }

    /// Mirrors `EntrenarHilo.Tone` (CenitDesign) case-for-case, but stays ITS OWN plain Codable enum
    /// rather than reusing `Tone` directly — the same reason `RestActivityBridge.Action` doesn't reuse
    /// a session-domain type: this file compiles into both the app and the extension, and a raw-string
    /// enum is the simplest thing that survives `JSONEncoder`/`JSONDecoder` across the process boundary.
    /// `CenitWidgets/HomeWidgets` maps it to Liquid reading colors (`positivo` / `atencionTexto` /
    /// `negativo` / `tinta700`) so the widget never re-derives the verdict.
    public enum VerdictTone: String, Codable, Equatable, Sendable {
        case clear, caution, ease, hollow
    }

    public struct Verdict: Codable, Equatable, Sendable {
        public let tone: VerdictTone
        /// Already localized, already resolved — the exact word `EntrenarHilo` shows in the landing.
        public let word: String
        public init(tone: VerdictTone, word: String) {
            self.tone = tone
            self.word = word
        }
    }

    /// Mirrors `WeeklySplit.DayState` (StrandAnalytics), without the family tint: E14's widgets don't
    /// show routine-by-family color (out of scope — decisión #13 del épico, ya resuelta en otra rama).
    public enum WeekDayState: String, Codable, Equatable, Sendable {
        case done, today, upcoming, rest
    }

    public struct WeekDay: Codable, Equatable, Sendable {
        public let weekday: Int   // Calendar convention: 1 = Sunday … 7 = Saturday
        public let state: WeekDayState
        /// The day's initial, already localized (`Calendar.current.veryShortWeekdaySymbols`) — the
        /// widget draws it verbatim, same as `WeekTokens` does with the labels the app hands it.
        public let label: String
        public init(weekday: Int, state: WeekDayState, label: String) {
            self.weekday = weekday
            self.state = state
            self.label = label
        }
    }

    // MARK: - App Group I/O

    private static let key = "train.widget.snapshot"
    private static var defaults: UserDefaults { AppGroup.sharedDefaults() }

    /// Called by the app after building a fresh snapshot.
    public static func write(_ snapshot: TrainWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// Called by both `TimelineProvider`s. `nil` = nothing written yet (first install) — the widget
    /// then shows WidgetKit's own `redacted(.placeholder)`, never invented data.
    public static func read() -> TrainWidgetSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TrainWidgetSnapshot.self, from: data)
    }
}
