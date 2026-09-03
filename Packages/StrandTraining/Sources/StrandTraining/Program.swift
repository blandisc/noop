import Foundation

// Program.swift — a multi-week training program (ola 1 · E1/E10, FER-324/FER-329).
//
// A program is the weekly split the user already has (`RoutineSchedule`, one routine per weekday) plus
// a week counter and a rule for the last week (the «semana ligera»). The counter is never stored:
// `ProgramCalendar` (E10) derives the current week from `startTs` and the weeks the user actually
// trained, so nothing can drift out of sync. This file is the storage contract only (E1); the
// calendar, the light-week rule and the templates land with E10.

/// How the light week («semana ligera») is served. Owner decision D-Q3 (2026-09-02): the default is
/// volume only; the load option reuses the SAME `ProgressionMath.deloadFraction` (7.5 %) the reactive
/// deload already uses — one family of «bajar», never two.
public enum DeloadRule: String, Codable, Sendable, CaseIterable {
    /// Work sets × 0.5 (min 1), same weight. The closest to the published consensus (Bell 2023).
    case volumeOnly
    /// Work sets × 0.5 (min 1) and weight × (1 − deloadFraction), snapped to buildable plates.
    case volumeAndLoad
    /// No light week: the cycle just restarts.
    case none
}

/// What happens when the light week ends (owner polish, «Al terminar el ciclo»).
public enum ProgramEndMode: String, Codable, Sendable, CaseIterable {
    /// Back to week 1 with the weights earned; the default.
    case `repeat`
    /// The program ends by itself; the plain weekly split stays.
    case single
}

/// The one active program (singleton row, `id == "active"`, table `program`, v43). Routines and the
/// weekly schedule live where they always did; deleting the program leaves them untouched.
public struct Program: Codable, Sendable, Identifiable, Equatable {
    public static let activeId = "active"
    /// Weeks a program created in the app may have (the UI offers 4 · 5 · 6).
    public static let appWeeks: ClosedRange<Int> = 4...6
    /// Weeks a program imported from the user's own AI may have (a coach block is often 6–8).
    public static let importWeeks: ClosedRange<Int> = 4...8

    public var id: String
    public var name: String
    public var weeks: Int
    /// Unix seconds of the day the program started (the Monday of that week is derived, not stored).
    public var startTs: Int
    public var deloadRule: DeloadRule
    public var endMode: ProgramEndMode
    /// The template id the program was materialized from (`ProgramTemplate`, E10); `nil` = converted
    /// from the user's own week or imported.
    public var templateId: String?
    public var createdTs: Int

    public init(id: String = Program.activeId, name: String, weeks: Int, startTs: Int,
                deloadRule: DeloadRule = .volumeOnly, endMode: ProgramEndMode = .repeat,
                templateId: String? = nil, createdTs: Int) {
        self.id = id; self.name = name; self.weeks = weeks; self.startTs = startTs
        self.deloadRule = deloadRule; self.endMode = endMode; self.templateId = templateId
        self.createdTs = createdTs
    }
}

// MARK: - ProgramCalendar — «¿en qué semana voy?» derivado, nunca guardado (ola 1 · E10, FER-329)
//
// EL ÚNICO oráculo de la semana del programa. Ninguna pantalla, ningún store y ninguna migración
// vuelve a contar semanas por su cuenta: todos llaman aquí. Puro y reproducible — `now` y `calendar`
// entran por parámetro (mismo contrato que `TrainingWeeks`), así que un test fija el día sin tocar el
// reloj del sistema.
//
// La regla (D-Q2, decisión del dueño): el contador avanza SOLO con semanas ENTRENADAS (≥ 1 sesión).
// Una semana en blanco —vacaciones, una gripa— no adelanta la semana ligera; el programa espera. Por eso
// no existe columna «semana actual» que pueda desincronizarse: la semana se deriva de `startTs` + los
// lunes en los que de verdad hubo sesión.
public enum ProgramCalendar {

