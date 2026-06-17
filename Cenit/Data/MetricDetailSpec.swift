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
}

/// How the hero numeral reads.
enum HeroKind {
    /// The 7-day moving average (the trailing mean — the vital's protagonist figure).
    case movingAverage7
    /// The latest single reading.
    case latest
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

    var id: String { descriptor.id }

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

    private static func catalog(_ key: String) -> MetricDescriptor {
        // Every key here is a known catalog entry; the fallback keeps the call non-optional.
        MetricCatalog.all.first { $0.key == key }
            ?? MetricDescriptor(key: key, title: key, category: "Recovery", unit: "",
                                source: "my-whoop", icon: "waveform.path.ecg", decimals: 0,
                                higherIsBetter: nil)
    }
}
