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
        let bands: [Band] = [
            Band(label: "Rest / Light", range: "0 – 7",
                 isActive: value.map { $0 < 7 } ?? false),
            Band(label: "Moderate", range: "7 – 14",
                 isActive: value.map { $0 >= 7 && $0 < 14 } ?? false),
            Band(label: "Hard", range: "14 – 18",
                 isActive: value.map { $0 >= 14 && $0 < 18 } ?? false),
            Band(label: "Extreme", range: "18 – 21",
                 isActive: value.map { $0 >= 18 } ?? false),
        ]
        return MetricInfo(
            id: "strain",
            name: "Day Strain",
            headline: "Cardiovascular load scored 0–21. Each second of the day your heart rate is recorded, it's assigned to a zone (1–5). Higher zones carry more weight. The total is compressed logarithmically so 21 represents a theoretical maximum — a full day at peak intensity.",
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
                : "HRV is personal. There are no universal good/bad thresholds — only your trend over time.",
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
            headline: "Your heart rate when your body is fully at rest — how hard your heart has to work doing nothing. Lower generally means a stronger, more efficient cardiovascular system. Cénit uses it as ~20% of your recovery score; a rise from your norm can signal fatigue or that something's coming on.",
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
            headline: "The share of your sleep spent in deep and REM — the stages that physically and mentally restore you. Around 40–50% is typical for a healthy adult.",
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
            headline: "How many times you briefly woke during the night. A few are completely normal — everyone surfaces between sleep cycles.",
            displayValue: count.map { "\($0)" } ?? "—",
            unit: nil,
            headerTint: count == nil ? .neutral : .metric,
            bands: [],
            note: "Brief awakenings are normal and often not remembered. What matters is the trend, not a single night."
        )
    }

    /// Sleep latency — minutes to fall asleep. Shown only when the night carries an onset latency.
    static func sleepLatency(_ minutes: Double?) -> MetricInfo {
        MetricInfo(
            id: "sleep_latency",
            name: "Latency",
            headline: "How long it took you to fall asleep after lights out. Ten to twenty minutes is a healthy range.",
            displayValue: minutes.map { "\(Int($0.rounded())) min" } ?? "—",
            unit: nil,
            headerTint: minutes == nil ? .neutral : .metric,
            bands: [],
            note: nil
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
            note: "Blood oxygen comes from Apple Health. Wrist-based sensors have lower accuracy than medical pulse oximeters — treat values as a trend, not a clinical reading.",
            method: Method(
                prose: "Cénit reads your blood oxygen from Apple Health — your strap senses it optically at the wrist, but Cénit doesn't turn that into a percentage on its own. A healthy adult typically sits at 95–100%; readings below 90% are considered low (hypoxemia). Isolated low nights are usually noise — altitude, a cold, or how the sensor sat. A sustained run of low nights is what's worth a look with a finger pulse oximeter.",
                citation: "Wrist optical sensors are less accurate than medical pulse oximeters — read this as a trend, not a clinical measurement. NOOP is not a medical device."),
            levelsMetric: .bloodOxygen,
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
            headline: "The most oxygen your body can use during hard exercise, per kilo of body weight. It's the single best measure of cardiorespiratory fitness — and one of the best-evidenced predictors of long-term health.",
            displayValue: value.map { String(format: "%.0f", $0) } ?? "—",
            unit: String(localized: "ml/kg/min"),
            headerTint: value == nil ? .neutral : .metric,
            bands: [],
            note: "Measured by your Apple Watch during outdoor walks and runs — it isn't recorded by the WHOOP strap.",
            method: Method(
                prose: "Your Apple Watch estimates VO₂max from your heart rate and pace during brisk outdoor walks and runs with a good GPS signal, so it updates every so often rather than daily. We read where it sits among healthy adults of your age and sex (the FRIEND reference median), and translate that into a plain band. A higher VO₂max is associated with a lower risk of all-cause mortality — it's one of the best-evidenced markers of long-term health.",
                citation: "Reference: Kaminsky et al., FRIEND Registry (Mayo Clin Proc 2015). Longevity association: Mandsager et al. (JAMA 2018), Kodama et al. (JAMA 2009). A coarse population reference, not a clinical measurement — NOOP is not a medical device.")
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
            headline: "Daily step count. Consistent activity — even a 30-minute walk — supports cardiovascular health, mood, and recovery quality.",
            displayValue: value.map { v in
                let f = NumberFormatter(); f.numberStyle = .decimal
                return f.string(from: NSNumber(value: v)) ?? "\(v)"
            } ?? "—",
            unit: nil,
            headerTint: value == nil ? .neutral : .metric,
            bands: bands,
            note: "Steps come from Apple Health.",
            method: Method(
                prose: "Steps come from Apple Health. The detail reads each day's total and smooths it into a 7-day trend, so weekday/weekend swings don't drown out the direction you're heading. Research links roughly 7,000–9,000 steps a day with lower mortality, with the benefit leveling off beyond that — there is nothing magic about exactly 10,000.",
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
            headline: "Your autonomic load today, from 0 to 3. We estimate it by comparing today's resting heart rate and HRV with your own 30-day baseline: a higher-than-usual resting HR and a lower-than-usual HRV both push the number up — classic signs your body is activated.",
            displayValue: score.map { String(format: "%.1f", $0) } ?? "—",
            unit: score == nil ? nil : "/ 3",
            headerTint: tint,
            bands: bands,
            note: "Derived from your overnight resting heart rate and HRV — a transparent proxy for autonomic load, not a clinical stress measure.",
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
                prose: "We average your heart rate in 5-minute buckets across the day, from midnight. Your resting heart rate — the low while you sleep — is its own metric. The zones split the day by how hard your heart worked, as a percentage of your estimated maximum heart rate (zone 1 is 50–60%, zone 5 is 90–100%).",
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
            headline: "Your recovery sums up how ready your body is today, from 0 to 100. It blends several signals from your night — your HRV above all — and compares them with your own average from recent weeks, not anyone else's.",
            displayValue: score.map { "\($0)" } ?? "—",
            unit: nil,
            headerTint: tint,
            bands: [],
            note: nil,
            impact: impact,
            method: Method(
                prose: "Each signal becomes a score of how far above or below your personal average it sits (a z-score, in σ). They're averaged with fixed weights — HRV 60%, resting heart rate 20%, sleep 15%, skin temperature 10%, respiration 5% — and mapped onto a 0–100 scale, calibrated so a typical day lands near 58. If a signal is missing on a given night, its weight is shared among the others.",
                citation: "A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996)."
            ),
            disclaimer: disclaimer,
            calibration: nil,
            levelsMetric: .recovery,
            levelsTodayValue: score.map(Double.init)
        )
    }
}

// MARK: - MetricInfoSheet

struct MetricInfoSheet: View {
    let info: MetricInfo

    /// The active «Instrumento diurno» theme. Passed explicitly (the theme does NOT propagate through
    /// `.sheet`'s fresh environment), so the sheet renders on the same warm paper as Today, recoloured
    /// by hour. (FER-162)
    var theme: InstrumentoTheme = .base

    /// When true, the metric can be sourced from Apple Health but it isn't connected and there's no
    /// value yet — so the sheet shows a quiet "connect it from Today" line instead of a bare "—".
    /// Strap-only metrics (strain, heart rate) never set this. (FER-162)
    var appleConnectHint: Bool = false

    /// When true, the value currently shown actually came from Apple Health (not the strap) — the sheet
    /// adds a quiet "Apple Health" line with the heart glyph at the foot, so the source reads at a
    /// glance. Resolved dynamically by the caller per reading (never hardcoded per metric), so a strap
    /// reading and an Apple fallback for the same metric badge differently.
    var appleSource: Bool = false

    /// Loads today's accumulated-strain curve. Supplied only for the Day Strain sheet; nil for every
    /// other metric (and on macOS). Run lazily when the sheet appears. (FER-110)
    var strainCurveLoader: (() async -> [TrendPoint])? = nil

    /// FER-730 §5 · «Hoy en tu plan» in the Day Strain summary: the SAME `TrainingBlock` Today's card
    /// shows (routine / rest / streak / pace), so the two never disagree. Supplied only for the strain
    /// sheet; nil (or no split) hides the block. (FER-710)
    var trainingBlock: DailyBrief.TrainingBlock? = nil

    /// The «Empezar» action for the plan block's CTA — opens Entrenar on today's session, mirroring the
    /// Today card. nil hides the CTA (and on a rest day there is none).
    var onStartTraining: (() -> Void)? = nil

    /// FER-732 · today's recommended day-strain ceiling (0–21), a personal recovery-scaled guardrail
    /// (`StrainCeiling`). Supplied only for the strain sheet; nil hides the ceiling line.
    var strainCeiling: Double? = nil

    /// FER-732 · the habitual training window (`TrainingHabit`), derived from past session start hours.
    /// Supplied only for the strain sheet; nil hides the amber band.
    var trainingWindow: TrainingHabit.Window? = nil

    /// Loads today's 24h HR curve (5-minute buckets). Supplied only for the Heart Rate sheet; nil
    /// elsewhere (and on macOS). Run lazily when the sheet appears. (FER-137)
    var heartRateCurveLoader: (() async -> [TrendPoint])? = nil

    /// Loads the 14-day trend for this metric. Supplied for all key metrics; triggers lazily on appear.
    var trendLoader: (() async -> [TrendPoint])? = nil

