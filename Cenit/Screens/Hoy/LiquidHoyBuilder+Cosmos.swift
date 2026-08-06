import Foundation
import SwiftUI
import StrandAnalytics
import StrandDesign
import StrandModels

// MARK: - FER-51 · Builder puro → CosmosAbiertoModel (Lane C)
//
// Proyección PURA: medidores por señal vía HoyGramatica (§6), severidad §8, fantasmas §4.
// CERO re-derivación de umbrales del motor. No toca LiquidHoyBuilder.swift ni TodayView.

extension LiquidHoyBuilder {

    /// Proyecta el estado de Hoy a la cara Cosmos abierta.
    static func cosmosAbierto(_ i: MatrizInputs, extra: CosmosExtraInputs) -> CosmosAbiertoModel {
        let prep = i.prep
        let razon = i.carga?.acwr
        let baseUsable = (prep?.maturity != .calibrating)
            && (prep.map { $0.autonomicNights >= Baselines.minNightsSeed } ?? false)
        let hoy = filaHoy(i)
        let eficiencia = hoy?.efficiency
        let locale = i.locale

        let heroe = heroeCosmos(prep: prep, nights: prep?.autonomicNights ?? 0)
        let destello = destelloTono(prep: prep)

        // G1
        let sleep = anclaSueno(extra: extra, prep: prep, eficiencia: eficiencia,
                               locale: locale)
        let guardian = anclaGuardian(extra: extra, prep: prep, baseUsable: baseUsable, locale: locale)
        let rhr = anclaRHR(extra: extra, prep: prep, baseUsable: baseUsable, locale: locale)
        // G2
        let carga = anclaCarga(razon: razon, prep: prep, locale: locale)
        let stress = anclaEstres(extra: extra, locale: locale)
        let hrv = anclaVFC(extra: extra, prep: prep, baseUsable: baseUsable, locale: locale)
        // G3
        let strain = anclaEsfuerzo(extra: extra, locale: locale)
        let steps = anclaPasos(extra: extra, locale: locale)

        return CosmosAbiertoModel(
            heroe: heroe,
            anclas: [sleep, guardian, rhr, carga, stress, hrv, strain, steps],
            destelloTono: destello)
    }

    // MARK: Héroe

    private static func heroeCosmos(prep: Preparedness.Read?, nights: Int) -> CosmosAbiertoModel.Heroe {
        let (hero, _, _) = Self.hero(prep: prep, nights: nights, healthConnected: true)
        let amb = ambiente(prep: prep)
        switch hero {
        case .veredicto(let title, _, let tone, _, let confianza):
            return .init(palabra: title,
                         tonoOrbe: particula(amb),
                         tonoPalabra: tone,
                         confianza: confianza,
                         a11y: String(localized: "Verdict: \(title)"))
        case .demotado(_, let title, _):
            return .init(palabra: title,
                         tonoOrbe: LiquidColor.particulaNeutra,
                         tonoPalabra: LiquidColor.tinta500,
                         a11y: title)
        }
    }

    private static func particula(_ amb: LiquidAmbiente) -> Color {
        switch amb {
        case .bien: return LiquidColor.particulaVerde
        case .atencion: return LiquidColor.particulaAmbar
        case .alerta: return LiquidColor.particulaRoja
        case .neutro: return LiquidColor.particulaNeutra
        }
    }

    private static func destelloTono(prep: Preparedness.Read?) -> Color {
        switch ambiente(prep: prep) {
        case .bien: return LiquidColor.verdePrimario
        case .atencion: return LiquidColor.atencion
        case .alerta: return LiquidColor.negativo
        case .neutro: return LiquidColor.tinta500
        }
    }

    // MARK: Anclas

