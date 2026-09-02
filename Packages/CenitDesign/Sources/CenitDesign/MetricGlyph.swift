import SwiftUI

// MARK: - MetricGlyph — the single source of truth for per-metric icon + hue (handoff v2 §8.7)
//
// One place that says "this metric looks like THIS icon in THIS hue", so Hoy's SEÑALES tiles and the
// Tendencias/Cuerpo detail titles can never drift apart (they used to each hardcode their own SF
// Symbol string). Icons are SF Symbols — native, legible, and what the DNA/Cupertino guidance calls
// for. Hues track Liquid data roles where one exists; the few metrics without a role keep a fixed
// handoff hex. Pure SwiftUI; no UIKit/AppKit. (FER-316)

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

    /// The metric's hue. Uses a Liquid data-role where one exists; the rest keep their handoff hex.
    /// `theme` is ignored for painting (FER-316).
    public func hue(_ theme: InstrumentoTheme = .base) -> Color {
        _ = theme
        switch self {
        case .recovery, .fitnessAge, .bodyAge: return LiquidColor.verdePrimario
        case .sleep:                            return LiquidColor.indigo
        case .strain, .skinTemp,
             .trainingLoad, .workouts, .afterSport: return LiquidColor.ambar
        case .stress:       return LiquidColor.atencionTexto
        case .heartRate:    return LiquidColor.rosa
        case .restingHR:    return LiquidColor.rosa
        case .hrv:          return LiquidColor.cian
        case .respiration, .vo2max: return LiquidColor.azul
        case .spo2:         return LiquidColor.verdeCarga
        case .steps:        return LiquidColor.teal
        }
    }
}
