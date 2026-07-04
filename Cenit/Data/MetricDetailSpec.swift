import Foundation
import StrandAnalytics

// MARK: - MetricDetailSpec — presentation descriptor for the unified Detalle de Métrica (FER-185)
//
// `MetricCatalog`/`MetricDescriptor` is IDENTITY (how to fetch a series + label it). This is the
// PRESENTATION layer on top: which blocks the unified detail screen renders for a metric, how the
// hero reads, and the baseline config + population range that drive its "normal range" band. It is
// deliberately separate so the catalog stays a clean fetch/identity model.
//
// The factories below WRAP and REUSE the existing `MetricInfo` factories (`.hrv`, `.restingHR`, and
// the new `.respiratory`) so the headline / method / band copy stays single-sourced — they do not
// duplicate it. Respiration had no `MetricInfo` factory; one is added (in `MetricInfoSheet.swift`,
// next to the others) and reused here.

/// The user's age & sex for the VO₂max detail's population reading (`VO2maxReference`). (FER-257)
struct VO2maxProfile {
    let age: Int
    let sex: String
}

/// Which presentation blocks the unified detail renders. A spec lists every block the metric *can*
/// show at full depth; `MetricDetailScreen` filters this set by `Depth` (Hoy = focus, Cuerpo = full).
struct BlockSet: OptionSet {
    let rawValue: Int

    /// The W/M/3M/6M/Año period selector above the chart.
    static let periodSelector = BlockSet(rawValue: 1 << 0)
    /// The 7-day moving-average line + p25–p75 "normal variation" band.
    static let seriesChartBand = BlockSet(rawValue: 1 << 1)
    /// The personal "normal range" (rolling mean ± SD) + valid-nights count.
    static let normalRange = BlockSet(rawValue: 1 << 2)
    /// Month-over-month trend (slope/day + % vs last month) with the stat strip.
    static let trend = BlockSet(rawValue: 1 << 3)
    /// The "Ver el método" disclosure (prose + citation).
    static let method = BlockSet(rawValue: 1 << 4)
    /// Week-to-week consistency (coefficient of variation).
    static let consistency = BlockSet(rawValue: 1 << 5)
    /// "Vitales de la noche" — respiration + resting HR read together.
    static let nightVitals = BlockSet(rawValue: 1 << 6)
    /// "Qué la mueve" — a documented, DIRECTIONAL tendency (never a coefficient or cause). FER-209.
    static let whatMovesIt = BlockSet(rawValue: 1 << 7)
    /// A fixed, population (not personal) range table — the metric's `MetricInfo.bands` with the
    /// active one marked. For clinically-anchored metrics like SpO₂ where the meaningful reference is
    /// the population floor (95%), not your own variance. (FER-252)
    static let fixedBands = BlockSet(rawValue: 1 << 8)
    /// "Nights below the clinical floor" — a count of recent nights under `lowThreshold` (last 30).
    /// Replaces `consistency` for SpO₂, where the CV is near-zero and a low-night count is the
    /// clinically legible figure. (FER-252)
    static let lowNightsCount = BlockSet(rawValue: 1 << 9)
    /// Today's intraday HR curve (5-minute buckets) — the protagonist block for Heart Rate, with its
    /// peak marked and the night's resting HR as a quiet reference line. Unlike the daily series the
    /// vitals carry, this is a single day at minute resolution. (FER-253)
    static let intradayCurve = BlockSet(rawValue: 1 << 10)
    /// "Time in zones · today" — minutes spent in HR zones 1–5 (as % of HRmax, Tanaka), led by the
    /// elevated total (zone 3+). Computed from the intraday curve. (FER-253)
    static let hrZones = BlockSet(rawValue: 1 << 11)
}

/// How the hero numeral reads.
enum HeroKind {
    /// The 7-day moving average (the trailing mean — the vital's protagonist figure).
    case movingAverage7
    /// The latest single reading.
    case latest
    /// The average of today's intraday curve (Heart Rate) — the day's mean bpm. (FER-253)
    case intradayAverage
}

/// A presentation descriptor for one metric in the unified Detalle de Métrica.
struct MetricDetailSpec: Identifiable {
    /// The series identity (fetch key + source + label/unit), reused from `MetricCatalog`.
    let descriptor: MetricDescriptor
    /// The shared info model (headline / note / method / bands), reused from the `MetricInfo` factories.
    let info: MetricInfo
    /// Blocks this metric can render at full depth.
    let blocks: BlockSet
    /// How the hero numeral reads.
    let hero: HeroKind
    /// Baseline config for the personal "normal range" band; `nil` disables the personal path
    /// (population range only) the same way `VitalBands` does.
    let baselineCfg: MetricCfg?
    /// The fixed typical-adult range, used as the cold-start / stale fallback for the normal-range band.
    let populationRange: ClosedRange<Double>?

