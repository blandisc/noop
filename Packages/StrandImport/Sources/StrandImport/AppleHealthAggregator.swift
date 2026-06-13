import Foundation

// MARK: - Civil-date arithmetic (no Calendar/DateFormatter)

/// Branch-light, allocation-free conversions between a civil (proleptic Gregorian) date and a day
/// number counting from 1970-01-01 = day 0 — Howard Hinnant's `days_from_civil` /
/// `civil_from_days` algorithms. Used on the Apple Health import hot path so we never touch
/// `Calendar`, `TimeZone`, `DateFormatter`, or `String(format:)` per record (each is orders of
/// magnitude slower than the integer math here, and the parse runs over tens of millions of records).
enum CivilDate {

    /// (year, month, day) → days since 1970-01-01. Valid for the full proleptic Gregorian range.
    static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let yy = (m <= 2) ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400                                       // [0, 399]
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1      // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy               // [0, 146096]
        return era * 146097 + doe - 719468
    }

    /// days since 1970-01-01 → (year, month, day).
    static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097                                     // [0, 146096]
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 // [0, 399]
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)             // [0, 365]
        let mp = (5 * doy + 2) / 153                                   // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1                           // [1, 31]
        let m = mp < 10 ? mp + 3 : mp - 9                             // [1, 12]
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// `yyyy-MM-dd`, zero-padded by hand (avoids `String(format:)`'s varargs/locale cost).
    static func format(year y: Int, month m: Int, day d: Int) -> String {
        func p2(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        let ys: String
        if y >= 1000 { ys = "\(y)" }
        else if y >= 100 { ys = "0\(y)" }
        else if y >= 10 { ys = "00\(y)" }
        else { ys = "000\(max(0, y))" }
        return "\(ys)-\(p2(m))-\(p2(d))"
    }
}

// MARK: - Daily aggregate model

/// One day's worth of Apple Health metrics, bucketed by the sample's own local
/// day (`start` shifted by `tzOffsetMin`). Mirrors the per-day shape the app
/// stores and charts alongside Whoop.
///
/// All `*Min` fields are minutes; energies are kcal; heart rates are count/min;
/// `spo2Pct` is a 0–100 percentage; `vo2max` is mL/kg/min.
public struct AppleDailyAggregate: Equatable, Sendable {
    /// `yyyy-MM-dd` in the sample's own UTC offset (local civil day).
    public let day: String

    // Cardio / respiratory means
    public let restingHr: Double?
    public let hrvSDNN: Double?
    public let spo2Pct: Double?
    public let respRate: Double?

    // Heart-rate stream
    public let avgHr: Double?
    public let maxHr: Double?
    public let walkingHr: Double?

    // Activity / fitness
    public let steps: Double?
    public let activeKcal: Double?
    public let basalKcal: Double?
    public let vo2max: Double?

    // Body composition (daily latest)
    public let weightKg: Double?
    public let bodyFatPct: Double?
    public let leanMassKg: Double?
    public let bmi: Double?

    // Sleep (minutes per stage), keyed by the wake day
    public let asleepMin: Double?
    public let deepMin: Double?
    public let remMin: Double?
    public let coreMin: Double?
    public let awakeMin: Double?
    public let inBedMin: Double?

    public init(
        day: String,
        restingHr: Double? = nil,
        hrvSDNN: Double? = nil,
        spo2Pct: Double? = nil,
        respRate: Double? = nil,
        avgHr: Double? = nil,
        maxHr: Double? = nil,
        walkingHr: Double? = nil,
        steps: Double? = nil,
        activeKcal: Double? = nil,
        basalKcal: Double? = nil,
        vo2max: Double? = nil,
        weightKg: Double? = nil,
        bodyFatPct: Double? = nil,
        leanMassKg: Double? = nil,
        bmi: Double? = nil,
        asleepMin: Double? = nil,
        deepMin: Double? = nil,
        remMin: Double? = nil,
        coreMin: Double? = nil,
        awakeMin: Double? = nil,
        inBedMin: Double? = nil
    ) {
        self.day = day
        self.restingHr = restingHr
        self.hrvSDNN = hrvSDNN
        self.spo2Pct = spo2Pct
        self.respRate = respRate
        self.avgHr = avgHr
        self.maxHr = maxHr
        self.walkingHr = walkingHr
        self.steps = steps
        self.activeKcal = activeKcal
        self.basalKcal = basalKcal
        self.vo2max = vo2max
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.leanMassKg = leanMassKg
        self.bmi = bmi
        self.asleepMin = asleepMin
        self.deepMin = deepMin
        self.remMin = remMin
        self.coreMin = coreMin
        self.awakeMin = awakeMin
        self.inBedMin = inBedMin
    }
}

