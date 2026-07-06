#if DEBUG
import Foundation
import WhoopProtocol
import WhoopStore
import StrandAnalytics

/// Deterministic synthetic data that forces TodayView into a specific readiness verdict, for the
/// screenshot UI test (`CenitUITests/NOOPScreenshotTests`). DEBUG-only — never compiled into a
/// Release build, and gated at the call site (`AppModel.init`) on the `-noop.fixture` launch argument.
///
/// The values are reverse-engineered against `ReadinessEngine` + `Baselines` so each state lands
/// unambiguously past the engine's thresholds (verified, not guessed):
///   - **primed**   — today's HRV well above baseline (z ≈ +2.7 → good), resting HR below baseline
///                    (good), training load in the ACWR sweet-spot (good) ⇒ `good ≥ 2`, no watch/bad.
///   - **strained** — today's HRV well below baseline (z ≈ −3.5 → bad), everything else neutral/good
///                    ⇒ exactly one bad recovery signal, load normal ⇒ `.strained` (not `.rundown`).
/// `respRate`/`skinTemp` are held flat so they raise no flag; the weekly strain cycle keeps monotony
/// low (≈0.9 < 2.0) and ACWR ≈ 1.0, so neither sneaks an extra flag in.
enum ScreenshotFixtures {

    /// The requested fixture state, or nil when not in fixture mode. `-noop.fixture empty` (and an
    /// absent argument) both return nil so the app takes its normal empty/first-launch path.
    /// FER-711 adds `calibrating` (the `··` numeral — a strap seen, base not yet seeded) so the
    /// «numeral nunca miente» discipline of the states map is deterministically capturable.
    static func activeState() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: "noop.fixture")?
            .trimmingCharacters(in: .whitespaces).lowercased(),
              raw == "primed" || raw == "strained" || raw == "calibrating" else { return nil }
        return raw
    }

    /// Seed the synthetic history (dashboard), matching workouts, and a 24h HR trace, then publish it.
    /// The dashboard `setDashboard` is published LAST so it wins over the store reads and fires a single
    /// `refreshSeq` bump (which drives TodayView's `loadAll`, reading the workouts + HR we just wrote).
    @MainActor
    static func seed(_ model: AppModel, state: String) async {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        // FER-711 · calibrating (`··`): a strap has been seen but only a couple of nights are banked,
        // below the recovery seed gate — so `heroState` lands on `.calibrating` and the hero numeral
        // is «··» (never a fake number). Seed a short strap history with usable HRV and NO recovery on
        // any row (recovery stays nil until the baseline seeds), and mark the strap as seen.
        if state == "calibrating" {
            model.live.lastSyncedAt = Date().timeIntervalSince1970   // strapSeen == true
            let nights = 2
            var days: [DailyMetric] = []
            for ago in stride(from: nights, through: 0, by: -1) {
                let dayKey = Repository.localDayKey(cal.date(byAdding: .day, value: -ago, to: today)!)
                days.append(DailyMetric(
                    day: dayKey, totalSleepMin: 430, efficiency: 0.9,
                    deepMin: 95, remMin: 110, lightMin: 225, disturbances: 4,
                    restingHr: 51, avgHrv: 56, recovery: nil, strain: 8,
                    exerciseCount: 0, spo2Pct: 97.4, skinTempDevC: 0.05,
                    respRateBpm: 14.4, steps: 5200, activeKcalEst: 420))
            }
            model.repo.setDashboard(days: days)
            return
        }

        let primed = (state == "primed")

        // Small, deterministic per-day wobble so trends/sparklines look real (no RNG → reproducible).
        func wobble(_ idx: Int, _ amp: Double, _ phase: Double) -> Double {
            amp * sin(Double(idx) * 0.7 + phase)
        }
        // A varied weekly strain cycle keeps ACWR in the sweet spot and monotony low.
        let strainCycle: [Double] = [6, 13, 9, 15, 7, 11, 14]

        let nDays = 40
        var days: [DailyMetric] = []
        for ago in stride(from: nDays - 1, through: 0, by: -1) {  // oldest → newest
            let idx = nDays - 1 - ago                              // 0 … 39, chronological
            let isToday = (ago == 0)
            let dayKey = Repository.localDayKey(cal.date(byAdding: .day, value: -ago, to: today)!)

            // History defaults (the personal baseline the engine learns).
            var hrv = 55 + wobble(idx, 4, 0)
            var rhr = 52 + Int(wobble(idx, 2, 1).rounded())
            var recovery = 64 + wobble(idx, 12, 0.5)
            var strain = strainCycle[idx % strainCycle.count]
            var sleepMin = 440 + wobble(idx, 30, 0.3)
            var spo2 = 97.5
            var steps = 8000 + Int(wobble(idx, 1500, 0.2))

            if isToday {
                if primed {
                    hrv = 72; rhr = 46; recovery = 82; strain = 9; sleepMin = 445; spo2 = 98; steps = 9240
                } else {
                    hrv = 33; rhr = 52; recovery = 45; strain = 11; sleepMin = 402; spo2 = 97; steps = 4180
                }
            }

            let deep = 95.0, rem = 110.0
            days.append(DailyMetric(
                day: dayKey,
                totalSleepMin: sleepMin,
                efficiency: 0.90 + wobble(idx, 0.03, 0.4),
                deepMin: deep, remMin: rem, lightMin: max(0, sleepMin - deep - rem),
                disturbances: 4,
                restingHr: rhr,
                avgHrv: hrv,
                recovery: recovery,
                strain: strain,
                exerciseCount: idx % 3,
                spo2Pct: spo2,
                skinTempDevC: 0.05,                 // flat ⇒ no skin-temp flag
                respRateBpm: 14.5,                  // flat ⇒ SD 0 ⇒ no respiratory flag
                steps: steps,
                activeKcalEst: 480 + wobble(idx, 120, 0.6)
            ))
        }

        // Workouts + a 24h HR trace need the store (TodayView reads them back via loadAll).
        if let store = await model.repo.storeHandle() {
            _ = try? await store.upsertWorkouts(syntheticWorkouts(today: today, cal: cal, primed: primed),
                                                deviceId: model.deviceId)
            let hr = syntheticHRSamples(today: today, cal: cal)
            _ = try? await store.insert(Streams(hr: hr), deviceId: model.deviceId)
        }

        // Publish the dashboard last — single refreshSeq bump, drives loadAll.
        model.repo.setDashboard(days: days)
    }

    /// Six recent sessions (newest first by start time) for the Workouts strip on Today.
    private static func syntheticWorkouts(today: Date, cal: Calendar, primed: Bool) -> [WorkoutRow] {
        struct Spec { let sport: String; let agoDays: Int; let hour: Int; let minutes: Double; let strain: Double }
        let specs: [Spec] = [
            Spec(sport: "Running",  agoDays: 0, hour: 7,  minutes: 45, strain: primed ? 12.4 : 14.2),
            Spec(sport: "Strength", agoDays: 0, hour: 18, minutes: 60, strain: 11.8),
            Spec(sport: "Cycling",  agoDays: 1, hour: 8,  minutes: 90, strain: 16.4),
            Spec(sport: "Yoga",     agoDays: 1, hour: 20, minutes: 30, strain: 5.2),
            Spec(sport: "Running",  agoDays: 3, hour: 7,  minutes: 38, strain: 12.1),
            Spec(sport: "Swimming", agoDays: 4, hour: 19, minutes: 50, strain: 13.7),
        ]
        return specs.map { s in
            let start = cal.date(byAdding: .day, value: -s.agoDays,
                                 to: cal.date(bySettingHour: s.hour, minute: 0, second: 0, of: today)!)!
            let startTs = Int(start.timeIntervalSince1970)
            let durS = s.minutes * 60
            return WorkoutRow(
                startTs: startTs, endTs: startTs + Int(durS),
                sport: s.sport, source: "manual",
                durationS: durS, energyKcal: s.minutes * 8.5,
                avgHr: 138, maxHr: 168, strain: s.strain,
                distanceM: s.sport == "Running" ? s.minutes * 180 : nil,
                zonesJSON: nil, notes: nil)
        }
    }

    /// A plausible 24h HR trace from local midnight to now, one sample every 5 minutes — enough for
    /// the Today "Heart Rate / Since midnight" trend to render (it needs > 1 bucketed point).
    private static func syntheticHRSamples(today: Date, cal: Calendar) -> [HRSample] {
        let midnight = Int(today.timeIntervalSince1970)
        let now = Int(Date().timeIntervalSince1970)
        guard now > midnight else { return [] }
        var out: [HRSample] = []
        var ts = midnight
        var k = 0
        while ts <= now {
            let hour = Double(ts - midnight) / 3600.0
            // Resting overnight, a morning workout bump, a daytime plateau.
            var bpm = 56.0 + 8.0 * sin(hour / 24.0 * 2 * .pi)
            if hour >= 7 && hour < 8 { bpm = 120 + 25 * sin((hour - 7) * .pi) }  // ~workout
            bpm += 4.0 * sin(Double(k) * 0.9)                                    // beat-to-beat texture
            out.append(HRSample(ts: ts, bpm: Int(bpm.rounded())))
            ts += 300; k += 1
        }
        return out
    }
}
#endif
