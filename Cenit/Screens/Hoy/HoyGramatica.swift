import Foundation
import StrandAnalytics

// MARK: - HoyGramatica (FER-51 · F1)
//
// El vocabulario PURO compartido por las caras de Hoy (Cosmos abierta y Matriz): mapeos p del
// medidor lunar (§6 del REQ), la tabla de severidad transversal (§8), la máquina de estados del
// chip del guardián (§7 / criterio 10) y el formateo de valores. Solo datos — NADA de SwiftUI,
// NADA de colores: las vistas mapean estos resultados a tokens de StrandDesign.
//
// Regla dura (heredada de `dominoGuardian` y extendida a las caras): esta capa JAMÁS re-deriva
// cortes del motor. Todo umbral viene de `Preparedness.Config` / `ReadinessEngine` públicos, y
// todo juicio (eje fuera, centinela, racha) se LEE de `Preparedness.Read` — nunca se recalcula.

enum HoyGramatica {

    // MARK: Identidad de señal (§4)

    /// Las nueve señales de Hoy, por id estable. El agrupamiento causal (G1 vota / G2 contexto /
    /// G3 bitácora) y los hues viven en las caras; aquí solo la identidad para la severidad.
    enum SenalID: String, CaseIterable {
        case sleep, rhr, skintemp, resp, carga, stress, hrv, strain, steps
    }

    /// Severidad §8 — la única escala de alerta de la pantalla.
    enum Alerta: Equatable {
        case ninguna
        case atencion   // UN aro/halo/subrayado ámbar
        case alarma     // aro DOBLE rojo profundo — SOLO el par centinela con racha ≥ 2
    }

    // MARK: Umbrales (tomados de los knobs públicos del motor — jamás literales sueltos)

    /// z_mal umbral del eje autonómico (FC): el corte del veredicto es `orientedZ ≤ autonomicOutZ`
    /// (−1.0), o sea z_mal (= −orientedZ) ≥ 1.0.
    static let zUmbralFC: Double = -Preparedness.Config.default.autonomicOutZ
    /// z_mal umbral de respiración (corte propio del centinela).
    static let zUmbralResp: Double = Preparedness.Config.default.respBadZ
    /// Temp se juzga en z equivalente: z_equiv = dev_ajustada / `thermalOutC` ⇒ umbral 1.0.
    static let zUmbralTempEquiv: Double = 1.0
    /// VFC: umbral NOMINAL para la geometría del medidor punteado (jamás alerta, §4).
    static let zUmbralVFC: Double = 1.0
    /// Piso izquierdo del medidor de FC (§6): el lado «inusualmente bajo» se estaciona en p = 25
    /// (el borde izquierdo del arco), sin premio y sin alerta.
    static let pisoFC: Double = 25

    // MARK: Mapeos p del medidor lunar (§6) — ángulo(p) = −90° + (p − 50) · 1.8°

    /// Sabor *desviación* (FC, resp, temp, VFC): p = 50 + 25·(z_mal / z_umbral), clamp [0, 100]
    /// (o [pisoIzquierdo, 100] cuando la señal declara piso — FC usa 25). El arco cubre p 25–75:
    /// cruzar el borde derecho (p = 75) equivale EXACTAMENTE a que la señal cruzó SU umbral formal.
    static func pDesviacion(zMal: Double, zUmbral: Double, pisoIzquierdo: Double = 0) -> Double {
        let p = 50 + 25 * (zMal / zUmbral)
        return min(100, max(pisoIzquierdo, max(0, p)))
    }

    /// Sabor *progreso* (sueño): anclas cerradas 420 min ⇒ p 50 y 375 min (el umbral real del
    /// eje) ⇒ p 75; interpolación lineal con pendiente 25/45 = 25/`sleepSlackMin`; clamp [25, 100]
    /// (dormir de más nunca sale del arco por la izquierda). Si el eje alerta por eficiencia
    /// (duración suficiente, eficiencia < `sleepEffFloor`): p fijo en 80 y `porEficiencia` true.
    /// nil sin dato de duración (medidor sin lunita).
    static func pSueno(durMin: Double?, eficiencia: Double?) -> (p: Double, porEficiencia: Bool)? {
        guard let dur = durMin else { return nil }
        let cfg = Preparedness.Config.default
        let corta = dur < cfg.sleepNeedFloorMin - cfg.sleepSlackMin
        if !corta, let eff = eficiencia, eff < cfg.sleepEffFloor {
            return (p: 80, porEficiencia: true)
        }
        let p = 50 + (cfg.sleepNeedFloorMin - dur) * (25 / cfg.sleepSlackMin)
        return (p: min(100, max(25, p)), porEficiencia: false)
    }

