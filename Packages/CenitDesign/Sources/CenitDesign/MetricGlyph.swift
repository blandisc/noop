import SwiftUI

// MARK: - MetricGlyph — the single source of truth for per-metric icon + hue (handoff v2 §8.7)
//
// One place that says "this metric looks like THIS icon in THIS hue", so Hoy's SEÑALES tiles and the
// Tendencias/Cuerpo detail titles can never drift apart (they used to each hardcode their own SF
// Symbol string). Icons are SF Symbols — native, legible, and what the DNA/Cupertino guidance calls
// for. Hues track the theme's data roles where one exists; the few metrics without a theme role carry
// their handoff hex here. Pure SwiftUI; no UIKit/AppKit.

/// Every metric that gets a standardized icon + hue across Hoy and Tendencias.
public enum MetricGlyph: String, Sendable, CaseIterable {
    case recovery, sleep, strain, stress, trainingLoad
    case heartRate, restingHR, hrv, respiration, spo2, skinTemp
    case steps, workouts, afterSport, fitnessAge, bodyAge, vo2max

    /// The SF Symbol name for this metric.
    public var sfSymbol: String {
        switch self {
        case .recovery:     return "sunrise.fill"
        case .sleep:        return "moon.fill"
        case .strain:       return "flame.fill"
        case .stress:       return "gauge.with.dots.needle.bottom.50percent"
        case .trainingLoad: return "mountain.2.fill"
        case .heartRate:    return "heart.fill"
        case .restingHR:    return "heart.fill"
        case .hrv:          return "waveform.path.ecg"
        case .respiration:  return "lungs.fill"
        case .spo2:         return "drop.fill"
        case .skinTemp:     return "thermometer.medium"
        case .steps:        return "figure.walk"
        case .workouts:     return "dumbbell.fill"
        case .afterSport:   return "arrow.triangle.2.circlepath"
        case .fitnessAge:   return "figure.run"
        case .bodyAge:      return "heart.fill"
        case .vo2max:       return "gauge.with.dots.needle.67percent"
        }
    }

    /// The metric's hue. Uses a theme data-role where one exists (so a palette change tracks
    /// automatically); the rest carry their handoff hex.
    public func hue(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .recovery, .fitnessAge, .bodyAge: return theme.dataRecovery
        case .sleep:                            return theme.dataSleep
        case .strain, .skinTemp,
             .trainingLoad, .workouts, .afterSport: return theme.dataStrain
        case .stress:       return Color(hex: "#9C5E10")
        case .heartRate:    return Color(hex: "#A23B49")
        case .restingHR:    return theme.dataHeart
        case .hrv:          return theme.dataHrv
        case .respiration, .vo2max: return theme.dataSpO2
        case .spo2:         return Color(hex: "#3F7A5E")
        case .steps:        return theme.dataSteps
        }
    }
}
