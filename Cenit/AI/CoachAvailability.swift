import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// CoachAvailability.swift — which answer engine "Pregúntale a tus datos" can use right now (FER-308).
//
// The tiers, the reasons, and `current()` ALL compile without FoundationModels (it's iOS 26+ and may
// be absent in the build SDK). Only the actual `SystemLanguageModel.availability` read is gated.

/// The answer engine available to "Pregúntale a tus datos" on this device, this moment.
enum CoachTier: Equatable {
    /// Apple Intelligence is ready → free-text questions answered on-device, grounded on the engine.
    case onDevice
    /// No Apple Intelligence → "Modo esencial": pre-armed chips answered with engine templates.
    case templatesOnly
}

/// Why the on-device tier isn't available — mapped 1:1 from `SystemLanguageModel` so the UI can show
/// a precise, Apple-pattern message (and what the user needs to fix it). es-MX.
enum CoachUnavailableReason: Equatable {
    case deviceNotEligible           // chip too old for Apple Intelligence
    case appleIntelligenceNotEnabled // eligible, but off in Settings
    case modelNotReady               // enabled, model still downloading
    case osTooOld                    // running below iOS 26 / no FoundationModels

    /// Short headline for the "por qué" explainer.
    var title: String {
        switch self {
        case .deviceNotEligible:           return "Tu iPhone no es compatible"
        case .appleIntelligenceNotEnabled: return "Activa Apple Intelligence"
        case .modelNotReady:               return "El modelo se está preparando"
        case .osTooOld:                    return "Necesitas iOS 26"
        }
    }

    /// One-line reason, in plain es-MX.
    var detail: String {
        switch self {
        case .deviceNotEligible:
            return "El texto libre lo redacta el modelo de Apple Intelligence, que corre dentro de tu iPhone. Tu equipo no lo soporta, así que respondo con preguntas prearmadas y las cifras de tu motor."
        case .appleIntelligenceNotEnabled:
            return "Tu iPhone es compatible. Enciende Apple Intelligence en Ajustes para escribir preguntas en texto libre."
        case .modelNotReady:
            return "Apple Intelligence está descargando el modelo. Inténtalo de nuevo en unos minutos; mientras, te respondo con preguntas prearmadas."
        case .osTooOld:
            return "El texto libre on-device requiere iOS 26 o posterior. Mientras, te respondo con preguntas prearmadas y las cifras de tu motor."
        }
    }

    /// What the user needs for the on-device tier — shown verbatim in the "qué necesitas" block.
    static let requirements = "iPhone 15 Pro o más nuevo (chip A17 Pro+), iOS 26 o posterior, y Apple Intelligence activado en Ajustes."
}

enum CoachAvailability {
    /// The current tier plus, when it's `.templatesOnly`, the reason on-device isn't available.
    static func current() -> (tier: CoachTier, reason: CoachUnavailableReason?) {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (.onDevice, nil)
            case .unavailable(let reason):
                return (.templatesOnly, CoachUnavailableReason(reason))
            }
        } else {
            return (.templatesOnly, .osTooOld)
        }
        #else
        return (.templatesOnly, .osTooOld)
        #endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
private extension CoachUnavailableReason {
    init(_ reason: SystemLanguageModel.Availability.UnavailableReason) {
        switch reason {
        case .deviceNotEligible:           self = .deviceNotEligible
        case .appleIntelligenceNotEnabled: self = .appleIntelligenceNotEnabled
        case .modelNotReady:               self = .modelNotReady
        @unknown default:                  self = .modelNotReady
        }
    }
}
#endif