    private static func anclaSueno(extra: CosmosExtraInputs, prep: Preparedness.Read?,
                                   eficiencia: Double?,
                                   locale: Locale) -> CosmosAbiertoModel.Ancla {
        let alertaG = HoyGramatica.severidad(senal: .sleep, prep: prep, razonCarga: nil)
        let alerta = mapAlerta(alertaG)
        let dur = extra.sleep?.value
        let mapeo = HoyGramatica.pSueno(durMin: dur, eficiencia: eficiencia)
        // Sueño: el medidor usa piso poblacional; fantasma solo sin dato de duración.
        let sinDato = dur == nil
        let fantasma = sinDato
        let lunitas: [CosmosAbiertoModel.Lunita] = {
            guard !fantasma, let m = mapeo else { return [] }
            return [.init(p: m.p, hue: LiquidColor.indigo, alerta: alerta)]
        }()
        let valor: String = {
            guard let d = dur else { return "—" }
            return HoyGramatica.formatoDuracion(d)
        }()
        let sub: String? = {
            if sinDato { return conociendote() }
            if let m = mapeo, m.porEficiencia, let e = eficiencia {
                let pct = Int((e * 100).rounded())
                // La sobrecarga LocalizationValue admite interpolación; la forma
                // key+defaultValue exige que la clave sea StaticString (sin \(…)).
                return String(localized: "efficiency \(pct) %")
            }
            return nil
        }()
        // Alerta formal jamás en fantasma (§4 / criterio 9).
        let alertaFinal: CosmosAbiertoModel.Alerta = fantasma ? .ninguna : alerta
        return .init(
            id: "sleep", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.indigo,
            medidor: .init(radioAnillo: 22, sabor: .progreso, lunitas: lunitas,
                           fantasma: fantasma),
            valorPartes: [.init(texto: valor, hue: LiquidColor.indigo)],
            valorSize: 26, sublabel: sub,
            rotulo: up(String(localized: "Sleep"), locale),
            alerta: alertaFinal,
            a11y: a11y("Sleep", valor, sub, alertaFinal))
    }

    private static func anclaGuardian(extra: CosmosExtraInputs, prep: Preparedness.Read?,
                                      baseUsable: Bool,
                                      locale: Locale) -> CosmosAbiertoModel.Ancla {
        // El par alerta JUNTO (HoyGramatica: skintemp/resp → misma severidad del centinela).
        let alertaG = HoyGramatica.severidad(senal: .skintemp, prep: prep, razonCarga: nil)
        let alerta = mapAlerta(alertaG)
        let tempDev = prep?.thermalAdjustedDevC ?? extra.temp?.value
        let respVal = extra.resp?.value
        let sinTemp = tempDev == nil
        let sinResp = respVal == nil
        // Fantasma: sin base usable O sin ninguna de las dos lecturas.
        let fantasma = !baseUsable || (sinTemp && sinResp)

        var lunitas: [CosmosAbiertoModel.Lunita] = []
        if !fantasma {
            if let t = tempDev {
                // z_equiv = dev_ajustada / thermalOutC; z_mal = z_equiv (subir es malo).
                let zMal = t / Preparedness.Config.default.thermalOutC
                let p = HoyGramatica.pDesviacion(zMal: zMal, zUmbral: HoyGramatica.zUmbralTempEquiv)
                lunitas.append(.init(p: p, hue: LiquidColor.doradoTemp, alerta: alerta))
            }
            if respVal != nil, let z = prep?.signals.first(where: { $0.signal == .resp })?.orientedZ {
                let zMal = -z
                let p = HoyGramatica.pDesviacion(zMal: zMal, zUmbral: HoyGramatica.zUmbralResp)
                lunitas.append(.init(p: p, hue: LiquidColor.azul, alerta: alerta))
            } else if respVal != nil, !fantasma {
                // Sin z del motor: lunita en el centro (informativa, sin inventar umbral).
                lunitas.append(.init(p: 50, hue: LiquidColor.azul, alerta: alerta))
            }
        }

        let valorPartes: [CosmosAbiertoModel.ValorParte] = {
            if fantasma || (sinTemp && sinResp) {
                return [.init(texto: "—", hue: LiquidColor.tinta500)]
            }
            if let t = tempDev, let r = respVal {
                return [
                    .init(texto: HoyGramatica.formatoDeltaTemp(t), hue: LiquidColor.doradoTemp),
                    .init(texto: " · ", hue: LiquidColor.tinta500),
                    .init(texto: String(format: "%.1f", r), hue: LiquidColor.azul),
                ]
            }
            if let t = tempDev {
                return [.init(texto: HoyGramatica.formatoDeltaTemp(t), hue: LiquidColor.doradoTemp)]
            }
            if let r = respVal {
                return [.init(texto: String(format: "%.1f", r), hue: LiquidColor.azul)]
            }
            return [.init(texto: "—", hue: LiquidColor.tinta500)]
        }()

        let sub: String? = fantasma ? conociendote() : nil
        let alertaFinal: CosmosAbiertoModel.Alerta = fantasma ? .ninguna : alerta
        let valorTxt = valorPartes.map(\.texto).joined()
        return .init(
            id: "guardian", grupo: 1, lunaRadio: 7,
            hueLuna: LiquidColor.doradoTemp, hueLuna2: LiquidColor.azul,
            medidor: .init(radioAnillo: 17, sabor: .desviacion, lunitas: lunitas,
                           fantasma: fantasma),
            valorPartes: valorPartes, valorSize: 16, sublabel: sub,
            rotulo: up(String(localized: "Guardian"), locale),
            alerta: alertaFinal,
            a11y: a11y("Guardian", valorTxt, sub, alertaFinal))
    }

