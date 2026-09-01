import SwiftUI

// MARK: - SleepInterval (§9.4 Sleep)
//
// FER-280·3c: el hypnograma de papel (`Hypnogram`, la vista) se podó — 0 usos reales, lo reemplazó
// `LiquidHipnograma` (LiquidGlass/LiquidHipnograma.swift). `SleepInterval` sigue viva: la usan
// `Cenit/Screens/SleepDetailScreen.swift` y `StrandAnalytics/NightThirds.swift`.

/// A single stage interval. `start`/`end` are seconds from the start of the night.
public struct SleepInterval: Identifiable, Sendable {
    public let id = UUID()
    public var stage: SleepStage
    public var start: TimeInterval
    public var end: TimeInterval

    public init(stage: SleepStage, start: TimeInterval, end: TimeInterval) {
        self.stage = stage
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end - start) }
}
