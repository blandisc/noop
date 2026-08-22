#if DEBUG
import Foundation
import BiometricStreams
import CenitStore
import StrandAnalytics
import StrandTraining

/// Deterministic synthetic data that forces TodayView into a specific readiness verdict, for the
/// screenshot UI test (`CenitUITests/CenitScreenshotTests`). DEBUG-only — never compiled into a
/// Release build, and gated at the call site (`AppModel.init`) on the `-noop.fixture` launch argument.
///
/// The values are calibrated against **`Preparedness`** (the engine the hero actually reads —
/// verdict = count of axes out: 0 → `.full`, 1 → `.caution`, ≥2 → `.easy`; re-verified against
/// thresholds 2026-08-15, conceptual review). Axes: autonomic = RHR only (wHRV=0), out at
/// z ≤ −1.0 with σ = 1.253·spread (floor 2 bpm); sleep out under 375 min or eff < 0.80;
/// sentinel votes only with temp ≥ 0.8 °C AND resp z ≥ 1.5 together. Hysteresis needs 2
/// consecutive days, so the bad states seed today AND yesterday:
///   - **primed**   — 0 axes out ⇒ `.full` («In range»).
///   - **strained** — RHR 60 vs base 52 (z≈−3.2), sleep fine ⇒ 1 axis ⇒ `.caution` («Go light today»).
///   - **rundown**  — RHR 62 + sleep 340 < 375 ⇒ 2 axes ⇒ `.easy` («Recover»).
/// `respRate`/`skinTemp` wave INSIDE the typical band (guardian sparklines look real, no flag).
enum ScreenshotFixtures {

    /// The requested fixture state, or nil when not in fixture mode. `-noop.fixture empty` (and an
    /// absent argument) both return nil so the app takes its normal empty/first-launch path.
    /// FER-711 adds `calibrating` (the `··` numeral — a strap seen, base not yet seeded) so the
    /// «numeral nunca miente» discipline of the states map is deterministically capturable.
    static func activeState() -> String? {
        // SIMULATOR-ONLY, ALWAYS. The fixtures write demo routines/sessions/workouts into the REAL
        // persistent store (TodayView reads them back via loadAll) and those rows OUTLIVE the flag —
        // on a physical device that permanently pollutes the on-device DB. Screenshot UI tests run on
        // the simulator, so hard-gating here loses no coverage while making it impossible for a stray
        // `-noop.fixture` launch arg (e.g. left in a personal Xcode scheme) to contaminate a real
        // iPhone build. Every fixture consumer (init seed, analysis skip, the fake 9:41 clock) routes
        // through this one guard, so they all go inert on device together.
        #if !targetEnvironment(simulator)
        return nil
        #else
        guard let raw = UserDefaults.standard.string(forKey: "noop.fixture")?
            .trimmingCharacters(in: .whitespaces).lowercased(),
              ["primed", "strained", "balanced", "rundown", "insufficient",
               "calibrating", "downloading", "train"].contains(raw) else { return nil }
        return raw
        #endif
    }

    /// Seed the synthetic history (dashboard), matching workouts, and a 24h HR trace, then publish it.
    /// The dashboard `setDashboard` is published LAST so it wins over the store reads and fires a single
    /// `refreshSeq` bump (which drives TodayView's `loadAll`, reading the workouts + HR we just wrote).
    @MainActor
    static func seed(_ model: AppModel, state: String) async {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())

        // FER-711 · calibrating (`··`): a strap has been seen but only a couple of nights are banked,
        // below the recovery seed gate — so Today renders its calibrating / cold-start state (never a
        // fake number). Seed a short strap history with usable HRV and NO recovery on
        // any row (recovery stays nil until the baseline seeds), and mark the strap as seen.
        if state == "calibrating" {
            // Ola 2: strap-seen fixture no longer applicable (no strap live state); calibrating is driven by night count alone.
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
            // Revisión conceptual (dueño 2026-08-15): SIN publicar Preparedness el héroe caía
            // al fallback con nights=0 («Night 0 of 4») — el progreso de las 2 noches bancadas
            // se perdía. Con evaluate: lowSignal + autonomicNights=2 ⇒ «Night 2 of 4».
            let prepCal = Preparedness.evaluate(.init(
                days: days, strainByDay: [:], trend: nil, asOf: Repository.localDayKey(today)))
            model.repo.setDashboard(days: days,
                                    appleHealthDays: Set(days.map(\.day)),
                                    preparedness: prepCal)
            return
        }