    /// When true, the chart draws RAW nightly values (not the 7-day MA) behind a FIXED clinical band
    /// (the `info.bands`, healthy band always shaded) instead of the personal p25–p75 band. For
    /// clinically-anchored vitals like SpO₂. Default false keeps the vitals' behaviour unchanged. (FER-252)
    var clinicalBands: Bool = false
    /// The clinical floor: chart points below it are flagged in the critical hue, and the
    /// `lowNightsCount` block counts nights under it. `nil` disables both. (FER-252)
    var lowThreshold: Double? = nil
    /// Explicit Y-domain for the chart (e.g. SpO₂ 88…100 so the 95% band reads clearly). `nil` =
    /// auto-fit to the line, as the vitals do. (FER-252)
    var chartDomain: ClosedRange<Double>? = nil
    /// When true, the metric is measured SPARSELY (Apple's VO₂max — updated every so often, not nightly):
    /// the hero reads the latest reading, the chart plots the RAW measured points (not a 7-day MA), a
    /// single reading is enough to render (no "calibrating" gate), and zero readings show a dedicated
    /// explanatory empty state instead of the nights-history calibration block. (FER-257)
    var sparseMeasured: Bool = false
    /// The user's age & sex, so the VO₂max detail can read the measured value against its age/sex peers
    /// (`VO2maxReference`: expected median, fitness category, cardiorespiratory-equivalent age). Only set
    /// for the VO₂max spec. (FER-257)
    var vo2maxProfile: VO2maxProfile? = nil
    /// When true, the CURRENT calendar day is still accumulating (a running daily total, not a finished
    /// value) — so the trend figures (range / average / period comparison) drop it and read only completed
    /// days. The hero and the chart still show today. Only steps sets this; a vital's "today" is last
    /// night's finished measurement. (FER-264)
    var currentDayIncomplete: Bool = false

    var id: String { descriptor.id }

    /// Whether metric `id`'s CURRENT calendar day is still accumulating — a running daily total, so the
    /// trend / levels series drops today's partial point and reads only completed days. THE single source
    /// of the "who drops today" policy, shared by the rich detail (its `currentDayIncomplete`, set from
    /// here) and Today's levels-series loader (`TodayView.levelsSeries`, FER-630), so the two can't
    /// diverge. Only steps accumulates; a vital's "today" is last night's finished measurement.
    /// (FER-264 / FER-471)
    static func accumulatesToday(_ id: String) -> Bool { id == "steps" }

    // MARK: - Factories (wrap + reuse the MetricInfo factories — no copy duplicated here)

    /// HRV detail. Full block set (it's the protagonist vital): selector, chart+band, normal range,
    /// consistency, trend, night vitals, what-moves-it, method. Hero = 7-day moving average.
    static func hrv(_ value: Double?) -> MetricDetailSpec {
        MetricDetailSpec(
            descriptor: Self.catalog("hrv"),
            info: .hrv(value),
            blocks: [.periodSelector, .seriesChartBand, .normalRange, .consistency,
                     .trend, .nightVitals, .whatMovesIt, .method],
            hero: .movingAverage7,
            baselineCfg: Baselines.hrvCfg,
            populationRange: 20...120
        )
    }

    /// Resting-HR detail. Simpler than HRV — no consistency / night vitals — but it DOES carry
    /// "Qué la mueve" (FER-209: same-night sleep + prior-day strain, mirrored from HRV with the
    /// opposite sign). Hero = 7-day moving average. Its bands ("lower is better") live in the reused
    /// `MetricInfo.restingHR`.
    static func restingHR(_ value: Int?) -> MetricDetailSpec {
        MetricDetailSpec(
            descriptor: Self.catalog("rhr"),
            info: .restingHR(value),
            blocks: [.periodSelector, .seriesChartBand, .normalRange, .trend, .whatMovesIt, .method],
            hero: .movingAverage7,
            baselineCfg: Baselines.restingHRCfg,
            populationRange: 40...85
        )
    }

