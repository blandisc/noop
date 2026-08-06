import Foundation
import StrandAnalytics

// MARK: - FER-51 · Máquina de estados T1–T5 (pura)
//
// Resolución de plantilla y causas T3/T4 sin efectos, sin fechas mágicas (usa `now` /
// `calendar` inyectados). El host y TodayView solo alimentan y proyectan.

extension LiquidHoyBuilder {

    enum Plantilla: Equatable {
        case t1Pleno
        case t2Provisional
        case t3SinVeredicto(CausaT3)
        case t4SinPermiso
        case t5Dormido
    }

    enum CausaT3: Equatable {
        case leyendo
        case sinSync
        case nocheNoRegistrada
    }

    /// Ventana nocturna del veredicto (KNOB de producto, nombrado). Cerrada si hay sesión de
    /// sueño que termina hoy, o si `now` ≥ 11:00 local. Inicio = 21:00 de ayer.
    struct VentanaNocturna: Equatable {
        static let inicioHora = 21   // knob
        static let cierreHora = 11   // knob
        let abierta: Bool
        let inicio: Date

        static func evaluar(now: Date, calendar: Calendar, sesionFinHoy: Date?) -> VentanaNocturna {
            let startOfToday = calendar.startOfDay(for: now)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            var comps = calendar.dateComponents([.year, .month, .day], from: yesterday)
            comps.hour = inicioHora
            comps.minute = 0
            comps.second = 0
            let inicio = calendar.date(from: comps) ?? yesterday

            let horaLocal = calendar.component(.hour, from: now)
            // Si hay sesión que termina hoy, la ventana ya cerró (noche leída).
            let abierta = (sesionFinHoy == nil) && (horaLocal < cierreHora)
            return VentanaNocturna(abierta: abierta, inicio: inicio)
        }
    }

    /// Máquina T3 — ALGORITMO ORDENADO, precedencia estricta, gana el primer caso (§11 del REQ):
    ///  1. sin veredicto ∧ ventana ABIERTA            ⇒ .leyendo (SIEMPRE, sin importar el import)
    ///  2. sin veredicto ∧ ventana CERRADA ∧ import anterior al inicio de ventana ⇒ .sinSync
    ///  3. sin veredicto ∧ ventana CERRADA ∧ import fresco ∧ noche vacía          ⇒ .nocheNoRegistrada
    static func causaT3(ventana: VentanaNocturna, lastSync: Date?, hayNocheRegistrada: Bool) -> CausaT3 {
        if ventana.abierta { return .leyendo }
        if let ls = lastSync, ls < ventana.inicio { return .sinSync }
        if lastSync == nil { return .sinSync }      // nil = conservador
        return hayNocheRegistrada ? .leyendo : .nocheNoRegistrada
    }

    /// Heurística T4 (§18): decisión PURA. Un tipo suma al ≥2 solo si (≥1 muestra en 14 d) ∧ (fetch 48h vacío).
    struct SilencioSalud: Equatable {
        /// por tipo {FC nocturna, sueño, pasos}: (historia14d>0, ultimas48hVacio)
        let tipos: [(tuvo14d: Bool, vacio48h: Bool)]
        var disparaT4: Bool { tipos.filter { $0.tuvo14d && $0.vacio48h }.count >= 2 }
    }

    /// Resolución global de plantilla: T5 > T4 > T3 > T2 > T1.
    static func plantilla(prep: Preparedness.Read?, healthConnected: Bool, hasAnySource: Bool,
                          silencioT4: SilencioSalud?, causaT3: CausaT3?) -> Plantilla {
        if !hasAnySource { return .t5Dormido }
        if !healthConnected || (silencioT4?.disparaT4 ?? false) { return .t4SinPermiso }
        guard let prep else { return .t3SinVeredicto(causaT3 ?? .leyendo) }
        switch prep.verdict {
        case .lowSignal: return .t3SinVeredicto(causaT3 ?? .leyendo)   // «Conociéndote»
        case .caution, .easy: return .t2Provisional                    // veredicto con menos certeza (mismo layout T1)
        case .full: return .t1Pleno
        }
    }
}