    /// Dónde cae HOY dentro del programa.
    public struct Position: Sendable, Equatable {
        /// Vuelta completa del ciclo, base 0 (0 = la primera pasada, 1 = «ciclo 2»).
        public let cycle: Int
        /// La semana del ciclo, 1…`weeks`.
        public let week: Int
        /// Sírvela ligera. Es la última semana del ciclo, el programa no terminó y su regla no es `.none`.
        public let isLight: Bool
        /// Semanas ENTRENADAS que faltan para la ligera (0 = es esta, o no aplica). Léelo junto a
        /// `isLight`: con `DeloadRule.none` o con el programa terminado no hay ligera a la que contar.
        public let weeksUntilLight: Int
        /// `ProgramEndMode.single` y el ciclo ya se completó: el programa se terminó solo y lo que
        /// queda es el split semanal de siempre (nunca ligero).
        public let ended: Bool

        public init(cycle: Int, week: Int, isLight: Bool, weeksUntilLight: Int, ended: Bool) {
            self.cycle = cycle; self.week = week; self.isLight = isLight
            self.weeksUntilLight = weeksUntilLight; self.ended = ended
        }
    }

    /// El lunes (unix s) de la semana de `ts`, con el mismo criterio lunes-primero que `TrainingWeeks`.
    public static func weekStart(of ts: Int, calendar: Calendar) -> Int {
        let cal = TrainingWeeks.mondayFirst(calendar)
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return Int(start.timeIntervalSince1970)
    }

    /// Los lunes de las semanas con ≥ 1 sesión. El caller pasa los `startTs` de las sesiones YA
    /// guardadas (una sesión sin nada registrado no se guarda), y esto las colapsa a su semana — así el
    /// store no necesita saber de calendarios ni la pantalla de contar sesiones.
    public static func trainedWeekStarts(sessionStartTs: [Int], calendar: Calendar) -> Set<Int> {
        Set(sessionStartTs.map { weekStart(of: $0, calendar: calendar) })
    }

    /// La posición de hoy. `n` = semanas entrenadas ESTRICTAMENTE anteriores a la semana en curso, desde
    /// la semana en la que arrancó el programa; `week = (n mod weeks) + 1`; `cycle = n / weeks`.
    ///
    /// Consecuencias que el modelo quiere y conviene leer explícitas:
    /// - Empezar a mitad de semana deja esa semana como la 1 (nada anterior cuenta).
    /// - Una semana en blanco no avanza nada (D-Q2).
    /// - La semana EN CURSO nunca se cuenta a sí misma, entrenada o no: si contara, la semana subiría a
    ///   media semana, en cuanto se registrara la primera sesión.
    ///
    /// No clampa `weeks` a ningún rango de producto (`Program.appWeeks` / `importWeeks` validan ANTES de
    /// llegar aquí, cada uno con su rango); solo se defiende del 0 para no dividir entre cero.
    public static func position(startTs: Int, trainedWeekStarts: Set<Int>, now: Date, weeks: Int,
                                deloadRule: DeloadRule = .volumeOnly,
                                endMode: ProgramEndMode = .repeat,
                                calendar: Calendar) -> Position {
        let w = max(1, weeks)
        let startWeek = weekStart(of: startTs, calendar: calendar)
        let currentWeek = weekStart(of: Int(now.timeIntervalSince1970), calendar: calendar)
        let n = trainedWeekStarts.filter { $0 >= startWeek && $0 < currentWeek }.count
        let cycle = n / w
        let week = (n % w) + 1
        let ended = endMode == .single && cycle >= 1
        let hasLight = deloadRule != .none && !ended
        return Position(cycle: cycle, week: week,
                        isLight: hasLight && week == w,
                        weeksUntilLight: hasLight ? w - week : 0,
                        ended: ended)
    }

    /// La misma regla leyendo el programa guardado — la forma en que la app la llama (un solo oráculo:
    /// nadie vuelve a desarmar `Program` para contar semanas).
    public static func position(of program: Program, trainedWeekStarts: Set<Int>,
                                now: Date, calendar: Calendar) -> Position {
        position(startTs: program.startTs, trainedWeekStarts: trainedWeekStarts, now: now,
                 weeks: program.weeks, deloadRule: program.deloadRule, endMode: program.endMode,
                 calendar: calendar)
    }
}

// MARK: - ProgramTemplate — los cuatro motores, como DATOS (ola 1 · E10, FER-329 · D-Q4)
//
// Decisión del dueño D-Q4: «cuatro motores = plantillas existentes + semanas», sin biblioteca de
// coaches. Así que un motor NO trae lógica propia: es una tabla de weekday → `StarterTemplate` ya
// empaquetada, más las semanas y la regla de la ligera. Toda la lógica del programa vive en
// `ProgramCalendar` (qué semana) y `ProgramDeload` (qué le pasa a la ligera).
public struct ProgramTemplate: Identifiable, Sendable, Equatable {