    /// Respiratory-rate detail. Selector, chart+band, normal range, trend, night vitals, method.
    /// Hero = 7-day moving average. Reuses the new `MetricInfo.respiratory` factory.
    static func respiratory(_ value: Double?) -> MetricDetailSpec {
        MetricDetailSpec(
            descriptor: Self.catalog("resp_rate"),
            info: .respiratory(value),
            blocks: [.periodSelector, .seriesChartBand, .normalRange, .trend, .nightVitals, .method],
            hero: .movingAverage7,
            baselineCfg: Baselines.respCfg,
            populationRange: 12...20
        )
    }

    /// Blood-oxygen detail. A clinically-anchored vital: hero = 7-day average, a fixed 95–100% band on
    /// the chart (raw nightly values, low nights flagged), the population band table, a "nights below
    /// 95%" count instead of consistency, and the method. No personal baseline (`baselineCfg: nil`) and
    /// no "Qué la mueve" / night-vitals (SpO₂ *is* a night vital). (FER-252)
    static func spo2(_ value: Double?) -> MetricDetailSpec {
        MetricDetailSpec(
            descriptor: Self.catalog("spo2"),
            info: .spo2(value),
            blocks: [.periodSelector, .seriesChartBand, .fixedBands, .lowNightsCount, .method],
            hero: .movingAverage7,
            baselineCfg: nil,
            populationRange: 90...100,
            clinicalBands: true,
            lowThreshold: 95,
            chartDomain: 88...100
        )
    }

    /// Heart-rate detail. Unlike the night vitals, Heart Rate has no daily series — its data is the
    /// intraday curve of TODAY (5-minute buckets). So the hero is the day's average bpm, the protagonist
    /// block is that curve (peak marked, resting HR as a reference line), followed by "time in zones"
    /// and the method. No personal baseline / trend / night-vitals (none apply to a single-day curve). (FER-253)
    static func heartRate(_ avgBpm: Int?) -> MetricDetailSpec {
        MetricDetailSpec(
            descriptor: MetricDescriptor(
                key: "heart_rate", title: String(localized: "Heart Rate"), category: "Heart",
                unit: String(localized: "bpm"), source: "my-whoop", icon: "waveform.path.ecg",
                decimals: 0, higherIsBetter: nil),
            info: .heartRate(avgBpm: avgBpm),
            blocks: [.intradayCurve, .hrZones, .method],
            hero: .intradayAverage,
            baselineCfg: nil,
            populationRange: nil
        )
    }

    /// Steps detail. NOT a clinical or night vital: hero = today's accumulated count (the figure people
    /// actually track), with the 7-day daily average as secondary context. The protagonist block is the
    /// daily trend (chart + month-over-month) — no personal "normal range", no consistency, and NO
    /// classificatory bands (the issue is explicit: steps carry no invented clinical band). Apple-sourced,
    /// so `baselineCfg`/`populationRange` are nil. (FER-254)
    static func steps(_ value: Int?) -> MetricDetailSpec {
        MetricDetailSpec(
            descriptor: Self.catalog("steps"),
            info: .steps(value),
            blocks: [.periodSelector, .seriesChartBand, .trend, .method],
            hero: .latest,
            baselineCfg: nil,
            populationRange: nil,
            currentDayIncomplete: Self.accumulatesToday("steps")   // running total, not a finished day (FER-264)
        )
    }

    /// VO₂max detail (Apple Health, measured · FER-257). A SPARSE measured metric: hero = latest reading
    /// read against age/sex peers, the chart plots the raw measured points over months, plus the extras
    /// the user asked for — change over the period, fitness category, cardiorespiratory-equivalent age,
    /// "why it matters" — and the method. No personal baseline (`baselineCfg: nil`), no fixed band table
    /// (VO₂max norms are age/sex-specific — that's the category block), no night/consistency blocks.
    static func vo2max(value: Double?, age: Int, sex: String) -> MetricDetailSpec {
        MetricDetailSpec(
            descriptor: Self.catalog("vo2max"),
            info: .vo2max(value),
            blocks: [.periodSelector, .seriesChartBand, .method],
            hero: .latest,
            baselineCfg: nil,
            populationRange: nil,
            sparseMeasured: true,
            vo2maxProfile: VO2maxProfile(age: age, sex: sex)
        )
    }

    private static func catalog(_ key: String) -> MetricDescriptor {
        // Every key here is a known catalog entry; the fallback keeps the call non-optional.
        MetricCatalog.all.first { $0.key == key }
            ?? MetricDescriptor(key: key, title: key, category: "Recovery", unit: "",
                                source: "my-whoop", icon: "waveform.path.ecg", decimals: 0,
                                higherIsBetter: nil)
    }
}
