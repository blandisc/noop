import Foundation

// MARK: - LiquidSheetCopy — claves del catálogo dichas en String
//
// `MetricInfo` entrega `LocalizedStringKey` (name/headline/note/method), del que no se
// puede extraer la clave. El compositor replica las MISMAS claves literales de
// `MetricInfoCatalog` con `String(localized:)` — cero copy nuevo, cero entradas nuevas
// en el catálogo. La PRESENCIA (qué hoja lleva nota/método/disclaimer) la decide el
// modelo (`info.note != nil`, …); este mapa solo resuelve el contenido.
// F6 puede migrar `MetricInfo` a String y borrar este archivo de claves.
// (Extraído de LiquidMetricSheetView.swift para adelgazar el compositor — FER-36.)

enum LiquidSheetCopy {

    /// `info.name` — mismas claves (en es-MX «HRV» ya dice «VFC»).
    static func titulo(_ id: String) -> String {
        switch id {
        case "sleep":             return String(localized: "Sleep")
        case "hrv":               return String(localized: "HRV")
        case "rhr":               return String(localized: "Resting HR")
        case "strain":            return String(localized: "Day Strain")
        case "steps":             return String(localized: "Steps")
        case "skin_temp":         return String(localized: "Skin Temperature")
        case "resp_rate":         return String(localized: "Respiratory Rate")
        case "stress":            return String(localized: "Stress")
        case "spo2":              return String(localized: "Blood Oxygen")
        case "heart_rate":        return String(localized: "Heart Rate")
        case "vo2max":            return String(localized: "VO₂ Max")
        case "sleep_performance": return String(localized: "Performance")
        case "sleep_efficiency":  return String(localized: "Efficiency")
        case "sleep_restorative": return String(localized: "Restorative")
        case "sleep_awakenings":  return String(localized: "Awakenings")
        case "sleep_latency":     return String(localized: "Latency")
        default:
            // B10 · Este `default` es un bug silencioso, no un fallback: una fábrica nueva
            // imprimiría «vo2max» como TÍTULO de la hoja y nadie se enteraría hasta verlo
            // en pantalla. Se avisa, no se aborta: un `assertionFailure` dentro de algo que
            // se evalúa en `body` mata la app en DEBUG — justo el build de las sesiones
            // /inject. (La migración de fondo es F6.)
            #if DEBUG
            print("LiquidSheetCopy · id sin titulo: \(id)")
            #endif
            return id
        }
    }

    /// `info.headline` — mismas claves.
    static func headline(_ info: MetricInfo) -> String {
        switch info.id {
        case "strain":
            return String(localized: "Cardiovascular load scored 0–21. Each second of the day your heart rate is recorded, it's assigned to a zone (1–5). Higher zones carry more weight. The total is compressed logarithmically so 21 represents a theoretical maximum: a full day at peak intensity.")
        case "sleep":
            return String(localized: "Total time asleep last night, estimated from movement and heart rate. Sleep is one of the signals behind your daily verdict.")
        case "hrv":
            return String(localized: "HRV is how much the time between your heartbeats varies, in milliseconds, while you sleep. More variation usually means a nervous system that's better rested. What matters isn't the number itself, but how it compares with your own average.")
        case "rhr":
            return String(localized: "Your heart rate when your body is fully at rest: how hard your heart has to work doing nothing. Lower generally means a stronger, more efficient cardiovascular system. Cénit reads it against your own norm as part of your daily verdict; a rise can signal fatigue or that something's coming on.")
        case "resp_rate":
            return String(localized: "How many breaths you take per minute while you sleep. It's one of the steadiest signals your body has, so even a small rise from your own normal can be an early sign of strain, illness, or a late, heavy meal.")
        case "sleep_performance":
            return String(localized: "How much you slept versus what your body needs. At 100% you fully covered last night's need.")
        case "sleep_efficiency":
            return String(localized: "Of the time you spent in bed, how much you actually spent asleep. Above about 85% is considered healthy.")
        case "sleep_restorative":
            return String(localized: "The share of your sleep spent in deep and REM: the stages that physically and mentally restore you. Around 40–50% is typical for a healthy adult.")
        case "sleep_awakenings":
            return String(localized: "How many times you briefly woke during the night. A few are completely normal: everyone surfaces between sleep cycles.")
        case "sleep_latency":
            return String(localized: "How long it took you to fall asleep after lights out. Ten to twenty minutes is a healthy range.")
        case "spo2":
            return String(localized: "Percentage of haemoglobin carrying oxygen in your blood. Healthy adults typically stay above 95%. A drop can indicate altitude effects, sleep apnea, or respiratory illness.")
        case "skin_temp":
            return String(localized: "The temperature of your skin, read at your wrist while you sleep. It shifts with your circadian rhythm. What matters isn't the number itself, but how far it sits from your own baseline. A sustained rise can be an early sign of inflammation or a coming illness; that's why it's one of the signals behind your daily verdict.")
        case "vo2max":
            return String(localized: "The most oxygen your body can use during hard exercise, per kilo of body weight. It's the single best measure of cardiorespiratory fitness, and one of the best-evidenced predictors of long-term health.")
        case "steps":
            return String(localized: "Daily step count. Consistent activity, even a 30-minute walk, supports cardiovascular health and mood. It's context for your day: it doesn't move your daily verdict or your load balance.")
        case "stress":
            return String(localized: "Your autonomic load today, from 0 to 3. We estimate it by comparing today's resting heart rate and HRV with your own 30-day baseline: a higher-than-usual resting HR and a lower-than-usual HRV both push the number up: classic signs your body is activated.")
        case "heart_rate":
            return String(localized: "Your heart rate across the day, averaged in 5-minute buckets.")
        default:
            return ""
        }
    }

