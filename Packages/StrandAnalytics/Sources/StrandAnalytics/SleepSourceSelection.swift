import Foundation

/// H1 (auditoría de estrés): cuando VARIAS fuentes de Apple Health escriben sueño la misma noche
/// (Apple Watch + otra app de sueño, o el Sleep Schedule del iPhone), sumar sus etapas double-cuenta
/// el total y empuja la eficiencia a un falso 100%. Por noche nos quedamos con UNA sola fuente para
/// las ETAPAS (deep/REM/core/asleep). Regla, aprobada por el dueño («una fuente, prioridad al Watch»):
/// preferir una fuente de Apple (Apple Watch / Sleep Schedule del iPhone → bundleId «com.apple…», la
/// familia que estadía el sueño), y entre las candidatas la de MÁS minutos dormidos (el registro más
/// completo). Mezclar etapas de dos fuentes no tiene sentido (¿qué etapa es ese minuto?), por eso se
/// elige una, no se fusiona.
///
/// El `inBed` (envolvente de eficiencia) se maneja APARTE y se puede sumar entre fuentes sin riesgo:
/// solaparlo solo puede bajar la eficiencia, nunca inventar una favorable — y el Apple Watch no escribe
/// `inBed`, así que tomarlo de quien sí lo escriba (el iPhone) es correcto.
public enum SleepSourceSelection {

    /// La fuente ganadora para las etapas de una noche, dado el total de minutos dormidos por fuente.
    /// `nil` si el mapa viene vacío. Determinista ante empates (gana el bundleId menor).
    public static func pick(asleepMinutesBySource: [String: Double]) -> String? {
        // D1 (gate /qa): considera SOLO fuentes con sueño real (> 0 min). Una fuente Apple con 0 min
        // —el `.asleep` genérico de watchOS ≤ 8 o `.awake`, que quedan presentes con 0— no debe ganar
        // la prioridad Apple y provocar que se descarte una fuente no-Apple con etapas válidas. Si
        // ninguna fuente tiene sueño, no hay noche que emitir → nil.
        let real = asleepMinutesBySource.filter { $0.value > 0 }
        guard !real.isEmpty else { return nil }
        let apple = real.filter { $0.key.hasPrefix("com.apple") }
        let pool = apple.isEmpty ? real : apple
        return pool.max { a, b in
            a.value != b.value ? a.value < b.value : a.key > b.key
        }?.key
    }
}