    private static func anclaRHR(extra: CosmosExtraInputs, prep: Preparedness.Read?,
                                 baseUsable: Bool,
                                 locale: Locale) -> CosmosAbiertoModel.Ancla {
        let alertaG = HoyGramatica.severidad(senal: .rhr, prep: prep, razonCarga: nil)
        let alerta = mapAlerta(alertaG)
        let valor = extra.rhr?.value
        let sinDato = valor == nil
        let fantasma = !baseUsable || sinDato

        let zMal: Double? = {
            // z_mal = −orientedZ del eje autonómico (compuesto; wRHR=1).
            guard let z = prep?.drivers.first(where: { $0.axis == .autonomic })?.orientedZ
            else { return nil }
            return -z
        }()

        let lunitas: [CosmosAbiertoModel.Lunita] = {
            guard !fantasma, let z = zMal else { return [] }
            let p = HoyGramatica.pDesviacion(zMal: z, zUmbral: HoyGramatica.zUmbralFC,
                                             pisoIzquierdo: HoyGramatica.pisoFC)
            return [.init(p: p, hue: LiquidColor.rosa, alerta: alerta)]
        }()

        let valorTxt: String = {
            guard let v = valor else { return "—" }
            return "\(Int(v.rounded()))"
        }()
        let sub: String? = {
            if fantasma { return conociendote() }
            // Lado bueno extremo: z_mal ≤ −2 → «inusualmente bajo» sin alerta (§6).
            if let z = zMal, z <= -2 {
                return String(localized: "unusually low", defaultValue: "unusually low")
            }
            return nil
        }()
        let alertaFinal: CosmosAbiertoModel.Alerta = fantasma ? .ninguna : alerta
        let bpm = String(localized: "bpm")
        return .init(
            id: "rhr", grupo: 1, lunaRadio: 15, hueLuna: LiquidColor.rosa,
            medidor: .init(radioAnillo: 22, sabor: .desviacion, lunitas: lunitas,
                           fantasma: fantasma),
            valorPartes: [
                .init(texto: valorTxt, hue: LiquidColor.rosa),
                .init(texto: sinDato ? "" : " \(bpm)", hue: LiquidColor.tinta500),
            ],
            valorSize: 22, sublabel: sub,
            rotulo: up(String(localized: "Resting HR"), locale),
            alerta: alertaFinal,
            a11y: a11y("Resting HR", "\(valorTxt) \(bpm)", sub, alertaFinal))
    }