    /// "Ver más" affordance: when non-nil, a trailing link at the foot of the sheet opens this metric's
    /// rich Detalle (the same screen Cuerpo opens), so Today can drill from the summary into the full
    /// detail in place. nil → no link (metrics without a rich detail destination yet: SpO₂, Heart Rate,
    /// Steps). (FER-251)
    var onSeeMore: (() -> Void)? = nil

    /// Full-history series for the levels instrument (FER-607): `(day, value)` per day with NO 14-day
    /// cutoff, so the range selector (S/M/3M/6M/1A/Todo) can re-window. Supplied only for metrics whose
    /// `info.usesLevels`; nil otherwise. Loaded lazily on appear.
    var levelsSeriesLoader: (() async -> [(day: String, value: Double)])? = nil

    /// FER-710 · «Tu patrón»: the WhatMovesIt findings for this metric, supplied by the caller. Only HRV
    /// and resting HR carry any (the engine returns [] for the rest), so the block hides itself on the
    /// other vitals. Default empty → hidden.
    var whatMovesIt: [WhatMovesItFinding] = []

    /// FER-710 · the sleep summary's rich data (stages, regularity, times) — the SAME model the detail
    /// builds, supplied by the caller only for the sleep sheet. nil (or a night-less model) → the sheet
    /// falls back to the shared single-value layout, so no-data / Apple-only states stay unchanged.
    var sleepDetail: SleepDetailModel? = nil

    @State private var strainCurve: [TrendPoint] = []
    @State private var strainLoading = false
    @State private var heartRateCurve: [TrendPoint] = []
    @State private var heartRateLoading = false
    @State private var trendData: [TrendPoint] = []
    @State private var trendLoading = false
    /// Measured natural height of the sheet's content — used to size the Day Strain detent to its
    /// content so it never opens taller than it needs to. (FER-112 follow-up)
    @State private var contentHeight: CGFloat = 0

    /// "See the method" disclosure — collapsed each time the sheet opens. (FER-108)
    @State private var methodExpanded = false

    /// The plain-language explanation (`info.headline`) is hidden behind the header's ⓘ; collapsed each
    /// time the sheet opens so the card reads clean (number first), one tap from the "why". (FER-243)
    @State private var headlineExpanded = false

    /// Range selection + loaded full-history series for the levels instrument (FER-607). Only used when
    /// `info.usesLevels`; the explorer re-windows the series by `levelsRange`. Each `day` is
    /// parsed to a `Date` exactly ONCE on load (not per render) — the same memoization the detail screens
    /// use, since the explorer re-windows on every range/level tap.
    @State private var levelsRange: ExploreRange = .month
    @State private var levelsParsed: MetricWindowMath.Parsed = []

    // MARK: Colour resolution (against the live theme)

    /// The metric's own data hue, from the «Instrumento» theme (the same per-metric colours the
    /// Today rows use for their sparklines). (FER-147 / FER-162)
    private var metricHue: Color {
        switch info.id {
        case "strain":              return theme.dataStrain
        case "sleep":               return theme.dataSleep
        // Detalle de Sueño night metrics share the sleep hue; respiration keeps its SpO₂-family blue
        // (matching its tile). (FER-227)
        case "sleep_performance", "sleep_efficiency", "sleep_restorative",
             "sleep_awakenings", "sleep_latency":
                                    return theme.dataSleep
        case "resp_rate":           return theme.dataSpO2
        case "hrv":                 return theme.dataHrv
        case "heart_rate", "rhr":   return theme.dataHeart
        case "spo2":                return theme.dataSpO2
        case "steps":               return theme.dataSteps
        case "recovery":            return theme.dataRecovery
        // Stress has no single data hue: its bands are tinted by level (verdict/warning/critical), so
        // the active-band highlight follows the header tint — green at LOW, amber at MEDIUM, red at HIGH.
        case "stress":              return tintColor(info.headerTint)
        default:                    return theme.dataRecovery
        }
    }

    /// Resolve a semantic header tint to a concrete theme colour.
    private func tintColor(_ tint: MetricInfo.Tint) -> Color {
        switch tint {
        case .metric:  return metricHue
        case .neutral: return theme.inkSecondary
        case .good:    return theme.verdict
        case .warn:    return theme.warning
        case .bad:     return theme.critical
        }
    }