        // FER · insufficient (numeral en TINTA + «Not enough context for a verdict»): hay recovery de HOY
        // (hay lectura de hoy) pero SIN historia previa, así que ninguna señal se puede z-scorear y
        // `synthesize` cae en `.insufficient`. Una sola fila (hoy).
        if state == "insufficient" {
            let dayKey = Repository.localDayKey(today)
            let dias = [DailyMetric(
                day: dayKey, totalSleepMin: 440, efficiency: 0.9,
                deepMin: 95, remMin: 110, lightMin: 235, disturbances: 4,
                restingHr: 50, avgHrv: 55, recovery: 58, strain: 9,
                exerciseCount: 0, spo2Pct: 98, skinTempDevC: 0.05,
                respRateBpm: 14.5, steps: 6000, activeKcalEst: 450)]
            // Como `calibrating`/`downloading`: el motor se publica para que héroe y acta digan
            // lo mismo que dirían en producción con una sola noche (FER-128 r12).
            let prepIns = Preparedness.evaluate(.init(
                days: dias, strainByDay: [:], trend: nil, asOf: dayKey))
            model.repo.setDashboard(days: dias, preparedness: prepIns)
            return
        }

        // FER · downloading: sin banda, no hay backfill flag. Sembramos noches PREVIAS con recovery
        // (para que `fullyLoaded` publique) pero NINGUNA fila de hoy → Today queda sin lectura de hoy.
        if state == "downloading" {
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
            // Como `calibrating`: SIN publicar Preparedness el héroe caía a «Conociéndote · Aún
            // sin noches útiles» sobre 6 noches reales; `evaluate` sin fila de hoy conserva las
            // noches bancadas y dice «Sin lectura hoy» (FER-128 r11).
            let prepDl = Preparedness.evaluate(.init(
                days: days, strainByDay: [:], trend: nil, asOf: Repository.localDayKey(today)))
            model.repo.setDashboard(days: days, preparedness: prepDl)
            return
        }