    /// `info.note` — mismas claves; la variante con/sin dato se re-deriva del
    /// `displayValue` (así eligió la factory). Presencia gobernada por `info.note != nil`.
    static func nota(_ info: MetricInfo) -> String? {
        guard info.note != nil else { return nil }
        let sinDato = info.displayValue == "—"
        switch info.id {
        case "hrv":
            return sinDato
                ? String(localized: "No HRV from last night. That can happen if you didn't wear your Apple Watch to sleep, or the night was too short for it to record.")
                : String(localized: "HRV is personal. There are no universal good/bad thresholds: only your trend over time.")
        case "rhr":
            return String(localized: "Measured overnight from your Apple Watch's heart rate; when it isn't worn to sleep, Cénit uses Apple Health's resting heart rate instead.")
        case "resp_rate":
            return String(localized: "Measured overnight from your heart rate during sleep. What matters is the change from your own baseline, not the absolute number.")
        case "sleep_performance":
            return String(localized: "Your need is your own rolling average of recent nights, never under 7.5 h.")
        case "sleep_awakenings":
            return String(localized: "Brief awakenings are normal and often not remembered. What matters is the trend, not a single night.")
        case "sleep_latency":
            return sinDato
                ? String(localized: "Onset time isn't available for this night yet. The range above is the healthy reference.")
                : String(localized: "One night says little on its own. What matters is whether your typical onset drifts over weeks.")
        case "spo2":
            return String(localized: "Blood oxygen comes from Apple Health. Wrist-based sensors have lower accuracy than medical pulse oximeters: treat values as a trend, not a clinical reading.")
        case "skin_temp":
            return sinDato
                ? String(localized: "No skin temperature last night. That can happen if you didn't wear your Apple Watch to sleep, or it hasn't gathered enough nights to set your baseline yet.")
                : String(localized: "Measured at your wrist; the deviation from your personal baseline matters more than the absolute value. An isolated reading is usually noise, like a cold room or how the sensor sat. A sustained run is what's worth a look.")
        case "vo2max":
            return String(localized: "Measured by your Apple Watch during outdoor walks and runs.")
        case "steps":
            return String(localized: "Steps come from Apple Health.")
        case "stress":
            return String(localized: "Derived from your overnight resting heart rate and HRV: a transparent proxy for autonomic load, not a clinical stress measure.")
        default:
            return nil
        }
    }

    /// `info.disclaimer` — solo recovery la trae hoy.
    static func disclaimer(_ info: MetricInfo) -> String? {
        guard info.disclaimer != nil else { return nil }
        return String(localized: "It's an estimate, not a diagnosis.")
    }

