import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - MetricInfo

/// Data model for the "tap a metric to learn more" bottom sheet.
/// Each metric defines its bands (fixed ranges) and which band is active for the user's current
/// value. Colour is NOT baked here — the sheet resolves every hue from the live «Instrumento»
/// theme (FER-162), so the same model recolours by time of day on warm paper.
struct MetricInfo: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let headline: LocalizedStringKey
    let displayValue: String
    let unit: String?
    /// How the header numeral is tinted, resolved against the theme by the sheet.
    let headerTint: Tint
    let bands: [Band]
    let note: LocalizedStringKey?

    // Progressive-disclosure extras for composite metrics (Recovery; reused by HRV in FER-109).
    // All optional with defaults so the band-based factories above stay untouched.
    /// «Qué la movió hoy» (FER-628): today's per-signal contributions to the recovery score, computed
    /// against the band-only baseline (the same slice the persisted score folds — FER-519/FER-629).
    /// nil hides the block (calibrating, no band reading today, or any non-recovery metric).
    var impact: RecoveryImpact.Result? = nil
    var method: Method? = nil
    var disclaimer: LocalizedStringKey? = nil
    var calibration: Calibration? = nil

    /// When set, the summary sheet renders the F6 levels instrument (`MetricLevelsExplorer`: a tappable
    /// levels list + range selector + chart over the active band) instead of the static 14-day trend +
    /// bands table, and its foot link reads «Ver más en Tendencias». Drives the per-metric levels from
    /// `MetricLevels` (FER-570). nil → the classic summary, untouched. Pilot: resting HR only. (FER-607)
    var levelsMetric: MetricLevels.FixedMetric? = nil

    /// The raw today value (in the metric's own domain) that highlights the active level — passed
    /// explicitly instead of parsing `displayValue`, which is formatted for several metrics (SpO₂ «97%»,
    /// Sleep «7h 18m», Steps «8,240»). Set alongside `levelsMetric` (or `levelsRelative`). (FER-617)
    var levelsTodayValue: Double? = nil

    /// HRV has no honest universal cut, so its levels are PERSONAL — below / in your base / above,
    /// derived from the user's own baseline rather than a fixed table. Set true on the HRV factory; the
    /// sheet builds the band from the loaded series via `Baselines`. (FER-619 · Plews 2013)
    var levelsRelative: Bool = false

    /// Whether this metric shows the F6 levels instrument at all — a fixed table (`levelsMetric`) or a
    /// personal band (`levelsRelative`). Gates the body, header, foot link and detent. (FER-619)
    var usesLevels: Bool { levelsMetric != nil || levelsRelative }

    /// A semantic tint for the header numeral, resolved against the «Instrumento» theme by the sheet.
    /// `metric` = the metric's own data hue; `neutral` = quiet ink (used for the "—" no-data state);
    /// `good`/`warn`/`bad` = the verdict/warning/critical roles (recovery's banded score). (FER-162)
    enum Tint { case metric, neutral, good, warn, bad }

    struct Band {
        let label: LocalizedStringKey
        let range: String
        var isActive: Bool
        /// Numeric bounds as a half-open interval [lower, upper); `nil` = open on that side. Only filled
        /// for sleep & stress (FER-244) so their trend chart can draw the active band + count days in it;
        /// every other metric leaves them `nil` and the chart stays band-less. Units match the chart's:
        /// sleep in HOURS, stress in score (0–3).
        var lower: Double? = nil
        var upper: Double? = nil
    }

    /// The "See the method" disclosure: plain-language prose plus an optional citation line.
    struct Method {
        let prose: LocalizedStringKey
        let citation: LocalizedStringKey?
    }

    /// Cold-start: recovery isn't scored yet, so show progress toward the seed gate instead
    /// of a number.
    struct Calibration {
        let done: Int
        let needed: Int
    }
}

// MARK: - Static factories

extension MetricInfo {

