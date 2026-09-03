import Foundation

// MARK: - Semanas de entrenamiento (FER-171 · hub v18)
//
// Cuatro motores puros de agregación por semana/mes/ventana para «La Principal v18»: volumen
// semanal en cubetas, su delta %, la rejilla de constancia (13 semanas × slots) y el promedio
// móvil de 7 días. Pure y Foundation-only (mismo criterio que `RoutineClassifier`): cero GRDB,
// cero SwiftUI, `now`/`calendar` siempre entran como parámetro — nunca `Date()`/`Calendar.current`
// implícitos, para que el resultado sea reproducible en `swift test`.
//
// El bucketing semanal replica `WorkoutHistoryScreen.weeklyVolumes` (lunes como primer día:
// `cal.firstWeekday = 2`) — el mismo criterio, ahora en un motor probado que Historial y el hub
// pueden compartir en vez de cada pantalla reimplementando su propia cubeta.

/// Una cubeta de volumen semanal.
public struct WeekVolumeBucket: Sendable, Equatable {
    public let weekStart: Date
    public let volumeKg: Double
    public let sessionCount: Int
    public let isCurrent: Bool

    public init(weekStart: Date, volumeKg: Double, sessionCount: Int, isCurrent: Bool) {
        self.weekStart = weekStart
        self.volumeKg = volumeKg
        self.sessionCount = sessionCount
        self.isCurrent = isCurrent
    }
}

public enum TrainingWeeks {

    /// Fuerza `firstWeekday = 2` (lunes) sobre una copia del calendario del caller — el mismo
    /// criterio que `WorkoutHistoryScreen.weeklyVolumes`, pero como contrato del motor (no algo
    /// que cada caller deba recordar configurar).
    ///
    /// Ola 1 · E10 (FER-329): pasa de `private` a `internal` porque `ProgramCalendar` cuenta semanas
    /// con EXACTAMENTE el mismo criterio de lunes. Un solo oráculo del «¿dónde empieza la semana?»:
    /// si mañana el dueño quisiera domingo, cambia aquí y cambia en los dos motores a la vez.
    static func mondayFirst(_ calendar: Calendar) -> Calendar {
        var cal = calendar
        cal.firstWeekday = 2
        return cal
    }

    /// Tonelaje semanal en `weeks` cubetas (la más vieja primero, la última = semana actual).
    /// Una sesión sin `endTs`/completar no llega aquí — eso lo filtra el caller, igual que
    /// `WorkoutHistoryScreen.weeklyVolumes` filtra `s.endTs != nil` antes de sumar.
    ///
    /// Siempre devuelve exactamente `weeks` cubetas (huecos sin sesión quedan en 0/0), para que
    /// el caller pueda dibujar una rejilla de ancho fijo sin lógica de padding propia.
    public static func volumeBuckets(sessions: [(ts: Double, volumeKg: Double)],
                                     weeks: Int, now: Date, calendar: Calendar) -> [WeekVolumeBucket] {
        guard weeks > 0 else { return [] }
        let cal = mondayFirst(calendar)
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        var kg = [Double](repeating: 0, count: weeks)
        var counts = [Int](repeating: 0, count: weeks)
        for s in sessions {
            let date = Date(timeIntervalSince1970: s.ts)
            guard let ws = cal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            let weeksAgo = cal.dateComponents([.weekOfYear], from: ws, to: thisWeekStart).weekOfYear ?? 0
            guard weeksAgo >= 0, weeksAgo < weeks else { continue }
            let idx = weeks - 1 - weeksAgo
            kg[idx] += s.volumeKg
            counts[idx] += 1
        }
        return (0..<weeks).map { i in
            let start = cal.date(byAdding: .weekOfYear, value: i - (weeks - 1), to: thisWeekStart) ?? thisWeekStart
            return WeekVolumeBucket(weekStart: start, volumeKg: kg[i], sessionCount: counts[i],
                                    isCurrent: i == weeks - 1)
        }
    }

    /// Delta % del volumen: la última semana COMPLETA (todas las cubetas salvo la actual, que
    /// sigue corriendo) contra el promedio de las 3 completas anteriores a esa. `nil` si no hay
    /// al menos 4 semanas completas (regla de silencio «delta volumen 4+ semanas») o si esas 3
    /// semanas previas suman 0 (división por cero — un caso degenerado, no una alza infinita).
    /// Redondea al entero más cercano; aritmética documentada, sin más decimales que eso.
    public static func volumeDeltaPercent(buckets: [WeekVolumeBucket]) -> Int? {
        let complete = buckets.filter { !$0.isCurrent }
        guard complete.count >= 4 else { return nil }
        let last = complete[complete.count - 1].volumeKg
        let previous3 = complete[(complete.count - 4)..<(complete.count - 1)]
        let avg = previous3.reduce(0) { $0 + $1.volumeKg } / 3
        guard avg > 0 else { return nil }
        return Int(((last - avg) / avg * 100).rounded())
    }

