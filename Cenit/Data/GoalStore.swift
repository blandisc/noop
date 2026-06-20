import Foundation
import Combine

/// The Bucle's goal — a single user preference (which metric to improve + an optional date),
/// UserDefaults-backed (single-user, on-device), mirroring `BehaviorStore`. Not analytics history, so
/// no database table (FER-311). If a widget ever needs it, graduate the keys to an App Group suite.
@MainActor
final class GoalStore: ObservableObject {

    /// The chosen metric, or nil when no goal is set.
    @Published var metric: GoalMetric? {
        didSet {
            if let m = metric { d.set(m.rawValue, forKey: K.metric) }
            else { d.removeObject(forKey: K.metric) }
        }
    }

    /// An optional target date (covers event goals); nil = open-ended.
    @Published var targetDate: Date? {
        didSet {
            if let t = targetDate { d.set(t, forKey: K.date) }
            else { d.removeObject(forKey: K.date) }
        }
    }

    private let d = UserDefaults.standard
    private enum K {
        static let metric = "goal.metric"
        static let date = "goal.targetDate"
    }

    init() {
        if let raw = d.string(forKey: K.metric) { metric = GoalMetric(rawValue: raw) }
        targetDate = d.object(forKey: K.date) as? Date
    }

    var isSet: Bool { metric != nil }

    /// Set the goal (metric + optional date) in one step.
    func set(metric: GoalMetric, targetDate: Date?) {
        self.metric = metric
        self.targetDate = targetDate
    }

    /// Clear the goal entirely (back to "Ponte una meta").
    func clear() {
        metric = nil
        targetDate = nil
    }
}
