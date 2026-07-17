#if os(iOS)
import SwiftUI
import WhoopStore
import StrandDesign
import StrandAnalytics
import Foundation

extension MetricDetailScreen {

    /// Heart Rate routes through a separate, intraday path (today's curve at minute resolution) rather
    /// than the daily-series machinery the vitals use. (FER-253)
    var isIntraday: Bool { spec.blocks.contains(.intradayCurve) }

    /// The five vitals the «Detalle de Vital» narrative redesign covers — HRV, Resting HR, Respiratory
    /// rate, Blood oxygen (SpO₂) and Heart Rate. They render the Hoy → Tu historia → (Tu patrón) → Método
    /// narrative with the inline range band, the tappable stat strip and per-datum disclosures. Steps and
    /// VO₂max also ride this screen but keep their existing block layout (out of the handoff's scope).
    var isNarrative: Bool {
        ["hrv", "rhr", "resp_rate", "spo2", "heart_rate"].contains(spec.descriptor.key)
    }

    // MARK: - Depth → visible blocks

    /// `.full` shows everything the spec declares; `.focus` shows only the day-photo subset.
    var visibleBlocks: BlockSet {
        switch depth {
        case .full:  return spec.blocks
        case .focus: return spec.blocks.intersection([.seriesChartBand, .normalRange, .method, .nightVitals, .intradayCurve, .hrZones])
        }
    }

    /// The default window: a short week in focus, a month at full depth.
    var defaultRange: ExploreRange { depth == .focus ? .week : .month }

    // MARK: - §8.7 header + origin seal (handoff v2, FER-804)

    /// The metric's standardized icon + hue for the §8.7 title overline. nil → keep the plain title.
    var metricGlyph: MetricGlyph? {
        switch spec.descriptor.key {
        case "hrv":        return .hrv
        case "rhr":        return .restingHR
        case "resp_rate":  return .respiration
        case "spo2":       return .spo2
        case "heart_rate": return .heartRate
        case "steps":      return .steps
        case "vo2max":     return .vo2max
        default:           return nil
        }
    }

    /// Where this metric's reading comes from, for the OriginStamp at the foot. Steps + VO₂max are Apple
    /// Health metrics; the cross-source vitals follow today's actual source; the rest default to the band.
    var footerOrigin: DataOrigin {
        switch spec.descriptor.key {
        case "steps", "vo2max": return .apple
        default:                return todayFromApple ? .apple : .band
        }
    }

    /// Resolve a `LocalizedStringKey` band label to a plain String for GraficaRangos lane copy.
    func plainLocalizedLabel(_ key: LocalizedStringKey) -> String {
        let mirror = Mirror(reflecting: key)
        for child in mirror.children {
            if child.label == "key", let s = child.value as? String {
                return String(localized: String.LocalizationValue(s))
            }
        }
        return ""
    }

    /// Colour ramp for population lanes: low index = first band in factory order (often “best” or “normal”).
    func bandLaneColors(count: Int) -> [Color] {
        switch spec.descriptor.key {
        case "spo2":
            // Normal / Borderline / Low
            return [theme.verdict, theme.warning, theme.critical]
        case "rhr":
            // Athlete / Excellent / Normal / Elevated — lower is better
            return [theme.verdictDeep, theme.verdict, theme.inkSecondary, theme.critical]
        case "resp_rate":
            // Low / Typical / Elevated / High
            return [theme.inkSecondary, theme.verdict, theme.warning, theme.critical]
        default:
            return (0..<count).map { _ in metricHue }
        }
    }

    var unit: String { spec.info.unit ?? "" }

    /// The three vitals the band and Apple measure with different instruments — folding both sources into
    /// one baseline/σ, CV or Δ% mixes two scales (FER-629). SpO₂/steps/skin-temp/VO₂max are single-source. (FER-635)
    var isCrossSource: Bool { ["hrv", "rhr", "resp_rate"].contains(spec.descriptor.key) }

    /// The chart's caption: the 7-day-average note, suffixed with the window ("· last month") for a
    /// bounded range and left bare for ALL. The window name is already localized, so it's interpolated
    /// as a `String` (a `%@` placeholder), not re-localized as a key. (FER-211)
    /// Whether the chart plots RAW measured points (clinical SpO₂ band, or sparse VO₂max readings) rather
    /// than the 7-day moving average the noisy nightly vitals smooth. (FER-252 / FER-257)
    var plotsRawValues: Bool { spec.clinicalBands || spec.sparseMeasured }