    /// Sabor *zona* (carga): p = clamp(razón/2 · 100, 0, 100). El arco es la zona dulce
    /// (`arcoCarga`, p 40–65) y el umbral de ALERTA vive aparte en p 75 (razón 1.5) — la
    /// excepción declarada del §6: entre el arco y p 75 la lunita está fuera SIN alerta.
    static func pCarga(razon: Double) -> Double {
        min(100, max(0, razon / 2 * 100))
    }

    /// Zona dulce de carga en espacio p (0.8–1.3 ⇒ 40–65), derivada de los cortes públicos.
    static var arcoCarga: ClosedRange<Double> {
        pCarga(razon: ReadinessEngine.acwrSweetSpotLow)...pCarga(razon: ReadinessEngine.acwrSweetSpotHigh)
    }

    // MARK: Tabla de severidad (§8 — exhaustiva; nada más produce alarma)

    /// (señal, condición) → nivel. Lee EXCLUSIVAMENTE los juicios que el motor ya emitió
    /// (`drivers`, `sentinel.streakNights`) más la razón de carga contra el corte público.
    /// Única fuente de alarma en toda la pantalla: el par centinela con racha ≥ 2 noches.
    static func severidad(senal: SenalID, prep: Preparedness.Read?,
                          razonCarga: Double?) -> Alerta {
        // §10: con veredicto global «lowSignal» («Conociéndote») NINGUNA señal alerta.
        // El motor puede devolver lowSignal con el eje de sueño aún en `.low` (autonómico
        // sin dato + noche corta), así que sin este corte la pantalla pintaría ámbar durante
        // la calibración — exactamente lo que §10 prohíbe (hallazgo adversarial Grok #1).
        if prep?.verdict == .lowSignal { return .ninguna }
        switch senal {
        case .sleep:
            guard let eje = prep?.drivers.first(where: { $0.axis == .sleep }) else { return .ninguna }
            return eje.state.isOut ? .atencion : .ninguna
        case .rhr:
            guard let eje = prep?.drivers.first(where: { $0.axis == .autonomic }) else { return .ninguna }
            return eje.state.isOut ? .atencion : .ninguna
        case .skintemp, .resp:
            // El par centinela alerta JUNTO o no alerta (§4: «solo el PAR, nunca sola»).
            guard let s = prep?.sentinel, s.state == .corroborated else { return .ninguna }
            return s.streakNights >= 2 ? .alarma : .atencion
        case .carga:
            guard let razon = razonCarga else { return .ninguna }
            return razon >= ReadinessEngine.acwrSpikeAt ? .atencion : .ninguna
        case .stress, .hrv, .strain, .steps:
            return .ninguna   // jamás alertan en Hoy (§4/§13)
        }
    }

    // MARK: Chip del guardián (§7 / criterio 10) — máquina de 5 estados

    /// El estado del chip de la banda del guardián en la Matriz. `racha` carga el ordinal REAL
    /// del centinela (`streakNights`), jamás un número fijo.
    enum ChipGuardian: Equatable {
        case calma                 // nada fuera — verde
        case vigilandoTemp         // solo temp fuera — informativo, tinta terciaria, SIN cálidos
        case vigilandoResp         // solo resp fuera — ídem
        case ambasPrimeraNoche     // par fuera, 1.ª noche — ámbar
        case racha(noches: Int)    // par fuera, racha ≥ 2 — rojo + «· N.ª noche»
    }

    /// Proyección pura de `Read.sentinel` al chip. nil cuando el motor no tuvo lectura del par
    /// esa noche (`sentinel == nil`): sin dato no se afirma calma — la banda cae a su fantasma.
    static func chipGuardian(sentinel: Preparedness.SentinelRead?) -> ChipGuardian? {
        guard let s = sentinel else { return nil }
        switch s.state {
        case .quiet:
            return .calma
        case .watchingOneSignal:
            return s.watchingSignal == .temp ? .vigilandoTemp : .vigilandoResp
        case .corroborated:
            return s.streakNights >= 2 ? .racha(noches: s.streakNights) : .ambasPrimeraNoche
        }
    }

