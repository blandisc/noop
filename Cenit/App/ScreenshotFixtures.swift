#if DEBUG
import Foundation
import WhoopProtocol
import WhoopStore
import StrandAnalytics
import StrandTraining

/// Deterministic synthetic data that forces TodayView into a specific readiness verdict, for the
/// screenshot UI test (`CenitUITests/CenitScreenshotTests`). DEBUG-only — never compiled into a
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
              ["primed", "strained", "balanced", "rundown", "insufficient",
               "calibrating", "downloading"].contains(raw) else { return nil }
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
            // FER-924: anclado a −125 s para que la línea de frescura muestre «hace 2 min» estable
            // (granularidad de minuto) — con `now` mostraba «hace 4 s» y variaba por corrida.
            model.live.lastSyncedAt = Date().timeIntervalSince1970 - 125   // strapSeen == true
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

        // FER · insufficient (numeral en TINTA + «Not enough context for a verdict»): hay recovery de HOY
        // (→ heroState `.verdict`) pero SIN historia previa, así que ninguna señal se puede z-scorear y
        // `synthesize` cae en `.insufficient`. Una sola fila (hoy).
        if state == "insufficient" {
            let dayKey = Repository.localDayKey(today)
            model.repo.setDashboard(days: [DailyMetric(
                day: dayKey, totalSleepMin: 440, efficiency: 0.9,
                deepMin: 95, remMin: 110, lightMin: 235, disturbances: 4,
                restingHr: 50, avgHrv: 55, recovery: 58, strain: 9,
                exerciseCount: 0, spo2Pct: 98, skinTempDevC: 0.05,
                respRateBpm: 14.5, steps: 6000, activeKcalEst: 450)])
            return
        }

        // FER · downloading («Downloading / your night is on its way»): un offload en curso
        // (`live.backfilling`) sin recovery de HOY todavía → `heroState` cae en `.waiting` con el
        // modificador de descarga. Sembramos noches PREVIAS con recovery (para que `fullyLoaded` publique)
        // pero NINGUNA fila de hoy, y prendemos el flag de backfill.
        if state == "downloading" {
            model.live.backfilling = true
            var days: [DailyMetric] = []
            for ago in stride(from: 6, through: 1, by: -1) {   // ayer … −6, sin hoy
                let dayKey = Repository.localDayKey(cal.date(byAdding: .day, value: -ago, to: today)!)
                days.append(DailyMetric(
                    day: dayKey, totalSleepMin: 440, efficiency: 0.9,
                    deepMin: 95, remMin: 110, lightMin: 235, disturbances: 4,
                    restingHr: 51, avgHrv: 56, recovery: 66, strain: 9,
                    exerciseCount: 0, spo2Pct: 97.5, skinTempDevC: 0.05,
                    respRateBpm: 14.5, steps: 7800, activeKcalEst: 450))
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
                switch state {
                case "primed":
                    // HRV muy arriba (z≈+2.7 good) + RHR bajo (good) + carga en el sweet-spot ⇒ good≥2.
                    hrv = 72; rhr = 46; recovery = 82; strain = 9; sleepMin = 445; spo2 = 98; steps = 9240
                case "balanced":
                    // Todo en rango normal (HRV/RHR neutral) — una sola señal good (carga) ⇒ `.balanced`.
                    hrv = 56; rhr = 52; recovery = 66; strain = 10; sleepMin = 440; spo2 = 98; steps = 8100
                case "rundown":
                    // Dos señales de recuperación abajo a la vez (HRV suprimida + RHR elevada) ⇒ `.rundown`.
                    hrv = 33; rhr = 60; recovery = 28; strain = 12; sleepMin = 388; spo2 = 96; steps = 3400
                default: // "strained": exactamente UNA señal mala (HRV) ⇒ `.strained`.
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
        // FER-924: el BPM del header muestra el último bucket — se fija a 62 constante para que
        // dos capturas del mismo estado salgan idénticas (la sinusoide variaba con la hora real).
        if let last = out.last { out[out.count - 1] = HRSample(ts: last.ts, bpm: 62) }
        return out
    }

    // MARK: - Weekly training plan (FER-939 — the Entrenar hub's planned state)

    /// Seed the handoff's demo plan (Día A/B/C + split + this week's completed sessions) so the
    /// Entrenar hub captures its FULL planned layout: open hero, «LA SESIÓN DE HOY», TU PLAN with
    /// check-marked week squares, and a tinted Constancia. Catalog ids are real (so muscles and the
    /// RoutineClassifier tints resolve); the split is laid out around TODAY so the hero always has
    /// a routine regardless of the day the capture runs.
    @MainActor
    static func seedTrainingPlan(_ model: AppModel) async {
        guard let store = await model.repo.storeHandle() else { return }
        let now = Int(Date().timeIntervalSince1970)
        let cal = Calendar(identifier: .gregorian)

        func rex(_ rid: String, _ eid: String, _ pos: Int, sets: Int, reps: Int, kg: Double) -> RoutineExercise {
            let planned = (0..<sets).map { RoutineSet(position: $0, reps: reps, weightKg: kg) }
            return RoutineExercise(routineId: rid, exerciseId: eid, position: pos,
                                   targetSets: sets, targetReps: reps, targetWeightKg: kg,
                                   restMode: .fixed, restSeconds: 90, sets: planned)
        }

        // Push (chest/shoulders → ember) / pull (lats/biceps → teal) / legs (quads → indigo).
        let a = Routine(name: "Día A — Empuje", createdTs: now, updatedTs: now, sortOrder: 0)
        let b = Routine(name: "Día B — Tirón", createdTs: now, updatedTs: now, sortOrder: 1)
        let c = Routine(name: "Día C — Pierna", createdTs: now, updatedTs: now, sortOrder: 2)
        try? await store.saveRoutine(a, exercises: [
            rex(a.id, "Barbell_Bench_Press_-_Medium_Grip", 0, sets: 4, reps: 8, kg: 80),
            rex(a.id, "Incline_Dumbbell_Press", 1, sets: 3, reps: 10, kg: 26),
            rex(a.id, "Dumbbell_Lying_One-Arm_Rear_Lateral_Raise", 2, sets: 3, reps: 12, kg: 8),
        ])
        try? await store.saveRoutine(b, exercises: [
            rex(b.id, "Barbell_Deadlift", 0, sets: 4, reps: 6, kg: 120),
            rex(b.id, "Close-Grip_Front_Lat_Pulldown", 1, sets: 3, reps: 10, kg: 55),
            rex(b.id, "Barbell_Curl", 2, sets: 3, reps: 10, kg: 30),
        ])
        try? await store.saveRoutine(c, exercises: [
            rex(c.id, "Barbell_Full_Squat", 0, sets: 4, reps: 8, kg: 100),
            rex(c.id, "Dumbbell_Lunges", 1, sets: 3, reps: 10, kg: 20),
        ])

        // Split anchored to TODAY: today = A (hero); +2/−3 days = B; −2 days = C. Weekday numbers
        // stay in Calendar convention (1 = Sun … 7 = Sat) by deriving them from real dates.
        func wd(_ offset: Int) -> Int {
            cal.component(.weekday, from: cal.date(byAdding: .day, value: offset, to: Date())!)
        }
        try? await store.setRoutineSchedule(weekday: wd(0), routineId: a.id)
        try? await store.setRoutineSchedule(weekday: wd(2), routineId: b.id)
        try? await store.setRoutineSchedule(weekday: wd(-3), routineId: b.id)
        try? await store.setRoutineSchedule(weekday: wd(-2), routineId: c.id)

        // Completed sessions: two earlier this week (check-marked week squares) and a few across
        // the prior weeks so the 90-day Constancia grid reads as a real, tinted pattern.
        func session(_ rid: String, exerciseId: String, daysAgo: Int, kg: Double) async {
            guard let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return }
            let start = Int(cal.startOfDay(for: day).timeIntervalSince1970) + 18 * 3600
            let s = StrengthSession(routineId: rid, startTs: start, endTs: start + 50 * 60)
            let sets = (0..<3).map {
                SetEntry(sessionId: s.id, exerciseId: exerciseId, position: $0,
                         kind: .work, weightKg: kg, reps: 8, done: true, ts: start + $0 * 300)
            }
            try? await store.saveSession(s, sets: sets)
        }
        await session(c.id, exerciseId: "Barbell_Full_Squat", daysAgo: 2, kg: 100)
        await session(b.id, exerciseId: "Barbell_Deadlift", daysAgo: 3, kg: 120)
        await session(a.id, exerciseId: "Barbell_Bench_Press_-_Medium_Grip", daysAgo: 7, kg: 80)
        await session(b.id, exerciseId: "Barbell_Deadlift", daysAgo: 10, kg: 115)
        await session(c.id, exerciseId: "Barbell_Full_Squat", daysAgo: 16, kg: 95)
        await session(a.id, exerciseId: "Barbell_Bench_Press_-_Medium_Grip", daysAgo: 23, kg: 77.5)
        await session(b.id, exerciseId: "Barbell_Deadlift", daysAgo: 31, kg: 110)
    }
}
#endif