    /// Rest (below Zone 1) reads in quiet ink; the five training zones grade up the metric hue so a
    /// harder zone reads darker. The bar segments ARE the datum, so hue is allowed here. (FER-253)
    /// Rampa DELIBERADA de opacidad del `metricHue` (NO la paleta compartida `hrZoneRamp`): esta es su propia geometría de zonas, 1 de 3 superficies HR distintas — no se unifican (FER-908).
    func zoneFill(_ i: Int) -> Color {
        switch i {
        case 0:  return theme.hairlineStrong
        case 1:  return metricHue.opacity(0.35) // token-exempt: rampa de intensidad de zona (geometría de dato)
        case 2:  return metricHue.opacity(0.5)  // token-exempt: rampa de intensidad de zona (geometría de dato)
        case 3:  return metricHue.opacity(0.65) // token-exempt: rampa de intensidad de zona (geometría de dato)
        case 4:  return metricHue.opacity(0.82) // token-exempt: rampa de intensidad de zona (geometría de dato)
        default: return metricHue
        }
    }

    func zoneLabel(_ n: Int) -> LocalizedStringKey {
        switch n {
        case 1:  return "Zone 1 · very light"
        case 2:  return "Zone 2 · light"
        case 3:  return "Zone 3 · moderate"
        case 4:  return "Zone 4 · hard"
        default: return "Zone 5 · max"
        }
    }

    /// Whether a rise is good for this metric, from the catalog's `higherIsBetter` — drives the trend
    /// chip's colour in `TrendStatSummary`. HRV rises = good, resting HR rises = bad, respiration neutral.
    var trendPolarity: TrendStatSummary.Polarity {
        switch spec.descriptor.higherIsBetter {
        case .some(true):  return .higherIsBetter
        case .some(false): return .lowerIsBetter
        case .none:        return .neutral
        }
    }

    /// The category as a display word — the same labels the former four-band table used. (FER-833)
    func vo2maxCategoryWord(_ c: VO2maxReference.Category) -> String {
        switch c {
        case .low:       return String(localized: "Low")
        case .average:   return String(localized: "Average")
        case .good:      return String(localized: "Good")
        case .excellent: return String(localized: "Excellent")
        }
    }

    func clampFrac(_ v: Double) -> CGFloat { CGFloat(min(max(v, 0.02), 0.98)) }

    static func whatMovesArrow(_ f: WhatMovesItFinding) -> String { f.trend == .rises ? "↑" : "↓" }
    func whatMovesColor(_ f: WhatMovesItFinding) -> Color {
        f.relationship == .sleepDuration ? theme.verdict : theme.dataStrain
    }

    // MARK: Disclosure copy (verbatim from the old ⓘ accordions, single-sourced here)

    var EX_TREND: LocalizedStringKey { "The slope is how much it rises or falls on average per day, by linear regression over the period. The percentage compares this period's average against the previous period of the same length. Average, Lowest and Highest are from the range you selected." }
    var EX_RANGO: LocalizedStringKey { "Your personal baseline: a moving average of your recent nights (weighted toward the latest) ± a band of your own variation. A value outside the band is unusual for you, not for the population. It becomes reliable after about 14 nights. (Buchheit 2014)" }
    var EX_CONSIST_TECH: LocalizedStringKey { "Coefficient of variation = standard deviation ÷ the mean of your last few weeks. It measures how spread out your values are around your average. Low = steady. In HRV, a rising CV can precede fatigue even while the value still looks high. (Plews 2013)" }
    var EX_SPO2_FLOOR: LocalizedStringKey { "95% is the typical floor for a healthy adult: the same reference for everyone, not your personal baseline. Below 90% is considered low (hypoxemia). The wrist sensor is less precise than a medical oximeter, so read it as a trend." }

    // MARK: - Colour + format

    var metricHue: Color {
        switch spec.descriptor.key {
        case "hrv":               return theme.dataHrv
        case "rhr":               return theme.dataHeart
        case "resp_rate":         return theme.dataSpO2
        case "spo2":              return theme.dataOxygen
        case "heart_rate":        return theme.dataHeart
        case "steps":             return theme.dataSteps
        case "vo2max":            return theme.dataSpO2
        default:                  return theme.dataRecovery
        }
    }

    var chartGradient: Gradient { ChartWell.fillGradient(metricHue) }

    /// Format a value with the descriptor's own decimal precision. Integers get locale grouping so a
    /// four-figure step count reads "9,210", not "9210"; the vitals stay under 1,000 so they're
    /// visually unchanged. (FER-254)
    func fmt(_ v: Double) -> String {
        guard spec.descriptor.decimals == 0 else { return String(format: "%.\(spec.descriptor.decimals)f", v) }
        return Self.groupedInt.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v.rounded()))"
    }

    static let groupedInt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    static let dayParser = DayKey.utcFormatter
}

#endif