    static func strain(_ value: Double?) -> MetricInfo {
        // Bounds filled (FER-859) so the Detalle's history lanes derive from THIS ladder instead of
        // restating the numbers — hero verdict, Niveles table and history stay one source.
        let bands: [Band] = [
            Band(label: "Rest / Light", range: "0 – 7",
                 isActive: value.map { $0 < 7 } ?? false, lower: nil, upper: 7),
            Band(label: "Moderate", range: "7 – 14",
                 isActive: value.map { $0 >= 7 && $0 < 14 } ?? false, lower: 7, upper: 14),
            Band(label: "Hard", range: "14 – 18",
                 isActive: value.map { $0 >= 14 && $0 < 18 } ?? false, lower: 14, upper: 18),
            Band(label: "Extreme", range: "18 – 21",
                 isActive: value.map { $0 >= 18 } ?? false, lower: 18, upper: nil),
        ]
        return MetricInfo(
            id: "strain",
            name: "Day Strain",
            headline: "Cardiovascular load scored 0–21. Each second of the day your heart rate is recorded, it's assigned to a zone (1–5). Higher zones carry more weight. The total is compressed logarithmically so 21 represents a theoretical maximum: a full day at peak intensity.",
            displayValue: value.map { String(format: "%.1f", $0) } ?? "—",
            unit: nil,
            headerTint: value == nil ? .neutral : .metric,
            bands: bands,
            note: nil,
            levelsMetric: .strain,
            levelsTodayValue: value
        )
    }

    static func sleep(_ totalMinutes: Int?) -> MetricInfo {
        let hours = totalMinutes.map { Double($0) / 60.0 }
        let bands: [Band] = [
            Band(label: "Short", range: "< 6 h",
                 isActive: hours.map { $0 < 6 } ?? false, lower: nil, upper: 6),
            Band(label: "Adequate", range: "6 – 7 h",
                 isActive: hours.map { $0 >= 6 && $0 < 7 } ?? false, lower: 6, upper: 7),
            // Half-open to match the chart's band math (TrendBand.contains): exactly 9.00 h reads as
            // Extended in both the table and the chart's bracket, never one each. (FER-244)
            Band(label: "Optimal", range: "7 – 9 h",
                 isActive: hours.map { $0 >= 7 && $0 < 9 } ?? false, lower: 7, upper: 9),
            Band(label: "Extended", range: "> 9 h",
                 isActive: hours.map { $0 >= 9 } ?? false, lower: 9, upper: nil),
        ]
        let display: String
        if let m = totalMinutes {
            let h = m / 60, min = m % 60
            display = min > 0 ? "\(h)h \(min)m" : "\(h)h"
        } else {
            display = "—"
        }
        return MetricInfo(
            id: "sleep",
            name: "Sleep",
            headline: "Total time asleep last night, estimated from movement and heart rate. Sleep contributes ~15% of your recovery score and feeds the strain-to-load balance (ACWR).",
            displayValue: display,
            unit: nil,
            headerTint: totalMinutes == nil ? .neutral : .metric,
            bands: bands,
            note: nil,
            levelsMetric: .sleep,
            levelsTodayValue: totalMinutes.map(Double.init)
        )
    }

    /// HRV (RMSSD, ms). Plain-language headline + the existing "it's personal" note, plus a
    /// "See the method" disclosure (reusing FER-108's component) with the real cleaning pipeline.
    /// When there's no reading, the note explains why instead of leaving a bare "—". (FER-109)
    static func hrv(_ value: Double?) -> MetricInfo {
        MetricInfo(
            id: "hrv",
            name: "HRV",
            headline: "HRV is how much the time between your heartbeats varies, in milliseconds, while you sleep. More variation usually means better recovery. What matters isn't the number itself, but how it compares with your own average.",
            displayValue: value.map { "\(Int($0.rounded()))" } ?? "—",
            unit: String(localized: "ms"),
            headerTint: value == nil ? .neutral : .metric,
            bands: [],
            note: value == nil
                ? "No HRV from last night. That can happen if you didn't wear the strap, or the night was too short to gather 20 clean beats."
                : "HRV is personal. There are no universal good/bad thresholds: only your trend over time.",
            method: Method(
                prose: "We take the intervals between your heartbeats overnight, drop any outside 300–2000 ms and any that deviate more than 20% from their neighbours (ectopic beats). If at least 20 clean beats remain, we compute RMSSD.",
                citation: "RMSSD (Task Force, 1996); ectopic rejection by Malik's rule. HRV is about 60% of your recovery score."
            ),
            levelsTodayValue: value,
            levelsRelative: true
        )
    }