    /// Una columna de la rejilla de constancia: hasta `slotsPerWeek` sesiones de esa semana,
    /// cada una con su familia (`nil` = sesión sin clasificar, se pinta neutra).
    public struct ConsistencyWeek: Sendable, Equatable {
        public let weekStart: Date
        public let sessions: [RoutineRegion?]
        public let isCurrent: Bool

        public init(weekStart: Date, sessions: [RoutineRegion?], isCurrent: Bool) {
            self.weekStart = weekStart
            self.sessions = sessions
            self.isCurrent = isCurrent
        }
    }

    /// 13 columnas = 13 semanas (izq la más vieja, der la semana actual); cada columna recorta a
    /// `slotsPerWeek` sesiones, tomando las cronológicamente PRIMERAS de esa semana (orden
    /// determinista: `sorted` por `ts`, no el orden de llegada de `sessions`).
    public static func consistency(sessions: [(ts: Double, family: RoutineRegion?)],
                                   weeks: Int, slotsPerWeek: Int,
                                   now: Date, calendar: Calendar) -> [ConsistencyWeek] {
        guard weeks > 0 else { return [] }
        let cal = mondayFirst(calendar)
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        var buckets = [[(ts: Double, family: RoutineRegion?)]](repeating: [], count: weeks)
        for s in sessions {
            let date = Date(timeIntervalSince1970: s.ts)
            guard let ws = cal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            let weeksAgo = cal.dateComponents([.weekOfYear], from: ws, to: thisWeekStart).weekOfYear ?? 0
            guard weeksAgo >= 0, weeksAgo < weeks else { continue }
            buckets[weeks - 1 - weeksAgo].append(s)
        }
        return (0..<weeks).map { i in
            let start = cal.date(byAdding: .weekOfYear, value: i - (weeks - 1), to: thisWeekStart) ?? thisWeekStart
            let ordered = buckets[i].sorted { $0.ts < $1.ts }.prefix(max(0, slotsPerWeek)).map(\.family)
            return ConsistencyWeek(weekStart: start, sessions: Array(ordered), isCurrent: i == weeks - 1)
        }
    }

    /// Conteo honesto de sesiones del mes calendario actual (mismo criterio que
    /// `WorkoutHistoryScreen.aggregate(forMonthOf:)`: `isDate(_:equalTo:toGranularity:.month)`).
    public static func sessionsThisMonth(sessionTs: [Double], now: Date, calendar: Calendar) -> Int {
        sessionTs.reduce(0) { count, ts in
            let date = Date(timeIntervalSince1970: ts)
            return calendar.isDate(date, equalTo: now, toGranularity: .month) ? count + 1 : count
        }
    }

    /// El promedio 7 días (min / kcal / toneladas).
    public struct SevenDayAverage: Sendable, Equatable {
        public let minutes: Int
        public let kcal: Int?
        public let tons: Double

        public init(minutes: Int, kcal: Int?, tons: Double) {
            self.minutes = minutes
            self.kcal = kcal
            self.tons = tons
        }
    }

    /// Promedio de las sesiones en la ventana móvil de los últimos 7 días (no semana calendario:
    /// `[now - 7d, now]`). `nil` si hay menos de 3 sesiones en la ventana (regla de silencio
    /// «promedio <3»). `kcal` es `nil` cuando NINGUNA sesión de la ventana trae energía; si al
    /// menos una la trae, el promedio se calcula solo sobre esas (las que no traen no cuentan
    /// como 0 — eso subestimaría el promedio real). `tons` es tonelaje promedio por sesión
    /// (kg / 1000), sin redondear — el redondeo de presentación es del caller.
    public static func sevenDayAverage(sessions: [(ts: Double, durationS: Double, volumeKg: Double, kcal: Double?)],
                                       now: Date) -> SevenDayAverage? {
        let windowStart = now.timeIntervalSince1970 - 7 * 86_400
        let nowTs = now.timeIntervalSince1970
        let inWindow = sessions.filter { $0.ts >= windowStart && $0.ts <= nowTs }
        guard inWindow.count >= 3 else { return nil }
        let n = Double(inWindow.count)
        let avgMinutes = inWindow.reduce(0.0) { $0 + $1.durationS } / n / 60
        let withKcal = inWindow.compactMap(\.kcal)
        let avgKcal = withKcal.isEmpty ? nil : Int((withKcal.reduce(0, +) / Double(withKcal.count)).rounded())
        let avgTons = inWindow.reduce(0.0) { $0 + $1.volumeKg } / n / 1000
        return SevenDayAverage(minutes: Int(avgMinutes.rounded()), kcal: avgKcal, tons: avgTons)
    }
}
