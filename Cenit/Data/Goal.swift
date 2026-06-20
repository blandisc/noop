import Foundation
import StrandAnalytics

// Goal.swift — the Bucle's goal model (FER-311).
//
// A goal is a single user PREFERENCE: which measurable to improve, and an optional date. It is not
// analytics history, so it lives in `UserDefaults` (`GoalStore`), not the database. The projection math
// is `TrajectorySimulator` (pure, StrandAnalytics); this layer only resolves "which metric / bounds /
// hue / copy" and feeds the engine.

/// The measurable NOOP projects toward a goal. The four cases map 1:1 to `InsightEngine.outcomes`
/// labels, so a proven lever (whose `outcome` is one of those labels) composes with the projection with
/// no special case. "Subir tu condición" fans out to two of them (HRV / resting HR).
enum GoalMetric: String, Codable, CaseIterable {
    case recovery, sleep, hrv, restingHr
}

/// The top-level focus shown in the picker — 3 plain-language outcomes, pure selection.
enum GoalFocus: String, CaseIterable {
    case recovery, sleep, condition
}

extension GoalMetric {
    /// es-MX outcome label — MUST equal an `InsightEngine.outcomes` label (the proven-lever join key).
    var outcomeLabel: String {
        switch self {
        case .recovery:  return "Recuperación"
        case .sleep:     return "Sueño"
        case .hrv:       return "HRV"
        case .restingHr: return "FC en reposo"
        }
    }

    var focus: GoalFocus {
        switch self {
        case .recovery:        return .recovery
        case .sleep:           return .sleep
        case .hrv, .restingHr: return .condition
        }
    }

    /// Resting HR is the only metric where a LOWER value is better — it orients the chart hint and the
    /// sign of the beneficial lever delta.
    var higherIsBetter: Bool { self != .restingHr }

    /// Generous, physiological clamp range for the projection (also filters impossible inputs).
    var bounds: ClosedRange<Double> {
        switch self {
        case .recovery:  return 0...100
        case .sleep:     return 0...720     // minutes (12 h)
        case .hrv:       return 0...200     // ms
        case .restingHr: return 30...110    // bpm
        }
    }

    /// The signal label shown under "Subir tu condición" in the picker.
    var signalLabel: String {
        switch self {
        case .hrv:       return "Por variabilidad (HRV)"
        case .restingHr: return "Por frecuencia en reposo"
        default:         return outcomeLabel
        }
    }

    /// Format a value (in the metric's native units) for display, with its unit. Sleep shows hours.
    func format(_ v: Double) -> String {
        switch self {
        case .sleep:     return String(format: "%.1f h", v / 60)
        case .recovery:  return "\(Int(v.rounded())) pts"
        case .hrv:       return "\(Int(v.rounded())) ms"
        case .restingHr: return "\(Int(v.rounded())) lpm"
        }
    }
}

extension GoalFocus {
    var title: String {
        switch self {
        case .recovery:  return "Recuperarte mejor"
        case .sleep:     return "Dormir mejor"
        case .condition: return "Subir tu condición"
        }
    }

    var subtitle: String {
        switch self {
        case .recovery:  return "Tu recuperación diaria"
        case .sleep:     return "Tus horas de sueño"
        case .condition: return "¿Por cuál señal?"
        }
    }

    /// The metric for focuses with a single signal; `nil` for condición (needs a sub-choice).
    var directMetric: GoalMetric? {
        switch self {
        case .recovery:  return .recovery
        case .sleep:     return .sleep
        case .condition: return nil
        }
    }

    /// The signals condición fans out to (empty for the single-signal focuses).
    var conditionMetrics: [GoalMetric] {
        self == .condition ? [.hrv, .restingHr] : []
    }
}

/// One built goal simulation, ready to render. `projection == nil` → not enough base yet (gate);
/// `leverName == nil` → no proven lever for this metric (the "sin palancas" state).
struct GoalSimulation {
    let metric: GoalMetric
    let horizonDays: Int
    let targetDate: Date?
    let projection: TrajectorySimulator.Projection?
    let leverName: String?
    let usableDays: Int
}