    static func restingHR(_ value: Int?) -> MetricInfo {
        let lpm = String(localized: "bpm")
        let bands: [Band] = [
            Band(label: "Athlete", range: "< 50 \(lpm)",
                 isActive: value.map { $0 < 50 } ?? false, lower: nil, upper: 50),
            Band(label: "Excellent", range: "50 – 60 \(lpm)",
                 isActive: value.map { $0 >= 50 && $0 < 60 } ?? false, lower: 50, upper: 60),
            Band(label: "Normal", range: "60 – 80 \(lpm)",
                 isActive: value.map { $0 >= 60 && $0 < 80 } ?? false, lower: 60, upper: 80),
            Band(label: "Elevated", range: "> 80 \(lpm)",
                 isActive: value.map { $0 >= 80 } ?? false, lower: 80, upper: nil),
        ]
        return MetricInfo(
            id: "rhr",
            name: "Resting HR",
            headline: "Your heart rate when your body is fully at rest: how hard your heart has to work doing nothing. Lower generally means a stronger, more efficient cardiovascular system. Cénit uses it as ~20% of your recovery score; a rise from your norm can signal fatigue or that something's coming on.",
            displayValue: value.map { "\($0)" } ?? "—",
            unit: lpm,
            headerTint: value == nil ? .neutral : .metric,
            bands: bands,
            note: "Measured overnight from your strap; when the strap isn't worn, Cénit uses Apple Health's resting heart rate instead.",
            levelsMetric: .restingHR,
            levelsTodayValue: value.map(Double.init)
        )
    }