// MARK: - Streaming day aggregator

/// Folds Apple Health records into per-day aggregates **incrementally** — one
/// record at a time, retaining only O(days) running state — so a multi-year
/// export (tens of millions of `<Record>` elements) never materializes a giant
/// `[HealthSample]` array (the old OOM-on-iOS path). Every reduction the daily
/// aggregate needs is running-computable: means are sum/count, `maxHr` is a
/// running max, body metrics keep the latest-by-`end`, steps/energy are summed.
///
/// This is the single source of truth for the reduction rules: the pure
/// `AppleHealthAggregator.daily(samples:)` / `sleepDaily(_:)` /
/// `aggregate(samples:sleepIntervals:)` helpers (used by tests) all feed it, and
/// so does the streaming SAX importer.
public final class AppleHealthDayAggregator {

    /// Running per-day accumulator — no per-sample arrays.
    private struct DayAcc {
        var restingSum = 0.0, restingCount = 0
        var hrvSum = 0.0, hrvCount = 0
        var spo2Sum = 0.0, spo2Count = 0
        var respSum = 0.0, respCount = 0
        var walkingSum = 0.0, walkingCount = 0
        var hrSum = 0.0, hrCount = 0
        var hrMax: Double?
        var steps = 0.0, hasSteps = false
        var active = 0.0, hasActive = false
        var basal = 0.0, hasBasal = false
        var vo2: Double?, vo2At: Date?
        var weight: Double?, weightAt: Date?
        var bodyFat: Double?, bodyFatAt: Date?
        var lean: Double?, leanAt: Date?
        var bmi: Double?, bmiAt: Date?
    }

    /// Running per-night sleep accumulator (minutes per stage).
    private struct NightAcc {
        var deep = 0.0, rem = 0.0, core = 0.0, unspecified = 0.0, awake = 0.0, inBed = 0.0
    }

    private var byDay: [String: DayAcc] = [:]
    private var dayOrder: [String] = []
    private var byNight: [String: NightAcc] = [:]

    public init() {}

