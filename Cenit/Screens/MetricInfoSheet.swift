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
    var weights: [WeightRow]? = nil
    var weightsNote: LocalizedStringKey? = nil
    var method: Method? = nil
    var disclaimer: LocalizedStringKey? = nil
    var calibration: Calibration? = nil

    /// When set, the summary sheet renders the F6 levels instrument (`MetricLevelsExplorer`: a tappable
    /// levels list + range selector + chart over the active band) instead of the static 14-day trend +
    /// bands table, and its foot link reads «Ver más en Tendencias». Drives the per-metric levels from
    /// `MetricLevels` (FER-570). nil → the classic summary, untouched. Pilot: resting HR only. (FER-607)
    var levelsMetric: MetricLevels.FixedMetric? = nil

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

    /// One driver in the recovery weight breakdown: a labeled bar whose fill length shows how much
    /// it contributes to the score (the fill is tinted with the recovery hue by the sheet).
    struct WeightRow {
        let label: LocalizedStringKey
        let percent: Int
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
            note: nil
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
            note: nil
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
            )
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
            levelsMetric: .restingHR
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
            )
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
                citation: "Wrist optical sensors are less accurate than medical pulse oximeters — read this as a trend, not a clinical measurement. NOOP is not a medical device.")
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
                citation: "Paluch et al. 2022, Lancet Public Health.")
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
            )
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
    /// a weight breakdown + a "See the method" disclosure. Weights mirror `RecoveryScorer`
    /// (HRV .60 · RHR .20 · sleep .15 · skin-temp .10 · resp .05); the bars normalize to the
    /// top driver so the row reads as relative contribution. While the baseline is still seeding
    /// (`calibrationNights` non-nil) it shows honest progress instead of a made-up number. The
    /// header numeral is tinted by the WHOOP recovery band (green ≥67 · yellow 34–67 · red <34),
    /// mirroring TodayView's `recoveryDataColor`. (FER-108 / FER-162)
    static func recovery(score: Int?, calibrationNights: Int?, nightsNeeded: Int) -> MetricInfo {
        let weights: [WeightRow] = [
            WeightRow(label: "HRV",         percent: 60),
            WeightRow(label: "Resting HR",  percent: 20),
            WeightRow(label: "Sleep",       percent: 15),
            WeightRow(label: "Skin temp",   percent: 10),
            WeightRow(label: "Respiration", percent:  5),
        ]
        let weightsNote: LocalizedStringKey =
            "If a signal is missing on a given night, its weight is shared among the others."
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
                weights: weights,
                weightsNote: weightsNote,
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
            weights: weights,
            weightsNote: weightsNote,
            method: Method(
                prose: "Each signal becomes a score of how far above or below your personal average it sits; they're averaged with the weights above and mapped onto a 0–100 scale, calibrated so a typical day lands near 58.",
                citation: "A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996)."
            ),
            disclaimer: disclaimer,
            calibration: nil
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
    /// `info.levelsMetric != nil`; nil otherwise. Loaded lazily on appear.
    var levelsSeriesLoader: (() async -> [(day: String, value: Double)])? = nil

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
    /// `info.levelsMetric != nil`; the explorer re-windows the series by `levelsRange`.
    @State private var levelsRange: ExploreRange = .month
    @State private var levelsSeries: [(day: String, value: Double)] = []

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
                if headlineExpanded {
                    Text(info.headline)
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if info.levelsMetric != nil {
                    // FER-607: the F6 levels instrument (selector + tappable levels + chart over the
                    // active band) replaces the static 14-day trend + bands table for migrated metrics.
                    // Pilot: resting HR. Every other metric stays on the classic summary below.
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
                    if let calibration = info.calibration { calibrationCard(calibration) }
                    if let weights = info.weights {
                        weightsBlock(weights, note: info.weightsNote, dimmed: info.calibration != nil)
                    }
                    if !info.bands.isEmpty {
                        bandsTable
                    }
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
            // selector can re-window. Supplied only when `info.levelsMetric != nil`.
            guard let loader = levelsSeriesLoader else { return }
            levelsSeries = await loader()
        }
    }

    /// Sheets with a trend chart (or the strain accumulation curve) are sized to their content so the
    /// chart is never cut off. Falls back to `.large` until the first layout pass measures the height.
    /// Short, band-only sheets stay at `.medium`. (FER-112 follow-up, extended for trend charts)
    private var strainDetents: Set<PresentationDetent> {
        guard info.id == "strain" || info.id == "heart_rate" || trendLoader != nil
                || info.levelsMetric != nil else { return [.medium] }
        return contentHeight > 0 ? [.height(contentHeight)] : [.large]
    }

    /// The datum leads: the name drops to a quiet overline and the value becomes the hero numeral
    /// (rule 1 — one dominant element; rule 4 — name as overline), so the two no longer compete on the
    /// same baseline. Tint still resolves through `headerTint` (band/level/neutral), unchanged. (FER-243)
    private var header: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                if info.levelsMetric != nil {
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
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
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
        return Text(appleSource ? "APPLE" : "BANDA")
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
        if let metric = info.levelsMetric {
            let parsed: MetricWindowMath.Parsed = levelsSeries.map {
                (day: $0.day, date: Repository.parseDayKey($0.day), value: $0.value)
            }
            let window = MetricWindowMath.make(parsed, selected: levelsRange)
            MetricLevelsExplorer(
                theme: theme,
                range: $levelsRange,
                window: window,
                levels: MetricLevels.levels(for: metric),
                todayValue: Double(info.displayValue),
                hue: metricHue,
                unit: info.unit ?? "",
                valueFormat: { "\(Int($0.rounded()))" },
                accessibilityLabel: info.name
            )
        }
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

    /// The weight breakdown — one labeled bar per driver, longest = top contributor. A single
    /// surface, no per-row rules: bar length already separates the rows (Tufte). Dimmed while
    /// calibrating, since the method exists but doesn't apply yet.
    private func weightsBlock(_ weights: [MetricInfo.WeightRow], note: LocalizedStringKey?, dimmed: Bool) -> some View {
        let maxPct = max(weights.map(\.percent).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(weights.enumerated()), id: \.offset) { _, w in
                weightRow(w, fraction: Double(w.percent) / Double(maxPct))
            }
            if let note {
                Text(note)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(dimmed ? StrandPalette.disabledOpacity : 1)
    }

    private func weightRow(_ w: MetricInfo.WeightRow, fraction: Double) -> some View {
        HStack(spacing: 10) {
            Text(w.label)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 8)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(8, geo.size.width * CGFloat(fraction)), height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)
            Text(verbatim: "\(w.percent)%")
                .font(StrandFont.captionNumber)
                .foregroundStyle(theme.inkSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

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
        if info.levelsMetric != nil {
            // FER-607: full-width «Ver más en Tendencias» with the trend-line glyph and an ink hairline
            // border — drills into the same rich detail Cuerpo opens (the handoff foot button).
            Button(action: action) {
                HStack(spacing: 7) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 14, weight: .medium))
                    Text("Ver más en Tendencias")
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
            .accessibilityLabel(Text("Ver más en Tendencias"))
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
                        strainCurveLoader: { sampleStrainCurve(score: 11.5) })
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
        MetricInfoSheet(info: .recovery(score: 92, calibrationNights: nil, nightsNeeded: 4))
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
