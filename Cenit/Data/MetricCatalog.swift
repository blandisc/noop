import Foundation

/// One interrogable metric: how to fetch it (key+source), how to label/format it, and whether
/// higher is better (drives delta tinting). The Metric Explorer + Compare are built from this list.
struct MetricDescriptor: Identifiable, Hashable {
    let key: String
    let title: String
    let category: String
    let unit: String
    let source: String       // "strap" or "apple-health"
    let icon: String
    let decimals: Int
    let higherIsBetter: Bool?
    var id: String { source + ":" + key }

    /// `category` is identity (grouping, comparisons like `category == "Strain"`)
    /// and stays English — surface it through this for anything user-visible.
    var localizedCategory: String { MetricCatalog.localizedCategory(category) }

    /// The ONE canonical display name — the name Hoy already shows, so a metric is called the same
    /// thing on every screen (FER-104 / HJ-13: «una métrica, un nombre»). The raw `title` stays
    /// «Day Strain» / «Day Stress» / «Heart Rate Variability» / «Resting Heart Rate» (identity other
    /// call sites read), but Hoy titles those with SHORT names — «Effort» / «Stress» and «HRV» / «VFC»
    /// and «Resting HR» / «FC en reposo» — so this override returns that canonical name and Compare /
    /// Explore stop reintroducing the long forms in chips / legends / tooltips / navTitle. The long
    /// name is only ever an ⓘ expansion, never a title (D4/C-18, HJ-12). Every other metric returns
    /// its catalog title unchanged. (Consumed by the visual migration, TND-30/31.)
    var canonicalTitle: String {
        switch key {
        case "strain": return String(localized: "Effort")
        case "stress": return String(localized: "Stress")
        // D4/C-18: the exact short strings Hoy's Matrix uses — «HRV»/«VFC» (matriz.vfc) and
        // «Resting HR»/«FC en reposo» — not the long «Heart Rate Variability»/«Resting Heart Rate».
        case "hrv":    return String(localized: "HRV")
        case "rhr":    return String(localized: "Resting HR")
        default:       return title
        }
    }

    func format(_ v: Double) -> String {
        let n = decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }

    /// Unit-aware format: for the three SI-stored metrics that have a non-metric counterpart
    /// (weight/lean_mass in kg, skin_temp in °C) convert + relabel via `UnitFormatter`. Every other
    /// metric (%, bpm, ms, min, …) is unit-agnostic and falls through to the plain `format` above, so
    /// the imperial toggle only ever touches the values that actually have an imperial form.
    func format(_ v: Double, system: UnitSystem, temperature: TemperatureUnit) -> String {
        switch unit {
        case "kg":  return UnitFormatter.massFromKilograms(v, system: system)
        case "°C":  return UnitFormatter.temperatureFromCelsius(v, unit: temperature, decimals: decimals)
        default:    return format(v)
        }
    }

    /// Like `format`, but for a DIFFERENCE between two values (e.g. the Δ StatTile). A temperature
    /// delta scales by 9/5 with NO +32 offset; mass/distance deltas scale by their plain factor. The
    /// caller supplies the magnitude (sign is rendered separately).
    func formatDelta(_ v: Double, system: UnitSystem, temperature: TemperatureUnit) -> String {
        switch unit {
        case "kg":  return UnitFormatter.massFromKilograms(v, system: system)
        case "°C":  return UnitFormatter.temperatureDeltaFromCelsius(v, unit: temperature, decimals: decimals)
        default:    return format(v)
        }
    }

    /// The unit LABEL as displayed (e.g. the trailing chip in the Metric Explorer list), mapped to the
    /// active system. Only the convertible units change; everything else returns its stored label.
    func displayUnit(system: UnitSystem, temperature: TemperatureUnit) -> String {
        switch unit {
        case "kg":  return UnitFormatter.massUnit(system)
        case "°C":  return UnitFormatter.temperatureUnit(temperature)
        default:    return unit
        }
    }
}

/// Canonical catalog — mirrors the WHOOP "Trend View" plus Apple Health body metrics.
/// Keys match exactly what the importers write into metricSeries.
enum MetricCatalog {
    static let categories = ["Heart", "Recovery", "Sleep", "Strain", "Health"]

