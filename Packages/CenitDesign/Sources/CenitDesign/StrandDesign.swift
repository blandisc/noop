import SwiftUI

/// Strand design system: palette, typography, motion, and signature components
/// (Recovery Ring, Strain Gauge, Hypnogram, Trend/Sparkline charts, Year heat
/// strip, cards, status chips). Dark-only, instrument-grade. See spec §9.
///
/// Token entry points:
/// - `StrandPalette` — every semantic color token (§9.1), recovery/strain sampling.
/// - `StrandFont` — the full type scale with tabular digits (§9.2).
/// - `StrandMotion` — spring presets + durations (§9.6).
public enum CenitDesign {
    public static let version = "0.1.0"
}