    private static func anclaCarga(razon: Double?, prep: Preparedness.Read?,
                                   locale: Locale) -> CosmosAbiertoModel.Ancla {
        let alertaG = HoyGramatica.severidad(senal: .carga, prep: prep, razonCarga: razon)
        let alerta = mapAlerta(alertaG)
        let fantasma = razon == nil
        let p = razon.map { HoyGramatica.pCarga(razon: $0) }
        let lunitas: [CosmosAbiertoModel.Lunita] = {
            guard !fantasma, let p else { return [] }
            return [.init(p: p, hue: LiquidColor.verdePrimario, alerta: alerta)]
        }()
        let valorTxt: String = {
            guard let r = razon else { return "—" }
            return String(format: "%.2f", r)
        }()
        let estadoKey = HoyGramatica.estadoCarga(razon: razon)
        let sub = resolveCargaEstado(estadoKey)
        let alertaFinal: CosmosAbiertoModel.Alerta = fantasma ? .ninguna : alerta
        return .init(
            id: "carga", grupo: 2, lunaRadio: 14, hueLuna: LiquidColor.verdePrimario,
            medidor: .init(radioAnillo: 21, sabor: .zona, lunitas: lunitas, fantasma: fantasma),
            valorPartes: [.init(texto: valorTxt, hue: LiquidColor.verdePrimario)],
            valorSize: 22, sublabel: sub,
            rotulo: up(String(localized: "Load"), locale),
            alerta: alertaFinal,
            a11y: a11y("Load", valorTxt, sub, alertaFinal))
    }

    private static func anclaEstres(extra: CosmosExtraInputs,
                                    locale: Locale) -> CosmosAbiertoModel.Ancla {
        // SIN medidor (§4). Palabra + «vs tus 7 días». Jamás alerta.
        let palabra: String = {
            guard let s = extra.stress else { return "—" }
            switch StressBand(score: s) {
            case .low:    return String(localized: "Low")
            case .medium: return String(localized: "Moderate")
            case .high:   return String(localized: "High")
            }
        }()
        let sub = String(localized: "vs your 7 days", defaultValue: "vs your 7 days")
        return .init(
            id: "stress", grupo: 2, lunaRadio: 9, hueLuna: LiquidColor.tinta500,
            medidor: nil,
            valorPartes: [.init(texto: palabra, hue: LiquidColor.tinta700)],
            valorSize: 15, sublabel: sub,
            rotulo: up(String(localized: "Stress"), locale),
            alerta: .ninguna,
            a11y: a11y("Stress", palabra, sub, .ninguna))
    }

    private static func anclaVFC(extra: CosmosExtraInputs, prep: Preparedness.Read?,
                                 baseUsable: Bool,
                                 locale: Locale) -> CosmosAbiertoModel.Ancla {
        // VFC: medidor PUNTEADO, jamás alerta (§4/§6, criterio 6).
        let valor = extra.hrv?.value
        let sinDato = valor == nil
        let fantasma = !baseUsable || sinDato
        let zMal: Double? = {
            guard let z = prep?.signals.first(where: { $0.signal == .hrv })?.orientedZ
            else { return nil }
            // betterWhenHigher ⇒ z_mal = −orientedZ (caer es malo).
            return -z
        }()
        let lunitas: [CosmosAbiertoModel.Lunita] = {
            guard !fantasma, let z = zMal else {
                // Sin z pero con valor: lunita al centro (geometría informativa).
                if !fantasma { return [.init(p: 50, hue: LiquidColor.cian)] }
                return []
            }
            let p = HoyGramatica.pDesviacion(zMal: z, zUmbral: HoyGramatica.zUmbralVFC)
            return [.init(p: p, hue: LiquidColor.cian, alerta: .ninguna)]
        }()
        let valorTxt: String = {
            guard let v = valor else { return "—" }
            return "\(Int(v.rounded()))"
        }()
        let sub = fantasma
            ? conociendote()
            : String(localized: "reference", defaultValue: "reference")
        let ms = String(localized: "ms")
        return .init(
            id: "hrv", grupo: 2, lunaRadio: 12, hueLuna: LiquidColor.cian,
            medidor: .init(radioAnillo: 17, sabor: .desviacion, lunitas: lunitas,
                           punteado: true, fantasma: fantasma),
            valorPartes: [
                .init(texto: valorTxt, hue: LiquidColor.cian),
                .init(texto: sinDato ? "" : " \(ms)", hue: LiquidColor.tinta500),
            ],
            valorSize: 20, sublabel: sub,
            rotulo: up(String(localized: "HRV"), locale),
            alerta: .ninguna,   // sagrado: VFC jamás cálida
            a11y: a11y("HRV", "\(valorTxt) \(ms)", sub, .ninguna))
    }

