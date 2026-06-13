import Foundation
import WhoopStore
import StrandImport

/// Maps a parsed Whoop CSV export into the on-device WhoopStore tables the UI reads
/// (dailyMetric + sleepSession), so importing lights up the full history immediately.
enum WhoopImporter {

    @discardableResult
    static func importExport(url: URL, into store: WhoopStore, deviceId: String) async throws -> ImportSummary {
        let result = try ImportCoordinator().importWhoopExport(from: url)
        // The CSV parse is synchronous; bail before the store writes if the import was cancelled
        // (e.g. the user left mid-import) so a cancelled run doesn't still write rows (FER-33).
        try Task.checkCancellation()

        // physiological_cycles → DailyMetric (one row per sleep-to-sleep day)
        var metrics: [DailyMetric] = []
        for c in result.cycles {
            guard let start = c.cycleStart else { continue }
            metrics.append(DailyMetric(
                day: dayString(start, tzOffsetMin: c.tzOffsetMin),
                totalSleepMin: c.asleepDurationMin,
                efficiency: c.sleepEfficiencyPct,
                deepMin: c.deepSleepDurationMin,
                remMin: c.remDurationMin,
                lightMin: c.lightSleepDurationMin,
                disturbances: nil,
                restingHr: c.restingHeartRate.map { Int($0.rounded()) },
                avgHrv: c.hrvMs,
                recovery: c.recoveryScore,
                strain: c.dayStrain,
                exerciseCount: nil,
                spo2Pct: c.bloodOxygenPct,
                skinTempDevC: c.skinTempCelsius,   // NOTE: Whoop export gives absolute °C, not a baseline deviation
                respRateBpm: c.respiratoryRate))
        }

        // sleeps → CachedSleepSession (stage durations encoded as JSON; export has no per-epoch timeline)
        var sessions: [CachedSleepSession] = []
        for s in result.sleeps where !s.isNap {
            guard let onset = s.sleepOnset, let wake = s.wakeOnset else { continue }
            let stages: [String: Double] = [
                "light": s.lightSleepDurationMin ?? 0,
                "deep": s.deepSleepDurationMin ?? 0,
                "rem": s.remDurationMin ?? 0,
                "awake": s.awakeDurationMin ?? 0,
            ]
            let json = (try? JSONSerialization.data(withJSONObject: stages))
                .flatMap { String(data: $0, encoding: .utf8) }
            sessions.append(CachedSleepSession(
                startTs: Int(onset.timeIntervalSince1970),
                endTs: Int(wake.timeIntervalSince1970),
                efficiency: s.sleepEfficiencyPct,
                restingHr: nil, avgHrv: nil, stagesJSON: json))
        }

        try await store.upsertDailyMetrics(metrics, deviceId: deviceId)
        try await store.upsertSleepSessions(sessions, deviceId: deviceId)

        // Generic metric series — every cycle field, keyed, for the explorer + correlations.
        var points: [MetricPoint] = []
        func add(_ day: String, _ key: String, _ v: Double?) {
            if let v { points.append(MetricPoint(day: day, key: key, value: v)) }
        }
        for c in result.cycles {
            guard let start = c.cycleStart else { continue }
            let day = dayString(start, tzOffsetMin: c.tzOffsetMin)
            add(day, "recovery", c.recoveryScore);        add(day, "strain", c.dayStrain)
            add(day, "rhr", c.restingHeartRate);          add(day, "hrv", c.hrvMs)
            add(day, "spo2", c.bloodOxygenPct);           add(day, "skin_temp", c.skinTempCelsius)
            add(day, "resp_rate", c.respiratoryRate);     add(day, "energy_kcal", c.energyKcal)
            add(day, "avg_hr", c.avgHeartRate);           add(day, "max_hr", c.maxHeartRate)
            add(day, "sleep_total_min", c.asleepDurationMin); add(day, "in_bed_min", c.inBedDurationMin)
            add(day, "sleep_deep_min", c.deepSleepDurationMin); add(day, "sleep_rem_min", c.remDurationMin)
            add(day, "sleep_light_min", c.lightSleepDurationMin); add(day, "awake_min", c.awakeDurationMin)
            add(day, "sleep_efficiency", c.sleepEfficiencyPct); add(day, "sleep_performance", c.sleepPerformancePct)
            add(day, "sleep_consistency", c.sleepConsistencyPct); add(day, "sleep_need_min", c.sleepNeedMin)
            add(day, "sleep_debt_min", c.sleepDebtMin)
            if let deep = c.deepSleepDurationMin, let rem = c.remDurationMin {
                add(day, "restorative_min", deep + rem)
                if let asleep = c.asleepDurationMin, asleep > 0 {
                    add(day, "restorative_pct", (deep + rem) / asleep * 100)
                }
            }
            if let asleep = c.asleepDurationMin, let need = c.sleepNeedMin, need > 0 {
                add(day, "hours_vs_needed_pct", asleep / need * 100)
            }
        }
        // Derived: a daily stress proxy from RHR (up) + HRV (down) vs the personal baseline.
        func meanStd(_ a: [Double]) -> (Double, Double) {
            guard !a.isEmpty else { return (0, 1) }
            let m = a.reduce(0, +) / Double(a.count)
            let v = a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(a.count)
            return (m, max(v.squareRoot(), 0.0001))
        }
        let (rm, rs) = meanStd(result.cycles.compactMap(\.restingHeartRate))
        let (hm, hs) = meanStd(result.cycles.compactMap(\.hrvMs))
        for c in result.cycles {
            guard let start = c.cycleStart, let rhr = c.restingHeartRate, let hrv = c.hrvMs else { continue }
            let z = 0.6 * ((rhr - rm) / rs) - 0.6 * ((hrv - hm) / hs)
            add(dayString(start, tzOffsetMin: c.tzOffsetMin), "stress", max(0, min(3, 1.5 + z)))
        }
        // Derived: daily HR-zone minutes + strength-activity time from workouts.
        var zoneByDay: [String: [Double]] = [:]
        var strengthByDay: [String: Double] = [:]
        for w in result.workouts {
            guard let s = w.workoutStart, let e = w.workoutEnd else { continue }
            let day = dayString(s, tzOffsetMin: w.tzOffsetMin)
            let dur = e.timeIntervalSince(s) / 60.0
            let zp = [w.hrZone1Pct, w.hrZone2Pct, w.hrZone3Pct, w.hrZone4Pct, w.hrZone5Pct]
            var arr = zoneByDay[day] ?? [0, 0, 0, 0, 0]
            for i in 0..<5 { if let p = zp[i] { arr[i] += dur * p / 100.0 } }
            zoneByDay[day] = arr
            if let n = w.activityName?.lowercased(), n.contains("strength") || n.contains("weight") {
                strengthByDay[day, default: 0] += dur
            }
        }
        for (day, a) in zoneByDay {
            add(day, "hr_zone1_min", a[0]); add(day, "hr_zone2_min", a[1]); add(day, "hr_zone3_min", a[2])
            add(day, "hr_zone4_min", a[3]); add(day, "hr_zone5_min", a[4])
            add(day, "hr_zones13_min", a[0] + a[1] + a[2]); add(day, "hr_zones45_min", a[3] + a[4])
            add(day, "hr_zones_all_min", a.reduce(0, +))
        }
        for (day, m) in strengthByDay { add(day, "strength_min", m) }
        try await store.upsertMetricSeries(points, deviceId: deviceId)

        // Journal behaviours → correlation insights.
        let journal: [JournalEntry] = result.journal.compactMap { j in
            guard let start = j.cycleStart, let q = j.question else { return nil }
            return JournalEntry(day: dayString(start, tzOffsetMin: j.tzOffsetMin),
                                question: q,
                                answeredYes: (j.answer ?? "").lowercased() == "true",
                                notes: j.notes)
        }
        try await store.upsertJournal(journal, deviceId: deviceId)

        // Workouts.
        let workouts: [WorkoutRow] = result.workouts.compactMap { w in
            guard let s = w.workoutStart, let e = w.workoutEnd else { return nil }
            let zones = ["z1": w.hrZone1Pct, "z2": w.hrZone2Pct, "z3": w.hrZone3Pct,
                         "z4": w.hrZone4Pct, "z5": w.hrZone5Pct].compactMapValues { $0 }
            let zjson = (try? JSONSerialization.data(withJSONObject: zones))
                .flatMap { String(data: $0, encoding: .utf8) }
            return WorkoutRow(startTs: Int(s.timeIntervalSince1970), endTs: Int(e.timeIntervalSince1970),
                              sport: w.activityName ?? "Workout", source: "whoop",
                              durationS: e.timeIntervalSince(s), energyKcal: w.energyKcal,
                              avgHr: w.avgHeartRate.map { Int($0.rounded()) },
                              maxHr: w.maxHeartRate.map { Int($0.rounded()) },
                              strain: w.activityStrain, distanceM: w.distanceMeters,
                              zonesJSON: zjson, notes: nil)
        }
        try await store.upsertWorkouts(workouts, deviceId: deviceId)

        return result.summary
    }

    /// Local-calendar day string for the cycle's own UTC offset.
    private static func dayString(_ d: Date, tzOffsetMin: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: tzOffsetMin * 60) ?? TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
