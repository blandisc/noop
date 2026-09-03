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
