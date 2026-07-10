import Foundation

/// Opt-in único (FER-848) que habilita las 4 superficies experimentales del épico FER-656:
/// reserva vagal nocturna (DC), estabilidad térmica, respiración nocturna y HRR-60s.
/// Las 4 UIs leen esta misma clave vía @AppStorage.
enum WhitespaceMetricsExperiment {
    static let enabledKey = "fer656.whitespaceMetrics.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }
}