    public let id: String
    /// weekday (convención `Calendar`/`RoutineSchedule`: 1 = domingo … 7 = sábado) → id de
    /// `StarterTemplate`. La MISMA plantilla puede repetirse en dos días: `routineSchedule` solo es
    /// única por weekday, así que PPL 6 días apunta dos veces a cada rutina en vez de duplicarla.
    public let weekdays: [Int: String]
    public let weeks: Int
    public let deloadRule: DeloadRule
    public let endMode: ProgramEndMode
    /// `progressionSessions` (el n del ciclo de doble progresión) para los slots de BARRA.
    public let barbellProgressionSessions: Int
    /// `progressionSessions` para todo lo demás (mancuerna, máquina, aislamiento).
    public let otherProgressionSessions: Int
    /// El ritmo «según reps en reserva» (E4). Apagado en los cuatro motores: un programa de fábrica no
    /// enciende un interruptor que el dueño decidió que nace apagado en toda rutina existente (D-Q6).
    public let progressionUseRPE: Bool

    public init(id: String, weekdays: [Int: String], weeks: Int, deloadRule: DeloadRule,
                endMode: ProgramEndMode = .repeat, barbellProgressionSessions: Int,
                otherProgressionSessions: Int, progressionUseRPE: Bool = false) {
        self.id = id; self.weekdays = weekdays; self.weeks = weeks; self.deloadRule = deloadRule
        self.endMode = endMode
        self.barbellProgressionSessions = barbellProgressionSessions
        self.otherProgressionSessions = otherProgressionSessions
        self.progressionUseRPE = progressionUseRPE
    }

    /// Lo que un motor produce al materializarse: las rutinas nuevas, sus ejercicios, el split semanal
    /// y la fila `program`. Nada de esto toca disco — la app lo escribe en UNA transacción.
    public struct Materialized: Sendable, Equatable {
        public let routines: [Routine]
        public let exercises: [RoutineExercise]
        public let schedule: [RoutineSchedule]
        public let program: Program
    }

    /// Materializa el motor reutilizando `StarterTemplate.makeRoutine` — la MISMA copia que hace el
    /// selector de plantillas, así que una rutina de programa es indistinguible de una copiada a mano
    /// (se edita y se borra igual). Pura: los nombres localizados, el reloj y (opcionalmente) los ids
    /// entran por parámetro.
    ///
    /// Una plantilla usada en dos weekdays produce UNA rutina y DOS filas de calendario — nunca dos
    /// copias del mismo plan.
    ///
    /// `names` mapea id de `StarterTemplate` → nombre localizado; una plantilla sin nombre cae a su id
    /// (nunca se inventa copy aquí: los textos viven en el catálogo de strings de la app).
    public func materialize(now: Int, names: [String: String], programName: String,
                            routineIds: [String: String] = [:]) -> Materialized {
        var routines: [Routine] = []
        var exercises: [RoutineExercise] = []
        var schedule: [RoutineSchedule] = []
        var idByTemplate: [String: String] = [:]
        for weekday in weekdays.keys.sorted() {
            guard let templateId = weekdays[weekday] else { continue }
            if idByTemplate[templateId] == nil {
                guard let template = StarterTemplates.byID(templateId) else { continue }
                let routineId = routineIds[templateId] ?? UUID().uuidString
                let (routine, slots) = template.makeRoutine(name: names[templateId] ?? templateId,
                                                            now: now, routineId: routineId)
                routines.append(routine)
                exercises.append(contentsOf: slots.map(withProgression))
                idByTemplate[templateId] = routineId
            }
            guard let routineId = idByTemplate[templateId] else { continue }
            schedule.append(RoutineSchedule(weekday: weekday, routineId: routineId))
        }
        let program = Program(name: programName, weeks: weeks, startTs: now,
                              deloadRule: deloadRule, endMode: endMode, templateId: id, createdTs: now)
        return Materialized(routines: routines, exercises: exercises, schedule: schedule, program: program)
    }