    /// Fold one quantity record into its local day. `value` is the already
    /// importer-normalized numeric (e.g. OxygenSaturation pre-scaled to percent);
    /// `type` may be the stripped or full HK identifier.
    public func addRecord(type rawType: String, value: Double?, unit: String?,
                          start: Date, tzOffsetMin: Int, end: Date) {
        guard let v = value else { return }
        let type = AppleHealthAggregator.normalizedType(rawType)
        let day = AppleHealthAggregator.localDay(start, tzOffsetMin: tzOffsetMin)
        if byDay[day] == nil { byDay[day] = DayAcc(); dayOrder.append(day) }

        switch type {
        case AppleHealthAggregator.T.restingHR:  byDay[day]!.restingSum += v; byDay[day]!.restingCount += 1
        case AppleHealthAggregator.T.hrvSDNN:    byDay[day]!.hrvSum += v; byDay[day]!.hrvCount += 1
        case AppleHealthAggregator.T.spo2:
            // Defend against raw fractional (0..1) values; importer already ×100.
            let pct = (v > 0 && v <= 1.0) ? v * 100.0 : v
            byDay[day]!.spo2Sum += pct; byDay[day]!.spo2Count += 1
        case AppleHealthAggregator.T.respRate:   byDay[day]!.respSum += v; byDay[day]!.respCount += 1
        case AppleHealthAggregator.T.walkingHR:  byDay[day]!.walkingSum += v; byDay[day]!.walkingCount += 1
        case AppleHealthAggregator.T.heartRate:
            byDay[day]!.hrSum += v; byDay[day]!.hrCount += 1
            byDay[day]!.hrMax = max(byDay[day]!.hrMax ?? v, v)
        case AppleHealthAggregator.T.stepCount:    byDay[day]!.steps += v; byDay[day]!.hasSteps = true
        case AppleHealthAggregator.T.activeEnergy: byDay[day]!.active += v; byDay[day]!.hasActive = true
        case AppleHealthAggregator.T.basalEnergy:  byDay[day]!.basal += v; byDay[day]!.hasBasal = true
        case AppleHealthAggregator.T.vo2max:
            if byDay[day]!.vo2 == nil || (byDay[day]!.vo2At ?? .distantPast) <= end {
                byDay[day]!.vo2 = v; byDay[day]!.vo2At = end
            }
        case AppleHealthAggregator.T.bodyMass:
            let kg = AppleHealthAggregator.unitLooksLikePounds(unit) ? v * 0.453592 : v
            if byDay[day]!.weight == nil || (byDay[day]!.weightAt ?? .distantPast) <= end {
                byDay[day]!.weight = kg; byDay[day]!.weightAt = end
            }
        case AppleHealthAggregator.T.bodyFat:
            let pct = (v > 0 && v <= 1.0) ? v * 100.0 : v
            if byDay[day]!.bodyFat == nil || (byDay[day]!.bodyFatAt ?? .distantPast) <= end {
                byDay[day]!.bodyFat = pct; byDay[day]!.bodyFatAt = end
            }
        case AppleHealthAggregator.T.leanMass:
            let kg = AppleHealthAggregator.unitLooksLikePounds(unit) ? v * 0.453592 : v
            if byDay[day]!.lean == nil || (byDay[day]!.leanAt ?? .distantPast) <= end {
                byDay[day]!.lean = kg; byDay[day]!.leanAt = end
            }
        case AppleHealthAggregator.T.bodyMassIndex:
            if byDay[day]!.bmi == nil || (byDay[day]!.bmiAt ?? .distantPast) <= end {
                byDay[day]!.bmi = v; byDay[day]!.bmiAt = end
            }
        default:
            break
        }
    }

    /// Fold one sleep-stage interval into its wake night (the local day of `end`).
    public func addSleep(stage: SleepStage, start: Date, end: Date, tzOffsetMin: Int) {
        let minutes = max(0, end.timeIntervalSince(start)) / 60.0
        let day = AppleHealthAggregator.localDay(end, tzOffsetMin: tzOffsetMin)
        var n = byNight[day] ?? NightAcc()
        switch stage {
        case .asleepDeep:        n.deep += minutes
        case .asleepREM:         n.rem += minutes
        case .asleepCore:        n.core += minutes
        case .asleepUnspecified: n.unspecified += minutes
        case .awake:             n.awake += minutes
        case .inBed:             n.inBed += minutes
        case .unknown:           break
        }
        byNight[day] = n
    }

    // MARK: Outputs

    /// Per-night stage totals keyed by wake day. `asleep = core+deep+rem+unspecified`.
    public func sleepByDay() -> [String: (asleep: Double, deep: Double, rem: Double, core: Double, awake: Double, inBed: Double)] {
        var out: [String: (asleep: Double, deep: Double, rem: Double, core: Double, awake: Double, inBed: Double)] = [:]
        for (day, n) in byNight {
            let asleep = n.core + n.deep + n.rem + n.unspecified
            out[day] = (asleep: asleep, deep: n.deep, rem: n.rem, core: n.core, awake: n.awake, inBed: n.inBed)
        }
        return out
    }

    /// Sample-only daily aggregates (sleep fields nil), first-seen day order then sorted.
    public func sampleDaily() -> [AppleDailyAggregate] {
        dayOrder.map { day in row(day: day, acc: byDay[day]!, sleep: nil) }
            .sorted { $0.day < $1.day }
    }

    /// Full merge of sample-days ∪ sleep-days into one sorted list.
    public func merged() -> [AppleDailyAggregate] {
        var days = Set(byDay.keys)
        days.formUnion(byNight.keys)
        let sleep = sleepByDay()
        return days.map { day in
            row(day: day, acc: byDay[day], sleep: sleep[day])
        }.sorted { $0.day < $1.day }
    }

