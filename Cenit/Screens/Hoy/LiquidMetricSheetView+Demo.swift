import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics

// MARK: - Modo DEMO en vivo (/inject) — generadores de fixtures
//
// El interruptor `demo` y `datoInfo` viven en LiquidMetricSheetView (los usa el `body`);
// aquí sólo están los GENERADORES de las series/fixtures de muestra, extraídos para
// adelgazar el compositor (FER-36). Siguen compilándose en Release (los llama el body
// bajo `if demo`, que en Release es siempre `false`), pero ya no ensucian el archivo
// principal. `demoCentro`/`demoKeyFmt` quedan `private` a este archivo.

extension LiquidMetricSheetView {

    /// Fixture con dato de muestra por id (mismas factories del catálogo → misma variante).
    static func demoInfo(_ id: String) -> MetricInfo {
        switch id {
        case "sleep":     return .sleep(432)
        case "hrv":       return .hrv(56)
        case "rhr":       return .restingHR(52)
        case "strain":    return .strain(10.0)
        case "steps":     return .steps(8432)
        case "spo2":      return .spo2(97)
        case "skin_temp": return .skinTemp(0.1)
        case "resp_rate": return .respiratory(14)
        case "stress":    return .stress(1.2)
        case "heart_rate": return .heartRate(avgBpm: 62)
        case "vo2max":    return .vo2max(42)
        // D2 · Las 5 submétricas del Detalle de Sueño caían al `default` (VFC), así que la
        // variante CLÁSICA —trend de 14 días + tabla de bandas— era inalcanzable en la app
        // corriendo: se estaba puliendo a ciegas.
        case "sleep_performance": return .sleepPerformance(85)
        case "sleep_efficiency":  return .sleepEfficiency(88)
        case "sleep_restorative": return .sleepRestorative(42)
        case "sleep_awakenings":  return .sleepAwakenings(3)
        case "sleep_latency":     return .sleepLatency(14)
        default:          return .hrv(56)
        }
    }

    /// Centro plausible de la serie por id (para niveles y trend de muestra).
    private static func demoCentro(_ id: String) -> (centro: Double, amp: Double) {
        switch id {
        case "sleep":     return (430, 45)
        case "rhr":       return (54, 5)
        case "strain":    return (10, 3)
        case "steps":     return (8000, 1600)
        case "spo2":      return (97, 1.2)
        case "skin_temp": return (0.1, 0.35)
        case "resp_rate": return (14, 1.2)
        case "stress":    return (1.2, 0.5)
        // D2 · Sin estos casos la SERIE de las submétricas de sueño caía al centro de VFC
        // (55 ± 8) mientras la cabecera decía «85 %»: la hoja se contradecía y los conteos
        // de la tabla no se podían leer. Las amplitudes CRUZAN las cotas de cada fábrica
        // (85 → <70/70-85/85+, 88 → <75/75-85/85+, 42 → <30/30-50/50+, 14 → <10/10-20/20+)
        // para que los tres conteos salgan repartidos y sumen 14.
        case "sleep_performance": return (85, 16)
        case "sleep_efficiency":  return (86, 12)
        case "sleep_restorative": return (42, 16)
        case "sleep_awakenings":  return (3, 2)
        case "sleep_latency":     return (14, 8)
        default:          return (55, 8)   // hrv
        }
    }

    /// Formateador de day-key «yyyy-MM-dd» (el que `parseDayKey` entiende).
    private static let demoKeyFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 30 días de serie diaria de muestra (day-keys válidas), deterministas.
    static func demoRows(_ id: String) -> [(day: String, value: Double)] {
        let (centro, amp) = demoCentro(id)
        let cal = Calendar.current
        let hoy = Date()
        return (0..<30).reversed().map { i in
            let fecha = cal.date(byAdding: .day, value: -i, to: hoy) ?? hoy
            let onda: Double = sin(Double(i) * 0.6)
            let v: Double = centro + amp * onda + Double(i % 4) - 1.5
            return (day: demoKeyFmt.string(from: fecha), value: v)
        }
    }

    /// 14 puntos de tendencia de muestra.
    static func demoTrend(_ id: String) -> [TrendPoint] {
        let (centro, amp) = demoCentro(id)
        let cal = Calendar.current
        let hoy = Date()
        return (0..<14).reversed().map { i in
            let fecha = cal.date(byAdding: .day, value: -i, to: hoy) ?? hoy
            let v: Double = centro + amp * sin(Double(i) * 0.5)
            return TrendPoint(date: fecha, value: v)
        }
    }

    /// La NOCHE de muestra: sin ella la variante rica de sueño (doble dato + etapas +
    /// regularidad) no se puede pulir en un simulador sin datos de Apple Salud, porque
    /// `sleepDetail` lo inyecta TodayView y en demo llega `nil`.
    ///
    /// Los números cuadran entre sí a propósito (si no, la hoja se contradice sola):
    /// 91 profundo + 104 REM + 237 ligero = 432 min dormido = «7h 12m», EXACTAMENTE el
    /// numeral del fixture `.sleep(432)` y su banda «Óptimo» (7-9 h); + 47 despierto =
    /// 479 min en cama = la ventana 23:38 → 7:37.
    static func demoNoche() -> SleepDetailModel.Night {
        let cal: Calendar = Calendar.current
        let medianoche: Date = cal.startOfDay(for: Date())
        let inicio: Date = cal.date(byAdding: .minute, value: -22, to: medianoche) ?? medianoche
        let fin: Date = cal.date(byAdding: .minute, value: 457, to: medianoche) ?? medianoche
        let etapas = SleepDetailModel.Stages(awake: 47, light: 237, deep: 91, rem: 104)
        return SleepDetailModel.Night(
            startTs: Int(inicio.timeIntervalSince1970),
            endTs: Int(fin.timeIntervalSince1970),
            efficiency: 90.2,
            respRate: 14.2,
            stages: etapas)
    }

    /// Curva de FC de un día de muestra (~180 puntos, 5 min).
    static func demoCurva() -> [TrendPoint] {
        let cal = Calendar.current
        let inicio = cal.startOfDay(for: Date())
        return (0..<180).map { (i: Int) -> TrendPoint in
            // Tipos explícitos: el type-checker se atora con expresiones mixtas largas.
            let seg: Double = Double(i) * 300
            let fecha: Date = inicio.addingTimeInterval(seg)
            let hora: Double = seg / 3600
            let circadiano: Double = sin(hora / 24 * 2 * Double.pi - 1.3)
            let ruido: Double = sin(hora * 1.7)
            let v: Double = 62 + 22 * circadiano + 6 * ruido
            return TrendPoint(date: fecha, value: Swift.max(48, v))
        }
    }
}