    /// Line/area gradient for this metric's charts — the metric hue, from translucent to solid, so the
    /// curve reads clearly on warm paper.
    private var chartGradient: Gradient {
        Gradient(colors: [metricHue.opacity(0.5), metricHue])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                header
                if isRecoverySummary {
                    // F2 (FER-710): the redesigned recovery summary — verdict word + zone meter under the
                    // hero, then «Hoy, vs tu normal» ABOVE the level instrument, no vs-ayer line. The
                    // detail (RecoveryDetailScreen, opened by «Ver más en Tendencias») keeps every block.
                    recoveryReading
                    recoveryZoneMeter
                    headlineText
                    if let impact = info.impact, !impact.signals.isEmpty { impactBlock(impact) }
                    levelsBlock
                } else if isVitalTemplate {
                    // F2 (FER-710): the six vitals — data-driven verdict reading under the hero, the level
                    // instrument, then «Tu patrón» (only where WhatMovesIt has an honest finding: HRV / FC).
                    vitalReading
                    headlineText
                    levelsBlock
                    vitalPatternBlock
                } else if isSleepSummary {
                    // F2 (FER-710) §4: doble dato (in place of the numeral) + verdict + «Anoche» stage bar,
                    // the active lane label moved above the selector, then the level instrument + «Para esta
                    // noche». No-night / Apple-only-without-stages fall through to the classic layout below.
                    sleepDobleDato
                    sleepReading
                    headlineText
                    sleepAnocheBlock
                    sleepActiveLaneLabel
                    levelsBlock
                    sleepParaEstaNoche
                } else if isStrainSummary {
                    // F2 (FER-710) + §5 (FER-730): Day Strain — verdict by level, then the intraday
                    // accumulated curve (between the verdict and the selector), the level instrument, and
                    // «Hoy en tu plan».
                    vitalReading
                    headlineText
                    strainIntradaySection
                    levelsBlock
                    if let tb = trainingBlock { strainPlanBlock(tb) }
                } else {
                    headlineText
                    if info.usesLevels {
                        // FER-607: the F6 levels instrument (selector + tappable levels + chart over the
                        // active band) replaces the static 14-day trend + bands table for migrated metrics.
                        levelsBlock
                    } else {
                        if trendLoader != nil { trendSection }
                        // Day Strain's intraday "How today added up" curve sits in the SAME middle slot as
                        // the 14-day trend on every other metric — after the headline, before the reference
                        // bands — so chart placement reads consistently across all sheets. (strain has no
                        // trendLoader, so the two never both appear.)
                        if info.id == "strain" { strainSection }
                        // Heart Rate's 24h curve sits in the same middle slot (it has no 14-day trendLoader,
                        // so the two never both appear). (FER-137)
                        if info.id == "heart_rate" { heartRateSection }
                        if !info.bands.isEmpty {
                            bandsTable
                        }
                    }
                    // Recovery's calibration card + today's impact block ride alongside BOTH layouts — only
                    // Recovery sets them, so they stay invisible on every other metric. With the levels
                    // instrument they sit just below it («qué la movió hoy»). (FER-620 / FER-628)
                    if let calibration = info.calibration { calibrationCard(calibration) }
                    if let impact = info.impact, !impact.signals.isEmpty { impactBlock(impact) }
                }
                if let method = info.method { methodDisclosure(method) }
                if appleConnectHint {
                    appleConnectLine
                } else if let note = info.note {
                    Text(note)
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let disclaimer = info.disclaimer {
                    Text(disclaimer)
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if appleSource { appleSourceLine }
                if let onSeeMore { seeMoreLink(onSeeMore) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: SheetContentHeightKey.self, value: g.size.height)
            })
        }
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
        .background(theme.paper)
        .presentationDetents(strainDetents)
        .presentationDragIndicator(.visible)
        .modifier(PresentationBackgroundModifier(paper: theme.paper))
        .task {
            guard info.id == "strain", let loader = strainCurveLoader else { return }
            strainLoading = true
            strainCurve = await loader()
            strainLoading = false
        }
        .task {
            guard info.id == "heart_rate", let loader = heartRateCurveLoader else { return }
            heartRateLoading = true
            heartRateCurve = await loader()
            heartRateLoading = false
        }
        .task {
            guard let loader = trendLoader else { return }
            trendLoading = true
            trendData = await loader()
            trendLoading = false
        }
        .task {
            // Full-history series for the levels instrument (FER-607) — no 14-day cutoff, so the range
            // selector can re-window. Parse each day to a `Date` ONCE here, not per render. Supplied only
            // when `info.usesLevels`.
            guard let loader = levelsSeriesLoader else { return }
            levelsParsed = await loader().map {
                (day: $0.day, date: Repository.parseDayKey($0.day), value: $0.value)
            }
        }
    }

    /// Sheets with a trend chart (or the strain accumulation curve) are sized to their content so the
    /// chart is never cut off. Falls back to `.large` until the first layout pass measures the height.
    /// Short, band-only sheets stay at `.medium`. (FER-112 follow-up, extended for trend charts)
    private var strainDetents: Set<PresentationDetent> {
        guard info.id == "strain" || info.id == "heart_rate" || trendLoader != nil
                || info.usesLevels else { return [.medium] }
        return contentHeight > 0 ? [.height(contentHeight)] : [.large]
    }

    /// The datum leads: the name drops to a quiet overline and the value becomes the hero numeral
    /// (rule 1 — one dominant element; rule 4 — name as overline), so the two no longer compete on the
    /// same baseline. Tint still resolves through `headerTint` (band/level/neutral), unchanged. (FER-243)
    private var header: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                if isRedesignedHeader {
                    // F2 (FER-710): recovery / strain / the six vitals / sleep share the Grotesk uppercase
                    // title + ⓘ, retiring the serif title + boxed source chip. A calculated score shows a
                    // «Calculated» origin dot; a measured signal shows its band/Apple dot.
                    Text(info.name).groteskSheetTitle().foregroundStyle(theme.ink)
                    infoButton
                    Spacer()
                    if isCalculatedSummary { originDot("Calculated", color: theme.inkTertiary) }
                    else { vitalOriginDot }
                } else if info.usesLevels {
                    // FER-607 (migrated metric): the title leads in serif (headline role only), with the
                    // ⓘ beside it and the source chip trailing — the handoff header.
                    Text(info.name)
                        .font(StrandFont.serif(23))
                        .foregroundStyle(theme.ink)
                    infoButton
                    Spacer()
                    sourceChip
                } else {
                    Text(info.name)
                        .instrumentoOverline()
                        .foregroundStyle(theme.inkTertiary)
                    Spacer()
                    infoButton
                }
            }
            // The rich sleep summary replaces the single numeral with its own doble-dato (in the body). (FER-710)
            if !isSleepSummary {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                if isCalculatedSummary || isVitalTemplate {
                    // Grotesk 56 numeral + suffix: «/ 100» (recovery, scored) · «/ 21» (strain, scored) ·
                    // the unit (a vital). (FER-710)
                    Text(info.displayValue)
                        .groteskSheetNumeral()
                        .foregroundStyle(tintColor(info.headerTint))
                    if let suffix = calculatedNumeralSuffix {
                        Text(verbatim: suffix).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    } else if isVitalTemplate, let unit = info.unit {
                        Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                } else {
                    Text(info.displayValue)
                        .instrumentoHero(46)
                        .foregroundStyle(tintColor(info.headerTint))
                    if let unit = info.unit {
                        Text(unit)
                            .font(StrandFont.unit)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            }
            }
        }
    }

    /// Recovery + Day Strain: calculated scores that share the Grotesk header with a «Calculated» origin
    /// dot and a «/ max» numeral suffix. (FER-710)
    private var isCalculatedSummary: Bool { info.id == "recovery" || info.id == "strain" }
    /// Any F2-redesigned sheet (recovery / strain / the six vitals / sleep): Grotesk uppercase title, no
    /// serif, an origin dot instead of the boxed source chip. (FER-710)
    private var isRedesignedHeader: Bool { isCalculatedSummary || isVitalTemplate || info.id == "sleep" }
    /// The «/ N» ceiling suffix for a calculated summary's numeral, only when there's a real score. nil for
    /// vitals (they show a unit instead) and for a calibrating/no-data calculated score. (FER-710)
    private var calculatedNumeralSuffix: String? {
        if info.id == "recovery" { return isRecoverySummary ? "/ 100" : nil }
        if info.id == "strain"   { return info.displayValue != "—" ? "/ 21" : nil }
        return nil
    }

    /// The redesigned recovery summary path (F2): a scored recovery reading. Calibrating / no-data
    /// recovery falls through to the shared layout, so those states stay unchanged. (FER-710)
    private var isRecoverySummary: Bool {
        info.id == "recovery" && info.calibration == nil && info.displayValue != "—"
    }

    /// The ⓘ-toggled plain-language explanation, shared by the recovery and classic body layouts.
    @ViewBuilder private var headlineText: some View {
        if headlineExpanded {
            Text(info.headline)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// The redesigned vital template path (F2 §6-11): the six single-signal vitals (HRV · resting HR ·
    /// SpO₂ · steps · stress · respiration) share one Grotesk header + hero skin. Sleep and strain carry
    /// bespoke blocks, so they keep their own layout; recovery has its own path above. (FER-710)
    private static let vitalTemplateIDs: Set<String> = ["hrv", "rhr", "spo2", "steps", "stress", "resp_rate"]
    private var isVitalTemplate: Bool { info.usesLevels && Self.vitalTemplateIDs.contains(info.id) }

    /// The data-origin dot for a redesigned header: a 6px dot in the origin's colour + a short label. The
    /// dot replaces the boxed source chip on these sheets. (FER-710)
    private func originDot(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Source"))
        .accessibilityValue(Text(label))
    }

    /// The vital header's origin dot: the metric hue for a band reading («Band · last night» for a nightly
    /// signal, «Band» otherwise) or the heart hue for an Apple reading — the same provenance signal the
    /// foot line + old chip resolved per reading, so it never lies about where the number came from. (FER-710)
    @ViewBuilder private var vitalOriginDot: some View {
        if appleSource {
            originDot("Apple Health", color: theme.dataHeart)
        } else if BandSummaryCopy.isNightly(metricID: info.id) {
            originDot("Band · last night", color: metricHue)
        } else {
            originDot("Band", color: metricHue)
        }
    }

    /// The active level for today's reading — the same classification the level instrument highlights —
    /// resolved from the metric's levels + today's value. nil with no reading or no levels yet. (FER-710)
    private var activeLevelKey: String? {
        guard let levels = resolvedLevels, let v = info.levelsTodayValue,
              let idx = MetricLevels.activeIndex(for: v, in: levels) else { return nil }
        return levels[idx].key
    }

    /// The vital's data-driven verdict under the hero: a short honest phrase for WHERE today's reading sits
    /// on the metric's own levels — never a fixed direction claim, so it can't contradict the day's data
    /// (repo rule: transparent, honest copy). nil hides it (no reading / no level yet). (FER-710)
    @ViewBuilder private var vitalReading: some View {
        if let phrase = vitalReadingText {
            Text(phrase)
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vitalReadingText: LocalizedStringKey? {
        guard let key = activeLevelKey else { return nil }
        switch (info.id, key) {
        case ("hrv", "above"):        return "Above your base, a good sign."
        case ("hrv", "inBase"):       return "In your usual range."
        case ("hrv", "below"):        return "Below your base, worth a look."
        case ("rhr", "athlete"):      return "Very low, athlete range."
        case ("rhr", "excellent"):    return "Low, a strong sign."
        case ("rhr", "normal"):       return "In a normal range."
        case ("rhr", "elevated"):     return "Above your usual, worth a look."
        case ("spo2", "normal"):      return "In a normal range."
        case ("spo2", "low"):         return "Below the typical range."
        case ("steps", "veryActive"): return "Very active today."
        case ("steps", "active"):     return "Active, a solid day."
        case ("steps", "sedentary"):  return "Quiet so far today."
        case ("stress", "low"):       return "Low, a calm day so far."
        case ("stress", "medium"):    return "Moderate so far today."
        case ("stress", "high"):      return "Running high today."
        case ("resp_rate", "normal"):   return "In a normal range."
        case ("resp_rate", "elevated"): return "Above your usual."
        case ("strain", "rest"):     return "Very light day so far."
        case ("strain", "light"):    return "A light day so far."
        case ("strain", "moderate"): return "A solid, moderate day."
        case ("strain", "hard"):     return "A hard day of load."
        case ("strain", "extreme"):  return "An all-out day."
        default: return nil
        }
    }

    /// The Day Strain summary path (F2 §5): a scored day. No-reading falls through to the classic layout.
    private var isStrainSummary: Bool { info.id == "strain" && info.displayValue != "—" }

    /// «Tu patrón» (FER-710): one honest line per WhatMovesIt finding — a paper block with the metric-hue
    /// left bar (the handoff's «patrón/conexión» shape). Only HRV and resting HR carry findings; for the
    /// other vitals `whatMovesIt` is empty and the block disappears. Copy shared with the detail. (FER-209)
    @ViewBuilder private var vitalPatternBlock: some View {
        if !whatMovesIt.isEmpty {
            HStack(spacing: 0) {
                Rectangle().fill(metricHue).frame(width: 2.5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your pattern").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    ForEach(whatMovesIt) { f in
                        Text(f.phrase)
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                Spacer(minLength: 0)
            }
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Sleep summary (F2 §4, FER-710) — doble dato + stage bar + «para esta noche»

    /// The rich sleep path: a night with stage data. No-night / Apple-only-without-stages fall through to
    /// the shared single-value layout, so those states stay unchanged.
    private var isSleepSummary: Bool { info.id == "sleep" && sleepDetail?.night != nil }

    /// «7:12» from minutes asleep.
    private static func sleepHM(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()); return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// A locale clock «23:38» from a unix timestamp.
    private static func clock(_ ts: Int) -> String { clockFmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }
    private static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("Hmm"); return f
    }()

    /// The two hero numerals — hours asleep | regularity /100 — split by a vertical hairline. Regularity
    /// reads «··» until the engine has enough nights (the numeral never lies). (FER-710)
    private var sleepDobleDato: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.sleepHM(sleepDetail?.night?.stages.asleep ?? 0))
                    .groteskSheetNumeral().foregroundStyle(theme.dataSleep)
                Text("hours asleep").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            Rectangle().fill(theme.hairlineStrong).frame(width: 1, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                if let r = sleepDetail?.regularity {
                    Text(verbatim: "\(r.score)").groteskSheetNumeral().foregroundStyle(theme.dataSleep)
                } else {
                    Text(verbatim: "··").groteskSheetNumeral().foregroundStyle(theme.inkTertiary)
                }
                Text("regularity").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A short honest sleep verdict from the active duration lane, without an em dash. (FER-710)
    @ViewBuilder private var sleepReading: some View {
        if let phrase = sleepReadingText {
            Text(phrase).font(StrandFont.headline).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var sleepReadingText: LocalizedStringKey? {
        switch activeLevelKey {
        case "optimal":  return "Right in your target range."
        case "adequate": return "Enough, close to your target."
        case "short":    return "Short of your target last night."
        case "extended": return "Longer than usual last night."
        default:         return nil
        }
    }

    /// «Anoche»: the stage bar (deep / REM / light / awake) + the onset→wake clock. Deep→REM→Light are one
    /// indigo graded by opacity (no new tokens); awake is quiet ink. (FER-710)
    @ViewBuilder private var sleepAnocheBlock: some View {
        if let night = sleepDetail?.night {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last night").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(verbatim: "\(Self.clock(night.startTs)) → \(Self.clock(night.endTs))")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                }
                SleepStageBar(stages: [
                    .init(minutes: night.stages.deep,  color: theme.dataSleep,               label: String(localized: "Deep")),
                    .init(minutes: night.stages.rem,   color: theme.dataSleep.opacity(0.78), label: String(localized: "REM")),
                    .init(minutes: night.stages.light, color: theme.dataSleep.opacity(0.52), label: String(localized: "Light")),
                    .init(minutes: night.stages.awake, color: theme.hairlineStrong,          label: String(localized: "Awake")),
                ], theme: theme)
            }
        }
    }

    /// The active duration lane label, moved just ABOVE the period selector for sleep (owner's call). (FER-710)
    @ViewBuilder private var sleepActiveLaneLabel: some View {
        if let name = sleepLaneName {
            (Text(name) + Text(verbatim: " · ") + Text("last night"))
                .font(InstrumentoType.groteskLane).tracking(InstrumentoType.groteskLaneTracking)
                .textCase(.uppercase).foregroundStyle(theme.dataSleep)
        }
    }
    /// The active sleep lane's label, from the single key→label home (FER-731); nil when there's no
    /// reading. A sleep sheet's `activeLevelKey` only ever resolves to a sleep level, so the name maps 1:1.
    private var sleepLaneName: LocalizedStringKey? {
        activeLevelKey.map { LocalizedStringKey(MetricLevels.name(for: $0)) }
    }

    /// «Para esta noche»: an honest, non-prescriptive line from regularity — the paper block with the sleep
    /// hue left bar. (FER-710)
    private var sleepParaEstaNoche: some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.dataSleep).frame(width: 2.5)
            VStack(alignment: .leading, spacing: 4) {
                Text("For tonight").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(sleepTonightText).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            Spacer(minLength: 0)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var sleepTonightText: LocalizedStringKey {
        if let r = sleepDetail?.regularity, r.score >= 80 {
            return "Keep to your usual bedtime to hold this rhythm."
        }
        return "A steadier bedtime tonight helps your rhythm."
    }

    /// The plain-language recovery reading under the hero, banded like the detail's (green ready / yellow
    /// controlled / red rest) and written WITHOUT em dashes for the redesigned sheet. (FER-710)
    private var recoveryReading: some View {
        Text(recoveryReadingText)
            .font(StrandFont.headline)
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var recoveryReadingText: LocalizedStringKey {
        switch info.headerTint {
        case .good: return "Above your baseline, ready for a strong day."
        case .warn: return "Recovering, train but keep it controlled."
        case .bad:  return "Low, prioritize rest today."
        default:    return ""
        }
    }

    /// The zone meter (FER-710): today's score placed on the fixed recovery zones (Agotado / Bajo /
    /// Moderado / Alto / Pleno), segment widths ∝ each zone's span of 0–100, the active zone highlighted,
    /// an ink tick at score/100. Colours map the 5 zones onto recovery's 3 band roles (red / amber /
    /// green) so no new tokens are minted; labels reuse the level list's localized names (FER-638: the
    /// 70–88 zone is «Alto», not «A punto»).
    private var recoveryZoneMeter: some View {
        let levels = MetricLevels.levels(for: .recovery)
        let score = info.levelsTodayValue ?? 0
        let activeIndex = MetricLevels.activeIndex(for: score, in: levels)
        let segments = levels.enumerated().map { i, lvl in
            ZoneMeter.Segment(
                weight: (lvl.upper ?? 100) - (lvl.lower ?? 0),
                color: recoveryZoneColor(i),
                isActive: i == activeIndex,
                label: recoveryLevelLabel(lvl.key))
        }
        return ZoneMeter(segments: segments, fraction: score / 100, theme: theme)
    }

    /// The 5 recovery zones mapped onto the 3 band roles: depleted/low → critical, moderate → warning,
    /// primed/peak → verdict. Keeps colour meaningful (red→amber→green) without minting new tokens.
    private func recoveryZoneColor(_ index: Int) -> Color {
        switch index {
        case 0, 1: return theme.critical
        case 2:    return theme.warning
        default:   return theme.verdict
        }
    }

    /// The localized, uppercased zone label, from the single key→label home (`MetricLevels.name(for:)`,
    /// FER-731) so the meter, the level list and the brief never drift — FER-638 keeps the 70–88 key
    /// "primed" reading «Alto», never «A punto». The English name doubles as the `Localizable.xcstrings`
    /// key, so `String(localized:)` resolves the es-MX at runtime. (FER-710)
    private func recoveryLevelLabel(_ key: String) -> String {
        String(localized: String.LocalizationValue(MetricLevels.name(for: key))).localizedUppercase
    }

    /// The ⓘ that toggles the plain-language explanation in place: quiet ink when closed, the metric hue
    /// when open. Extracted so the serif (migrated) and overline (classic) headers share it. (FER-243)
    private var infoButton: some View {
        Button {
            withAnimation(StrandMotion.interactive) { headlineExpanded.toggle() }
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .foregroundStyle(headlineExpanded ? metricHue : theme.inkTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(headlineExpanded ? "Hide explanation" : "Show explanation"))
    }

    /// FER-607: a quiet source chip in the migrated-metric header — «APPLE» (heart hue) when the shown
    /// reading came from Apple Health, «BANDA» (the metric hue) when it came from the strap. Reuses the
    /// same `appleSource` signal the foot line resolves per reading, so it never lies about provenance.
    private var sourceChip: some View {
        let tint = appleSource ? theme.dataHeart : metricHue
        return Text(appleSource ? "APPLE" : "BAND")
            .font(StrandFont.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(appleSource ? "Source · Apple Health" : "Source · band"))
    }

    /// Quiet "this can come from Apple Health" line for an Apple-sourced metric that isn't connected
    /// and has no value yet. No button — the connect action lives in Today (single source of truth);
    /// closing the sheet leaves it one tap away. (FER-162)
    private var appleConnectLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.dataHeart)
            Text("This reading can come from Apple Health. Connect it from Today to see it here.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 0.5))
    }

    /// Quiet provenance line at the foot of the sheet: the displayed reading came from Apple Health (not
    /// the strap). The heart glyph (in the heart data hue) lets the source read at a glance, mirroring the
    /// Today tile's Apple badge. Shown only when `appleSource` — resolved per reading by the caller.
    private var appleSourceLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11))
                .foregroundStyle(theme.dataHeart)
            Text("Apple Health")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Source · Apple Health"))
    }

    /// The F6 levels instrument for a migrated metric (FER-607): the shared `MetricLevelsExplorer` — a
    /// range selector, a «{level} · N de tus últimos M días» phrase, the trend drawn over the active
    /// band, and a tappable levels list — fed by the full-history series (re-windowed by `levelsRange`)
    /// and the per-metric thresholds from `MetricLevels` (FER-570). `todayValue` is the same number the
    /// header shows (`info.displayValue`), so the highlighted level matches the hero numeral.
    @ViewBuilder private var levelsBlock: some View {
        if let levels = resolvedLevels {
            let window = MetricWindowMath.make(levelsParsed, selected: levelsRange)
            MetricLevelsExplorer(
                theme: theme,
                range: $levelsRange,
                window: window,
                levels: levels,
                todayValue: info.levelsTodayValue,
                hue: metricHue,
                unit: info.unit ?? "",
                valueFormat: info.id == "sleep"
                    ? { mins in let h = Int(mins) / 60; let m = Int(mins) % 60; return m == 0 ? "\(h)h" : "\(h)h \(m)m" }
                    : { "\(Int($0.rounded()))" },
                nightly: BandSummaryCopy.isNightly(metricID: info.id),
                accessibilityLabel: info.name
            )
        } else if info.levelsRelative {
            // HRV with no personal baseline yet — an honest note, not an empty levels list.
            emptyWell(icon: "waveform.path.ecg",
                      text: "Your levels come from your own baseline — a few more nights and they'll appear.")
        }
    }

    /// The levels for the explorer: `MetricLevels`' fixed thresholds (FER-570) for a `levelsMetric`, or —
    /// for HRV — the user's PERSONAL band from their own baseline. HRV is log-normal, so the cut points
    /// come from `Baselines.normalRange` (which back-transforms `exp(lnBaseline ± σ)` to ms: a
    /// multiplicative band, not a raw linear ±SD), over the SAME production baseline engine the recovery
    /// score uses (`foldHistory` + `hrvCfg`, logDomain). The band *structure* (below/inBase/above,
    /// guard `nValid >= 1`) mirrors FER-571. nil for HRV until there's at least one valid night.
    /// (FER-619 · Plews 2013)
    private var resolvedLevels: [MetricLevels.Level]? {
        if let metric = info.levelsMetric { return MetricLevels.levels(for: metric) }
        guard info.levelsRelative else { return nil }
        let state = Baselines.foldHistory(levelsParsed.map { Optional($0.value) }, cfg: Baselines.hrvCfg)
        guard state.nValid >= 1 else { return nil }
        let band = Baselines.normalRange(state)
        return [
            MetricLevels.Level(key: "below",  lower: nil,             upper: band.lowerBound),
            MetricLevels.Level(key: "inBase", lower: band.lowerBound, upper: band.upperBound),
            MetricLevels.Level(key: "above",  lower: band.upperBound, upper: nil),
        ]
    }

    private var bandsTable: some View {
        let counts = bandSummary?.counts
        return VStack(spacing: 0) {
            ForEach(Array(info.bands.enumerated()), id: \.offset) { i, band in
                bandRow(band, count: counts.flatMap { i < $0.count ? $0[i] : nil })
                if i < info.bands.count - 1 {
                    Divider().overlay(theme.hairline).padding(.leading, 36)
                }
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One reference-band row. `count` (when the trend has loaded) shows how many of the windowed
    /// days/nights fell in this band — the "días en tu rango" readout, now per band. (FER-459)
    private func bandRow(_ band: MetricInfo.Band, count: Int?) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? metricHue : theme.inkTertiary.opacity(0.45))
                .frame(width: 8, height: 8)
                .padding(.leading, 14)
            Text(band.label)
                .font(StrandFont.subhead)
                .foregroundStyle(band.isActive ? theme.ink : theme.inkSecondary)
            Spacer()
            Text(band.range)
                .font(StrandFont.captionNumber)
                .foregroundStyle(band.isActive ? metricHue : theme.inkTertiary)
            if let count {
                Text(BandSummaryCopy.countLabel(count, nightly: BandSummaryCopy.isNightly(metricID: info.id)))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(band.isActive ? metricHue : theme.inkTertiary.opacity(0.85))
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(band.isActive ? metricHue.opacity(0.12) : Color.clear)
    }

    // MARK: - Band trend summary (FER-459)

    /// Band classification of the loaded 14-day trend — the per-band counts + the summary sentence.
    /// `nil` until the trend loads, or when the metric carries no bands (HRV). Steps' in-progress day is
    /// excluded from the trend (FER-264), so it gets no "today" band → no today clause.
    private var bandSummary: BandTrendSummary? {
        guard !info.bands.isEmpty, !trendData.isEmpty else { return nil }
        // Sleep's bands are in HOURS but its trend is in minutes — convert so the classification lines up
        // (same `toHours` as `bandedTrend`). Every other metric's trend already matches its band units.
        let toHours = info.id == "sleep"
        // Steps' latest point is the in-progress day (FER-264) — drop it so the counts read completed days
        // only, and it carries no "today" band.
        let isSteps = info.id == "steps"
        let sorted = trendData.sorted { $0.date < $1.date }
        let source = (isSteps && sorted.count > 1) ? Array(sorted.dropLast()) : sorted
        let values = source.map { toHours ? $0.value / 60 : $0.value }
        let bands = info.bands.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        let todayIndex = isSteps ? nil : info.bands.firstIndex(where: { $0.isActive })
        return TrendBands.summarize(values: values, bands: bands, todayIndex: todayIndex)
    }

    /// The standardized «{band} · X of the last N days/nights in this range» readout shown above the ranges
    /// table on every summary sheet — the active band = today's band (matching the highlighted row + the
    /// chart; falls back to the latest completed reading), plus how many completed days share it. One
    /// wording everywhere. Nocturnal metrics (sleep, SpO₂) read "nights". (FER-469 / FER-471)
    private var rangeReadout: (label: LocalizedStringKey, count: Int, total: Int)? {
        guard !info.bands.isEmpty, !trendData.isEmpty else { return nil }
        let toHours = info.id == "sleep"
        let isSteps = info.id == "steps"
        let sorted = trendData.sorted { $0.date < $1.date }
        let source = (isSteps && sorted.count > 1) ? Array(sorted.dropLast()) : sorted
        let values = source.map { toHours ? $0.value / 60 : $0.value }
        let bands = info.bands.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        // Active band = today's band (the highlighted row + the chart's shaded band), so the line agrees
        // with both; the count still comes from completed days. Falls back to the most recent completed
        // reading when there's no today value (e.g. no steps yet). (FER-471)
        guard let ai = info.bands.firstIndex(where: { $0.isActive })
            ?? TrendBands.activeBand(values: values, bands: bands)?.index else { return nil }
        let count = values.reduce(0) { $0 + (bands[ai].contains($1) ? 1 : 0) }
        return (info.bands[ai].label, count, values.count)
    }

    @ViewBuilder private var rangeReadoutLine: some View {
        if let r = rangeReadout {
            let nightly = BandSummaryCopy.isNightly(metricID: info.id)
            HStack(spacing: 6) {
                Text(r.label).foregroundStyle(metricHue)
                Text(verbatim: "·").foregroundStyle(theme.inkTertiary)
                Text(nightly ? "\(r.count) of the last \(r.total) nights in this range"
                             : "\(r.count) of the last \(r.total) days in this range")
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(StrandFont.subhead)
        }
    }

    // MARK: - Heart-rate 24h chart (FER-137)

    /// Today's continuous HR curve, a bit taller than the standard chart. Built inline with theme
    /// tokens (rather than the shared, dark `ChartCard`) so it reads on warm paper. Empty curve → an
    /// honest "no readings yet" well (a strap-only day with no wear).
    @ViewBuilder private var heartRateSection: some View {
        if heartRateCurve.count > 1 {
            let v = heartRateCurve.map(\.value)
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beats per minute")
                            .font(StrandFont.headline)
                            .foregroundStyle(theme.ink)
                        Text("5-minute average · since midnight")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                    }
                    Spacer()
                    if let last = v.last {
                        Text("\(Int(last.rounded())) bpm")
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(theme.ink)
                    }
                }
                TrendChart(
                    points: heartRateCurve,
                    gradient: chartGradient,
                    valueRange: Self.hrRange(v),
                    showsArea: true,
                    height: 260,
                    showsScrub: true,
                    valueFormat: { "\(Int($0.rounded())) \(String(localized: "bpm"))" },
                    dateFormat: { Self.hrClock.string(from: $0) },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline,
                    tightTrailing: true
                )
                hrFooter(v)
            }
        } else if heartRateLoading {
            loadingWell(height: 200)
        } else {
            emptyWell(icon: "waveform.path.ecg", text: "No readings yet today.")
        }
    }

    private func hrFooter(_ v: [Double]) -> some View {
        let lo = Int((v.min() ?? 0).rounded())
        let avg = Int((v.reduce(0, +) / Double(max(v.count, 1))).rounded())
        let hi = Int((v.max() ?? 0).rounded())
        return HStack {
            footerStat("Min", "\(lo)")
            Spacer()
            footerStat("Avg", "\(avg)")
            Spacer()
            footerStat("Max", "\(hi)")
        }
    }

    private func footerStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textCase(.uppercase)
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value)
                .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
        }
    }

    /// Padded HR axis range so the line never sits flush against an edge (mirrors TodayView.hrRange).
    private static func hrRange(_ v: [Double]) -> ClosedRange<Double> {
        guard let lo = v.min(), let hi = v.max() else { return 40...120 }
        if hi <= lo { return (lo - 5)...(hi + 5) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    private static let hrClock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h a"; return f
    }()

    // MARK: - 14-day trend chart

    /// "Last 14 days" trend chart shown in the upper section of every key-metric sheet. The chart
    /// auto-scales to the metric's own range so a narrow RHR window (52–58 bpm) still reads as a
    /// clear curve instead of a flat line pinned to 0–200. Line/area use the metric hue. (FER-115 /
    /// FER-162)
    @ViewBuilder private var trendSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Last 14 days")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            // The «{band} · X of N days in this range» readout sits right under the title, contextualizing
            // the period before the chart (instead of floating below it). (FER-473)
            rangeReadoutLine
            if trendData.count > 1 {
                if let bt = bandedTrend {
                    // The «{band} · X of N days in this range» readout now lives once, above the ranges
                    // table (`rangeReadoutLine`), standardized across every metric. (FER-469)
                    TrendChart(
                        points: bt.points,
                        gradient: chartGradient,
                        valueRange: bt.range,
                        showsArea: true,
                        height: 140,
                        showsScrub: true,
                        valueFormat: bt.valueFormat,
                        dateFormat: Self.trendDayString,
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline,
                        bands: bt.bands,
                        bandColor: bt.color,
                        yAxisValues: bt.yTicks
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("14-day trend with classification bands"))
                } else {
                    TrendChart(
                        points: trendData,
                        gradient: chartGradient,
                        valueRange: trendValueRange,
                        showsArea: true,
                        height: 140,
                        showsScrub: true,
                        valueFormat: trendValueFormat,
                        dateFormat: Self.trendDayString,
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline,
                        // HRV has no right-side range labels, so let its curve reach the edge instead of
                        // reserving the band-label gutter. (FER-460)
                        tightTrailing: info.id == "hrv"
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("14-day trend"))
                }
            } else if trendLoading {
                loadingWell(height: 140)
            } else {
                emptyWell(icon: "chart.xyaxis.line", text: "No data for the last 14 days.")
            }
        }
    }

    /// The banded-chart configuration for the metrics whose trend reads against fixed classification
    /// bands (sleep, stress, SpO₂, FC reposo, steps) — today's band shaded (the same one the ranges table
    /// highlights and the readout names, FER-471), the Y range anchored to the band thresholds, ticks at
    /// those thresholds, and a paper-legible value format. Sleep is converted to HOURS here (its series is
    /// stored in minutes); the others keep their own units. `nil` for every other metric (HRV, VO₂max…),
    /// so they keep the plain auto-scaled chart. (FER-244)
    private struct BandedTrend {
        var points: [TrendPoint]
        var bands: [TrendBand]
        var range: ClosedRange<Double>
        var yTicks: [Double]
        var color: Color
        var valueFormat: (Double) -> String
        var activeLabel: LocalizedStringKey
        var count: Int
        var total: Int
    }

    private var bandedTrend: BandedTrend? {
        // The metrics whose summary-sheet trend reads against fixed classification bands, drawn behind the
        // line like sleep/stress — the same family that already carries the ranges table + readout
        // (FER-459/469). Extending it here gives SpO₂, FC reposo and Pasos the labelled carriles their
        // chart was missing, matching sleep/stress.
        let banded: Set<String> = ["sleep", "stress", "spo2", "rhr", "steps"]
        guard banded.contains(info.id), !info.bands.isEmpty, trendData.count > 1 else { return nil }
        let toHours = info.id == "sleep"
        let isSteps = info.id == "steps"
        let sorted = trendData.sorted { $0.date < $1.date }
        let pts = sorted.map { TrendPoint(date: $0.date, value: toHours ? $0.value / 60 : $0.value) }
        let values = pts.map(\.value)
        // Steps' latest point is today's partial total (FER-264): plot every day, but count completed days
        // only so the partial total doesn't inflate the active band's tally.
        let completed = (isSteps && values.count > 1) ? Array(values.dropLast()) : values
        var bands = info.bands.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        // Shade today's band — the same one the ranges table highlights and the readout names (FER-471);
        // fall back to the latest completed reading when there's no usable today.
        guard let activeIdx = info.bands.firstIndex(where: { $0.isActive })
            ?? TrendBands.activeBand(values: completed, bands: bands)?.index else { return nil }
        bands[activeIdx].isActive = true
        let activeCount = completed.reduce(0) { $0 + (bands[activeIdx].contains($1) ? 1 : 0) }
        let thresholds = Set(info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } }).sorted()
        let tLo = thresholds.first ?? (values.min() ?? 0)
        let tHi = thresholds.last ?? (values.max() ?? 1)
        let lo = min(values.min() ?? tLo, tLo)
        let hi = max(values.max() ?? tHi, tHi)
        let pad = max((hi - lo) * 0.08, 0.25)
        let range = max(0, lo - pad)...(hi + pad)
        // Sleep plots in hours (h/m); every other banded metric reuses its standard per-metric formatter
        // (rhr → bpm, spo2 → %, steps → grouped integer, stress → one decimal).
        let fmt: (Double) -> String = toHours
            ? { v in let m = Int((v * 60).rounded()); return m % 60 > 0 ? "\(m / 60)h \(m % 60)m" : "\(m / 60)h" }
            : trendValueFormat
        return BandedTrend(points: pts, bands: bands, range: range, yTicks: thresholds,
                           color: metricHue, valueFormat: fmt,
                           activeLabel: bands[activeIdx].label, count: activeCount, total: completed.count)
    }

    /// Auto-scale: 15% headroom above the max, floor capped at zero.
    private var trendValueRange: ClosedRange<Double> {
        let vals = trendData.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return 0...100 }
        let span = max(hi - lo, 1)
        let pad  = span * 0.15
        return max(0, lo - pad)...hi + pad
    }

    private var trendValueFormat: (Double) -> String {
        switch info.id {
        case "strain":  return { String(format: "%.1f", $0) }
        case "stress":  return { String(format: "%.1f", $0) }   // 0–3 proxy reads with one decimal, not rounded to "2"
        case "sleep":   return { Self.formatSleep(Int($0.rounded())) }
        // Detalle de Sueño night metrics (FER-227): percent shares, a 0.1-rpm respiration, integer wakes.
        case "sleep_performance", "sleep_efficiency", "sleep_restorative":
                        return { "\(Int($0.rounded()))%" }
        case "resp_rate":
                        return { String(format: "%.1f", $0) }
        case "sleep_awakenings":
                        return { "\(Int($0.rounded()))" }
        case "rhr":     return { "\(Int($0.rounded())) \(String(localized: "bpm"))" }
        case "spo2":    return { String(format: "%.0f%%", $0) }
        case "steps":   return { Self.stepFmt.string(from: NSNumber(value: Int($0.rounded()))) ?? "\(Int($0.rounded()))" }
        default:        return { "\(Int($0.rounded()))" }
        }
    }

    private static let trendDayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
    private static func trendDayString(_ date: Date) -> String { trendDayFmt.string(from: date) }

    private static let stepFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    private static func formatSleep(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60, m = totalMinutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    // MARK: - Day-strain accumulation chart (FER-110)

    /// "How today added up" — the day's strain building from 0 to the score in the header. Shows the
    /// curve once loaded, a quiet placeholder while loading, and a short message when there isn't
    /// enough of today's activity to chart.
    @ViewBuilder private var strainSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("How today added up")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            if strainCurve.count > 1 {
                TrendChart(
                    points: strainCurve,
                    gradient: chartGradient,
                    valueRange: strainCurveRange,
                    showsArea: true,
                    height: 132,
                    showsScrub: true,
                    valueFormat: { String(format: "%.1f", $0) },
                    dateFormat: { Self.hourString($0) },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline
                )
                .accessibilityElement()
                .accessibilityLabel(Text("Accumulated day strain, rising through the day."))
            } else if strainLoading {
                loadingWell(height: 132)
            } else {
                emptyWell(icon: "chart.xyaxis.line", text: "Not enough activity yet today to chart.")
            }
        }
    }

    /// Auto-scale the Y axis to the day's own buildup (0 → a little above the peak) so a low-strain
    /// day still reads as a clear curve instead of a flat line pinned to the 0–21 floor.
    private var strainCurveRange: ClosedRange<Double> {
        let peak = strainCurve.map(\.value).max() ?? 1
        return 0...max(peak * 1.15, 1)
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")   // locale hour, 12/24h per region
        return f
    }()
    private static func hourString(_ date: Date) -> String { hourFormatter.string(from: date) }

    // MARK: - Day-strain intraday curve + «Hoy en tu plan» (FER-730 §5)

    /// «Hoy, hora a hora»: today's accumulated strain — solid through the lived portion, a flat dashed
    /// projection from «now» to midnight (strain only accumulates, so the honest projection is «if you
    /// stop here»), a breathing dot at now, and a fixed 00/6/12/18/24 axis. When the real data exists it
    /// also draws the recommended ceiling (`StrainCeiling`, a dashed ink guardrail) and the habitual
    /// training window (`TrainingHabit`, an amber band); each is omitted when its source is absent, so the
    /// curve stays exactly as it was when neither is available. (§5, FER-732)
    @ViewBuilder private var strainIntradaySection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Today, hour by hour").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if strainCurve.count > 1 {
                StrainIntradayCurve(points: strainCurve, hue: theme.dataStrain, theme: theme,
                                    ceiling: strainCeiling, window: trainingWindow)
                    .frame(height: 130)
                    .accessibilityElement()
                    .accessibilityLabel(strainCurveAxLabel)
                HStack(spacing: 16) {
                    curveLegend(dashed: false, label: "lived")
                    curveLegend(dashed: true, label: "projected")
                    if strainCeiling != nil { ceilingLegend }
                    if trainingWindow != nil { windowLegend }
                }
                if strainCeiling != nil {
                    // Honest framing (FER-732 / CSO): the ceiling is a personal reference, not a goal
                    // or a medical instruction, and you can pass it.
                    Text("Your ceiling is a reference from your recent load and how recovered you woke up. It is context, not a goal, and you can go past it.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if strainLoading {
                loadingWell(height: 130)
            } else {
                emptyWell(icon: "chart.xyaxis.line", text: "Not enough activity yet today to chart.")
            }
        }
    }

    /// One legend entry: a short solid swatch, or three dashes, in the strain hue + its label.
    private func curveLegend(dashed: Bool, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(theme.dataStrain.opacity(0.75)).frame(width: 3, height: 2.4)
                    }
                }
            } else {
                Capsule().fill(theme.dataStrain).frame(width: 14, height: 2.4)
            }
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Legend entry for the recommended ceiling: a short dashed ink line. (FER-732)
    private var ceilingLegend: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(theme.inkSecondary.opacity(0.55)).frame(width: 3, height: 1.6)
                }
            }
            Text("ceiling").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Legend entry for the habitual training window: a small amber swatch. (FER-732)
    private var windowLegend: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(theme.warning.opacity(0.14)).frame(width: 14, height: 9)
            Text("your training").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// VoiceOver label for the curve, naming the ceiling / window only when they are actually drawn. (FER-732)
    private var strainCurveAxLabel: Text {
        var s = String(localized: "Accumulated day strain, rising through the day and projected flat to midnight.")
        if strainCeiling != nil {
            s += " " + String(localized: "A dashed line marks your recommended ceiling for today.")
        }
        if trainingWindow != nil {
            s += " " + String(localized: "An amber band marks when you usually train.")
        }
        return Text(s)
    }

    /// «Hoy en tu plan» (§5): the same training block Today's card shows, in a paper block with the strain
    /// left bar — training day (routine + streak + pace + «Empezar» CTA) or rest day. Copy is the shared
    /// es-MX literals Today already ships, so the two surfaces never drift. No em dashes.
    @ViewBuilder private func strainPlanBlock(_ tb: DailyBrief.TrainingBlock) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.dataStrain).frame(width: 2.5)
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Hoy en tu plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                switch tb.state {
                case .training:
                    HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                        Text(tb.routineName ?? "").font(StrandFont.title2).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        planStreakChip(tb.streakDays)
                        Spacer(minLength: 0)
                    }
                    if let copy = tb.paceCopy {
                        HStack(spacing: NoopMetrics.space2) {
                            Image(systemName: planPaceGlyph(tb.pace)).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(planPaceColor(tb.pace))
                            Text(copy).font(StrandFont.subhead).foregroundStyle(planPaceColor(tb.pace))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let start = onStartTraining {
                        Button(action: start) {
                            HStack(spacing: NoopMetrics.space2) {
                                Text(tb.routineName ?? String(localized: "Tu entrenamiento"))
                                    .font(InstrumentoType.grotesk(13, weight: .bold))
                                    .foregroundStyle(theme.paperHi)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: NoopMetrics.space2)
                                HStack(spacing: NoopMetrics.space1) {
                                    Text("Empezar")
                                        .font(InstrumentoType.grotesk(11, weight: .semibold))
                                        .tracking(1.2).textCase(.uppercase)
                                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(theme.ctaAccent)
                            }
                            .padding(.horizontal, NoopMetrics.cardPadding)
                            .padding(.vertical, 14)
                            .background(theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, NoopMetrics.space1)
                        .accessibilityHint(Text("Abre Entrenar y arranca la sesión de hoy"))
                    }
                case .rest:
                    HStack(spacing: NoopMetrics.gap) {
                        Image(systemName: "moon.fill").font(.system(size: 16)).foregroundStyle(theme.inkSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Hoy descansas").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                            Text("tu split no asigna rutina hoy").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The streak chip: flame + «racha N días» (singular «día» at 1). Same number Entrenar shows.
    private func planStreakChip(_ days: Int) -> some View {
        let unit = days == 1 ? "día" : "días"
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(theme.warning)
            Text("racha \(days) \(unit)").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .padding(.horizontal, NoopMetrics.space2).padding(.vertical, 2)
        .background(theme.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Racha de \(days) \(unit) en tu plan"))
    }

    private func planPaceColor(_ pace: DailyBrief.TrainingBlock.Pace?) -> Color {
        switch pace {
        case .up:   return theme.verdict
        case .down: return theme.warning
        case .hold, .none: return theme.inkSecondary
        }
    }

    private func planPaceGlyph(_ pace: DailyBrief.TrainingBlock.Pace?) -> String {
        switch pace {
        case .up:   return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .hold, .none: return "arrow.right"
        }
    }

    // MARK: - Shared chart wells (loading / empty), themed for warm paper

    private func loadingWell(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.surface)
            .frame(height: height)
            .overlay { ProgressView().tint(theme.inkTertiary) }
    }

    private func emptyWell(icon: String, text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Recovery weight breakdown + method disclosure (FER-108)

    /// Cold-start progress: "Calibrating baseline" over a thin recovery-tinted track, shown instead of
    /// a score while the recovery baseline is still seeding.
    private func calibrationCard(_ cal: MetricInfo.Calibration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calibrating baseline").strandOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(cal.done) of \(cal.needed) nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 6)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(6, geo.size.width * CGFloat(cal.done) / CGFloat(max(cal.needed, 1))),
                               height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: «Qué la movió hoy» (FER-628)

    /// |contribution| below this reads as "barely moved it" — no arrow, quiet copy. The buckets are
    /// copy thresholds only (the math is `RecoveryImpact`); in composite-z units, where the score's
    /// full Red–Green band spans ≈ ±2 (RecoveryScorer.logisticK).
    private static let impactBarely = 0.12

    /// «Qué la movió hoy»: today's per-signal impact on the recovery score, ordered by REAL
    /// contribution (|z·weight|, the FER-632 ranking — never |z| alone). One plain-language headline
    /// naming the day's driver, then a row per signal: its state word, an impact phrase, and a
    /// divergent vs-your-base bar whose length is the contribution. No σ and no % here — those live
    /// under "How it's calculated".
    private func impactBlock(_ impact: RecoveryImpact.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today, vs your normal")
                .instrumentoOverline()
                .foregroundStyle(theme.inkTertiary)
            impactHeadline(impact)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(impact.signals) { impactRow($0) }
            }
            impactLegend
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The plain-language headline names the signal with the LARGEST contribution to today's score
    /// (its state word in the flag color, everything else in ink). Built from fragments so it
    /// localizes cleanly, like `RecoveryDetailScreen`'s titular.
    private func impactHeadline(_ impact: RecoveryImpact.Result) -> Text {
        guard let top = impact.top, abs(top.contribution) >= Self.impactBarely else {
            return Text("All your signals sat near your base today.")
        }
        let tail: LocalizedStringKey = top.contribution < 0
            ? ", is what holds your recovery back most today."
            : ", is what holds your recovery up most today."
        return Text("Your ")
            + Text(Self.impactLabel(top.key)).foregroundColor(impactColor(impactFlag(top))).fontWeight(.semibold)
            + Text(Self.positionPhrase(top))
            + Text(tail)
    }

    /// One signal: overline label · position-vs-base word (flag hue) · `· N%` weight, and the divergent
    /// contribution bar below. IDENTICAL to the Detalle's `levelSignalRow` (FER-642). VoiceOver reads the
    /// combined row.
    private func impactRow(_ s: RecoveryImpact.Signal) -> some View {
        let flag = impactFlag(s)
        let color = flag == .neutral ? theme.inkSecondary : impactColor(flag)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.impactLabel(s.key)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Text(Self.baseBandWord(s))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(color)
                Text(verbatim: "· \(Int((s.weight * 100).rounded()))%")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkTertiary)
            }
            impactBar(contribution: s.contribution, color: color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The position-vs-base word from the RAW deviation (+ = the metric itself sits above your average),
    /// so the word is honest about where the value is; the row color (oriented flag) carries the valence.
    /// |z| < 1 reads «In your base». Shared vocabulary with the Detalle. (FER-642)
    private static func baseBandWord(_ s: RecoveryImpact.Signal) -> LocalizedStringKey {
        if s.z >= 1 { return "Above your base" }
        if s.z <= -1 { return "Below your base" }
        return "In your base"
    }

    /// The headline's inline position clause, «, above your base, » etc., with a «well» qualifier past 1σ.
    /// Matches `baseBandWord`. (FER-642)
    private static func positionPhrase(_ s: RecoveryImpact.Signal) -> LocalizedStringKey {
        let above = s.z >= 0
        let strong = abs(s.z) >= 1.0
        return strong
            ? (above ? ", well above your base" : ", well below your base")
            : (above ? ", above your base"      : ", below your base")
    }

    /// The divergent «vs your base» bar: a center base tick, a capsule extending left (it pulled the
    /// score down) or right (it lifted it), length ∝ |contribution| clamped at ~1.5 composite-z units
    /// (the dominant driver on a very bad night). Family thickness (6px), like the Detalle's axis.
    private func impactBar(contribution: Double, color: Color) -> some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let maxC: CGFloat = 1.5
            let mag = Swift.max(4, Swift.min(abs(CGFloat(contribution)) / maxC, 1.0) * half)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(width: mag, height: 6)
                    .offset(x: contribution >= 0 ? half : half - mag)
                Rectangle()
                    .fill(theme.hairlineStrong)
                    .frame(width: 1, height: 9)
                    .offset(x: half - 0.5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 9)
    }

    /// The axis legend: «◀ te la bajó · tu base · te la subió ▶» — decorative, hidden from VoiceOver.
    private var impactLegend: some View {
        HStack {
            Text("◀ holds it back").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer()
            Text("your base").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer()
            Text("holds it up ▶").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .accessibilityHidden(true)
    }

    /// The signal's display name — the same catalog keys the Detalle's driver rows use.
    private static func impactLabel(_ key: String) -> LocalizedStringKey {
        switch key {
        case "hrv":      return "HRV"
        case "rhr":      return "Resting HR"
        case "sleep":    return "Sleep"
        case "skinTemp": return "Skin temp"
        case "respRate": return "Respiration"
        default:         return LocalizedStringKey(key)
        }
    }

    /// State flag from the ORIENTED z (+ = pushed the score up) — the single source of the σ cuts
    /// (`ReadinessEngine.Flag(orientedZ:)`), so the state words agree with the Detalle's and the score.
    private func impactFlag(_ s: RecoveryImpact.Signal) -> ReadinessEngine.Flag {
        ReadinessEngine.Flag(orientedZ: s.orientedZ)
    }

    /// flag → theme color, shared with the Detalle's driver rows so both surfaces color states alike.
    private func impactColor(_ flag: ReadinessEngine.Flag) -> Color { flag.color(theme) }

    /// Progressive disclosure: the technical "how" lives one tap down, collapsed by default.
    private func methodDisclosure(_ method: MetricInfo.Method) -> some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text(method.prose)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let citation = method.citation {
                    Text(citation)
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("How it's calculated")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Trailing "Ver más" link at the foot of the sheet: drills from this summary into the metric's rich
    /// Detalle. Tinted with the metric hue (the one place colour lives on an action here) so it reads as
    /// tappable and ties to the metric. Right-aligned. (FER-251)
    @ViewBuilder private func seeMoreLink(_ action: @escaping () -> Void) -> some View {
        if info.usesLevels {
            // FER-607: full-width «Ver más en Tendencias» with the trend-line glyph and an ink hairline
            // border — drills into the same rich detail Cuerpo opens (the handoff foot button).
            Button(action: action) {
                HStack(spacing: 7) {
                    // The actual «Tendencias» screen glyph (curve-with-nodes), not a generic chart icon. (FER-710)
                    TendenciasGlyph(color: theme.ink, lineWidth: 1.8)
                        .frame(width: 15, height: 15)
                    Text("See more in Trends")
                        .font(StrandFont.subhead.weight(.medium))
                }
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .overlay(
                    RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.ink, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("See more in Trends"))
            .accessibilityHint(Text("Opens the full detail"))
        } else {
            HStack {
                Spacer(minLength: 0)
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text("See more")
                            .font(StrandFont.subhead.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(metricHue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(metricHue.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("See more"))
                .accessibilityHint(Text("Opens the full detail"))
            }
        }
    }
}

// MARK: - Helpers

/// Carries the sheet content's measured natural height up to size the Day Strain detent. (FER-112)
private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The bespoke intraday accumulated-strain curve (FER-730 §5). Solid through the lived portion, a flat
/// dashed projection from «now» to midnight, an area wash under the lived line, a breathing dot at now,
/// and a fixed 00/6/12/18/24 hour axis. Pure StrandDesign tokens; no invented ceiling/window (§5).
private struct StrainIntradayCurve: View {
    let points: [TrendPoint]
    let hue: Color
    let theme: InstrumentoTheme
    /// FER-732 · the recommended day-strain ceiling (0–21), a personal recovery-scaled guardrail. nil hides it.
    var ceiling: Double? = nil
    /// FER-732 · the habitual training window in decimal clock hours [0, 24]. nil hides the amber band.
    var window: TrainingHabit.Window? = nil

    /// The x of the scrubbing finger (nil when not scrubbing) — drives the crosshair + tooltip. (FER-748)
    @State private var hoverX: CGFloat? = nil

    /// Locale-aware hour:minute for the scrub tooltip (12/24h per region).
    private static let hourFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let startOfDay = Calendar.current.startOfDay(for: points.last?.date ?? Date())
                let peak = points.map(\.value).max() ?? 1
                // The ceiling shares the axis, so keep it in view when it sits above today's peak.
                let vMax = max(max(peak, ceiling ?? 0) * 1.15, 1)
                let pts: [CGPoint] = points.map { p in
                    let f = min(max(p.date.timeIntervalSince(startOfDay) / 86_400, 0), 1)
                    return CGPoint(x: CGFloat(f) * w, y: h - CGFloat(p.value / vMax) * h)
                }
                let nowPt = pts.last ?? CGPoint(x: 0, y: h)

                ZStack(alignment: .topLeading) {
                    // Planned-training window (amber), drawn first so the curve reads over it. (FER-732)
                    if let window {
                        let x0 = CGFloat(min(max(window.start / 24, 0), 1)) * w
                        let x1 = CGFloat(min(max(window.end / 24, 0), 1)) * w
                        theme.warning.opacity(0.14)
                            .frame(width: max(0, x1 - x0), height: h)
                            .position(x: (x0 + x1) / 2, y: h / 2)
                    }
                    Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)) }
                        .stroke(theme.hairline, lineWidth: 1)
                    // Recommended ceiling: a dashed ink line labelled at the left. (FER-732)
                    if let ceiling {
                        let cy = h - CGFloat(min(ceiling, vMax) / vMax) * h
                        Path { p in p.move(to: CGPoint(x: 0, y: cy)); p.addLine(to: CGPoint(x: w, y: cy)) }
                            .stroke(theme.inkSecondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text("ceiling")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.inkTertiary)
                            .padding(.horizontal, 3)
                            .background(theme.paper.opacity(0.85))
                            .fixedSize()
                            .position(x: 20, y: max(6, cy - 8))
                    }
                    // Area wash under the lived line.
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: CGPoint(x: first.x, y: h))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: nowPt.x, y: h))
                        p.closeSubpath()
                    }.fill(hue.opacity(0.10))
                    // Lived line (solid).
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: first)
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }.stroke(hue, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    // Projection: flat, dashed, now → midnight (strain only accumulates).
                    if nowPt.x < w - 0.5 {
                        Path { p in
                            p.move(to: nowPt)
                            p.addLine(to: CGPoint(x: w, y: nowPt.y))
                        }.stroke(hue.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 4]))
                    }
                    BreathingDot(color: hue, radius: 3.4).position(x: nowPt.x, y: nowPt.y)

                    // Scrub: crosshair + handle + tooltip that follow the finger over the LIVED curve.
                    // Beyond «now» the finger anchors to the last real point (the projection is synthetic,
                    // so there is no datum to read there). Reuses the shared StrandDesign scrub. (FER-748)
                    let snapped: Int? = hoverX.flatMap { hx in
                        ChartScrubMath.nearestIndex(toX: min(hx, nowPt.x), xs: pts.map(\.x))
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .scrubGesture(enabled: pts.count > 1, hoverX: $hoverX)
                        .onChange(of: snapped) { if $0 != nil { ChartHaptics.datumChanged() } }
                    if let i = snapped, pts.indices.contains(i) {
                        CrosshairRule(x: pts[i].x, height: h)
                        HighlightDot(color: hue).position(x: pts[i].x, y: pts[i].y)
                        PositionedTooltip(
                            anchor: pts[i],
                            container: geo.size,
                            tooltip: ChartTooltip(
                                value: String(format: "%.1f", points[i].value),
                                label: Self.hourFmt.string(from: points[i].date),
                                accent: hue
                            )
                        )
                    }
                }
                .environment(\.instrumentoTheme, theme)
                .environment(\.instrumentoFlat, true)
                .animation(StrandMotion.fade, value: hoverX)
            }
            HStack(spacing: 0) {
                ForEach(["00", "6", "12", "18", "24"], id: \.self) { label in
                    Text(verbatim: label).font(.system(size: 10)).foregroundStyle(theme.inkTertiary)
                    if label != "24" { Spacer(minLength: 0) }
                }
            }
            .frame(height: 12)
        }
    }
}