    private func row(
        day: String,
        acc a: DayAcc?,
        sleep s: (asleep: Double, deep: Double, rem: Double, core: Double, awake: Double, inBed: Double)?
    ) -> AppleDailyAggregate {
        func mean(_ sum: Double, _ count: Int) -> Double? { count > 0 ? sum / Double(count) : nil }
        return AppleDailyAggregate(
            day: day,
            restingHr: a.flatMap { mean($0.restingSum, $0.restingCount) },
            hrvSDNN: a.flatMap { mean($0.hrvSum, $0.hrvCount) },
            spo2Pct: a.flatMap { mean($0.spo2Sum, $0.spo2Count) },
            respRate: a.flatMap { mean($0.respSum, $0.respCount) },
            avgHr: a.flatMap { mean($0.hrSum, $0.hrCount) },
            maxHr: a?.hrMax,
            walkingHr: a.flatMap { mean($0.walkingSum, $0.walkingCount) },
            steps: (a?.hasSteps ?? false) ? a!.steps : nil,
            activeKcal: (a?.hasActive ?? false) ? a!.active : nil,
            basalKcal: (a?.hasBasal ?? false) ? a!.basal : nil,
            vo2max: a?.vo2,
            weightKg: a?.weight,
            bodyFatPct: a?.bodyFat,
            leanMassKg: a?.lean,
            bmi: a?.bmi,
            asleepMin: s?.asleep,
            deepMin: s?.deep,
            remMin: s?.rem,
            coreMin: s?.core,
            awakeMin: s?.awake,
            inBedMin: s?.inBed
        )
    }
}

// MARK: - Aggregator (pure helpers over the streaming engine)

/// Turns parsed Apple Health records into per-day aggregates.
public enum AppleHealthAggregator {

    // MARK: Type identifiers
    //
    // `HealthSample.type` is stored with the `HKQuantityTypeIdentifier` /
    // `HKCategoryTypeIdentifier` prefix already stripped (see
    // `AppleHealthImporter.stripPrefix`). We still accept the full identifier
    // form so callers feeding raw HK strings get the same mapping.

    enum T {
        static let restingHR = "RestingHeartRate"
        static let hrvSDNN = "HeartRateVariabilitySDNN"
        static let spo2 = "OxygenSaturation"
        static let respRate = "RespiratoryRate"
        static let walkingHR = "WalkingHeartRateAverage"
        static let heartRate = "HeartRate"
        static let stepCount = "StepCount"
        static let activeEnergy = "ActiveEnergyBurned"
        static let basalEnergy = "BasalEnergyBurned"
        static let vo2max = "VO2Max"
        static let bodyMass = "BodyMass"
        static let bodyFat = "BodyFatPercentage"
        static let leanMass = "LeanBodyMass"
        static let bodyMassIndex = "BodyMassIndex"
    }

    /// Normalize a sample's `type` to the stripped HK identifier so matching
    /// works whether the caller passed `HeartRate` or
    /// `HKQuantityTypeIdentifierHeartRate`.
    static func normalizedType(_ raw: String) -> String {
        let prefixes = [
            "HKQuantityTypeIdentifier",
            "HKCategoryTypeIdentifier",
            "HKDataTypeIdentifier",
        ]
        for p in prefixes where raw.hasPrefix(p) {
            return String(raw.dropFirst(p.count))
        }
        return raw
    }

    /// Whether a HealthKit mass unit string denotes pounds (`lb`, `lbs`).
    /// HealthKit normally exports BodyMass/LeanBodyMass in kg, but guard against
    /// pound-denominated exports.
    static func unitLooksLikePounds(_ unit: String?) -> Bool {
        guard let u = unit?.lowercased() else { return false }
        return u == "lb" || u == "lbs" || u.contains("pound")
    }

    // MARK: Day bucketing

