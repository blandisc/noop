import SwiftUI

// MARK: - StrandTone (status color mapping)

public enum StrandTone: Sendable {
    case neutral
    case accent
    case positive
    case warning
    case critical

    public var color: Color {
        switch self {
        case .neutral:  return InstrumentoTheme.base.inkSecondary
        case .accent:   return StrandPalette.accent
        case .positive: return StrandPalette.statusPositive
        case .warning:  return StrandPalette.statusWarning
        case .critical: return StrandPalette.statusCritical
        }
    }
}