    /// Respiratory rate (breaths/min, measured during sleep). No `MetricInfo` factory existed; this
    /// adds one in the same shape as the others (headline + bands + a "See the method" disclosure) so
    /// the unified Detalle de Métrica (FER-185) can reuse it instead of duplicating the copy. Bands are
    /// the typical sleeping-adult ranges; respiration is most informative as a deviation from your own
    /// nightly norm, which the detail's normal-range band shows.
    static func respiratory(_ value: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Low", range: "< 12 rpm",
                 isActive: value.map { $0 < 12 } ?? false, lower: nil, upper: 12),
            Band(label: "Typical", range: "12 – 18 rpm",
                 isActive: value.map { $0 >= 12 && $0 <= 18 } ?? false, lower: 12, upper: 18),
            Band(label: "Elevated", range: "18 – 20 rpm",
                 isActive: value.map { $0 > 18 && $0 <= 20 } ?? false, lower: 18, upper: 20),
            Band(label: "High", range: "> 20 rpm",
                 isActive: value.map { $0 > 20 } ?? false, lower: 20, upper: nil),
        ]
        return MetricInfo(
            id: "resp_rate",
            name: "Respiratory Rate",
            headline: "How many breaths you take per minute while you sleep. It's one of the steadiest signals your body has, so even a small rise from your own normal can be an early sign of strain, illness, or a late, heavy meal.",
            displayValue: value.map { String(format: "%.1f", $0) } ?? "—",
            unit: String(localized: "rpm"),
            headerTint: value == nil ? .neutral : .metric,
            bands: bands,
            note: "Measured overnight from your strap. What matters is the change from your own baseline, not the absolute number.",
            method: Method(
                prose: "We count your breaths across the night from the slow rise and fall in your heart-rate signal (respiratory sinus arrhythmia) and report the nightly mean.",
                citation: "Respiration from RSA in the overnight inter-beat intervals; reported as the nightly mean."
            ),
            levelsMetric: .respiration,
            levelsTodayValue: value
        )
    }

    // MARK: - Sleep night metrics (FER-227)
    //
    // The "Tonight's metrics" tiles in the Detalle de Sueño open these. Same shape as the seven Today
    // sheets (plain-language headline + reference bands + a 14-day trend the screen feeds). Their data
    // hue is `dataSleep`, resolved in `metricHue` by id; the trend number format is keyed in
    // `trendValueFormat`.

    /// Sleep performance — time asleep vs your personal need, capped at 100%.
    static func sleepPerformance(_ pct: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Low", range: "< 70%", isActive: pct.map { $0 < 70 } ?? false),
            Band(label: "Adequate", range: "70 – 85%", isActive: pct.map { $0 >= 70 && $0 < 85 } ?? false),
            Band(label: "Optimal", range: "85 – 100%", isActive: pct.map { $0 >= 85 } ?? false),
        ]
        return MetricInfo(
            id: "sleep_performance",
            name: "Performance",
            headline: "How much you slept versus what your body needs. At 100% you fully covered last night's need.",
            displayValue: pct.map { "\(Int(min(100, $0).rounded()))%" } ?? "—",
            unit: nil,
            headerTint: pct == nil ? .neutral : .metric,
            bands: bands,
            note: "Your need is your own rolling average of recent nights, never under 7.5 h."
        )
    }

    /// Sleep efficiency — of the time in bed, how much was actually spent asleep.
    static func sleepEfficiency(_ pct: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Low", range: "< 75%", isActive: pct.map { $0 < 75 } ?? false),
            Band(label: "Adequate", range: "75 – 85%", isActive: pct.map { $0 >= 75 && $0 < 85 } ?? false),
            Band(label: "Optimal", range: "> 85%", isActive: pct.map { $0 >= 85 } ?? false),
        ]
        return MetricInfo(
            id: "sleep_efficiency",
            name: "Efficiency",
            headline: "Of the time you spent in bed, how much you actually spent asleep. Above about 85% is considered healthy.",
            displayValue: pct.map { "\(Int($0.rounded()))%" } ?? "—",
            unit: nil,
            headerTint: pct == nil ? .neutral : .metric,
            bands: bands,
            note: nil
        )
    }

    /// Restorative sleep — the share of the night in deep + REM, the stages that do the repair.
    static func sleepRestorative(_ pct: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Low", range: "< 30%", isActive: pct.map { $0 < 30 } ?? false),
            Band(label: "Typical", range: "30 – 50%", isActive: pct.map { $0 >= 30 && $0 <= 50 } ?? false),
            Band(label: "High", range: "> 50%", isActive: pct.map { $0 > 50 } ?? false),
        ]
        return MetricInfo(
            id: "sleep_restorative",
            name: "Restorative",
            headline: "The share of your sleep spent in deep and REM: the stages that physically and mentally restore you. Around 40–50% is typical for a healthy adult.",
            displayValue: pct.map { "\(Int($0.rounded()))%" } ?? "—",
            unit: nil,
            headerTint: pct == nil ? .neutral : .metric,
            bands: bands,
            note: nil
        )
    }

    /// Awakenings — brief surfacing during the night. No bands (no honest universal threshold); the
    /// trend matters more than any single night.
    static func sleepAwakenings(_ count: Int?) -> MetricInfo {
        MetricInfo(
            id: "sleep_awakenings",
            name: "Awakenings",
            headline: "How many times you briefly woke during the night. A few are completely normal: everyone surfaces between sleep cycles.",
            displayValue: count.map { "\($0)" } ?? "—",
            unit: nil,
            headerTint: count == nil ? .neutral : .metric,
            bands: [],
            note: "Brief awakenings are normal and often not remembered. What matters is the trend, not a single night."
        )
    }

    /// Sleep latency — minutes to fall asleep. The onset value isn't in the cache yet, so it usually
    /// reads "—"; the reference bands still teach the healthy range so the sheet is never empty.
    static func sleepLatency(_ minutes: Double?) -> MetricInfo {
        // Half-open bounds [lower, upper) so a value lands in exactly one band. Ranges follow the sleep
        // literature: 10–20 min is the healthy adult norm; falling asleep almost instantly can signal
        // sleep debt, and > 20 min is prolonged onset. (Ohayon 2017)
        let bands: [Band] = [
            Band(label: "Quick", range: "< 10 min",
                 isActive: minutes.map { $0 < 10 } ?? false, lower: nil, upper: 10),
            Band(label: "Healthy", range: "10 – 20 min",
                 isActive: minutes.map { $0 >= 10 && $0 < 20 } ?? false, lower: 10, upper: 20),
            Band(label: "Prolonged", range: "> 20 min",
                 isActive: minutes.map { $0 >= 20 } ?? false, lower: 20, upper: nil),
        ]
        return MetricInfo(
            id: "sleep_latency",
            name: "Latency",
            headline: "How long it took you to fall asleep after lights out. Ten to twenty minutes is a healthy range.",
            displayValue: minutes.map { "\(Int($0.rounded())) min" } ?? "—",
            unit: nil,
            headerTint: minutes == nil ? .neutral : .metric,
            bands: bands,
            note: minutes == nil
                ? "Onset time isn't available for this night yet; it needs the strap's own lights-out mark. The range above is the healthy reference."
                : "One night says little on its own. What matters is whether your typical onset drifts over weeks."
        )
    }

    static func spo2(_ value: Double?) -> MetricInfo {
        // Half-open bounds [lower, upper) so the chart's TrendBand math (FER-244) and the fixed-bands
        // table agree on the edge: exactly 95.0% reads as Normal in both. The 95% floor is the typical
        // healthy adult threshold; < 90% is hypoxemia. (FER-252)
        let bands: [Band] = [
            Band(label: "Normal", range: "95 – 100%",
                 isActive: value.map { $0 >= 95 } ?? false, lower: 95, upper: nil),
            Band(label: "Borderline", range: "90 – 94%",
                 isActive: value.map { $0 >= 90 && $0 < 95 } ?? false, lower: 90, upper: 95),
            Band(label: "Low", range: "< 90%",
                 isActive: value.map { $0 < 90 } ?? false, lower: nil, upper: 90),
        ]
        return MetricInfo(
            id: "spo2",
            name: "Blood Oxygen",
            headline: "Percentage of haemoglobin carrying oxygen in your blood. Healthy adults typically stay above 95%. A drop can indicate altitude effects, sleep apnea, or respiratory illness.",
            displayValue: value.map { String(format: "%.0f", $0) } ?? "—",
            unit: "%",
            headerTint: value == nil ? .neutral : .metric,
            bands: bands,
            note: "Blood oxygen comes from Apple Health. Wrist-based sensors have lower accuracy than medical pulse oximeters: treat values as a trend, not a clinical reading.",
            method: Method(
                prose: "Cénit reads your blood oxygen from Apple Health, your strap senses it optically at the wrist, but Cénit doesn't turn that into a percentage on its own. A healthy adult typically sits at 95–100%; readings below 90% are considered low (hypoxemia). Isolated low nights are usually noise, altitude, a cold, or how the sensor sat. A sustained run of low nights is what's worth a look with a finger pulse oximeter.",
                citation: "Wrist optical sensors are less accurate than medical pulse oximeters: read this as a trend, not a clinical measurement. NOOP is not a medical device."),
            levelsMetric: .bloodOxygen,
            levelsTodayValue: value
        )
    }

    /// Skin temperature — the nightly deviation (°C) from your own baseline, the way the strap reports it
    /// (not an absolute temperature). Modelled like the other vitals: the F6 levels instrument over the
    /// engine's own cut points (`MetricLevels.skinTemp`, ±0.4 / +0.8 °C, mirroring `ReadinessEngine`), so
    /// the summary reads «where today sits vs your base» with the chart + range selector, never a clinical
    /// claim. Blood oxygen used to hold this tile but only ever came from Apple Health; skin temp is a real
    /// on-device band signal at rest, so it earns the slot. (FER-763)
    static func skinTemp(_ value: Double?) -> MetricInfo {
        MetricInfo(
            id: "skin_temp",
            name: "Skin Temperature",
            headline: "The temperature of your skin, read at your wrist while you sleep. It shifts with your circadian rhythm and recovery. What matters isn't the number itself, but how far it sits from your own baseline. A sustained rise can be an early sign of inflammation or a coming illness.",
            displayValue: value.map { String(format: "%+.1f", $0) } ?? "—",
            unit: "°C",
            headerTint: value == nil ? .neutral : .metric,
            bands: [],
            note: value == nil
                ? "No skin temperature last night. That can happen if you didn't wear the strap, or it hasn't gathered enough nights to set your baseline yet."
                : "Measured at your wrist; the deviation from your personal baseline matters more than the absolute value. An isolated reading is usually noise, like a cold room or how the sensor sat. A sustained run is what's worth a look.",
            method: Method(
                prose: "Your strap reads your skin temperature through the night; Cénit averages the worn, asleep portion and compares it with your own recent baseline, so what you see is the deviation in °C, not a raw temperature. Around your base is normal; a sustained rise of roughly +0.4 °C or more is a classic early illness marker, so Cénit flags it as running warm (~+0.4 °C) or well above (~+0.8 °C).",
                citation: "Baseline-relative skin temperature as an early illness signal (cf. Oura ~+0.5 °C). A wrist trend, not a clinical thermometer. NOOP is not a medical device."),
            levelsMetric: .skinTemp,
            levelsTodayValue: value
        )
    }

    /// VO₂max (Apple Health, measured · FER-257). No fixed band table — VO₂max norms are age- & sex-
    /// specific, so the "where you stand" reading lives in the detail's category block (`VO2maxReference`),
    /// not a one-size table here. The method disclosure carries the source (Apple Watch), the reference
    /// method (FRIEND p50, Kaminsky 2015) and the longevity context (Mandsager 2018 / Kodama 2009).
    static func vo2max(_ value: Double?) -> MetricInfo {
        MetricInfo(
            id: "vo2max",
            name: "VO₂ Max",
            headline: "The most oxygen your body can use during hard exercise, per kilo of body weight. It's the single best measure of cardiorespiratory fitness, and one of the best-evidenced predictors of long-term health.",
            displayValue: value.map { String(format: "%.0f", $0) } ?? "—",
            unit: String(localized: "ml/kg/min"),
            headerTint: value == nil ? .neutral : .metric,
            bands: [],
            note: "Measured by your Apple Watch during outdoor walks and runs: it isn't recorded by the strap.",
            method: Method(
                prose: "Your Apple Watch estimates VO₂max from your heart rate and pace during brisk outdoor walks and runs with a good GPS signal, so it updates every so often rather than daily. We read where it sits among healthy adults of your age and sex (the FRIEND reference median), and translate that into a plain band. A higher VO₂max is associated with a lower risk of all-cause mortality: it's one of the best-evidenced markers of long-term health.",
                citation: "Reference: Kaminsky et al., FRIEND Registry (Mayo Clin Proc 2015). Longevity association: Mandsager et al. (JAMA 2018), Kodama et al. (JAMA 2009). A coarse population reference, not a clinical measurement: NOOP is not a medical device.")
        )
    }

    static func steps(_ value: Int?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Sedentary", range: "< 5 000",
                 isActive: value.map { $0 < 5_000 } ?? false, lower: nil, upper: 5_000),
            Band(label: "Light", range: "5 000 – 8 000",
                 isActive: value.map { $0 >= 5_000 && $0 < 8_000 } ?? false, lower: 5_000, upper: 8_000),
            Band(label: "Active", range: "8 000 – 10 000",
                 isActive: value.map { $0 >= 8_000 && $0 < 10_000 } ?? false, lower: 8_000, upper: 10_000),
            Band(label: "Very active", range: "> 10 000",
                 isActive: value.map { $0 >= 10_000 } ?? false, lower: 10_000, upper: nil),
        ]
        return MetricInfo(
            id: "steps",
            name: "Steps",
            headline: "Daily step count. Consistent activity, even a 30-minute walk, supports cardiovascular health, mood, and recovery quality.",
            displayValue: value.map { v in
                let f = NumberFormatter(); f.numberStyle = .decimal
                return f.string(from: NSNumber(value: v)) ?? "\(v)"
            } ?? "—",
            unit: nil,
            headerTint: value == nil ? .neutral : .metric,
            bands: bands,
            note: "Steps come from Apple Health.",
            method: Method(
                prose: "Steps come from Apple Health. The detail reads each day's total and smooths it into a 7-day trend, so weekday/weekend swings don't drown out the direction you're heading. Research links roughly 7,000–9,000 steps a day with lower mortality, with the benefit leveling off beyond that: there is nothing magic about exactly 10,000.",
                citation: "Paluch et al. 2022, Lancet Public Health."),
            levelsMetric: .steps,
            levelsTodayValue: value.map(Double.init)
        )
    }

    /// Stress (0–3) — the same transparent autonomic proxy `StressView` shows, reachable from the new
    /// Today tile (FER-180). Banded LOW (0–1) · MEDIUM (1–2) · HIGH (2–3); the header numeral is tinted
    /// by the band (low → verdict green, medium → warning, high → critical), mirroring the tile. A
    /// plain-language headline plus a "See the method" disclosure with the z-score derivation keep it
    /// consistent with the other seven sheets.
    static func stress(_ score: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Low", range: "0 – 1",
                 isActive: score.map { $0 < 1 } ?? false, lower: nil, upper: 1),
            Band(label: "Medium", range: "1 – 2",
                 isActive: score.map { $0 >= 1 && $0 < 2 } ?? false, lower: 1, upper: 2),
            Band(label: "High", range: "2 – 3",
                 isActive: score.map { $0 >= 2 } ?? false, lower: 2, upper: nil),
        ]
        // WHOOP-style band → header tint, matching TodayView's stress tile (low green, medium amber,
        // high red). Reserved roles, never the StressView blue→amber ramp (that's its own gauge).
        let tint: Tint = score.map { s in
            switch s {
            case ..<1:  return .good
            case ..<2:  return .warn
            default:    return .bad
            }
        } ?? .neutral
        return MetricInfo(
            id: "stress",
            name: "Stress",
            headline: "Your autonomic load today, from 0 to 3. We estimate it by comparing today's resting heart rate and HRV with your own 30-day baseline: a higher-than-usual resting HR and a lower-than-usual HRV both push the number up: classic signs your body is activated.",
            displayValue: score.map { String(format: "%.1f", $0) } ?? "—",
            unit: score == nil ? nil : "/ 3",
            headerTint: tint,
            bands: bands,
            note: "Derived from your overnight resting heart rate and HRV: a transparent proxy for autonomic load, not a clinical stress measure.",
            method: Method(
                prose: "We take today's resting heart rate and HRV and express each as how far it sits from your 30-day average (a z-score). A resting HR above your norm and an HRV below it both add to the load; the two are summed and squashed onto a 0–3 scale where 0 is calm, 1.5 is your baseline, and 3 is highly activated.",
                citation: "Combined resting-HR / HRV z-score through a logistic curve; HRV via RMSSD (Task Force, 1996)."
            ),
            levelsMetric: .stress,
            levelsTodayValue: score
        )
    }

    /// Heart Rate — today's continuous HR off the strap's own ~1Hz history. No bands (a personalized
    /// zone model would need the user's HRmax — out of scope), so the body is just one context line +
    /// the 24h curve. Distinct from Resting HR (the night's low), which keeps its own banded sheet.
    /// (FER-137)
    static func heartRate(avgBpm: Int?) -> MetricInfo {
        MetricInfo(
            id: "heart_rate",
            name: "Heart Rate",
            headline: "Your heart rate across the day, averaged in 5-minute buckets.",
            displayValue: avgBpm.map { "\($0)" } ?? "—",
            unit: String(localized: "bpm"),
            headerTint: avgBpm == nil ? .neutral : .metric,
            bands: [],
            note: nil,
            method: Method(
                prose: "We average your heart rate in 5-minute buckets across the day, from midnight. Your resting heart rate, the low while you sleep, is its own metric. The zones split the day by how hard your heart worked, as a percentage of your estimated maximum heart rate (zone 1 is 50–60%, zone 5 is 90–100%).",
                citation: "Max HR estimated by Tanaka et al. (2001): 208 − 0.7 × age.")
        )
    }

    /// Recovery (0–100) is a weighted composite, not a banded range, so it gets its own body:
    /// «Qué la movió hoy» (today's per-signal impact, FER-628) + a "See the method" disclosure
    /// (where the exact weights and the σ language now live). While the baseline is still seeding
    /// (`calibrationNights` non-nil) it shows honest progress instead of a made-up number. The
    /// header numeral is tinted by the WHOOP recovery band (green ≥67 · yellow 34–67 · red <34),
    /// mirroring TodayView's `recoveryDataColor`. (FER-108 / FER-162)
    static func recovery(score: Int?, calibrationNights: Int?, nightsNeeded: Int,
                         impact: RecoveryImpact.Result? = nil) -> MetricInfo {
        let disclaimer: LocalizedStringKey = "It's an estimate, not a diagnosis."

        if let done = calibrationNights {
            return MetricInfo(
                id: "recovery",
                name: "Recovery",
                headline: "We can't score your recovery yet. We need at least \(nightsNeeded) nights with your strap to learn your baseline; you're at \(done) of \(nightsNeeded). We'd rather not show you a made-up number.",
                displayValue: "\(done)/\(nightsNeeded)",
                unit: nil,
                headerTint: .neutral,
                bands: [],
                note: nil,
                method: nil,
                disclaimer: disclaimer,
                calibration: Calibration(done: done, needed: nightsNeeded)
            )
        }

        // WHOOP recovery bands → header tint (matches TodayView.recoveryDataColor): red <34,
        // yellow 34–67, green ≥67.
        let tint: Tint = score.map { s in
            switch s {
            case ..<34: return .bad
            case ..<67: return .warn
            default:    return .good
            }
        } ?? .neutral

        return MetricInfo(
            id: "recovery",
            name: "Recovery",
            headline: "Your recovery sums up how ready your body is today, from 0 to 100. It blends several signals from your night, your HRV above all, and compares them with your own average from recent weeks, not anyone else's.",
            displayValue: score.map { "\($0)" } ?? "—",
            unit: nil,
            headerTint: tint,
            bands: [],
            note: nil,
            impact: impact,
            method: Method(
                prose: "Each signal becomes a score of how far above or below your personal average it sits (a z-score, in σ). They're averaged with fixed weights, HRV 60%, resting heart rate 20%, sleep 15%, skin temperature 10%, respiration 5%, and mapped onto a 0–100 scale, calibrated so a typical day lands near 58. If a signal is missing on a given night, its weight is shared among the others.",
                citation: "A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996)."
            ),
            disclaimer: disclaimer,
            calibration: nil,
            levelsMetric: .recovery,
            levelsTodayValue: score.map(Double.init)
        )
    }
}