    // MARK: Sublabels de estado (claves §11 — la vista las resuelve contra el catálogo)

    /// Estado de la carga como CLAVE de catálogo: estable / subiendo / descargando / pico /
    /// calibrando. Ruta por `ReadinessEngine.loadBand` (los cortes 0.8/1.3/1.5 viven ahí, una
    /// sola vez). nil (sin razón todavía) ⇒ calibrando.
    static func estadoCarga(razon: Double?) -> String {
        guard let r = razon else { return "carga.calibrando" }
        switch ReadinessEngine.loadBand(forACWR: r) {
        case .rampingDown:  return "carga.descargando"
        case .sweetSpot:    return "carga.estable"
        case .buildingFast: return "carga.subiendo"
        case .spiking:      return "carga.pico"
        }
    }

    // MARK: Formateo de valores (§4 / §6 — locale-neutral, dígitos con punto decimal)

    /// Duración de sueño «7:42» (462 min). Minutos negativos se tratan como 0.
    static func formatoDuracion(_ minutos: Double) -> String {
        let total = max(0, Int(minutos.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Delta de temp SIEMPRE con signo («+0.2°», «−0.4°») — el motor solo expone el delta;
    /// jamás temperatura absoluta en Hoy (contrato §11).
    static func formatoDeltaTemp(_ dev: Double) -> String {
        // FER-73 · H15: `%+.1f` produce «-0.0°» en (−0.05, 0) —un cero con signo negativo, que
        // se lee como «bajaste» sin haber bajado— y escribe el guion ASCII donde el resto de la
        // pantalla usa el menos tipográfico (U+2212). Se normaliza el cero y se unifica el signo.
        let redondeado = (dev * 10).rounded() / 10
        if redondeado == 0 { return "0.0°" }
        let cuerpo = String(format: "%.1f", abs(redondeado))
        return (redondeado > 0 ? "+" : "\u{2212}") + cuerpo + "°"
    }

    /// Respiración: SIEMPRE una décima, en las tres superficies (Matriz, héroe/guardián y su
    /// hoja). Antes el héroe redondeaba a entero y la Matriz mostraba la décima: «14 rpm» y
    /// «14.4» para la misma noche (FER-73 · H17/HJ-18).
    static func formatoResp(_ rpm: Double) -> String {
        String(format: "%.1f", rpm)
    }

    /// Valor del par guardián: delta de temp con signo + respiración, «+0.2° · 14.2».
    static func formatoParGuardian(deltaTemp: Double, resp: Double) -> String {
        formatoDeltaTemp(deltaTemp) + " · " + formatoResp(resp)
    }

    /// Miles con espacio fino no separable («8 432»), para pasos.
    /// Pasos en MILES con un decimal, sin unidad (la unidad «k» la pone el módulo): 6 200 →
    /// «6,2» en es / «6.2» en en; 850 → «0,9». Redondea a centenas: el número corto del
    /// prototipo (FER-125); el conteo exacto sigue en la hoja de Pasos.
    static func formatoMilesK(_ v: Double, locale: Locale) -> String {
        let miles = max(v, 0) / 1000
        let sep = locale.decimalSeparator ?? "."
        return String(format: "%.1f", miles).replacingOccurrences(of: ".", with: sep)
    }

    static func formatoMiles(_ v: Double) -> String {
        let entero = Int(v.rounded())
        let crudo = String(entero)
        guard crudo.count > 3, entero >= 0 else { return crudo }
        var digitos = Array(crudo)
        var resultado = ""
        while digitos.count > 3 {
            let grupo = digitos.suffix(3)
            digitos.removeLast(3)
            resultado = "\u{202F}" + String(grupo) + resultado
        }
        return String(digitos) + resultado
    }

    /// «—» vs «0» (§4): nil (sin dato) formatea el glifo de dato ausente (permitido por el guard:
    /// solo copy con letras prohíbe em-dash); un cero REAL se formatea como cero. La distinción
    /// es sagrada en esfuerzo/pasos.
    static func valorODash(_ v: Double?, formato: (Double) -> String) -> String {
        guard let v else { return "—" }
        return formato(v)
    }
}
