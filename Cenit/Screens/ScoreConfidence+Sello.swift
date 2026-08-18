import SwiftUI
import StrandAnalytics
import StrandDesign

// MARK: - ScoreConfidence → sello (FER-676, app layer)
//
// The one place a ScoreConfidence tier turns into visible copy and a ready-to-place
// ConfidenceSello. It lives in the app layer because the label/a11y strings resolve
// against Cenit's String Catalog (StrandDesign stays copy-free). Every score — Esfuerzo,
// Sueño, and future ones — builds its stamp here, so the tier→copy and tier→emphasis
// rules exist ONCE instead of being re-derived per screen.
extension ScoreConfidence {

    /// The tier's visible label. English source; es-MX in the String Catalog. `calibrating`
    /// only shows when a score somehow exists below the data floor — reads as still settling.
    var confidenceLabel: LocalizedStringKey {
        switch self {
        case .solid:       return "High confidence"
        case .building:    return "Medium confidence"
        case .calibrating: return "Calibrating"
        }
    }

    /// El MISMO rótulo, ya resuelto a `String` — las piezas Liquid (la pastilla de
    /// `LiquidCampoMetrica`) reciben texto, no `LocalizedStringKey`. Mismas claves.
    var confidenceLabelText: String {
        switch self {
        case .solid:       return String(localized: "High confidence")
        case .building:    return String(localized: "Medium confidence")
        case .calibrating: return String(localized: "Calibrating")
        }
    }

    /// VoiceOver phrase — spells out "confidence: …" so the tier is never announced as a
    /// bare adjective.
    /// La misma frase de VoiceOver, resuelta a `String` — las piezas Liquid piden texto, no
    /// claves (gemela de `confidenceLabelText`).
    var confidenceA11yText: String {
        switch self {
        case .solid:       return String(localized: "Confidence: high")
        case .building:    return String(localized: "Confidence: medium")
        case .calibrating: return String(localized: "Confidence: calibrating")
        }
    }

    var confidenceA11y: LocalizedStringKey {
        switch self {
        case .solid:       return "Confidence: high"
        case .building:    return "Confidence: medium"
        case .calibrating: return "Confidence: calibrating"
        }
    }

    /// The ready-to-place stamp for this tier. `solid` reads a step stronger; every thinner
    /// tier dims — the emphasis rule owned in one place, not per call site. Pass `onField: true`
    /// when it sits on a coloured hero field (Sleep/Strain) so it flips to paper ink for contrast.
    func sello(theme: InstrumentoTheme, onField: Bool = false) -> ConfidenceSello {
        ConfidenceSello(Text(confidenceLabel), a11yLabel: Text(confidenceA11y),
                        dimmed: self != .solid, onField: onField, theme: theme)
    }
}
