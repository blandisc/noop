import Foundation
import StrandAnalytics

// JetLagPlanStore.swift — persistence + progress for the «Reajuste» (jet-lag) plan of «Tu reloj
// corporal» (FER-713 F2). We store only the plan's INPUTS (the shift + the starting sleep window + the
// start day); the full day-by-day plan is recomputed on the fly from `CircadianEngine.planShift`, so
// there is no derived state to keep in sync and no migration — a single current-plan object lives in
// UserDefaults (like the experimental toggles), not a per-day table.

/// The active plan's inputs. `startEpoch` = unix seconds at the local start of day 1.
struct ActiveJetLagPlan: Codable, Equatable {
    var shiftHours: Double        // signed: + advance (eastward), − delay (westward)
    var currentSleepHour: Double  // clock hours at plan start
    var currentWakeHour: Double
    var startEpoch: Int
}

enum JetLagPlanStore {
    /// UserDefaults key; shared by `RelojCorporalSheet` and `PlanViajeSheet` via `@AppStorage`.
    static let key = "noop.jetLagPlan"

    static func decode(_ json: String) -> ActiveJetLagPlan? {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ActiveJetLagPlan.self, from: data)
    }

    static func encode(_ plan: ActiveJetLagPlan) -> String {
        guard let data = try? JSONEncoder().encode(plan) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// The recomputed plan plus the 1-based day index for `now`. `dayIndex > jetLag.estimatedDays`
    /// means the plan is finished. Counts elapsed local calendar days from the start day.
    static func progress(_ plan: ActiveJetLagPlan, now: Date = Date(), calendar: Calendar = .current)
        -> (jetLag: CircadianEngine.JetLagPlan, dayIndex: Int) {
        let jetLag = CircadianEngine.planShift(shiftHours: plan.shiftHours,
                                               currentSleepHour: plan.currentSleepHour,
                                               currentWakeHour: plan.currentWakeHour)
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(plan.startEpoch)))
        let elapsed = calendar.dateComponents([.day], from: start,
                                              to: calendar.startOfDay(for: now)).day ?? 0
        return (jetLag, max(1, elapsed + 1))
    }

    /// A clock hour (0..<24) as a locale short time (e.g. "9:00 p.m."). Shared by the plan surfaces.
    static func clock(_ hour: Double) -> String {
        let wrapped = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        var comps = DateComponents()
        comps.hour = Int(wrapped)
        comps.minute = Int((wrapped - Double(Int(wrapped))) * 60)
        let date = Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 0)
        let f = DateFormatter(); f.dateStyle = .none; f.timeStyle = .short
        return f.string(from: date)
    }
}