        // FER · train (flujo de Entrenar): recuperación de hoy (para la banda de Entrenar) + 3 rutinas
        // de plantilla (Empuje/Jalón/Pierna) guardadas en el store y asignadas al split semanal, con
        // Empuje = HOY. Puebla el hub, «Tu Plan», «Rutina de hoy» y la sesión guiada con datos reales.
        if state == "train" {
            var days: [DailyMetric] = []
            for ago in stride(from: 6, through: 0, by: -1) {
                let dayKey = Repository.localDayKey(cal.date(byAdding: .day, value: -ago, to: today)!)
                days.append(DailyMetric(
                    day: dayKey, totalSleepMin: 445, efficiency: 0.9,
                    deepMin: 95, remMin: 110, lightMin: 240, disturbances: 4,
                    restingHr: 50, avgHrv: 60, recovery: ago == 0 ? 74 : 64, strain: 9,
                    exerciseCount: 0, spo2Pct: 98, skinTempDevC: 0.05,
                    respRateBpm: 14.5, steps: 8200, activeKcalEst: 450))
            }
            if let store = await model.repo.storeHandle() {
                let now = Int(Date().timeIntervalSince1970)
                let picks: [(String, String)] = [("ppl-push", "Empuje"), ("ppl-pull", "Jalón"), ("ppl-legs", "Pierna")]
                var ids: [String] = []
                for (tid, name) in picks {
                    guard let t = StarterTemplates.byID(tid) else { continue }
                    let rid = UUID().uuidString
                    let (routine, exercises) = t.makeRoutine(name: name, now: now, routineId: rid)
                    try? await store.saveRoutine(routine, exercises: exercises)
                    ids.append(rid)
                }
                // Split: Empuje = HOY; Jalón y Pierna en los dos días siguientes.
                let wd = cal.component(.weekday, from: Date())   // 1…7
                if ids.count == 3 {
                    try? await store.setRoutineSchedule(weekday: wd, routineId: ids[0])
                    try? await store.setRoutineSchedule(weekday: (wd % 7) + 1, routineId: ids[1])
                    try? await store.setRoutineSchedule(weekday: ((wd + 1) % 7) + 1, routineId: ids[2])
                }
            }
            model.repo.setDashboard(days: days)   // publica al final → dispara loadAll
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

            // Los estados MALOS (strained/rundown) se siembran los ÚLTIMOS 2 DÍAS, no solo hoy:
            // el veredicto tiene histéresis (una señal fuera un solo día NO baja el veredicto —
            // se sostiene hasta que se repite dos días seguidos), así que con un único día malo
            // el fixture renderizaba «Dale con todo» sobre un orbe rojo. Los estados de un día
            // (primed/balanced, buenos) solo tocan HOY.
            // RE-CALIBRADO contra Preparedness (revisión conceptual del dueño, 2026-08-15): el
            // héroe lee Preparedness.Verdict (ejes fuera: 0→full, 1→caution, ≥2→easy), NO el
            // ReadinessEngine legado. Ejes: autonómico = SOLO RHR (wHRV=0, O'Grady 2024; fuera
            // si z≤−1.0 con σ=1.253·spread, piso 2 bpm ⇒ rhr 60 vs base 52 → z≈−3.2); sueño =
            // fuera si <375 min (420−45 de slack) o eff<0.80; centinela = temp≥0.8 °C ∧ resp
            // z≥1.5 juntas. La histéresis exige 2 días seguidos → los malos siembran HOY y AYER.
            let esMalo = (state == "strained" || state == "rundown")
            if isToday || (esMalo && ago == 1) {
                switch state {
                case "primed":
                    // 0 ejes fuera ⇒ .full («In range»). RHR bajo + sueño amplio.
                    hrv = 72; rhr = 46; recovery = 82; strain = 9; sleepMin = 445; spo2 = 98; steps = 9240
                case "balanced":
                    // También .full — Preparedness NO tiene estado intermedio (legado del motor
                    // viejo; se conserva por compat, la galería usa primed).
                    hrv = 56; rhr = 52; recovery = 66; strain = 10; sleepMin = 440; spo2 = 98; steps = 8100
                case "rundown":
                    // DOS ejes fuera 2 días (RHR z≈−3.5 + sueño 340<375) ⇒ .easy («Recover») —
                    // antes sleep 388 se quedaba 14 min ARRIBA del corte y salía ámbar.
                    hrv = 33; rhr = 62; recovery = 28; strain = 12; sleepMin = 340; spo2 = 96; steps = 3400
                default: // "strained": UN eje fuera (RHR elevada; sueño en rango) ⇒ .caution
                    // («Go light today»). Antes rhr 52 ≈ base ⇒ 0 ejes ⇒ pintaba VERDE: la HRV
                    // baja NO vota — queda como señal informativa en el detalle.
                    hrv = 33; rhr = 60; recovery = 45; strain = 11; sleepMin = 440; spo2 = 97; steps = 4180
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
                // Ola nocturna DENTRO de la banda típica (temp ±0.4, resp 12–16) — natural, NO
                // dispara flag: los sparklines del guardián se leen como datos reales, no una raya.
                skinTempDevC: 0.05 + wobble(idx, 0.14, 0.9),
                respRateBpm: 14.5 + wobble(idx, 0.85, 0.5),
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

        // FER-1030: the Liquid Hoy hero/axes read `repo.todayPreparedness`, not `days` directly — compute
        // it with the real engine over the same synthetic history so the fixture states drive the hero
        // (no `trend`/`strainByDay`: the autonomic axis reads `days` alone, matching a whoopOnly user).
        let preparedness = Preparedness.evaluate(.init(
            days: days, strainByDay: [:], trend: nil, asOf: Repository.localDayKey(today)))

        // Publish the dashboard last — single refreshSeq bump, drives loadAll.
        // #inject · `sleeps` enciende la ruta RICA de la hoja de Sueño en el simulador
        // (ventana acostarse→despertar, etapas medidas y regularidad con puntaje). Sin ellas
        // la hoja cae a su fallback clásico —sin etapas ni regularidad—, que es lo que el
        // dueño reportó «faltando». Solo el fixture de screenshots (DEBUG/sim).
        // #inject · `appleHealthDays`: los días del fixture SON datos «de Apple Salud»
        // (axioma Apple-only) — sin marcarlos, `fromApple` resolvía false y el pie de las
        // hojas perdía su chip de procedencia («Apple Salud · en tu dispositivo»).
        model.repo.setDashboard(days: days,
                                sleeps: Self.syntheticSleepSessions(days: days),
                                appleHealthDays: Set(days.map(\.day)),
                                preparedness: preparedness)
    }

    /// #inject · Una sesión de sueño por noche del dashboard, para que `SleepDetailModel.build`
    /// arme una noche RICA (ventana real + etapas + regularidad). Acostarse ~23:00 con una
    /// deriva chica noche a noche (regularidad alta); las etapas salen de los minutos del día.
    private static func syntheticSleepSessions(days: [DailyMetric]) -> [CachedSleepSession] {
        days.enumerated().compactMap { (idx, d) -> CachedSleepSession? in
            // Medianoche LOCAL del día (revisión adversarial DeepSeek): `parseDayKey`
            // devuelve medianoche UTC — con ella, en UTC−6 la «acostada 23:00» salía 17:00.
            // El day key es una fecha civil local: se re-arma en el calendario local.
            let parts = d.day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let localMidnight = Calendar.current.date(from: DateComponents(
                      year: parts[0], month: parts[1], day: parts[2])) else { return nil }
            let midnight = Int(localMidnight.timeIntervalSince1970)
            let drift = (idx % 3 - 1) * 12 * 60                 // −12 · 0 · +12 min noche a noche
            let onset = midnight - 3600 + drift                 // ~23:00 local de la noche anterior
            let total = max(3600, Int(d.totalSleepMin ?? 445) * 60)   // piso defensivo (endTs > startTs)
            let deep = Int(d.deepMin ?? 95), rem = Int(d.remMin ?? 110)
            let light = Int(d.lightMin ?? 235), awake = 28
            // TRAMOS por época, no totales. `decodeSegments` espera un ARREGLO de
            // {start,end,stage} con marcas absolutas y descarta cualquier otra cosa: con el
            // objeto de totales que había aquí, `intervals` salía vacío y el detalle de Sueño
            // caía siempre a la barra apilada — el hipnograma no se podía ver ni en capturas
            // ni en el simulador. (FER-102)
            let stages = hipnogramaJSON(onset: onset, deep: deep, rem: rem,
                                        light: light, awake: awake)
            // La VENTANA en cama = dormido + despierto (revisión Grok): sin sumar `awake`,
            // las etapas exceden el reloj acostarse→despertar por 28 min cada noche.
            return CachedSleepSession(startTs: onset, endTs: onset + total + awake * 60,
                                      efficiency: d.efficiency, restingHr: d.restingHr,
                                      avgHrv: d.avgHrv, stagesJSON: stages)
        }
    }


    /// Una noche con FORMA: ciclos de ~90 min (ligero → profundo → ligero → REM) con
    /// microdespertares, en el formato que `SleepDetailScreen.decodeSegments` sabe leer.
    ///
    /// No es un adorno de la fixture: sin tramos, la pantalla de detalle no puede dibujar su
    /// hipnograma, que es la pieza firma de la sección «Anoche». Los minutos por etapa suman
    /// exactamente los que pide el caller, para que la barra, la leyenda y el hipnograma
    /// cuenten lo mismo.
    private static func hipnogramaJSON(onset: Int, deep: Int, rem: Int,
                                       light: Int, awake: Int) -> String {
        // 4 ciclos: el profundo pesa al principio de la noche y el REM al final, como en la
        // fisiología real (y como lo cuenta el bloque «Forma de la noche»).
        let pesosProfundo = [0.40, 0.30, 0.20, 0.10]
        let pesosRem      = [0.10, 0.20, 0.30, 0.40]
        let pesosLigero   = [0.25, 0.25, 0.25, 0.25]
        // Reparto entero con el residuo en el último ciclo: los tramos suman EXACTO lo que el
        // titular dice (antes `Int(…)` por tramo perdía hasta 7 min — FER-128 r9).
        func reparto(_ total: Int, _ pesos: [Double]) -> [Int] {
            var partes = pesos.map { Int(Double(total) * $0) }
            partes[partes.count - 1] += total - partes.reduce(0, +)
            return partes
        }
        let ligero = reparto(light, pesosLigero)
        let ligeroMitad = ligero.map { $0 / 2 }
        let ligeroResto = zip(ligero, ligeroMitad).map { $0 - $1 }
        let profundo = reparto(deep, pesosProfundo), remP = reparto(rem, pesosRem)
        let despierto = reparto(awake, [0.25, 0.25, 0.25, 0.25])   // 3 microdespertares + el final
        var t = onset
        var segs: [String] = []
        func tramo(_ nombre: String, _ minutos: Int) {
            guard minutos > 0 else { return }
            let fin = t + minutos * 60
            segs.append("{\"start\":\(t),\"end\":\(fin),\"stage\":\"\(nombre)\"}")
            t = fin
        }
        for i in 0..<4 {
            tramo("light", ligeroMitad[i])
            tramo("deep",  profundo[i])
            tramo("light", ligeroResto[i])
            tramo("rem",   remP[i])
            if i < 3 { tramo("wake", despierto[i]) }   // el microdespertar entre ciclos
        }
        tramo("wake", despierto[3])                  // el resto del despierto, al final
        return "[" + segs.joined(separator: ",") + "]"
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
        // WIPE + RESEED, always: the preview store PERSISTS across canvas runs, so any stale demo
        // (yesterday's weekday split → «No routine» today; an old seed without sessions/zones) would
        // shadow the fresh one forever. Deleting the demo first also keeps the old idempotence promise
        // — no duplicated routines — while re-anchoring the split to TODAY on every run (FER-952).
        if let stale = try? await store.routines() {
            for r in stale { try? await store.deleteRoutine(id: r.id) }
        }
        for s in (try? await store.recentSessions(limit: 500)) ?? [] {
            try? await store.deleteSession(id: s.id)
        }
        // A live-session snapshot left by an earlier canvas run (Serie activa previews) would be
        // restored by every fresh AppModel and LOCK the routine editor — the demo starts at rest.
        try? await store.clearInProgressSession()
        model.strengthSession = nil
        let now = Int(Date().timeIntervalSince1970)
        let cal = Calendar(identifier: .gregorian)

        func rex(_ rid: String, _ eid: String, _ pos: Int, sets: Int, reps: Int, kg: Double,
                 progression: Bool = false) -> RoutineExercise {
            let planned = (0..<sets).map { RoutineSet(position: $0, reps: reps, weightKg: kg) }
            var re = RoutineExercise(routineId: rid, exerciseId: eid, position: pos,
                                     targetSets: sets, targetReps: reps, targetWeightKg: kg,
                                     restMode: .fixed, restSeconds: 90, sets: planned)
            // FER-952: progression ON for the big three so «Tu progresión» (accents ↑ / … / ＝)
            // always has rows to draw in the canvas.
            if progression {
                re.progressionEnabled = true
                re.progressionSessions = 2
                re.progressionIncrementKg = 2.5
            }
            return re
        }

        // Push (chest/shoulders → ember) / pull (lats/biceps → teal) / legs (quads → indigo).
        let a = Routine(name: "Día A — Empuje", createdTs: now, updatedTs: now, sortOrder: 0)
        let b = Routine(name: "Día B — Tirón", createdTs: now, updatedTs: now, sortOrder: 1)
        let c = Routine(name: "Día C — Pierna", createdTs: now, updatedTs: now, sortOrder: 2)
        try? await store.saveRoutine(a, exercises: [
            rex(a.id, "Barbell_Bench_Press_-_Medium_Grip", 0, sets: 4, reps: 8, kg: 80, progression: true),
            rex(a.id, "Incline_Dumbbell_Press", 1, sets: 3, reps: 10, kg: 26),
            rex(a.id, "Dumbbell_Lying_One-Arm_Rear_Lateral_Raise", 2, sets: 3, reps: 12, kg: 8),
        ])
        try? await store.saveRoutine(b, exercises: [
            rex(b.id, "Barbell_Deadlift", 0, sets: 4, reps: 6, kg: 120, progression: true),
            rex(b.id, "Close-Grip_Front_Lat_Pulldown", 1, sets: 3, reps: 10, kg: 55),
            rex(b.id, "Barbell_Curl", 2, sets: 3, reps: 10, kg: 30),
        ])
        try? await store.saveRoutine(c, exercises: [
            rex(c.id, "Barbell_Full_Squat", 0, sets: 4, reps: 8, kg: 100, progression: true),
            rex(c.id, "Dumbbell_Lunges", 1, sets: 3, reps: 10, kg: 20),
            // Core en el plan para que «Volumen por grupo» de Tu Plan pinte SIEMPRE las 4 barras.
            rex(c.id, "Cable_Crunch", 2, sets: 3, reps: 15, kg: 25),
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

        await seedSessions(store: store, pushId: a.id, pullId: b.id, legsId: c.id)
    }

    /// Completed demo sessions: squat/deadlift days across the prior weeks (a real, tinted Constancia)
    /// plus a dense 8-week bench progression (2 sessions/week, a raise every ~2) so «Detalle · Progreso»
    /// draws real charts — 1RM trend, best-set sparkline, weekly volume bars — and «Historial» shows
    /// day blocks with set chips + the RÉCORD badge on today (FER-951).
    private static func seedSessions(store: CenitStore, pushId: String, pullId: String, legsId: String) async {
        let cal = Calendar(identifier: .gregorian)
        /// Matches `AppModel.deviceId`, so `Repository.workoutRows` joins the journal row (zones/max HR).
        let journalDeviceId = "strap"

        /// One completed session — optionally MULTI-exercise (`extras`), with strain/HR/kcal/notes and,
        /// when `zones` is set, a time-overlapping journal `WorkoutRow` so the detail's HR-zones bar
        /// renders (StrengthSession doesn't persist zones; the journal join does).
        func session(_ rid: String, exerciseId: String, daysAgo: Int, kg: Double, sets: Int = 3,
                     extras: [(id: String, kg: Double, sets: Int)] = [],
                     strain: Double? = nil, avgHr: Int? = nil, energyKcal: Double? = nil,
                     notes: String? = nil, zones: Bool = false) async {
            guard let day = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return }
            let start = Int(cal.startOfDay(for: day).timeIntervalSince1970) + 18 * 3600
            let end = start + 50 * 60
            let s = StrengthSession(routineId: rid, startTs: start, endTs: end,
                                    strain: strain, avgHr: avgHr, notes: notes,
                                    energyKcal: energyKcal, energySource: energyKcal != nil ? .estimated : nil)
            var rows: [SetEntry] = []
            for (pos, spec) in ([(exerciseId, kg, sets)] + extras.map { ($0.id, $0.kg, $0.sets) }).enumerated() {
                for i in 0..<spec.2 {
                    rows.append(SetEntry(sessionId: s.id, exerciseId: spec.0, position: pos * 10 + i,
                                         kind: .work, weightKg: spec.1, reps: 8, done: true,
                                         ts: start + rows.count * 240))
                }
            }
            try? await store.saveSession(s, sets: rows)
            if zones {
                let row = WorkoutRow(
                    startTs: start, endTs: end,
                    sport: "Strength Training", source: "whoop",
                    durationS: Double(end - start), energyKcal: energyKcal,
                    avgHr: avgHr, maxHr: avgHr.map { $0 + 36 }, strain: strain, distanceM: nil,
                    zonesJSON: #"{"z1":8,"z2":22,"z3":40,"z4":25,"z5":5}"#,
                    notes: nil)
                _ = try? await store.upsertWorkouts([row], deviceId: journalDeviceId)
            }
        }

        // ── LA SESIÓN ESTRELLA (hoy): banca + accesorios, con TODO — esfuerzo, FC, kcal, nota y
        // zonas de FC vía journal — para verificar el detalle de sesión completo (FER-952).
        await session(pushId, exerciseId: "Barbell_Bench_Press_-_Medium_Grip", daysAgo: 0, kg: 82.5, sets: 4,
                      extras: [("Incline_Dumbbell_Press", 26, 3), ("Cable_Crunch", 25, 3)],
                      strain: 11.2, avgHr: 132, energyKcal: 316,
                      notes: "Felt strong; moved bench up to 82.5.", zones: true)

        // ── SEMANA DENSA: sesiones recientes multi-ejercicio para que «Volumen por músculo» pinte
        // bandas VARIADAS (pecho en banda, pierna abajo, etc.), no todo en ámbar por falta de datos.
        await session(pullId, exerciseId: "Barbell_Deadlift", daysAgo: 1, kg: 120, sets: 4,
                      extras: [("Close-Grip_Front_Lat_Pulldown", 55, 4), ("Barbell_Curl", 30, 3)],
                      strain: 12.8, avgHr: 128, energyKcal: 342, zones: true)
        await session(legsId, exerciseId: "Barbell_Full_Squat", daysAgo: 2, kg: 100, sets: 4,
                      extras: [("Dumbbell_Lunges", 20, 3), ("Cable_Crunch", 25, 3)],
                      strain: 13.1, avgHr: 126, energyKcal: 358, zones: true)
        await session(pushId, exerciseId: "Barbell_Bench_Press_-_Medium_Grip", daysAgo: 3, kg: 80, sets: 5,
                      extras: [("Incline_Dumbbell_Press", 24, 4)])
        // Un empuje extra dentro de la ventana de 30 d para que PECHO cruce la banda (≥10 series/sem
        // ponderadas) y el color de familia conviva con el ámbar de los que quedan abajo.
        await session(pushId, exerciseId: "Barbell_Bench_Press_-_Medium_Grip", daysAgo: 8, kg: 80, sets: 5,
                      extras: [("Incline_Dumbbell_Press", 24, 4)])
        await session(pushId, exerciseId: "Barbell_Bench_Press_-_Medium_Grip", daysAgo: 9, kg: 77.5, sets: 4,
                      extras: [("Incline_Dumbbell_Press", 24, 3)])
        await session(pullId, exerciseId: "Barbell_Deadlift", daysAgo: 5, kg: 117.5, sets: 4,
                      extras: [("Close-Grip_Front_Lat_Pulldown", 52.5, 4)])
        await session(pushId, exerciseId: "Barbell_Bench_Press_-_Medium_Grip", daysAgo: 6, kg: 80, sets: 4,
                      extras: [("Incline_Dumbbell_Press", 24, 3)])

        // ── Historia previa: la progresión de banca de 8 semanas (tendencia 1RM del Detalle) y
        // pierna/jalón salpicados para la Constancia.
        await session(legsId, exerciseId: "Barbell_Full_Squat", daysAgo: 16, kg: 95)
        await session(pullId, exerciseId: "Barbell_Deadlift", daysAgo: 10, kg: 115)
        await session(pullId, exerciseId: "Barbell_Deadlift", daysAgo: 31, kg: 110)
        let benchRamp: [(daysAgo: Int, kg: Double)] = [
            (11, 80), (14, 77.5), (18, 77.5), (21, 77.5), (25, 75),
            (28, 75), (32, 75), (35, 72.5), (39, 72.5), (42, 72.5), (46, 70), (49, 70), (53, 70),
        ]
        for step in benchRamp {
            await session(pushId, exerciseId: "Barbell_Bench_Press_-_Medium_Grip",
                          daysAgo: step.daysAgo, kg: step.kg)
        }
    }
}
#endif