private struct PresentationBackgroundModifier: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(macOS 13.3, iOS 16.4, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
/// A rising sample curve from local midnight, ending at `score`, for previews/renders.
private func sampleStrainCurve(score: Double) -> [TrendPoint] {
    let midnight = Calendar.current.startOfDay(for: Date())
    let shape: [(h: Double, f: Double)] = [
        (0, 0), (6.5, 0.09), (8, 0.19), (10, 0.32), (12, 0.49),
        (12.75, 0.67), (13.25, 0.80), (14, 0.90), (15, 1.0),
    ]
    return shape.map { p in
        TrendPoint(date: midnight.addingTimeInterval(p.h * 3600), value: score * p.f)
    }
}

#Preview("MetricInfoSheet — Strain (curve)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .strain(11.5),
                        strainCurveLoader: { sampleStrainCurve(score: 11.5) },
                        trainingBlock: DailyBrief.TrainingBlock(
                            state: .training, routineName: "Empuje A", streakDays: 6,
                            pace: .up, paceCopy: "Recuperación alta para ti · puedes con todo el plan"),
                        onStartTraining: {},
                        strainCeiling: 14.2,
                        trainingWindow: TrainingHabit.Window(start: 16.5, end: 18.5))
    }
}

#Preview("MetricInfoSheet — Strain (no data)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .strain(3.9))
    }
}

