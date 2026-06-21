import Foundation

// StressDaySummary.swift — a compact, per-day reduction of the intraday stress curve (FER-378).
//
// The intraday curve (`StressEngine.intradayStress`) is large and recomputed per day. To find patterns
// ACROSS days (which parts of the day, which weekdays tend to run more activated) without re-reading
// every day's RR, the app stores this tiny summary per day (as `metricSeries` rows — no new table). The
// cross-day detector (`StressTimeOfDayPatterns`) then works off these summaries, not the raw curve.
//
// Pure + DB-free: the app computes it from a day's curve and persists it; this file only reduces.

/// The four parts of the waking/sleeping day a reading is bucketed into.
public enum PartOfDay: String, CaseIterable, Sendable {
    case morning      // 05:00–11:59
    case afternoon    // 12:00–17:59
    case evening      // 18:00–22:59
    case night        // 23:00–04:59 (wraps midnight)

    /// Which part an hour-of-day (0–23) falls in.
    public init(hour: Int) {
        switch hour {
        case 5...11:  self = .morning
        case 12...17: self = .afternoon
        case 18...22: self = .evening
        default:      self = .night     // 23, 0–4
        }
    }
}

/// One day's stress reduced to what cross-day pattern detection needs.
public struct StressDaySummary: Equatable, Sendable {
    /// Mean 0–3 stress per part of the day — only parts that had at least one reading appear.
    public let partMeans: [PartOfDay: Double]
    /// Hour-of-day (0–23) of the day's single highest reading, or nil if the day had no reading.
    public let peakHour: Int?
    /// Mean 0–3 over all of the day's readings, or nil if none.
    public let dayMean: Double?

    public init(partMeans: [PartOfDay: Double], peakHour: Int?, dayMean: Double?) {
        self.partMeans = partMeans
        self.peakHour = peakHour
        self.dayMean = dayMean
    }

    /// True when the day had no usable reading (every bucket was no-reading). Such days are skipped by
    /// the persister and the detector.
    public var isEmpty: Bool { dayMean == nil }
}

public extension StressEngine {

    /// Reduce a day's intraday curve to a `StressDaySummary`. Buckets readings by part-of-day using
    /// `calendar` (defaults to the device's current zone — inject a fixed calendar in tests). Ignores
    /// no-reading buckets. Pure.
    static func daySummary(_ curve: [StressPoint], calendar: Calendar = .current) -> StressDaySummary {
        var byPart: [PartOfDay: [Double]] = [:]
        var all: [Double] = []
        var peak: (hour: Int, stress: Double)?
        for p in curve {
            guard let s = p.stress else { continue }
            let hour = calendar.component(.hour, from: p.date)
            byPart[PartOfDay(hour: hour), default: []].append(s)
            all.append(s)
            if peak == nil || s > peak!.stress { peak = (hour, s) }
        }
        let partMeans = byPart.mapValues { $0.reduce(0, +) / Double($0.count) }
        let dayMean = all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
        return StressDaySummary(partMeans: partMeans, peakHour: peak?.hour, dayMean: dayMean)
    }
}