    static let all: [MetricDescriptor] = [
        // ── Heart
        // Titles are wrapped in String(localized:) AT the literal so Xcode's
        // string extraction sees them; a plain String field never localizes.
        d("avg_hr", String(localized: "Average Heart Rate"), "Heart", String(localized: "bpm"), "strap", "heart", 0, nil),
        d("max_hr", String(localized: "Max Heart Rate"), "Heart", String(localized: "bpm"), "strap", "bolt.heart", 0, nil),
        d("energy_kcal", String(localized: "Calories"), "Heart", "kcal", "strap", "flame", 0, nil),
        d("vo2max", String(localized: "VO₂ Max"), "Heart", "", "apple-health", "lungs.fill", 1, true),

        // ── Recovery
        d("recovery", String(localized: "Recovery"), "Recovery", "%", "strap", "heart.circle", 0, true),
        d("hrv", String(localized: "Heart Rate Variability"), "Recovery", "ms", "strap", "waveform.path.ecg", 0, true),
        d("rhr", String(localized: "Resting Heart Rate"), "Recovery", String(localized: "bpm"), "strap", "heart", 0, false),
        d("resp_rate", String(localized: "Respiratory Rate"), "Recovery", "rpm", "strap", "lungs", 1, false),
        d("spo2", String(localized: "Blood Oxygen"), "Recovery", "%", "strap", "drop", 0, true),
        d("skin_temp", String(localized: "Skin Temperature"), "Recovery", "°C", "strap", "thermometer", 1, nil),

        // ── Sleep
        d("sleep_performance", String(localized: "Sleep Performance"), "Sleep", "%", "strap", "moon.stars", 0, true),
        d("in_bed_min", String(localized: "Time in Bed"), "Sleep", "min", "strap", "bed.double", 0, nil),
        d("sleep_total_min", String(localized: "Asleep Time"), "Sleep", "min", "strap", "moon.zzz", 0, true),
        d("hours_vs_needed_pct", String(localized: "Hours vs Needed"), "Sleep", "%", "strap", "gauge.medium", 0, true),
        d("sleep_consistency", String(localized: "Sleep Consistency"), "Sleep", "%", "strap", "calendar", 0, true),
        d("restorative_pct", String(localized: "Restorative Sleep"), "Sleep", "%", "strap", "sparkles", 0, true),
        d("restorative_min", String(localized: "Restorative Sleep"), "Sleep", "min", "strap", "sparkles", 0, true),
        d("sleep_efficiency", String(localized: "Sleep Efficiency"), "Sleep", "%", "strap", "bed.double.fill", 0, true),
        d("sleep_deep_min", String(localized: "Deep (SWS) Sleep"), "Sleep", "min", "strap", "moon.fill", 0, true),
        d("sleep_rem_min", String(localized: "REM Sleep"), "Sleep", "min", "strap", "moon.haze", 0, true),
        d("sleep_light_min", String(localized: "Light Sleep"), "Sleep", "min", "strap", "moon", 0, nil),
        d("sleep_need_min", String(localized: "Sleep Need"), "Sleep", "min", "strap", "gauge", 0, nil),
        d("sleep_debt_min", String(localized: "Sleep Debt"), "Sleep", "min", "strap", "exclamationmark.circle", 0, false),

        // ── Strain
        d("strain", String(localized: "Day Strain"), "Strain", "/21", "strap", "flame", 1, nil),
        d("steps", String(localized: "Steps"), "Strain", "", "apple-health", "figure.walk", 0, true),
        d("hr_zones13_min", String(localized: "HR Zones 1–3"), "Strain", "min", "strap", "heart", 0, nil),
        d("hr_zones45_min", String(localized: "HR Zones 4–5"), "Strain", "min", "strap", "heart.fill", 0, nil),
        d("hr_zones_all_min", String(localized: "HR Zones (All)"), "Strain", "min", "strap", "heart.text.square", 0, nil),
        d("strength_min", String(localized: "Strength Activity Time"), "Strain", "min", "strap", "dumbbell", 0, nil),
        d("active_kcal", String(localized: "Active Energy"), "Strain", "kcal", "apple-health", "flame.fill", 0, nil),

        // ── Health / Body
        d("weight", String(localized: "Weight"), "Health", "kg", "apple-health", "scalemass", 1, nil),
        d("body_fat", String(localized: "Body Fat"), "Health", "%", "apple-health", "percent", 1, false),
        d("lean_mass", String(localized: "Lean Body Mass"), "Health", "kg", "apple-health", "figure.arms.open", 1, true),
        d("bmi", String(localized: "BMI"), "Health", "", "apple-health", "figure", 1, nil),
        d("stress", String(localized: "Day Stress"), "Health", "/3", "strap", "gauge.with.needle", 1, false),
    ]

    static func inCategory(_ c: String) -> [MetricDescriptor] { all.filter { $0.category == c } }

    /// The ONE normalization from an INGEST key — what the HealthKit path and the two Apple-Health
    /// screens (`DataSourcesView`, `AppleHealthView`) speak — to the CATALOG key that `MetricCatalog`,
    /// `MetricIdentity` (Liquid hue/glyph) and `canonicalTitle` are all keyed by. Only two keys
    /// diverge: `resting_hr` (catalog `rhr`) and `asleep_min` (catalog `sleep_total_min`); every
    /// other ingest key already IS a catalog key and passes through. Coined here (FER-108 cimientos)
    /// so the Apple-Health screens reuse the ONE identity/title source instead of re-inventing a third
    /// convention for the same metric. See [[MetricIdentity.identity(forIngestKey:)]].
    static func catalogKey(forIngestKey key: String) -> String {
        switch key {
        case "resting_hr": return "rhr"
        case "asleep_min": return "sleep_total_min"
        default:           return key
        }
    }

    /// The catalog descriptor for an INGEST or catalog key (normalizes via `catalogKey(forIngestKey:)`
    /// first). `nil` only for a key that is in neither convention.
    static func descriptor(forIngestKey key: String) -> MetricDescriptor? {
        let ck = catalogKey(forIngestKey: key)
        return all.first { $0.key == ck }
    }

    /// Display name for a category key (`categories` stays English internally —
    /// it's identity for grouping and checks like `category == "Strain"`).
    static func localizedCategory(_ c: String) -> String {
        switch c {
        case "Heart":    return String(localized: "Heart")
        case "Recovery": return String(localized: "Recovery")
        case "Sleep":    return String(localized: "Sleep")
        case "Strain":   return String(localized: "Strain")
        case "Health":   return String(localized: "Health")
        default:         return c
        }
    }

    private static func d(_ key: String, _ title: String, _ category: String, _ unit: String,
                          _ source: String, _ icon: String, _ decimals: Int,
                          _ higherIsBetter: Bool?) -> MetricDescriptor {
        MetricDescriptor(key: key, title: title, category: category, unit: unit,
                         source: source, icon: icon, decimals: decimals, higherIsBetter: higherIsBetter)
    }
}