    private static func anclaEsfuerzo(extra: CosmosExtraInputs,
                                      locale: Locale) -> CosmosAbiertoModel.Ancla {
        // SIN medidor, SIN alerta. «—» vs «0» sagrado.
        let valorTxt = HoyGramatica.valorODash(extra.strain) { String(format: "%.1f", $0) }
        return .init(
            id: "strain", grupo: 3, lunaRadio: 8, hueLuna: LiquidColor.teal,
            medidor: nil,
            valorPartes: [.init(texto: valorTxt, hue: LiquidColor.tinta900)],
            valorSize: 18,
            rotulo: up(String(localized: "Strain"), locale),
            alerta: .ninguna,
            a11y: a11y("Strain", valorTxt, nil, .ninguna))
    }

    private static func anclaPasos(extra: CosmosExtraInputs,
                                   locale: Locale) -> CosmosAbiertoModel.Ancla {
        let valorTxt = HoyGramatica.valorODash(extra.steps) { HoyGramatica.formatoMiles($0) }
        return .init(
            id: "steps", grupo: 3, lunaRadio: 8, hueLuna: LiquidColor.tinta500,
            medidor: nil,
            valorPartes: [.init(texto: valorTxt, hue: LiquidColor.tinta900)],
            valorSize: 18,
            rotulo: up(String(localized: "Steps"), locale),
            alerta: .ninguna,
            a11y: a11y("Steps", valorTxt, nil, .ninguna))
    }

    // MARK: Helpers

    private static func mapAlerta(_ a: HoyGramatica.Alerta) -> CosmosAbiertoModel.Alerta {
        switch a {
        case .ninguna: return .ninguna
        case .atencion: return .atencion
        case .alarma: return .alarma
        }
    }

    private static func resolveCargaEstado(_ key: String) -> String {
        switch key {
        case "carga.estable":     return String(localized: "stable", defaultValue: "stable")
        case "carga.subiendo":    return String(localized: "rising", defaultValue: "rising")
        case "carga.descargando": return String(localized: "unloading", defaultValue: "unloading")
        case "carga.pico":        return String(localized: "peak", defaultValue: "peak")
        case "carga.calibrando":  return String(localized: "calibrating", defaultValue: "calibrating")
        default: return key
        }
    }

    private static func conociendote() -> String {
        String(localized: "getting to know you", defaultValue: "getting to know you")
    }

    private static func up(_ s: String, _ locale: Locale) -> String {
        s.uppercased(with: locale)
    }

    private static func a11y(_ nombre: String, _ valor: String, _ sub: String?,
                             _ alerta: CosmosAbiertoModel.Alerta) -> String {
        var parts = [nombre, valor]
        if let sub { parts.append(sub) }
        switch alerta {
        case .ninguna: break
        case .atencion: parts.append(String(localized: "attention", defaultValue: "attention"))
        case .alarma: parts.append(String(localized: "alarm", defaultValue: "alarm"))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private static func filaHoy(_ i: MatrizInputs) -> DailyMetric? {
        let f = DateFormatter()
        f.calendar = i.calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = i.calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        let key = f.string(from: i.now)
        return i.diasRecientes.last(where: { $0.day == key }) ?? i.diasRecientes.last
    }
}