#Preview("MetricInfoSheet — HRV") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .hrv(66))
    }
}

#Preview("MetricInfoSheet — HRV (no data)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .hrv(nil))
    }
}

#Preview("MetricInfoSheet — Steps (no permission)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .steps(nil), appleConnectHint: true)
    }
}

#Preview("MetricInfoSheet — SpO₂") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .spo2(97))
    }
}

#Preview("MetricInfoSheet — Recovery") {
    Color.clear.sheet(isPresented: .constant(true)) {
        // The 27-jun-2026 sick-day shape: HRV collapsed (the driver), resting HR way up, the rest quiet.
        MetricInfoSheet(info: .recovery(score: 12, calibrationNights: nil, nightsNeeded: 4,
            impact: RecoveryImpact.Result(signals: [
                .init(key: "hrv",      z: -3.6, orientedZ: -3.6, weight: 0.545),
                .init(key: "rhr",      z:  3.0, orientedZ: -3.0, weight: 0.182),
                .init(key: "skinTemp", z:  2.4, orientedZ: -2.4, weight: 0.091),
                .init(key: "sleep",    z: -0.4, orientedZ: -0.4, weight: 0.136),
                .init(key: "respRate", z:  0.6, orientedZ: -0.6, weight: 0.045),
            ])))
    }
}

#Preview("MetricInfoSheet — Recovery (calibrating)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .recovery(score: nil, calibrationNights: 2, nightsNeeded: 4))
    }
}

#Preview("MetricInfoSheet — Stress (low)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .stress(0.8))
    }
}

#Preview("MetricInfoSheet — Stress (high)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .stress(2.4))
    }
}
#endif