    /// `yyyy-MM-dd` for a UTC `Date` shifted into its own local offset.
    /// We add the offset to the UTC instant and read the calendar fields in
    /// UTC, which yields the civil (wall-clock) date the sample was recorded on.
    ///
    /// HOT PATH: called once per record over the tens of millions of `<Record>` elements a
    /// multi-year export holds. The old implementation allocated a fresh `Calendar` + `TimeZone`
    /// and ran `String(format:)` on EVERY call — together by far the dominant cost of the parse.
    /// This rewrite uses pure integer arithmetic (no Foundation date machinery, no allocation):
    /// shift the instant, floor-divide to a civil day number, convert to (y,m,d) with Hinnant's
    /// algorithm, and build the string by hand. Behaviour is identical to reading the UTC calendar
    /// fields of the shifted instant.
    static func localDay(_ utc: Date, tzOffsetMin: Int) -> String {
        let shiftedSecs = utc.timeIntervalSince1970 + Double(tzOffsetMin) * 60.0
        let dayNumber = Int((shiftedSecs / 86_400.0).rounded(.down))   // whole days since 1970-01-01 UTC
        let c = CivilDate.civilFromDays(dayNumber)
        return CivilDate.format(year: c.year, month: c.month, day: c.day)
    }

    // MARK: - Pure helpers (feed the streaming aggregator; used by tests)

    /// Group `HealthSamples` by local day and apply the per-type reduction rules.
    /// Sample-only (no sleep) — sleep fields are nil.
    public static func daily(samples: [HealthSample]) -> [AppleDailyAggregate] {
        let agg = AppleHealthDayAggregator()
        for s in samples {
            agg.addRecord(type: s.type, value: s.value, unit: s.unit,
                          start: s.start, tzOffsetMin: s.tzOffsetMin, end: s.end)
        }
        return agg.sampleDaily()
    }

    /// Collapse sleep-stage intervals into per-night totals keyed by the **wake
    /// day** — the local civil day of each interval's `end`.
    public static func sleepDaily(
        _ intervals: [SleepStageInterval]
    ) -> [String: (asleep: Double, deep: Double, rem: Double, core: Double, awake: Double, inBed: Double)] {
        let agg = AppleHealthDayAggregator()
        for iv in intervals {
            agg.addSleep(stage: iv.stage, start: iv.start, end: iv.end, tzOffsetMin: iv.tzOffsetMin)
        }
        return agg.sleepByDay()
    }

    /// Full merge of sample-daily + sleep-daily into `[AppleDailyAggregate]`,
    /// one row per day present in either source, sorted ascending by day.
    public static func aggregate(
        samples: [HealthSample],
        sleepIntervals: [SleepStageInterval]
    ) -> [AppleDailyAggregate] {
        let agg = AppleHealthDayAggregator()
        for s in samples {
            agg.addRecord(type: s.type, value: s.value, unit: s.unit,
                          start: s.start, tzOffsetMin: s.tzOffsetMin, end: s.end)
        }
        for iv in sleepIntervals {
            agg.addSleep(stage: iv.stage, start: iv.start, end: iv.end, tzOffsetMin: iv.tzOffsetMin)
        }
        return agg.merged()
    }

    // MARK: - Metric point flattening

    /// Flatten daily aggregates into generic `(day, key, value)` metric points
    /// for the metricSeries store. Only present (non-nil) values are emitted.
    /// Keys are stable, snake_case identifiers.
    public static func metricPoints(_ daily: [AppleDailyAggregate]) -> [(day: String, key: String, value: Double)] {
        var out: [(day: String, key: String, value: Double)] = []
        for d in daily {
            func add(_ key: String, _ value: Double?) {
                if let v = value { out.append((day: d.day, key: key, value: v)) }
            }
            add("resting_hr", d.restingHr)
            add("hrv", d.hrvSDNN)
            add("spo2", d.spo2Pct)
            add("resp_rate", d.respRate)
            add("avg_hr", d.avgHr)
            add("max_hr", d.maxHr)
            add("walking_hr", d.walkingHr)
            add("steps", d.steps)
            add("active_kcal", d.activeKcal)
            add("basal_kcal", d.basalKcal)
            add("vo2max", d.vo2max)
            add("weight", d.weightKg)
            add("body_fat", d.bodyFatPct)
            add("lean_mass", d.leanMassKg)
            add("bmi", d.bmi)
            add("asleep_min", d.asleepMin)
            add("deep_min", d.deepMin)
            add("rem_min", d.remMin)
            add("core_min", d.coreMin)
            add("awake_min", d.awakeMin)
            add("in_bed_min", d.inBedMin)
        }
        return out
    }
}
