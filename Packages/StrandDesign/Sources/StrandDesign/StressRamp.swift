import SwiftUI

// MARK: - Stress ramp (its own scale: calm blue → balanced mint → tense amber)
//
// Deliberately distinct from the recovery ramp — low stress reads cool/blue,
// rising stress warms toward amber. Never the red→green recovery traffic light.
// Lives in the design system so screens consume tokens instead of raw hex.

public enum StressRamp {
    public static let calm    = Color(hex: "#4FA9C9") // cool blue — low
    public static let steady  = Color(hex: "#5BD3A0") // mint — balanced
    public static let tense   = Color(hex: "#E8C24B") // amber — high

    public static let stops: [Gradient.Stop] = [
        .init(color: calm,   location: 0.00),
        .init(color: steady, location: 0.50),
        .init(color: tense,  location: 1.00),
    ]

    public static let gradient = Gradient(stops: stops)

    /// Sample the ramp at a 0–3 stress score.
    public static func color(_ score: Double) -> Color {
        StrandPalette.sample(stops: stops, at: min(max(score / 3.0, 0), 1))
    }
}