    /// `info.method` — mismas claves (prosa + cita). Presencia gobernada por
    /// `info.method != nil` (recovery calibrando NO lo trae, paridad de la factory).
    static func metodo(_ info: MetricInfo) -> (prosa: String, cita: String?)? {
        guard info.method != nil else { return nil }
        switch info.id {
        case "hrv":
            return (String(localized: "The number you see is the HRV Apple records: SDNN, the overall spread of the time between your heartbeats. Your daily verdict reads this same signal against your own baseline. The trend uses a different HRV measure, RMSSD, recomputed from the beat-to-beat intervals of your densest nights; RMSSD tracks the vagal, rest-and-repair branch specifically, while SDNN blends both branches, so the two won't always move together."),
                    String(localized: "SDNN and RMSSD (Task Force, 1996); RMSSD is the vagal recovery measure (Shaffer & Ginsberg, 2017)."))
        case "resp_rate":
            return (String(localized: "We count your breaths across the night from the slow rise and fall in your heart-rate signal (respiratory sinus arrhythmia) and report the nightly mean."),
                    String(localized: "Respiration from RSA in the overnight inter-beat intervals; reported as the nightly mean."))
        case "spo2":
            return (String(localized: "Cénit reads your blood oxygen from Apple Health; the Apple Watch senses it optically at the wrist. A healthy adult typically sits at 95–100%; readings below 90% are considered low (hypoxemia). Isolated low nights are usually noise, altitude, a cold, or how the sensor sat. A sustained run of low nights is what's worth a look with a finger pulse oximeter."),
                    String(localized: "Wrist optical sensors are less accurate than medical pulse oximeters: read this as a trend, not a clinical measurement. Cénit is not a medical device."))
        case "skin_temp":
            return (String(localized: "Your Apple Watch reads your skin temperature through the night; Cénit averages the worn, asleep portion and compares it with your own recent baseline, so what you see is the deviation in °C, not a raw temperature. Around your base is normal; a sustained rise of roughly +0.4 °C or more is a classic early illness marker, so Cénit flags it as running warm (~+0.4 °C) or well above (~+0.8 °C)."),
                    String(localized: "Baseline-relative skin temperature as an early illness signal (cf. Oura ~+0.5 °C). A wrist trend, not a clinical thermometer. Cénit is not a medical device."))
        case "vo2max":
            return (String(localized: "Your Apple Watch estimates VO₂max from your heart rate and pace during brisk outdoor walks and runs with a good GPS signal, so it updates every so often rather than daily. We read where it sits among healthy adults of your age and sex (the FRIEND reference median), and translate that into a plain band. A higher VO₂max is associated with a lower risk of all-cause mortality: it's one of the best-evidenced markers of long-term health."),
                    String(localized: "Reference: Kaminsky et al., FRIEND Registry (Mayo Clin Proc 2015). Longevity association: Mandsager et al. (JAMA 2018), Kodama et al. (JAMA 2009). A coarse population reference, not a clinical measurement: Cénit is not a medical device."))
        case "steps":
            return (String(localized: "Steps come from Apple Health. The detail reads each day's total and smooths it into a 7-day trend, so weekday/weekend swings don't drown out the direction you're heading. Research links roughly 7,000–9,000 steps a day with lower mortality, with the benefit leveling off beyond that: there is nothing magic about exactly 10,000."),
                    String(localized: "Paluch et al. 2022, Lancet Public Health."))
        case "stress":
            return (String(localized: "We take today's resting heart rate and HRV and express each as how far it sits from your 30-day average (a z-score). A resting HR above your norm and an HRV below it both add to the load; the two are summed and squashed onto a 0–3 scale where 0 is calm, 1.5 is your baseline, and 3 is highly activated."),
                    String(localized: "Combined resting-HR / HRV z-score through a logistic curve; HRV via RMSSD (Task Force, 1996)."))
        case "heart_rate":
            return (String(localized: "We average your heart rate in 5-minute buckets across the day, from midnight. Your resting heart rate, the low while you sleep, is its own metric. The zones split the day by how hard your heart worked, as a percentage of your estimated maximum heart rate (zone 1 is 50–60%, zone 5 is 90–100%)."),
                    String(localized: "Max HR estimated by Tanaka et al. (2001): 208 − 0.7 × age."))
        default:
            return nil
        }
    }
}