    /// El único punto que decide el n del ciclo por slot: barra vs. lo demás. La barra sube en
    /// escalones grandes y con menos margen técnico, así que un motor lineal puede pedirle una sola
    /// sesión limpia; una mancuerna o un aislamiento piden las dos de siempre.
    private func withProgression(_ re: RoutineExercise) -> RoutineExercise {
        var out = re
        out.progressionSessions = Self.progressesEverySession(re)
            ? barbellProgressionSessions : otherProgressionSessions
        out.progressionUseRPE = progressionUseRPE
        return out
    }

    /// Tope de reps para que un slot de barra progrese sesión a sesión: los básicos de bajas reps
    /// (sentadilla, press, remo a 5–8) son los que un lineal de novato sube cada vez; un curl de barra a
    /// 3×12 es aislamiento aunque lleve barra, y con 20 kg un paso de 2,5 kg cada sesión es +12,5 % —
    /// fuera de la banda 2,5–10 % del NSCA (gate /biomecanico FER-329 #2). Calibration default.
    public static let everySessionMaxReps = 8

    /// ¿Este slot sube con UNA sesión limpia? Barra Y bajas reps; el catálogo no trae `mechanic`, así
    /// que las reps hacen de proxy de «básico» vs. «aislamiento».
    static func progressesEverySession(_ re: RoutineExercise) -> Bool {
        let reps = re.targetReps ?? re.sets.first(where: { $0.kind == .work })?.reps ?? Int.max
        return usesBarbell(exerciseId: re.exerciseId) && reps <= everySessionMaxReps
    }

    /// ¿El slot se carga con barra? Se lee del catálogo empaquetado (`Exercise.equipment`), no de una
    /// lista de ids escrita a mano que se pudriría con el catálogo.
    static func usesBarbell(exerciseId: String) -> Bool {
        guard let equipment = ExerciseCatalog.byID(exerciseId)?.equipment?.lowercased() else { return false }
        return equipment.contains("barbell") || equipment.contains("curl bar")
    }
}

public extension ProgramTemplate {

    /// Los cuatro motores de la ola 1 (D-Q4). Semanas y regla son un punto de partida EDITABLE por
    /// quien entrena, no una prescripción: 5 semanas cae dentro de `Program.appWeeks` y la ligera por
    /// default es la de menos series (D-Q3).
    static let all: [ProgramTemplate] = [
        // Lineal de novato: cuerpo completo L/M/V. La barra sube con UNA sesión limpia (el motor
        // lineal clásico sube cada sesión mientras se cumpla el objetivo); el resto, con dos. Sin
        // semana ligera: un novato progresa semanas seguidas y la descarga REACTIVA (−7,5 % tras 3
        // sesiones estancado) sigue viva dentro del programa y es la que lo cuida.
        ProgramTemplate(id: "linear-novice",
                        weekdays: [2: "full-body", 4: "full-body", 6: "full-body"],
                        weeks: 5, deloadRule: .none,
                        barbellProgressionSessions: 1, otherProgressionSessions: 2),
        // Cuerpo completo 3 días: el mismo calendario con el ciclo de dos sesiones de siempre.
        ProgramTemplate(id: "full-body-3",
                        weekdays: [2: "full-body", 4: "full-body", 6: "full-body"],
                        weeks: 5, deloadRule: .volumeOnly,
                        barbellProgressionSessions: 2, otherProgressionSessions: 2),
        // Push / pull / legs 6 días, L→S. Cada rutina se materializa UNA vez y aparece dos veces en el
        // calendario.
        ProgramTemplate(id: "ppl-6",
                        weekdays: [2: "ppl-push", 3: "ppl-pull", 4: "ppl-legs",
                                   5: "ppl-push", 6: "ppl-pull", 7: "ppl-legs"],
                        weeks: 5, deloadRule: .volumeOnly,
                        barbellProgressionSessions: 2, otherProgressionSessions: 2),
        // Torso / pierna 4 días: torso L/J, pierna M/V.
        ProgramTemplate(id: "upper-lower-4",
                        weekdays: [2: "upper", 3: "lower", 5: "upper", 6: "lower"],
                        weeks: 5, deloadRule: .volumeOnly,
                        barbellProgressionSessions: 2, otherProgressionSessions: 2),
    ]

    /// Un motor por id, o nil.
    static func byID(_ id: String) -> ProgramTemplate? { all.first { $0.id == id } }
}
